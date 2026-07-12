#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERILATOR="${VERILATOR:-verilator}"
VERILATOR_CXX="${VERILATOR_CXX:-clang++-12}"
VERILATOR_TIMING_CFLAGS="${VERILATOR_TIMING_CFLAGS:--std=c++20 -O0 -Wno-unknown-warning-option}"
VERILATOR_TIMING_LDFLAGS="${VERILATOR_TIMING_LDFLAGS:--no-pie}"
VCD2SAIF="${VCD2SAIF:-/opt/synopsys/syn/L-2016.03-SP1/bin/vcd2saif}"
DC_NETLIST_DIR="${DC_NETLIST_DIR:-$ROOT_DIR/netlist/dc/tsmc28/vpu_core_sliced_10ns_nopower}"
DC_POLICY_MATRIX_WORK_DIR="${DC_POLICY_MATRIX_WORK_DIR:-$ROOT_DIR/work/dc/tsmc28/vpu_policy_matrix}"
DC_POLICY_MATRIX_REPORT_DIR="${DC_POLICY_MATRIX_REPORT_DIR:-$ROOT_DIR/reports/dc/tsmc28/vpu_policy_matrix}"
DDC_FILE="$DC_NETLIST_DIR/sap_vpu_core.ddc"
SAIF_INSTANCE="sap_vpu_core_gate_tb/dut"
POLICIES=(
  dense_int8 static_int4 static_int2 adaptive_int4 adaptive_sparse75
  adaptive_unstructured no_sparse no_lane no_precision
)

test -x "$VCD2SAIF"
test -s "$DDC_FILE"
mkdir -p "$DC_POLICY_MATRIX_WORK_DIR" "$DC_POLICY_MATRIX_REPORT_DIR"

OBJ_DIR="$DC_POLICY_MATRIX_WORK_DIR/obj"
SIM_BIN="$OBJ_DIR/sap_vpu_core_gate_tb"
"$VERILATOR" --binary --timing --trace -sv -Wno-fatal \
  "$ROOT_DIR/rtl/sap_vpu_pkg.sv" \
  "$ROOT_DIR/rtl/sap_vpu_core.sv" \
  "$ROOT_DIR/tb/sap_vpu_core_gate_tb.sv" \
  --Mdir "$OBJ_DIR" \
  -MAKEFLAGS "CXX=$VERILATOR_CXX" \
  -CFLAGS "$VERILATOR_TIMING_CFLAGS" \
  -LDFLAGS "$VERILATOR_TIMING_LDFLAGS" \
  -o sap_vpu_core_gate_tb

CSV_FILE="$DC_POLICY_MATRIX_WORK_DIR/dc_vpu_policy_power_matrix.csv"
MD_FILE="$DC_POLICY_MATRIX_WORK_DIR/dc_vpu_policy_power_matrix.md"
printf '%s\n' 'policy,internal_uw,switching_uw,leakage_uw,dynamic_uw,total_uw,dynamic_pj_per_vdot,duration_ps,annotation_unmatched' > "$CSV_FILE"

expected_duration=""
expected_unmatched=""
for policy in "${POLICIES[@]}"; do
  policy_dir="$DC_POLICY_MATRIX_WORK_DIR/$policy"
  report_dir="$DC_POLICY_MATRIX_REPORT_DIR/$policy"
  vcd_file="$policy_dir/$policy.vcd"
  saif_file="$policy_dir/$policy.saif"
  sim_log="$policy_dir/sim.log"
  dc_work_dir="$policy_dir/dc"
  dc_log="$dc_work_dir/dc.log"
  power_report="$report_dir/power.rpt"
  mkdir -p "$policy_dir" "$report_dir"

  "$SIM_BIN" "+policy=$policy" "+vcd=$vcd_file" | tee "$sim_log"
  grep -q "GATE_POLICY_PASS: $policy" "$sim_log"
  ! grep -q 'GATE_.*_FAIL' "$sim_log"
  test -s "$vcd_file"

  "$VCD2SAIF" -input "$vcd_file" -output "$saif_file"
  test -s "$saif_file"
  grep -q '(TIMESCALE 1 ps)' "$saif_file"
  duration_ps="$(sed -n 's/^[[:space:]]*(DURATION[[:space:]]\+\([0-9][0-9]*\)).*/\1/p' "$saif_file" | head -n1)"
  test -n "$duration_ps"
  if [[ -z "$expected_duration" ]]; then
    expected_duration="$duration_ps"
  elif [[ "$duration_ps" != "$expected_duration" ]]; then
    echo "SAIF duration mismatch for $policy: $duration_ps vs $expected_duration" >&2
    exit 9
  fi

  POWER_ONLY=1 \
    CLOCK_PERIOD=10.0 \
    WORK_DIR="$dc_work_dir" \
    REPORT_DIR="$report_dir" \
    NETLIST_DIR="$DC_NETLIST_DIR" \
    DDC_FILE="$DDC_FILE" \
    SAIF_FILE="$saif_file" \
    SAIF_INSTANCE="$SAIF_INSTANCE" \
    "$ROOT_DIR/scripts/run_dc_vpu_synth.sh"
  test -s "$dc_log"
  test -s "$power_report"
  ! grep -q 'PWR-362' "$dc_log"

  unmatched="$(sed -n 's/.*There are \([0-9][0-9]*\) objects not found during annotation.*PWR-452.*/\1/p' "$dc_log" | head -n1)"
  unmatched="${unmatched:-0}"
  if [[ -z "$expected_unmatched" ]]; then
    expected_unmatched="$unmatched"
  elif [[ "$unmatched" != "$expected_unmatched" ]]; then
    echo "SAIF annotation mismatch for $policy: $unmatched vs $expected_unmatched" >&2
    exit 10
  fi

  internal_uw="$(awk '/Cell Internal Power/{print $5; exit}' "$power_report")"
  switching_uw="$(awk '/Net Switching Power/{print $5; exit}' "$power_report")"
  leakage_uw="$(awk '/Cell Leakage Power/{print $5; exit}' "$power_report")"
  test -n "$internal_uw"
  test -n "$switching_uw"
  test -n "$leakage_uw"
  dynamic_uw="$(awk -v internal="$internal_uw" -v switching="$switching_uw" 'BEGIN { printf "%.4f", internal + switching }')"
  total_uw="$(awk -v dynamic="$dynamic_uw" -v leakage="$leakage_uw" 'BEGIN { printf "%.4f", dynamic + leakage }')"
  dynamic_pj_per_vdot="$(awk -v dynamic="$dynamic_uw" -v duration="$duration_ps" 'BEGIN { printf "%.4f", dynamic * duration / 512000000 }')"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$policy" "$internal_uw" "$switching_uw" "$leakage_uw" "$dynamic_uw" \
    "$total_uw" "$dynamic_pj_per_vdot" "$duration_ps" "$unmatched" >> "$CSV_FILE"
done

{
  printf '%s\n\n' '# SAP-VPU ASIC Policy Power Matrix'
  printf '%s\n' '| Policy | Internal uW | Switching uW | Dynamic uW | Leakage uW | Total uW | Dynamic pJ/VDOT | SAIF unmatched |'
  printf '%s\n' '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |'
  tail -n +2 "$CSV_FILE" | while IFS=, read -r policy internal switching leakage dynamic total energy duration unmatched; do
    printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$policy" "$internal" "$switching" "$dynamic" "$leakage" "$total" "$energy" "$unmatched"
  done
  printf '\n%s\n' "Standalone TSMC28 TT 10 ns runtime-policy activity. All rows use a ${expected_duration} ps capture window and share ${expected_unmatched} unmatched SAIF objects; this is not a hardware-removal, full-SoC, board, or end-to-end result."
} > "$MD_FILE"

test -s "$MD_FILE"
printf 'DC policy power matrix written to %s\n' "$DC_POLICY_MATRIX_WORK_DIR"
