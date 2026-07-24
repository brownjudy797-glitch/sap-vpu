#!/usr/bin/env python3
"""Check the host aggregation of independently run TinyViT FC2 windows."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from prepare_tinyvit_fc1_k128 import fc2_lowest_l1_group_masks, fc2_masked_window_outputs


RESULT_RE = re.compile(
    r"^TinyViT FC2 window (\d+): (-?\d+) (-?\d+) (-?\d+) (-?\d+)$",
    re.MULTILINE,
)
GLOBAL_RESULT_RE = re.compile(
    r"^TinyViT FC2 global-l1-6p25 window (\d+): (-?\d+) (-?\d+) (-?\d+) (-?\d+)$",
    re.MULTILINE,
)
BUDGET_RESULT_RE = re.compile(
    r"^TinyViT FC2 l1-budget-2pct window (\d+): (-?\d+) (-?\d+) (-?\d+) (-?\d+)$",
    re.MULTILINE,
)


def parse_window_result(path: Path) -> tuple[int, list[int], list[int], list[int]]:
    text = path.read_text(encoding="utf-8")
    matches = [pattern.findall(text) for pattern in (RESULT_RE, GLOBAL_RESULT_RE, BUDGET_RESULT_RE)]
    if any(len(result) != 1 for result in matches):
        raise ValueError(f"{path}: expected one dense and two policy FC2 results")
    windows = [result[0][0] for result in matches]
    if len(set(windows)) != 1:
        raise ValueError(f"{path}: dense and policy window ids differ")
    return (int(windows[0]), *([int(value) for value in result[0][1:]] for result in matches))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()

    parsed = [parse_window_result(path) for path in args.logs]
    results = {window: values for window, values, _, _ in parsed}
    global_results = {window: values for window, _, values, _ in parsed}
    budget_results = {window: values for window, _, _, values in parsed}
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
    gelu = fc1["software_postprocess"]["expected_gelu_int8"]
    weights = fc1["fc2_partial"]["weights"]
    policy_results = {
        "global_l1_6p25": (
            global_results,
            fc2_lowest_l1_group_masks(weights, drop_count=4),
        ),
        "l1_budget_2pct": (
            budget_results,
            fc2_lowest_l1_group_masks(weights, l1_budget=0.02),
        ),
    }
    aggregates = {}
    for name, (measured, masks) in policy_results.items():
        expected_policy_windows = fc2_masked_window_outputs(gelu, weights, masks)
        expected_policy = [
            sum(expected_policy_windows[window][token][output] for window in expected_windows)
            for token in range(2)
            for output in range(2)
        ]
        aggregates[name] = [
            sum(measured[window][index] for window in expected_windows) for index in range(4)
        ]
        if aggregates[name] != expected_policy:
            raise ValueError(
                f"{name} aggregate mismatch: expected {expected_policy}, got {aggregates[name]}"
            )

    print(f"TinyViT FC2 aggregate: {[actual[:2], actual[2:]]}")
    for name, aggregate in aggregates.items():
        print(f"TinyViT FC2 {name} aggregate: {[aggregate[:2], aggregate[2:]]}")


if __name__ == "__main__":
    main()
