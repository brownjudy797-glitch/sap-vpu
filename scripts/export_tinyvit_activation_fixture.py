#!/usr/bin/env python3
"""Capture a real-image TinyViT activation slice as an INT8 MLP2 fixture."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any


MODEL_ID = "timm/tiny_vit_5m_224.dist_in22k_ft_in1k"
TIMM_MODEL = "tiny_vit_5m_224"
LAYER_ID = "stages.1.blocks.0.mlp"
CHECKPOINT_URL = f"https://huggingface.co/{MODEL_ID}/resolve/main/model.safetensors"
DEFAULT_IMAGE_URL = (
    "https://huggingface.co/datasets/huggingface/documentation-images/"
    "resolve/main/beignets-task-guide.png"
)
TOKEN_INDICES = (0, 1)
FC1_K128_OUTPUT_CHANNELS = 128
FC1_GELU_REQUANT_SHIFT = 16


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def as_list(tensor: Any) -> list[Any]:
    return tensor.detach().cpu().tolist()


def quantize_symmetric(tensor: Any) -> tuple[Any, float]:
    import torch

    maximum = float(tensor.abs().max())
    if not math.isfinite(maximum) or maximum == 0:
        raise ValueError("selected tensor slice must contain finite nonzero values")
    scale = maximum / 127.0
    quantized = torch.sign(tensor) * torch.floor(tensor.abs() / scale + 0.5)
    return quantized.clamp(-127, 127).to(torch.int32), scale


def choose_requant_shift(accumulators: Any) -> int:
    maximum = max(0, int(accumulators.max()))
    for shift in range(32):
        rounding = 0 if shift == 0 else 1 << (shift - 1)
        if (maximum + rounding) >> shift <= 127:
            return shift
    raise ValueError("FC1 accumulator cannot be requantized with a 31-bit shift")


def requantize_relu(accumulators: Any, shift: int) -> Any:
    import torch

    values = torch.clamp(accumulators, min=0)
    if shift:
        values = (values + (1 << (shift - 1))) >> shift
    if int(values.max()) > 127:
        raise ValueError("requantized FC1 activation exceeds signed INT8")
    return values.to(torch.int32)


def error_metrics(reference: Any, estimate: Any) -> dict[str, float]:
    difference = (reference - estimate).abs()
    return {"max_abs": float(difference.max()), "mean_abs": float(difference.mean())}


def round_ties_away(tensor: Any) -> Any:
    import torch

    return torch.sign(tensor) * torch.floor(torch.abs(tensor) + 0.5)


def requantize_signed(values: Any, multiplier: int, shift: int) -> Any:
    import torch

    scaled = values.to(torch.int64) * multiplier
    rounded = (scaled.abs() + (1 << (shift - 1))) >> shift
    return torch.where(scaled < 0, -rounded, rounded).clamp(-128, 127).to(torch.int32)


def build_fixture(checkpoint: Path, image: Path, image_url: str) -> dict[str, Any]:
    import PIL
    import safetensors
    import timm
    import torch
    import torch.nn.functional as functional
    import torchvision
    from PIL import Image
    from safetensors.torch import load_file
    from timm.data import create_transform, resolve_model_data_config

    model = timm.create_model(TIMM_MODEL, pretrained=False, num_classes=1000)
    model.load_state_dict(load_file(str(checkpoint)))
    model.eval()
    mlp = model.stages[1].blocks[0].mlp
    captured: dict[str, Any] = {}
    hooks = [
        mlp.fc1.register_forward_hook(
            lambda _module, inputs, output: captured.update(
                fc1_input=inputs[0].detach(), fc1_output=output.detach()
            )
        ),
        mlp.fc2.register_forward_hook(
            lambda _module, inputs, output: captured.update(
                fc2_input=inputs[0].detach(), fc2_output=output.detach()
            )
        ),
    ]
    data_config = resolve_model_data_config(model)
    transform = create_transform(**data_config, is_training=False)
    model_input = transform(Image.open(image).convert("RGB")).unsqueeze(0)
    with torch.inference_mode():
        model(model_input)
    for hook in hooks:
        hook.remove()

    fc1_input = captured["fc1_input"][0, list(TOKEN_INDICES), :4]
    fc1_weight = mlp.fc1.weight[:4, :4].detach()
    fc2_weight = mlp.fc2.weight[:2, :4].detach()
    input_int8, input_scale = quantize_symmetric(fc1_input)
    fc1_int8, fc1_scale = quantize_symmetric(fc1_weight)
    fc2_int8, fc2_scale = quantize_symmetric(fc2_weight)

    fc1_accumulator = input_int8 @ fc1_int8.T
    requant_shift = choose_requant_shift(fc1_accumulator)
    hidden_int8 = requantize_relu(fc1_accumulator, requant_shift)
    fc2_accumulator = hidden_int8 @ fc2_int8.T
    hidden_scale = input_scale * fc1_scale * (1 << requant_shift)
    integer_partial = fc2_accumulator.to(torch.float32) * hidden_scale * fc2_scale

    float_fc1_partial = fc1_input @ fc1_weight.T
    float_relu_fc2_partial = torch.relu(float_fc1_partial) @ fc2_weight.T
    float_gelu_partial = functional.gelu(float_fc1_partial + mlp.fc1.bias[:4])
    float_gelu_fc2_partial = float_gelu_partial @ fc2_weight.T + mlp.fc2.bias[:2]
    actual_fc1 = captured["fc1_output"][0, list(TOKEN_INDICES), :4]
    actual_gelu = captured["fc2_input"][0, list(TOKEN_INDICES), :4]
    actual_fc2 = captured["fc2_output"][0, list(TOKEN_INDICES), :2]

    fc1_k128_input = captured["fc1_input"][0, list(TOKEN_INDICES), :128]
    fc1_k128_weight = mlp.fc1.weight[:FC1_K128_OUTPUT_CHANNELS, :128].detach()
    fc1_k128_input_int8, fc1_k128_input_scale = quantize_symmetric(fc1_k128_input)
    fc1_k128_weight_int8, fc1_k128_weight_scale = quantize_symmetric(fc1_k128_weight)
    fc1_k128_accumulator = fc1_k128_input_int8 @ fc1_k128_weight_int8.T
    fc1_k128_dequantized = (
        fc1_k128_accumulator.to(torch.float32) * fc1_k128_input_scale * fc1_k128_weight_scale
    )
    fc1_k128_float_no_bias = fc1_k128_input @ fc1_k128_weight.T
    fc1_k128_float_with_bias = (
        fc1_k128_float_no_bias + mlp.fc1.bias[:FC1_K128_OUTPUT_CHANNELS]
    )
    fc1_k128_actual = captured["fc1_output"][
        0, list(TOKEN_INDICES), :FC1_K128_OUTPUT_CHANNELS
    ]
    fc1_k128_actual_gelu = captured["fc2_input"][
        0, list(TOKEN_INDICES), :FC1_K128_OUTPUT_CHANNELS
    ]
    fc1_k128_accumulator_scale = fc1_k128_input_scale * fc1_k128_weight_scale
    fc1_k128_bias_accumulator = round_ties_away(
        mlp.fc1.bias[:FC1_K128_OUTPUT_CHANNELS] / fc1_k128_accumulator_scale
    ).to(torch.int32)
    fc1_k128_biased_accumulator = fc1_k128_accumulator + fc1_k128_bias_accumulator
    fc1_k128_gelu_scale = float(fc1_k128_actual.abs().max()) / 127.0
    fc1_k128_requant_multiplier = int(
        math.floor(
            fc1_k128_accumulator_scale
            / fc1_k128_gelu_scale
            * (1 << FC1_GELU_REQUANT_SHIFT)
            + 0.5
        )
    )
    fc1_k128_preactivation_int8 = requantize_signed(
        fc1_k128_biased_accumulator,
        fc1_k128_requant_multiplier,
        FC1_GELU_REQUANT_SHIFT,
    )
    fc1_k128_gelu_lut_input = (
        torch.arange(-128, 128, dtype=torch.float32) * fc1_k128_gelu_scale
    )
    fc1_k128_gelu_lut = round_ties_away(
        functional.gelu(fc1_k128_gelu_lut_input) / fc1_k128_gelu_scale
    ).clamp(-128, 127).to(torch.int32)
    fc1_k128_gelu_int8 = fc1_k128_gelu_lut[
        (fc1_k128_preactivation_int8 + 128).to(torch.int64)
    ]
    fc1_k128_gelu_dequantized = fc1_k128_gelu_int8.to(torch.float32) * fc1_k128_gelu_scale
    fc2_partial_weight = mlp.fc2.weight[:2, :FC1_K128_OUTPUT_CHANNELS].detach()
    fc2_partial_weight_int8, fc2_partial_weight_scale = quantize_symmetric(fc2_partial_weight)
    fc2_partial_accumulator = fc1_k128_gelu_int8 @ fc2_partial_weight_int8.T
    fc2_partial_dequantized = (
        fc2_partial_accumulator.to(torch.float32)
        * fc1_k128_gelu_scale
        * fc2_partial_weight_scale
    )
    fc2_float_partial = fc1_k128_actual_gelu @ fc2_partial_weight.T

    return {
        "schema": "sap-vpu-tinyvit-mlp2-int8-v1",
        "provenance": {
            "kind": "checkpoint",
            "model_id": MODEL_ID,
            "layer_id": LAYER_ID,
            "checkpoint_sha256": sha256(checkpoint),
            "checkpoint_source_url": CHECKPOINT_URL,
            "input_source": "real-image-model-activation",
            "image_source_url": image_url,
            "image_sha256": sha256(image),
            "token_indices": list(TOKEN_INDICES),
            "software_versions": {
                "torch": torch.__version__,
                "torchvision": torchvision.__version__,
                "timm": timm.__version__,
                "pillow": PIL.__version__,
                "safetensors": safetensors.__version__,
            },
            "preprocessing": {
                "input_size": list(data_config["input_size"]),
                "interpolation": data_config["interpolation"],
                "mean": list(data_config["mean"]),
                "std": list(data_config["std"]),
                "crop_pct": data_config["crop_pct"],
                "crop_mode": data_config["crop_mode"],
            },
            "tensor_slices": {
                "fc1_input": f"{LAYER_ID}.fc1_input[0,{list(TOKEN_INDICES)},0:4]",
                "fc1_weights": f"{LAYER_ID}.fc1.weight[0:4,0:4]",
                "fc2_weights": f"{LAYER_ID}.fc2.weight[0:2,0:4]",
                "fc1_k128_input": f"{LAYER_ID}.fc1_input[0,{list(TOKEN_INDICES)},0:128]",
                "fc1_k128_weights": (
                    f"{LAYER_ID}.fc1.weight[0:{FC1_K128_OUTPUT_CHANNELS},0:128]"
                ),
                "fc2_partial_weights": (
                    f"{LAYER_ID}.fc2.weight[0:2,0:{FC1_K128_OUTPUT_CHANNELS}]"
                ),
            },
            "model_semantics": {
                "fc1_bias": True,
                "activation": "gelu-exact",
                "fc2_bias": True,
            },
            "hardware_mapping_semantics": (
                "four-channel-partial-dot-power-of-two-requantization-relu-no-bias"
            ),
            "float_reference": {
                "actual_full_fc1_preactivation": as_list(actual_fc1),
                "actual_full_gelu_selected_channels": as_list(actual_gelu),
                "actual_full_fc2_output_selected_channels": as_list(actual_fc2),
                "four_channel_relu_no_bias_fc2_partial": as_list(float_relu_fc2_partial),
                "four_channel_gelu_with_selected_bias_fc2_partial": as_list(float_gelu_fc2_partial),
                "integer_path_dequantized_fc2_partial": as_list(integer_partial),
                "integer_vs_relu_partial_error": error_metrics(float_relu_fc2_partial, integer_partial),
                "integer_vs_full_model_output_error": error_metrics(actual_fc2, integer_partial),
            },
        },
        "quantization": {
            "scheme": "symmetric-int8",
            "input_scale": input_scale,
            "fc1_weight_scale": fc1_scale,
            "fc2_weight_scale": fc2_scale,
            "hidden_scale": hidden_scale,
            "input_zero_point": 0,
            "fc1_weight_zero_point": 0,
            "fc2_weight_zero_point": 0,
            "fc1_output_requant_shift": requant_shift,
            "weight_scope": "selected-slice-max-abs",
            "input_scope": "selected-token-and-channel-slice-max-abs",
            "rounding": "nearest-ties-away-from-zero",
        },
        "input_tokens": as_list(input_int8),
        "fc1_weights": as_list(fc1_int8),
        "fc2_weights": as_list(fc2_int8),
        "fc1_k128": {
            "schema": "sap-vpu-tinyvit-fc1-k128-int8-v1",
            "shape": {
                "tokens": 2,
                "input_channels": 128,
                "output_channels": FC1_K128_OUTPUT_CHANNELS,
            },
            "chunk_k": 8,
            "input_tokens": as_list(fc1_k128_input_int8),
            "weights": as_list(fc1_k128_weight_int8),
            "expected_integer_output": as_list(fc1_k128_accumulator),
            "software_postprocess": {
                "boundary": "cv32e40x-int32-bias-q16-requant-int8-gelu-lut",
                "bias_accumulator": as_list(fc1_k128_bias_accumulator),
                "requant_multiplier": fc1_k128_requant_multiplier,
                "requant_shift": FC1_GELU_REQUANT_SHIFT,
                "gelu_scale": fc1_k128_gelu_scale,
                "gelu_lut": as_list(fc1_k128_gelu_lut),
                "expected_preactivation_int8": as_list(fc1_k128_preactivation_int8),
                "expected_gelu_int8": as_list(fc1_k128_gelu_int8),
                "float_reference": {
                    "actual_gelu": as_list(fc1_k128_actual_gelu),
                    "integer_gelu_dequantized": as_list(fc1_k128_gelu_dequantized),
                    "integer_vs_actual_gelu_error": error_metrics(
                        fc1_k128_actual_gelu, fc1_k128_gelu_dequantized
                    ),
                },
            },
            "fc2_partial": {
                "boundary": "sap-vpu-int8-fc2-k8-chunked-partial-no-bias",
                "shape": {
                    "tokens": 2,
                    "input_channels": FC1_K128_OUTPUT_CHANNELS,
                    "output_channels": 2,
                },
                "chunk_k": 8,
                "weights": as_list(fc2_partial_weight_int8),
                "expected_integer_output": as_list(fc2_partial_accumulator),
                "quantization": {
                    "scheme": "symmetric-int8",
                    "input_scale": fc1_k128_gelu_scale,
                    "weight_scale": fc2_partial_weight_scale,
                    "input_zero_point": 0,
                    "weight_zero_point": 0,
                },
                "float_reference": {
                    "selected_channel_partial_no_bias": as_list(fc2_float_partial),
                    "integer_path_dequantized": as_list(fc2_partial_dequantized),
                    "integer_vs_selected_partial_error": error_metrics(
                        fc2_float_partial, fc2_partial_dequantized
                    ),
                },
            },
            "quantization": {
                "scheme": "symmetric-int8",
                "input_scale": fc1_k128_input_scale,
                "weight_scale": fc1_k128_weight_scale,
                "input_zero_point": 0,
                "weight_zero_point": 0,
                "rounding": "nearest-ties-away-from-zero",
            },
            "float_reference": {
                "fc1_no_bias": as_list(fc1_k128_float_no_bias),
                "fc1_bias": as_list(mlp.fc1.bias[:FC1_K128_OUTPUT_CHANNELS]),
                "fc1_with_bias": as_list(fc1_k128_float_with_bias),
                "actual_full_fc1_preactivation": as_list(fc1_k128_actual),
                "integer_path_dequantized": as_list(fc1_k128_dequantized),
                "integer_vs_no_bias_error": error_metrics(
                    fc1_k128_float_no_bias, fc1_k128_dequantized
                ),
                "integer_vs_full_model_error": error_metrics(
                    fc1_k128_actual, fc1_k128_dequantized
                ),
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("image", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--image-url", default=DEFAULT_IMAGE_URL)
    args = parser.parse_args()
    try:
        fixture = build_fixture(args.checkpoint, args.image, args.image_url)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="ascii", newline="\n") as stream:
            stream.write(json.dumps(fixture, indent=2, sort_keys=True) + "\n")
    except (ImportError, OSError, RuntimeError, ValueError) as exc:
        print(f"TinyViT activation export failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
