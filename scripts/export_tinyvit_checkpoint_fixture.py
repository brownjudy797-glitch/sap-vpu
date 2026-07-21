#!/usr/bin/env python3
"""Export a fixed TinyViT MLP weight slice from an F32 SafeTensors checkpoint."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile
from typing import Any


MODEL_ID = "timm/tiny_vit_5m_224.dist_in22k_ft_in1k"
LAYER_ID = "stages.1.blocks.0.mlp"
SOURCE_URL = f"https://huggingface.co/{MODEL_ID}/resolve/main/model.safetensors"
FC1_NAME = f"{LAYER_ID}.fc1.weight"
FC2_NAME = f"{LAYER_ID}.fc2.weight"


def read_f32_matrix(checkpoint: Path, name: str) -> list[list[float]]:
    file_size = checkpoint.stat().st_size
    with checkpoint.open("rb") as stream:
        header_size_raw = stream.read(8)
        if len(header_size_raw) != 8:
            raise ValueError("checkpoint is too short for a SafeTensors header")
        header_size = struct.unpack("<Q", header_size_raw)[0]
        if header_size > file_size - 8:
            raise ValueError("SafeTensors header exceeds checkpoint size")
        header = json.loads(stream.read(header_size))
        if not isinstance(header, dict):
            raise ValueError("SafeTensors header must be an object")
        tensor = header.get(name)
        if not isinstance(tensor, dict):
            raise ValueError(f"missing tensor {name!r}")
        shape = tensor.get("shape")
        offsets = tensor.get("data_offsets")
        if tensor.get("dtype") != "F32" or not isinstance(shape, list) or len(shape) != 2:
            raise ValueError(f"tensor {name!r} must be a two-dimensional F32 matrix")
        if not isinstance(offsets, list) or len(offsets) != 2:
            raise ValueError(f"tensor {name!r} has invalid data offsets")
        rows, columns = shape
        start, end = offsets
        if not all(isinstance(value, int) and not isinstance(value, bool) for value in (rows, columns, start, end)):
            raise ValueError(f"tensor {name!r} has invalid shape or offsets")
        if rows <= 0 or columns <= 0 or start < 0 or end < start:
            raise ValueError(f"tensor {name!r} has invalid shape or offsets")
        expected_bytes = rows * columns * 4
        if end - start != expected_bytes or 8 + header_size + end > file_size:
            raise ValueError(f"tensor {name!r} byte range does not match its shape")
        stream.seek(8 + header_size + start)
        values = struct.unpack(f"<{rows * columns}f", stream.read(expected_bytes))
    return [list(values[row * columns : (row + 1) * columns]) for row in range(rows)]


def quantize_symmetric(matrix: list[list[float]]) -> tuple[list[list[int]], float]:
    maximum = max(abs(value) for row in matrix for value in row)
    if not math.isfinite(maximum) or maximum == 0:
        raise ValueError("selected weight slice must contain finite nonzero values")
    scale = maximum / 127.0

    def quantize(value: float) -> int:
        magnitude = math.floor(abs(value) / scale + 0.5)
        return max(-127, min(127, -magnitude if value < 0 else magnitude))

    return [[quantize(value) for value in row] for row in matrix], scale


def checkpoint_sha256(checkpoint: Path) -> str:
    digest = hashlib.sha256()
    with checkpoint.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_fixture(checkpoint: Path) -> dict[str, Any]:
    fc1 = read_f32_matrix(checkpoint, FC1_NAME)
    fc2 = read_f32_matrix(checkpoint, FC2_NAME)
    if len(fc1) < 4 or len(fc1[0]) < 4 or len(fc2) < 2 or len(fc2[0]) < 4:
        raise ValueError("checkpoint MLP tensors are smaller than the 2x4x4x2 fixture")
    fc1_slice, fc1_scale = quantize_symmetric([row[:4] for row in fc1[:4]])
    fc2_slice, fc2_scale = quantize_symmetric([row[:4] for row in fc2[:2]])
    return {
        "schema": "sap-vpu-tinyvit-mlp2-int8-v1",
        "provenance": {
            "kind": "checkpoint",
            "model_id": MODEL_ID,
            "layer_id": LAYER_ID,
            "checkpoint_sha256": checkpoint_sha256(checkpoint),
            "checkpoint_source_url": SOURCE_URL,
            "input_source": "deterministic-int8-basis-probe-not-model-activation",
            "tensor_slices": {
                "fc1_weights": f"{FC1_NAME}[0:4,0:4]",
                "fc2_weights": f"{FC2_NAME}[0:2,0:4]",
            },
        },
        "quantization": {
            "scheme": "symmetric-int8",
            "input_scale": 1.0,
            "fc1_weight_scale": fc1_scale,
            "fc2_weight_scale": fc2_scale,
            "input_zero_point": 0,
            "fc1_weight_zero_point": 0,
            "fc2_weight_zero_point": 0,
            "weight_scope": "selected-slice-max-abs",
            "rounding": "nearest-ties-away-from-zero",
        },
        "input_tokens": [[1, 0, 0, 0], [0, 1, 0, 0]],
        "fc1_weights": fc1_slice,
        "fc2_weights": fc2_slice,
    }


def write_test_checkpoint(path: Path) -> None:
    tensors = {
        FC1_NAME: ([4, 4], [float(value) for value in range(-8, 8)]),
        FC2_NAME: ([2, 4], [0.5, -0.5, 1.0, -1.0, 0.25, -0.25, 0.75, -0.75]),
    }
    header: dict[str, Any] = {}
    payload = bytearray()
    for name, (shape, values) in tensors.items():
        start = len(payload)
        payload.extend(struct.pack(f"<{len(values)}f", *values))
        header[name] = {"dtype": "F32", "shape": shape, "data_offsets": [start, len(payload)]}
    encoded_header = json.dumps(header, separators=(",", ":")).encode("utf-8")
    path.write_bytes(struct.pack("<Q", len(encoded_header)) + encoded_header + payload)


def self_test() -> None:
    with tempfile.TemporaryDirectory() as directory:
        checkpoint = Path(directory) / "model.safetensors"
        write_test_checkpoint(checkpoint)
        fixture = build_fixture(checkpoint)
        assert fixture["input_tokens"] == [[1, 0, 0, 0], [0, 1, 0, 0]]
        assert fixture["fc1_weights"][0] == [-127, -111, -95, -79]
        assert fixture["fc2_weights"][0] == [64, -64, 127, -127]
        assert len(fixture["provenance"]["checkpoint_sha256"]) == 64


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path, nargs="?")
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        if args.checkpoint or args.output:
            parser.error("--self-test does not accept paths")
        self_test()
        return 0
    if not args.checkpoint or not args.output:
        parser.error("checkpoint and output paths are required")
    try:
        fixture = build_fixture(args.checkpoint)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n", encoding="ascii")
    except (OSError, json.JSONDecodeError, ValueError, struct.error) as exc:
        print(f"TinyViT checkpoint export failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
