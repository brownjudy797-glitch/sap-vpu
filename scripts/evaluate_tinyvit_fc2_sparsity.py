#!/usr/bin/env python3
"""Measure TinyViT FC2 quantization and structured-sparsity error over real images."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import sys
from urllib.request import urlretrieve

from export_tinyvit_activation_fixture import (
    FC1_GELU_REQUANT_SHIFT,
    FC1_K128_OUTPUT_CHANNELS,
    LAYER_ID,
    MODEL_ID,
    TIMM_MODEL,
    quantize_symmetric,
    requantize_signed,
    round_ties_away,
    sha256,
)
from prepare_tinyvit_fc1_k128 import fc2_structured_group_masks


IMAGE_SET = (
    ("dog.jpg", "f3f87bb8ab3c26c7ecfd3ac60421d7f32b0503d1d6c5baf8bac42ed93d86351a"),
    ("pgan_celebaHQ.jpg", "d3ec05ddc66f25e455b41a895e9d5ae4a6f1053a6092a2d20e5e6ee1b8cd1581"),
    ("pgan_mix.jpg", "c9d6c46bdab039710db9928711f0bb5f8dcdc331242b4ab7977bbd98167eda5a"),
    ("ultralytics_yolov5_img0.jpg", "e533b8fb332ea1a5fe5282d96adcda6726b7dc10a6507f0435b6042d4699ab83"),
    ("ultralytics_yolov5_img1.png", "34c5f32559dee59e7ebfef2f330bd8fba280836e0ab25f3f04858e149cb78046"),
    ("ultralytics_yolov5_img2.png", "d5a9fed34df9ad72bdf472b6f207ffb751908fd4348f73edb028086eeee84986"),
    ("hybridnets.jpg", "ffdd49c47b6f27a5a2bf5f79eb06d8c1f7ca58ff75496542dfb013b9c13a434c"),
    ("unet_brain_mri.png", "be225a6130bb1a370579e533a7e751b111f9f8fb00d00bfc3c7235b3ce017426"),
)
IMAGE_BASE_URL = "https://raw.githubusercontent.com/pytorch/hub/master/images"


def prepare_images(directory: Path) -> list[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    paths: list[Path] = []
    for name, expected_sha256 in IMAGE_SET:
        path = directory / name
        if not path.exists():
            temporary = path.with_suffix(path.suffix + ".part")
            urlretrieve(f"{IMAGE_BASE_URL}/{name}", temporary)
            temporary.replace(path)
        actual_sha256 = sha256(path)
        if actual_sha256 != expected_sha256:
            raise ValueError(f"{path}: expected SHA256 {expected_sha256}, got {actual_sha256}")
        paths.append(path)
    return paths


def error_metrics(reference: object, estimate: object) -> dict[str, float]:
    import torch

    difference = (reference - estimate).abs().flatten()
    return {
        "max_abs": float(difference.max()),
        "mean_abs": float(difference.mean()),
        "p95_abs": float(torch.quantile(difference, 0.95)),
        "rmse": float(torch.sqrt(torch.mean(difference * difference))),
    }


def apply_group_masks(weights: object, masks: list[int]) -> tuple[object, object]:
    import torch

    sparse = weights.clone()
    valid = torch.zeros((2, FC1_K128_OUTPUT_CHANNELS // 4), dtype=torch.bool)
    for chunk, mask in enumerate(masks):
        for output in range(2):
            for group in range(2):
                group_index = output * 2 + group
                channel_group = chunk * 2 + group
                if mask & (1 << group_index):
                    valid[output, channel_group] = True
                else:
                    base = channel_group * 4
                    sparse[output, base : base + 4] = 0
    return sparse, valid


def capture_activations(model: object, transform: object, image_paths: list[Path]) -> tuple:
    import torch
    from PIL import Image

    mlp = model.stages[1].blocks[0].mlp
    captured: dict[str, object] = {}
    hooks = [
        mlp.fc1.register_forward_hook(
            lambda _module, inputs, output: captured.update(
                fc1_input=inputs[0].detach(), fc1_output=output.detach()
            )
        ),
        mlp.fc2.register_forward_hook(
            lambda _module, inputs, _output: captured.update(gelu=inputs[0].detach())
        ),
    ]
    inputs = []
    preactivations = []
    gelu = []
    token_counts = []
    try:
        for path in image_paths:
            with Image.open(path) as image:
                if image.mode == "P" and "transparency" in image.info:
                    image = image.convert("RGBA")
                model_input = transform(image.convert("RGB")).unsqueeze(0)
            with torch.inference_mode():
                model(model_input)
            inputs.append(captured["fc1_input"][0, :, :FC1_K128_OUTPUT_CHANNELS])
            preactivations.append(captured["fc1_output"][0, :, :FC1_K128_OUTPUT_CHANNELS])
            gelu.append(captured["gelu"][0, :, :FC1_K128_OUTPUT_CHANNELS])
            token_counts.append(int(inputs[-1].shape[0]))
    finally:
        for hook in hooks:
            hook.remove()
    return torch.cat(inputs), torch.cat(preactivations), torch.cat(gelu), token_counts


def evaluate(checkpoint: Path, image_paths: list[Path]) -> dict[str, object]:
    import PIL
    import safetensors
    import timm
    import torch
    import torchvision
    import torch.nn.functional as functional
    from safetensors.torch import load_file
    from timm.data import create_transform, resolve_model_data_config

    model = timm.create_model(TIMM_MODEL, pretrained=False, num_classes=1000)
    model.load_state_dict(load_file(str(checkpoint)))
    model.eval()
    data_config = resolve_model_data_config(model)
    transform = create_transform(**data_config, is_training=False)
    inputs, actual_preactivation, actual_gelu, token_counts = capture_activations(
        model, transform, image_paths
    )
    mlp = model.stages[1].blocks[0].mlp

    input_int8, input_scale = quantize_symmetric(inputs)
    fc1_weight = mlp.fc1.weight[
        :FC1_K128_OUTPUT_CHANNELS, :FC1_K128_OUTPUT_CHANNELS
    ].detach()
    fc1_weight_int8, fc1_weight_scale = quantize_symmetric(fc1_weight)
    accumulator_scale = input_scale * fc1_weight_scale
    accumulator = input_int8 @ fc1_weight_int8.T
    bias = round_ties_away(mlp.fc1.bias[:FC1_K128_OUTPUT_CHANNELS] / accumulator_scale)
    biased_accumulator = accumulator + bias.to(torch.int32)

    gelu_scale = float(actual_preactivation.abs().max()) / 127.0
    requant_multiplier = int(
        math.floor(accumulator_scale / gelu_scale * (1 << FC1_GELU_REQUANT_SHIFT) + 0.5)
    )
    preactivation_int8 = requantize_signed(
        biased_accumulator, requant_multiplier, FC1_GELU_REQUANT_SHIFT
    )
    lut_input = torch.arange(-128, 128, dtype=torch.float32) * gelu_scale
    gelu_lut = round_ties_away(functional.gelu(lut_input) / gelu_scale).clamp(-128, 127)
    gelu_int8 = gelu_lut[(preactivation_int8 + 128).to(torch.int64)].to(torch.int32)

    fc2_weight = mlp.fc2.weight[:2, :FC1_K128_OUTPUT_CHANNELS].detach()
    fc2_weight_int8, fc2_weight_scale = quantize_symmetric(fc2_weight)
    dense = gelu_int8 @ fc2_weight_int8.T
    masks = fc2_structured_group_masks(fc2_weight_int8.tolist())
    sparse_weight, structured_valid = apply_group_masks(fc2_weight_int8, masks)
    sparse = gelu_int8 @ sparse_weight.T
    output_scale = gelu_scale * fc2_weight_scale
    reference = actual_gelu @ fc2_weight.T
    dense_dequantized = dense.to(torch.float32) * output_scale
    sparse_dequantized = sparse.to(torch.float32) * output_scale

    activation_nonzero = ~gelu_int8.reshape(-1, FC1_K128_OUTPUT_CHANNELS // 4, 4).eq(0).all(2)
    total_tokens = int(gelu_int8.shape[0])
    dense_vdots = total_tokens * 2 * (FC1_K128_OUTPUT_CHANNELS // 4)
    structured_vdots = total_tokens * int(structured_valid.sum())
    combined_vdots = int((activation_nonzero[:, None, :] & structured_valid[None, :, :]).sum())
    token_pairs = sum((count + 1) // 2 for count in token_counts)
    dense_weight_reads = token_pairs * 2 * (FC1_K128_OUTPUT_CHANNELS // 4)
    structured_weight_reads = token_pairs * int(structured_valid.sum())
    dense_input_reads = total_tokens * (FC1_K128_OUTPUT_CHANNELS // 4)

    per_image = []
    offset = 0
    for path, count in zip(image_paths, token_counts):
        image_slice = slice(offset, offset + count)
        per_image.append(
            {
                "name": path.name,
                "sha256": sha256(path),
                "tokens": count,
                "dense_error": error_metrics(reference[image_slice], dense_dequantized[image_slice]),
                "structured_sparse_error": error_metrics(
                    reference[image_slice], sparse_dequantized[image_slice]
                ),
            }
        )
        offset += count

    return {
        "schema": "sap-vpu-tinyvit-fc2-sparsity-study-v1",
        "provenance": {
            "model_id": MODEL_ID,
            "layer_id": LAYER_ID,
            "checkpoint_sha256": sha256(checkpoint),
            "image_source": IMAGE_BASE_URL,
            "software_versions": {
                "torch": torch.__version__,
                "torchvision": torchvision.__version__,
                "timm": timm.__version__,
                "pillow": PIL.__version__,
                "safetensors": safetensors.__version__,
            },
        },
        "shape": {
            "images": len(image_paths),
            "tokens_per_image": token_counts,
            "token_samples": total_tokens,
            "fc2_input_channels": FC1_K128_OUTPUT_CHANNELS,
            "fc2_output_channels": 2,
        },
        "quantization": {
            "scheme": "dataset-calibrated-symmetric-int8",
            "input_scale": input_scale,
            "fc1_weight_scale": fc1_weight_scale,
            "gelu_scale": gelu_scale,
            "fc2_weight_scale": fc2_weight_scale,
            "requant_multiplier": requant_multiplier,
            "requant_shift": FC1_GELU_REQUANT_SHIFT,
        },
        "policy": {
            "name": "lowest-l1-weight-group-per-k8",
            "weight_group_sparsity": 0.25,
            "group_lanes": 4,
            "group_masks": [f"0x{mask:x}" for mask in masks],
        },
        "error": {
            "dense": error_metrics(reference, dense_dequantized),
            "structured_sparse": error_metrics(reference, sparse_dequantized),
            "pruning_delta": error_metrics(dense_dequantized, sparse_dequantized),
        },
        "activity": {
            "dense_vdots": dense_vdots,
            "structured_sparse_vdots": structured_vdots,
            "structured_sparse_vdot_reduction": 1.0 - structured_vdots / dense_vdots,
            "natural_zero_activation_groups": int((~activation_nonzero).sum()),
            "activation_groups": int(activation_nonzero.numel()),
            "combined_sparse_vdots": combined_vdots,
            "combined_sparse_vdot_reduction": 1.0 - combined_vdots / dense_vdots,
            "dense_payload_reads": dense_input_reads + dense_weight_reads,
            "structured_sparse_payload_reads": dense_input_reads + structured_weight_reads,
            "structured_sparse_reads_saved": dense_weight_reads - structured_weight_reads,
            "potential_activation_reads_saved": int((~activation_nonzero).sum()),
        },
        "images": per_image,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("image_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        result = evaluate(args.checkpoint, prepare_images(args.image_dir))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="ascii")
    except (ImportError, OSError, RuntimeError, ValueError) as exc:
        print(f"TinyViT sparsity study failed: {exc}", file=sys.stderr)
        return 1
    print(
        f"TinyViT sparsity study: {result['shape']['images']} images, "
        f"{result['shape']['token_samples']} tokens"
    )
    print(f"dense error: {result['error']['dense']}")
    print(f"structured sparse error: {result['error']['structured_sparse']}")
    print(f"activity: {result['activity']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
