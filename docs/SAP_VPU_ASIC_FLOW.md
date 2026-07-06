# SAP-VPU TSMC28 ASIC Flow

## Scope

This flow captures a first Synopsys Design Compiler evidence path for the
standalone `sap_vpu_core`. It is intended for rough VPU-core area, timing, and
vectorless power estimates before the later FPGA and board work is complete.

Use only the local TSMC28 standard-cell `.db` files for this flow. Do not use
open PDK or Nangate-style libraries for paper-facing ASIC numbers.

## Default Target

Default Make variables:

```sh
DC_CLOCK_PERIOD=10.0
DC_WORK_DIR=work/dc/tsmc28/vpu_core
DC_REPORT_DIR=reports/dc/tsmc28/vpu_core
```

The wrapper script defaults to:

```sh
SNPS_LICENSE=27000@localhost
SYNOPSYS_ENV_FILE=
TSMC28_ROOT=/opt/pdk/tsmc28hpcplus/tcbn28hpcplusbwp7t40p140_180b
TSMC28_CORNER=tt0p9v85c
TSMC28_DB=$TSMC28_ROOT/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp7t40p140_180a/tcbn28hpcplusbwp7t40p140tt0p9v85c.db
```

Override `TSMC28_DB` and `TSMC28_CORNER` together when running another TSMC28
corner. `SYNOPSYS_ENV_FILE` is intentionally empty by default so this flow does
not import unrelated open-library environment variables.

Crash-workaround knobs for old DC installations:

```sh
COMPILE_ULTRA=0
MAP_EFFORT=low
AREA_EFFORT=none
EXACT_MAP=1
USE_DW=0
```

These knobs are for tool triage only; report the exact settings with any PPA
number generated from them.

## Commands

Run DC synthesis:

```sh
make dc-vpu-synth DC_CLOCK_PERIOD=10.0
```

Start or verify the Synopsys license server before running the target if
`27000@localhost` is not already active.

Local license helper:

```sh
mkdir -p work/license
/opt/synopsys/scl/2018.06/linux64/bin/lmgrd \
  -c /opt/synopsys/scl/2018.06/admin/license/Synopsys.dat \
  -l work/license/synopsys_lmgrd.log
```

Run only the DC front-end precheck, stopping after analyze, elaborate, link,
`check_design`, and `check_timing`:

```sh
make dc-vpu-precheck DC_CLOCK_PERIOD=10.0
```

This target is for isolating tool setup and RTL/library readability from the
mapping-stage crash. It does not produce area, timing, or power evidence.

Summarize generated reports:

```sh
make dc-vpu-summary
```

The flow writes:

- `work/dc/tsmc28/vpu_core/dc_vpu_summary.csv`
- `work/dc/tsmc28/vpu_core/dc_vpu_precheck.csv`
- `work/dc/tsmc28/vpu_core/dc.log`
- `reports/dc/tsmc28/vpu_core/area.rpt`
- `reports/dc/tsmc28/vpu_core/qor.rpt`
- `reports/dc/tsmc28/vpu_core/timing_max.rpt`
- `reports/dc/tsmc28/vpu_core/timing_min.rpt`
- `reports/dc/tsmc28/vpu_core/power.rpt`
- `netlist/dc/tsmc28/vpu_core/sap_vpu_core.v`
- `netlist/dc/tsmc28/vpu_core/sap_vpu_core.sdc`

Generated reports and netlists remain ignored local artifacts.

## Evidence Boundary

- The current target is the standalone VPU core, not the full CV32E40X SoC.
- SRAMs are not modeled as foundry macros in this standalone core flow.
- Power is vectorless DC power unless SAIF/VCD activity is provided later.
- Treat the numbers as early ASIC synthesis evidence, not final silicon PPA.
- On the current local DC L-2016.03-SP1 installation, TSMC28 mapping reached
  Pass 1 Mapping but hit an internal DC crash across several conservative
  settings. Do not cite a DC PPA number until a complete `dc_vpu_summary.csv`,
  `area.rpt`, `timing_max.rpt`, and `power.rpt` are generated.
- `make dc-vpu-precheck` was added to separate front-end setup from mapping.
  It has verified that the local license, TSMC28 `.db`, RTL analyze/elaborate,
  link, `check_design`, and `check_timing` path can complete before compile.
