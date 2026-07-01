#!/usr/bin/env python3
"""Convert a little-endian binary image to one 32-bit Verilog hex word per line."""

from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: bin_to_verilog_hex.py <input.bin> <output.hex>", file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    data = src.read_bytes()
    if len(data) % 4:
        data += bytes(4 - (len(data) % 4))

    dst.parent.mkdir(parents=True, exist_ok=True)
    with dst.open("w", encoding="ascii") as f:
        for idx in range(0, len(data), 4):
            f.write(f"{int.from_bytes(data[idx:idx + 4], 'little'):08x}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
