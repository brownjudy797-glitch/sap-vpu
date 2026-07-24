#!/usr/bin/env python3
"""Measure TinyViT FC2 quantization and structured-sparsity error over real images."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from urllib.request import urlretrieve

from export_tinyvit_activation_fixture import (
    LAYER_ID,
    MODEL_ID,
    TIMM_MODEL,
    quantize_symmetric,
    sha256,
)


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
FC2_INPUT_CHANNELS = 512
FC2_OUTPUT_CHANNELS = 128
GROUP_LANES = 4
CHUNK_K = 8
OUTPUT_TILE_CHANNELS = 2


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
    rmse = torch.sqrt(torch.mean(difference * difference))
    reference_rms = torch.sqrt(torch.mean(reference.flatten() ** 2))
    return {
        "max_abs": float(difference.max()),
        "mean_abs": float(difference.mean()),
        "p95_abs": float(torch.quantile(difference, 0.95)),
        "rmse": float(rmse),
        "nrmse": float(rmse / reference_rms),
    }


def policy_group_valid(weights: object, policy: str) -> object:
    import torch

    group_l1 = weights.abs().reshape(weights.shape[0], -1, GROUP_LANES).sum(2)
    valid = torch.ones_like(group_l1, dtype=torch.bool)
    if policy == "tile_local_l1_25":
        tiles = group_l1.reshape(
            weights.shape[0] // OUTPUT_TILE_CHANNELS,
            OUTPUT_TILE_CHANNELS,
            weights.shape[1] // CHUNK_K,
            CHUNK_K // GROUP_LANES,
        ).permute(0, 2, 1, 3).reshape(-1, 4)
        tile_valid = torch.ones_like(tiles, dtype=torch.bool)
        tile_valid.scatter_(1, tiles.argmin(1, keepdim=True), False)
        return tile_valid.reshape(
            weights.shape[0] // OUTPUT_TILE_CHANNELS,
            weights.shape[1] // CHUNK_K,
            OUTPUT_TILE_CHANNELS,
            CHUNK_K // GROUP_LANES,
        ).permute(0, 2, 1, 3).reshape_as(valid)

    kind, value = policy.rsplit("_", 1)
    ordered = torch.argsort(group_l1.flatten())
    if kind == "layer_global_l1":
        drop_count = int(valid.numel() * float(value) / 100.0)
    elif kind == "layer_l1_budget":
        limit = float(group_l1.sum()) * float(value) / 100.0
        drop_count = int((group_l1.flatten()[ordered].cumsum(0) <= limit).sum())
    else:
        raise ValueError(f"unsupported policy: {policy}")
    valid.flatten()[ordered[:drop_count]] = False
    return valid


def apply_group_valid(weights: object, valid: object) -> object:
    return (
        weights.reshape(weights.shape[0], -1, GROUP_LANES)
        * valid.unsqueeze(2)
    ).reshape_as(weights)


def self_test() -> None:
    import torch

    weights = torch.arange(1, 33, dtype=torch.int32).reshape(4, 8)
    global_valid = policy_group_valid(weights, "layer_global_l1_25")
    tile_valid = policy_group_valid(weights, "tile_local_l1_25")
    assert global_valid.shape == (4, 2)
    assert int((~global_valid).sum()) == 2
    assert int((~tile_valid).sum()) == 2
    assert int(apply_group_valid(weights, global_valid).count_nonzero()) == 24


def capture_activations(model: object, transform: object, image_paths: list[Path]) -> tuple:
    import torch
    from PIL import Image

    mlp = model.stages[1].blocks[0].mlp
    captured: dict[str, object] = {}
    hook = mlp.fc2.register_forward_hook(
        lambda _module, inputs, _output: captured.update(gelu=inputs[0].detach())
    )
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
            gelu.append(captured["gelu"][0, :, :FC2_INPUT_CHANNELS])
            token_counts.append(int(gelu[-1].shape[0]))
    finally:
        hook.remove()
    return torch.cat(gelu), token_counts


def evaluate(checkpoint: Path, image_paths: list[Path]) -> dict[str, object]:
    import PIL
    import safetensors
    import timm
    import torch
    import torchvision
    from safetensors.torch import load_file
    from timm.data import create_transform, resolve_model_data_config

    model = timm.create_model(TIMM_MODEL, pretrained=False, num_classes=1000)
    model.load_state_dict(load_file(str(checkpoint)))
    model.eval()
    data_config = resolve_model_data_config(model)
    transform = create_transform(**data_config, is_training=False)
    actual_gelu, token_counts = capture_activations(model, transform, image_paths)
    mlp = model.stages[1].blocks[0].mlp
    if tuple(actual_gelu.shape[1:]) != (FC2_INPUT_CHANNELS,):
        raise ValueError(f"expected GELU width {FC2_INPUT_CHANNELS}, got {actual_gelu.shape[1]}")

    gelu_int8, gelu_scale = quantize_symmetric(actual_gelu)
    fc2_weight = mlp.fc2.weight[
        :FC2_OUTPUT_CHANNELS, :FC2_INPUT_CHANNELS
    ].detach()
    if tuple(fc2_weight.shape) != (FC2_OUTPUT_CHANNELS, FC2_INPUT_CHANNELS):
        raise ValueError(
            f"expected FC2 weight shape [{FC2_OUTPUT_CHANNELS}, {FC2_INPUT_CHANNELS}], "
            f"got {list(fc2_weight.shape)}"
        )
    fc2_weight_int8, fc2_weight_scale = quantize_symmetric(fc2_weight)
    output_scale = gelu_scale * fc2_weight_scale
    reference = actual_gelu @ fc2_weight.T
    dense = gelu_int8 @ fc2_weight_int8.T
    dense_dequantized = dense.to(torch.float32) * output_scale

    activation_nonzero = ~gelu_int8.reshape(-1, FC2_INPUT_CHANNELS // GROUP_LANES, GROUP_LANES).eq(0).all(2)
    total_tokens = int(gelu_int8.shape[0])
    input_groups = FC2_INPUT_CHANNELS // GROUP_LANES
    output_pairs = FC2_OUTPUT_CHANNELS // OUTPUT_TILE_CHANNELS
    dense_vdots = total_tokens * FC2_OUTPUT_CHANNELS * input_groups
    token_pairs = sum((count + 1) // 2 for count in token_counts)
    dense_weight_reads = token_pairs * FC2_OUTPUT_CHANNELS * input_groups
    dense_input_reads = total_tokens * output_pairs * input_groups

    policy_names = (
        "layer_global_l1_6.25",
        "layer_global_l1_12.5",
        "layer_global_l1_25",
        "tile_local_l1_25",
        "layer_l1_budget_1",
        "layer_l1_budget_2",
        "layer_l1_budget_5",
    )
    policies = {}
    policy_estimates = {}
    total_weight_l1 = int(fc2_weight_int8.abs().sum())
    for name in policy_names:
        structured_valid = policy_group_valid(fc2_weight_int8, name)
        sparse_weight = apply_group_valid(fc2_weight_int8, structured_valid)
        estimate = (gelu_int8 @ sparse_weight.T).to(torch.float32) * output_scale
        policy_estimates[name] = estimate
        active_groups = int(structured_valid.sum())
        structured_vdots = total_tokens * active_groups
        combined_vdots = int(
            (activation_nonzero.to(torch.int32) @ structured_valid.T.to(torch.int32)).sum()
        )
        pair_valid = structured_valid.reshape(output_pairs, OUTPUT_TILE_CHANNELS, input_groups).any(1)
        structured_input_reads = total_tokens * int(pair_valid.sum())
        structured_weight_reads = token_pairs * active_groups
        policies[name] = {
            "selection_scope": "full-layer" if name.startswith("layer_") else "2x2x8-tile",
            "weight_group_sparsity": 1.0 - active_groups / structured_valid.numel(),
            "dropped_weight_l1_ratio": 1.0 - float(sparse_weight.abs().sum()) / total_weight_l1,
            "error": error_metrics(reference, estimate),
            "pruning_delta": error_metrics(dense_dequantized, estimate),
            "vdots": structured_vdots,
            "vdot_reduction": 1.0 - structured_vdots / dense_vdots,
            "combined_zero_activation_vdots": combined_vdots,
            "combined_vdot_reduction": 1.0 - combined_vdots / dense_vdots,
            "payload_reads": structured_input_reads + structured_weight_reads,
            "payload_reads_saved": (
                dense_input_reads + dense_weight_reads
                - structured_input_reads - structured_weight_reads
            ),
        }

    per_image = []
    offset = 0
    for path, count in zip(image_paths, token_counts):
        image_slice = slice(offset, offset + count)
        per_image.append(
            {
                "name": path.name,
                "sha256": sha256(path),
                "tokens": count,
                "error": {
                    "dense": error_metrics(reference[image_slice], dense_dequantized[image_slice]),
                    **{
                        name: error_metrics(reference[image_slice], estimate[image_slice])
                        for name, estimate in policy_estimates.items()
                    },
                },
            }
        )
        offset += count

    return {
        "schema": "sap-vpu-tinyvit-fc2-sparsity-study-v3",
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
            "fc2_input_channels": FC2_INPUT_CHANNELS,
            "fc2_output_channels": FC2_OUTPUT_CHANNELS,
        },
        "quantization": {
            "scheme": "dataset-calibrated-symmetric-int8",
            "gelu_scale": gelu_scale,
            "fc2_weight_scale": fc2_weight_scale,
        },
        "baseline": {
            "error": error_metrics(reference, dense_dequantized),
            "dense_vdots": dense_vdots,
            "dense_payload_reads": dense_input_reads + dense_weight_reads,
        },
        "activation_sparsity": {
            "natural_zero_activation_groups": int((~activation_nonzero).sum()),
            "activation_groups": int(activation_nonzero.numel()),
            "potential_activation_reads_saved": int((~activation_nonzero).sum()),
        },
        "group_lanes": 4,
        "policies": policies,
        "images": per_image,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path, nargs="?")
    parser.add_argument("image_dir", type=Path, nargs="?")
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            if args.checkpoint or args.image_dir or args.output:
                parser.error("--self-test does not accept paths")
            self_test()
            return 0
        if not args.checkpoint or not args.image_dir or not args.output:
            parser.error("checkpoint, image_dir, and output are required")
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
    print(f"dense error: {result['baseline']['error']}")
    for name, policy in result["policies"].items():
        print(
            f"{name}: sparsity={policy['weight_group_sparsity']:.4f}, "
            f"mean_abs={policy['error']['mean_abs']:.6f}, "
            f"nrmse={policy['error']['nrmse']:.6f}, "
            f"read_saved={policy['payload_reads_saved']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
