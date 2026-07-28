#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PT_SHELL="${PT_SHELL:-pt_shell}"
DESIGN_NAME="${DESIGN_NAME:-sap_vpu_subsystem}"
STD_CELL_DB="${STD_CELL_DB:-}"
PROCESS_CORNER="${PROCESS_CORNER:-unknown}"
NETLIST_FILE="${NETLIST_FILE:-$ROOT_DIR/netlist/dc/tsmc28/vpu_subsystem/${DESIGN_NAME}.v}"
SDC_FILE="${SDC_FILE:-$ROOT_DIR/netlist/dc/tsmc28/vpu_subsystem/${DESIGN_NAME}.sdc}"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/reports/pt/tsmc28/vpu_subsystem}"
SAIF_FILE="${SAIF_FILE:-}"
SAIF_STRIP_PATH="${SAIF_STRIP_PATH:-}"

if [[ "$PT_SHELL" == */* ]]; then
  test -x "$PT_SHELL"
else
  command -v "$PT_SHELL" >/dev/null
fi
test -s "$STD_CELL_DB"
test -s "$NETLIST_FILE"
test -s "$SDC_FILE"
mkdir -p "$REPORT_DIR"

(
  cd "$REPORT_DIR"
  DESIGN_NAME="$DESIGN_NAME" \
    STD_CELL_DB="$STD_CELL_DB" \
    PROCESS_CORNER="$PROCESS_CORNER" \
    NETLIST_FILE="$NETLIST_FILE" \
    SDC_FILE="$SDC_FILE" \
    REPORT_DIR="$REPORT_DIR" \
    SAIF_FILE="$SAIF_FILE" \
    SAIF_STRIP_PATH="$SAIF_STRIP_PATH" \
    "$PT_SHELL" -f "$ROOT_DIR/scripts/pt_vpu_analyze.tcl" | tee pt.log
)
