#!/usr/bin/env python3
"""Check the host aggregation of independently run TinyViT FC2 windows."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from prepare_tinyvit_fc1_k128 import fc2_structured_window_outputs


RESULT_RE = re.compile(
    r"^TinyViT FC2 window (\d+): (-?\d+) (-?\d+) (-?\d+) (-?\d+)$",
    re.MULTILINE,
)
SPARSE_RESULT_RE = re.compile(
    r"^TinyViT FC2 sparse window (\d+): (-?\d+) (-?\d+) (-?\d+) (-?\d+)$",
    re.MULTILINE,
)


def parse_window_result(path: Path) -> tuple[int, list[int], list[int]]:
    matches = RESULT_RE.findall(path.read_text(encoding="utf-8"))
    sparse_matches = SPARSE_RESULT_RE.findall(path.read_text(encoding="utf-8"))
    if len(matches) != 1:
        raise ValueError(f"{path}: expected one FC2 window result, found {len(matches)}")
    if len(sparse_matches) != 1:
        raise ValueError(f"{path}: expected one sparse FC2 window result, found {len(sparse_matches)}")
    window, *values = matches[0]
    sparse_window, *sparse_values = sparse_matches[0]
    if sparse_window != window:
        raise ValueError(f"{path}: dense and sparse window ids differ")
    return int(window), [int(value) for value in values], [int(value) for value in sparse_values]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()

    parsed = [parse_window_result(path) for path in args.logs]
    results = {window: values for window, values, _ in parsed}
    sparse_results = {window: values for window, _, values in parsed}
    expected_windows = set(range(len(args.logs)))
    if set(results) != expected_windows:
        raise ValueError(f"expected windows {sorted(expected_windows)}, found {sorted(results)}")

    actual = [sum(results[window][index] for window in expected_windows) for index in range(4)]
    fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    expected_matrix = fixture["fc1_k128"]["fc2_partial"]["expected_integer_output"]
    expected = [value for row in expected_matrix for value in row]
    if len(expected) != 4 or any(not isinstance(value, int) for value in expected):
        raise ValueError("fixture FC2 expected output must be a 2x2 integer matrix")
    if actual != expected:
        raise ValueError(f"FC2 aggregate mismatch: expected {expected}, got {actual}")

    fc1 = fixture["fc1_k128"]
    sparse_windows = fc2_structured_window_outputs(
        fc1["software_postprocess"]["expected_gelu_int8"],
        fc1["fc2_partial"]["weights"],
    )
    expected_sparse = [
        sum(sparse_windows[window][token][output] for window in expected_windows)
        for token in range(2)
        for output in range(2)
    ]
    actual_sparse = [
        sum(sparse_results[window][index] for window in expected_windows) for index in range(4)
    ]
    if actual_sparse != expected_sparse:
        raise ValueError(f"sparse FC2 aggregate mismatch: expected {expected_sparse}, got {actual_sparse}")

    print(f"TinyViT FC2 aggregate: {[actual[:2], actual[2:]]}")
    print(f"TinyViT FC2 structured sparse aggregate: {[actual_sparse[:2], actual_sparse[2:]]}")


if __name__ == "__main__":
    main()
