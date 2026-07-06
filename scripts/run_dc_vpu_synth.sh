#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SYNOPSYS_ENV_FILE="${SYNOPSYS_ENV_FILE:-}"
DC_HOME="${DC_HOME:-/opt/synopsys/syn/L-2016.03-SP1}"
DC_SHELL="${DC_SHELL:-$DC_HOME/bin/dc_shell}"
SNPS_LICENSE="${SNPS_LICENSE:-27000@localhost}"

TSMC28_ROOT="${TSMC28_ROOT:-/opt/pdk/tsmc28hpcplus/tcbn28hpcplusbwp7t40p140_180b}"
TSMC28_NLDM_DIR="${TSMC28_NLDM_DIR:-$TSMC28_ROOT/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp7t40p140_180a}"
TSMC28_DB="${TSMC28_DB:-$TSMC28_NLDM_DIR/tcbn28hpcplusbwp7t40p140tt0p9v85c.db}"
TSMC28_CORNER="${TSMC28_CORNER:-tt0p9v85c}"

CLOCK_PERIOD="${CLOCK_PERIOD:-10.0}"
CLOCK_UNCERTAINTY="${CLOCK_UNCERTAINTY:-0.20}"
INPUT_DELAY="${INPUT_DELAY:-1.0}"
OUTPUT_DELAY="${OUTPUT_DELAY:-1.0}"
COMPILE_ULTRA="${COMPILE_ULTRA:-1}"
MAP_EFFORT="${MAP_EFFORT:-medium}"
AREA_EFFORT="${AREA_EFFORT:-none}"
EXACT_MAP="${EXACT_MAP:-0}"
USE_DW="${USE_DW:-1}"

WORK_DIR="${WORK_DIR:-$ROOT_DIR/work/dc/tsmc28/vpu_core}"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/reports/dc/tsmc28/vpu_core}"
NETLIST_DIR="${NETLIST_DIR:-$ROOT_DIR/netlist/dc/tsmc28/vpu_core}"

test -x "$DC_SHELL" || {
  echo "Design Compiler not executable: $DC_SHELL" >&2
  exit 4
}

test -s "$TSMC28_DB" || {
  echo "TSMC28 DB not found: $TSMC28_DB" >&2
  echo "Set TSMC28_DB to a valid compiled TSMC28 .db file." >&2
  exit 6
}

mkdir -p "$WORK_DIR" "$REPORT_DIR" "$NETLIST_DIR"

(
  cd "$ROOT_DIR"
  if [[ -n "$SYNOPSYS_ENV_FILE" && -f "$SYNOPSYS_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SYNOPSYS_ENV_FILE" >/dev/null 2>&1
  fi
  export LM_LICENSE_FILE="${LM_LICENSE_FILE:-$SNPS_LICENSE}"
  export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-$SNPS_LICENSE}"

  REPO_ROOT="$ROOT_DIR" \
    DESIGN_NAME="sap_vpu_core" \
    STD_CELL_DB="$TSMC28_DB" \
    TSMC28_CORNER="$TSMC28_CORNER" \
    WORK_DIR="$WORK_DIR" \
    REPORT_DIR="$REPORT_DIR" \
    NETLIST_DIR="$NETLIST_DIR" \
    CLOCK_PERIOD="$CLOCK_PERIOD" \
    CLOCK_UNCERTAINTY="$CLOCK_UNCERTAINTY" \
    INPUT_DELAY="$INPUT_DELAY" \
    OUTPUT_DELAY="$OUTPUT_DELAY" \
    COMPILE_ULTRA="$COMPILE_ULTRA" \
    MAP_EFFORT="$MAP_EFFORT" \
    AREA_EFFORT="$AREA_EFFORT" \
    EXACT_MAP="$EXACT_MAP" \
    USE_DW="$USE_DW" \
    "$DC_SHELL" -64bit -f scripts/dc_vpu_synth.tcl | tee "$WORK_DIR/dc.log"
)
