#!/usr/bin/env python3
"""Check that documented SAP-VPU custom-0 encodings stay synchronized."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "sw" / "baremetal" / "sap_vpu_custom.h"

EXPECTED = {
    "SAP_OPCODE_CUSTOM0": "0x0b",
    "SAP_FUNCT7_VSET": "0x09",
    "SAP_FUNCT7_VMOV": "0x09",
    "SAP_FUNCT7_VDOT": "0x10",
    "SAP_FUNCT7_VSETPREC": "0x18",
    "SAP_FUNCT7_VSETSPARSE_BMP": "0x1c",
    "SAP_FUNCT7_VREADCNT": "0x1a",
    "SAP_FUNCT7_VCLEARCNT": "0x1d",
    "SAP_FUNCT7_VSETLANE": "0x1b",
    "SAP_FUNCT7_VTLOAD": "0x20",
    "SAP_FUNCT7_VTSTART": "0x21",
    "SAP_FUNCT7_VTREAD": "0x22",
    "SAP_FUNCT7_VTDMA": "0x23",
    "SAP_FUNCT7_VTSTORE": "0x24",
}


def read_macros():
    text = HEADER.read_text(encoding="utf-8")
    macros = {}
    for name, value in re.findall(r"#define\s+(SAP_[A-Z0-9_]+)\s+\(?([x0-9a-fA-F]+)u?\)?", text):
        macros[name] = value.lower()
    return macros


def main():
    macros = read_macros()
    missing = sorted(set(EXPECTED) - set(macros))
    assert not missing, f"missing macros: {', '.join(missing)}"
    for name, value in EXPECTED.items():
        assert macros[name] == value, f"{name}: expected {value}, got {macros[name]}"


if __name__ == "__main__":
    main()
