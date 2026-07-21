#!/usr/bin/env python3
"""Check the host aggregation of independently run TinyViT FC2 windows."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


RESULT_RE = re.compile(
    r"^TinyViT FC2 window (\d+): (-?\d+) (-?\d+) (-?\d+) (-?\d+)$",
    re.MULTILINE,
)


def parse_window_result(path: Path) -> tuple[int, list[int]]:
    matches = RESULT_RE.findall(path.read_text(encoding="utf-8"))
    if len(matches) != 1:
        raise ValueError(f"{path}: expected one FC2 window result, found {len(matches)}")
    window, *values = matches[0]
    return int(window), [int(value) for value in values]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("logs", nargs=2, type=Path)
    args = parser.parse_args()

    results = dict(parse_window_result(path) for path in args.logs)
    if set(results) != {0, 1}:
        raise ValueError(f"expected windows 0 and 1, found {sorted(results)}")

    actual = [left + right for left, right in zip(results[0], results[1])]
    fixture = json.loads(args.fixture.read_text(encoding="utf-8"))
    expected_matrix = fixture["fc1_k128"]["fc2_partial"]["expected_integer_output"]
    expected = [value for row in expected_matrix for value in row]
    if len(expected) != 4 or any(not isinstance(value, int) for value in expected):
        raise ValueError("fixture FC2 expected output must be a 2x2 integer matrix")
    if actual != expected:
        raise ValueError(f"FC2 aggregate mismatch: expected {expected}, got {actual}")

    print(f"TinyViT FC2 aggregate: {[actual[:2], actual[2:]]}")


if __name__ == "__main__":
    main()
