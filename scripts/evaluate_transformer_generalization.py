#!/usr/bin/env python3
"""Build SAP-VPU Transformer fixtures or evaluate labeled Imagenette images."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any

from evaluate_tinyvit_fc2_sparsity import apply_group_valid, policy_group_valid
from export_tinyvit_activation_fixture import round_ties_away, sha256


DATASET_URL = "https://s3.amazonaws.com/fast-ai-imageclas/imagenette2-160.tgz"
POLICIES = ("layer_global_l1_12.5", "layer_l1_budget_5")
GROUP_LANES = 4
IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png"}
MODEL_SPECS = (
    {
        "name": "tinyvit_5m",
        "timm_model": "tiny_vit_5m_224",
        "model_id": "timm/tiny_vit_5m_224.dist_in22k_ft_in1k",
        "layer": "stages.1.blocks.0.mlp.fc2",
    },
    {
        "name": "deit_tiny",
        "timm_model": "deit_tiny_patch16_224",
        "model_id": "timm/deit_tiny_patch16_224.fb_in1k",
        "layer": "blocks.5.mlp.fc1",
    },
)


def resolve_module(model: Any, path: str) -> Any:
    current = model
    for part in path.split("."):
        current = current[int(part)] if part.isdigit() else getattr(current, part)
    return current


def quantize_symmetric(tensor: Any, bits: int) -> tuple[Any, float]:
    import torch

    qmax = (1 << (bits - 1)) - 1
    maximum = float(tensor.abs().max())
    if qmax <= 0 or not math.isfinite(maximum) or maximum == 0:
        raise ValueError(f"cannot quantize nonzero tensor to INT{bits}")
    scale = maximum / qmax
    values = round_ties_away(tensor / scale).clamp(-qmax, qmax).to(torch.int32)
    return values, scale


def classification_metrics(logits: Any, labels: Any, reference: Any | None = None) -> dict[str, Any]:
    import torch

    top1 = logits.argmax(1)
    top5 = logits.topk(5, dim=1).indices
    result = {
        "images": int(labels.numel()),
        "top1_correct": int((top1 == labels).sum()),
        "top1_accuracy": float((top1 == labels).to(torch.float32).mean()),
        "top5_correct": int((top5 == labels.unsqueeze(1)).any(1).sum()),
        "top5_accuracy": float((top5 == labels.unsqueeze(1)).any(1).to(torch.float32).mean()),
    }
    if reference is not None:
        reference_top1 = reference.argmax(1)
        result["float_top1_agreement"] = float(
            (top1 == reference_top1).to(torch.float32).mean()
        )
    return result


def select_images(dataset_root: Path, images_per_class: int, timm: Any) -> tuple[list[Path], Any, dict[str, int]]:
    import torch

    validation_root = dataset_root / "val" if (dataset_root / "val").is_dir() else dataset_root
    synset_file = Path(timm.__file__).parent / "data" / "_info" / "imagenet_synsets.txt"
    synsets = synset_file.read_text(encoding="ascii").splitlines()
    synset_to_index = {synset: index for index, synset in enumerate(synsets)}
    class_dirs = sorted(path for path in validation_root.iterdir() if path.is_dir())
    if len(class_dirs) != 10:
        raise ValueError(f"expected 10 Imagenette classes, found {len(class_dirs)}")

    paths: list[Path] = []
    labels: list[int] = []
    class_map: dict[str, int] = {}
    for class_dir in class_dirs:
        if class_dir.name not in synset_to_index:
            raise ValueError(f"unknown ImageNet synset: {class_dir.name}")
        candidates = sorted(
            (path for path in class_dir.iterdir() if path.is_file()),
            key=lambda path: hashlib.sha256(path.name.encode("ascii")).hexdigest(),
        )
        selected = candidates if images_per_class == 0 else candidates[:images_per_class]
        if not selected:
            raise ValueError(f"no images selected from {class_dir}")
        label = synset_to_index[class_dir.name]
        class_map[class_dir.name] = label
        paths.extend(selected)
        labels.extend([label] * len(selected))
    return paths, torch.tensor(labels, dtype=torch.long), class_map


def load_inputs(paths: list[Path], transform: Any) -> list[Any]:
    from PIL import Image

    tensors = []
    for path in paths:
        with Image.open(path) as image:
            tensors.append(transform(image.convert("RGB")))
    return tensors


def select_fixture_images(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if not path.is_dir():
        raise ValueError(f"fixture input does not exist: {path}")
    paths = sorted(
        candidate
        for candidate in path.rglob("*")
        if candidate.is_file() and candidate.suffix.lower() in IMAGE_SUFFIXES
    )
    if not paths:
        raise ValueError(f"fixture directory contains no supported images: {path}")
    return paths


def run_logits(model: Any, inputs: list[Any], batch_size: int) -> Any:
    import torch

    logits = []
    with torch.inference_mode():
        for offset in range(0, len(inputs), batch_size):
            logits.append(model(torch.stack(inputs[offset : offset + batch_size])).detach().cpu())
    return torch.cat(logits)


def pair_masks(valid: Any) -> list[int]:
    masks = []
    for chunk in range(valid.shape[1] // 2):
        masks.append(
            int(valid[0, 2 * chunk])
            | (int(valid[0, 2 * chunk + 1]) << 1)
            | (int(valid[1, 2 * chunk]) << 2)
            | (int(valid[1, 2 * chunk + 1]) << 3)
        )
    return masks


def representative_output_pairs(
    output_channels: int, pair_count: int = 4
) -> list[tuple[int, int]]:
    available_pairs = output_channels // 2
    if output_channels < 8 or output_channels % 2 or not 2 <= pair_count <= available_pairs:
        raise ValueError("output pairs require an even layer with at least four outputs")
    starts = [
        2 * round(index * (available_pairs - 1) / (pair_count - 1))
        for index in range(pair_count)
    ]
    if len(set(starts)) != pair_count:
        raise ValueError("representative output pairs are not unique")
    return [(start, start + 1) for start in starts]


def build_fixture(
    spec: dict[str, str], activation: Any, input_scale: float, weight: Any, weight_scale: float,
    output_pair_count: int = 4,
) -> dict[str, Any]:
    import torch

    input_int8 = round_ties_away(activation / input_scale).clamp(-127, 127).to(torch.int32)
    weight_int8 = round_ties_away(weight / weight_scale).clamp(-127, 127).to(torch.int32)
    output_pairs = representative_output_pairs(weight_int8.shape[0], output_pair_count)
    pair_weights = [weight_int8[list(pair)] for pair in output_pairs]
    fixture = {
        "schema": "sap-vpu-transformer-linear-int8-v1",
        "model": spec["model_id"],
        "layer": spec["layer"],
        "group_lanes": GROUP_LANES,
        "input_tokens": input_int8.tolist(),
        "weights": weight_int8[:2].tolist(),
        "expected_integer_output": (input_int8 @ weight_int8[:2].T).tolist(),
        "policies": {},
        "representative_pairs": {
            "output_pairs": [list(pair) for pair in output_pairs],
            "weights": [values.tolist() for values in pair_weights],
            "expected_integer_output": [
                (input_int8 @ values.T).tolist() for values in pair_weights
            ],
            "policies": {},
        },
    }
    for policy in POLICIES:
        valid = policy_group_valid(weight_int8, policy)
        sparse_pair = apply_group_valid(weight_int8[:2], valid[:2])
        fixture["policies"][policy] = {
            "masks": pair_masks(valid[:2]),
            "expected_integer_output": (input_int8 @ sparse_pair.T).tolist(),
        }
        representative = fixture["representative_pairs"]["policies"]
        representative[policy] = {
            "masks": [pair_masks(valid[list(pair)]) for pair in output_pairs],
            "expected_integer_output": [
                (input_int8 @ apply_group_valid(values, valid[list(pair)]).T).tolist()
                for pair, values in zip(output_pairs, pair_weights)
            ],
        }
    return fixture


def evaluate_model(
    spec: dict[str, str], checkpoint: Path, paths: list[Path], labels: Any, batch_size: int,
    fixture_only: bool = False, output_pair_count: int = 4,
    fixture_tokens_per_image: int = 2,
) -> dict[str, Any]:
    import PIL
    import safetensors
    import timm
    import torch
    import torchvision
    from safetensors.torch import load_file
    from timm.data import create_transform, resolve_model_data_config

    model = timm.create_model(spec["timm_model"], pretrained=False, num_classes=1000)
    if checkpoint.suffix == ".safetensors":
        state = load_file(str(checkpoint))
    elif checkpoint.suffix in (".pth", ".pt"):
        raw = torch.load(checkpoint, map_location="cpu", weights_only=True)
        state = raw.get("model", raw)
    else:
        raise ValueError(f"unsupported checkpoint format: {checkpoint.suffix}")
    model.load_state_dict(state)
    model.eval()
    layer = resolve_module(model, spec["layer"])
    if not isinstance(layer, torch.nn.Linear):
        raise ValueError(f"{spec['layer']} is not a Linear layer")
    if layer.in_features % 8 or layer.out_features % 2:
        raise ValueError("selected layer shape is incompatible with SAP-VPU K8/output-pair tiling")

    transform = create_transform(**resolve_model_data_config(model), is_training=False)
    inputs = load_inputs(paths, transform)
    activation_max = 0.0
    token_samples = 0
    fixture_activations = []

    def calibrate(_module: Any, values: tuple[Any, ...], _output: Any) -> None:
        nonlocal activation_max, token_samples
        activation = values[0].detach()
        activation_max = max(activation_max, float(activation.abs().max()))
        token_samples += activation.numel() // layer.in_features
        if fixture_only:
            per_image = activation.reshape(activation.shape[0], -1, layer.in_features)
            if per_image.shape[1] < fixture_tokens_per_image:
                raise ValueError(
                    f"requested {fixture_tokens_per_image} fixture tokens, layer has {per_image.shape[1]}"
                )
            fixture_activations.append(
                per_image[:, :fixture_tokens_per_image].reshape(-1, layer.in_features).cpu()
            )
        elif not fixture_activations:
            fixture_activations.append(activation.reshape(-1, layer.in_features)[:2].cpu())

    hook = layer.register_forward_hook(calibrate)
    try:
        float_logits = run_logits(model, inputs, batch_size)
    finally:
        hook.remove()
    if not fixture_activations or activation_max == 0:
        raise ValueError("selected layer produced no nonzero activation")
    fixture_activation = torch.cat(fixture_activations)

    weight_int8, weight_scale8 = quantize_symmetric(layer.weight.detach(), 8)
    result = {
        "provenance": {
            "model_id": spec["model_id"],
            "checkpoint_sha256": sha256(checkpoint),
            "layer": spec["layer"],
            "software_versions": {
                "torch": torch.__version__,
                "torchvision": torchvision.__version__,
                "timm": timm.__version__,
                "pillow": PIL.__version__,
                "safetensors": safetensors.__version__,
            },
        },
        "shape": {
            "input_channels": layer.in_features,
            "output_channels": layer.out_features,
            "token_samples": token_samples,
        },
        "boundary": "one-selected-linear-layer-emulated; remaining network is float",
        "fixture": build_fixture(
            spec, fixture_activation, activation_max / 127, layer.weight.detach(), weight_scale8,
            output_pair_count,
        ),
    }
    if fixture_only:
        return result

    variants: dict[str, dict[str, Any]] = {}
    quantized_weights: dict[int, tuple[Any, float]] = {8: (weight_int8, weight_scale8)}
    input_scales = {bits: activation_max / ((1 << (bits - 1)) - 1) for bits in (8, 4, 2)}
    for bits in (4, 2):
        quantized_weights[bits] = quantize_symmetric(layer.weight.detach(), bits)

    def run_variant(name: str, bits: int, weight_int: Any, weight_scale: float, active_groups: int) -> None:
        input_scale = input_scales[bits]

        def emulate(_module: Any, values: tuple[Any, ...], _output: Any) -> Any:
            input_int = round_ties_away(values[0] / input_scale).clamp(
                -((1 << (bits - 1)) - 1), (1 << (bits - 1)) - 1
            ).to(torch.int32)
            output = (input_int @ weight_int.T).to(torch.float32) * input_scale * weight_scale
            return output + layer.bias if layer.bias is not None else output

        variant_hook = layer.register_forward_hook(emulate)
        try:
            logits = run_logits(model, inputs, batch_size)
        finally:
            variant_hook.remove()
        lanes = 32 // bits
        dense_groups = layer.out_features * math.ceil(layer.in_features / lanes)
        variants[name] = {
            "precision_bits": bits,
            "classification": classification_metrics(logits, labels, float_logits),
            "active_weight_groups": active_groups,
            "weight_group_sparsity": 1.0 - active_groups / (layer.out_features * (layer.in_features // GROUP_LANES)),
            "estimated_vdots": token_samples * (active_groups if bits == 8 else dense_groups),
        }

    total_groups = layer.out_features * (layer.in_features // GROUP_LANES)
    for bits in (8, 4, 2):
        weight_int, weight_scale = quantized_weights[bits]
        run_variant(f"dense_int{bits}", bits, weight_int, weight_scale, total_groups)

    for policy in POLICIES:
        valid = policy_group_valid(weight_int8, policy)
        sparse_weight = apply_group_valid(weight_int8, valid)
        run_variant(policy, 8, sparse_weight, weight_scale8, int(valid.sum()))

    result["float"] = classification_metrics(float_logits, labels)
    result["variants"] = variants
    return result


def self_test() -> None:
    import torch

    values, scale = quantize_symmetric(torch.tensor([-2.0, 0.0, 2.0]), 4)
    assert values.tolist() == [-7, 0, 7]
    assert scale == 2.0 / 7.0
    labels = torch.tensor([1, 0])
    logits = torch.tensor([[0.0, 2.0, 1.0, 0.0, 0.0], [2.0, 1.0, 0.0, 0.0, 0.0]])
    assert classification_metrics(logits, labels)["top1_accuracy"] == 1.0
    valid = torch.tensor([[True, False, True, False], [False, True, False, True]])
    assert pair_masks(valid) == [0x9, 0x9]
    assert representative_output_pairs(128) == [(0, 1), (42, 43), (84, 85), (126, 127)]
    assert representative_output_pairs(768) == [(0, 1), (256, 257), (510, 511), (766, 767)]
    assert representative_output_pairs(768, 384) == [
        (channel, channel + 1) for channel in range(0, 768, 2)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tinyvit_checkpoint", type=Path, nargs="?")
    parser.add_argument("deit_checkpoint", type=Path, nargs="?")
    parser.add_argument("dataset_root", type=Path, nargs="?")
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--images-per-class", type=int, default=1)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--deit-output-pairs", type=int, default=4)
    parser.add_argument("--deit-tokens", type=int, default=2)
    parser.add_argument("--fixture-only", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        if not all((args.tinyvit_checkpoint, args.deit_checkpoint, args.dataset_root, args.output)):
            parser.error("checkpoints, dataset root, and output are required")
        if (
            args.images_per_class < 0
            or args.batch_size <= 0
            or not 2 <= args.deit_output_pairs <= 384
            or not 1 <= args.deit_tokens <= 197
        ):
            parser.error("invalid image count, batch size, DeiT pair count, or DeiT token count")
        checkpoints = (args.tinyvit_checkpoint, args.deit_checkpoint)
        if args.fixture_only:
            import torch

            paths = select_fixture_images(args.dataset_root)
            labels = torch.zeros(len(paths), dtype=torch.long)
            evaluated = {
                spec["name"]: evaluate_model(
                    spec, checkpoint, paths, labels, args.batch_size, fixture_only=True,
                    output_pair_count=args.deit_output_pairs if spec["name"] == "deit_tiny" else 4,
                    fixture_tokens_per_image=args.deit_tokens if spec["name"] == "deit_tiny" else 2,
                )
                for spec, checkpoint in zip(MODEL_SPECS, checkpoints)
            }
            models = {
                name: {
                    key: model[key]
                    for key in ("provenance", "shape", "boundary", "fixture")
                }
                for name, model in evaluated.items()
            }
            result: dict[str, Any] = {
                "schema": "sap-vpu-transformer-linear-fixtures-v1",
                "models": models,
            }
            if len(paths) == 1:
                result["source_image"] = {
                    "path": str(paths[0]),
                    "sha256": sha256(paths[0]),
                    "label_status": "unlabeled; classification metrics intentionally omitted",
                }
            else:
                result["source_images"] = {
                    "root": str(args.dataset_root),
                    "count": len(paths),
                    "fixture_tokens_per_image": {
                        "tinyvit_5m": 2,
                        "deit_tiny": args.deit_tokens,
                    },
                    "label_status": "unlabeled; classification metrics intentionally omitted",
                    "files": [
                        {
                            "path": str(path.relative_to(args.dataset_root)),
                            "sha256": sha256(path),
                        }
                        for path in paths
                    ],
                }
        else:
            import timm

            paths, labels, class_map = select_images(args.dataset_root, args.images_per_class, timm)
            models = {
                spec["name"]: evaluate_model(
                    spec, checkpoint, paths, labels, args.batch_size,
                    output_pair_count=args.deit_output_pairs if spec["name"] == "deit_tiny" else 4,
                )
                for spec, checkpoint in zip(MODEL_SPECS, checkpoints)
            }
            result = {
                "schema": "sap-vpu-transformer-generalization-v1",
                "dataset": {
                    "name": "Imagenette-160 validation",
                    "source": DATASET_URL,
                    "images_per_class": args.images_per_class,
                    "images": len(paths),
                    "class_to_imagenet_index": class_map,
                    "selection": "sha256(relative filename), ascending",
                    "files": [
                        {"path": str(path.relative_to(args.dataset_root)), "sha256": sha256(path)}
                        for path in paths
                    ],
                },
                "models": models,
            }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="ascii")
    except (ImportError, OSError, RuntimeError, ValueError) as exc:
        print(f"Transformer generalization failed: {exc}", file=sys.stderr)
        return 1
    if args.fixture_only:
        print(f"Transformer fixtures: {len(paths)} image(s) -> {args.output}")
        for name, model in models.items():
            shape = model["shape"]
            print(
                f"{name}: K={shape['input_channels']}, N={shape['output_channels']}, "
                f"tokens={shape['token_samples']}"
            )
        return 0

    print(f"Transformer generalization: {len(paths)} labeled images -> {args.output}")
    for name, model in models.items():
        print(f"{name}: float top1={model['float']['top1_accuracy']:.3f}")
        for variant, metrics in model["variants"].items():
            classification = metrics["classification"]
            print(
                f"  {variant}: top1={classification['top1_accuracy']:.3f}, "
                f"agreement={classification['float_top1_agreement']:.3f}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
