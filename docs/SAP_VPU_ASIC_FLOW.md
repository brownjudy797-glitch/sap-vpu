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

Run power-only from an existing mapped DDC:

```sh
make dc-vpu-power DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core_sliced_10ns_nopower
```

Run SAIF activity power from the standalone VPU smoke:

```sh
make dc-vpu-saif-power \
  DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core_sliced_10ns_nopower \
  DC_WORK_DIR=work/dc/tsmc28/vpu_core_sliced_10ns_saif_power \
  DC_REPORT_DIR=reports/dc/tsmc28/vpu_core_sliced_10ns_saif_power
```

Run SAIF activity power from the TinyViT SoC smoke VPU instance:

```sh
make dc-vpu-tinyvit-saif-power \
  DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_core_sliced_10ns_nopower \
  DC_WORK_DIR=work/dc/tsmc28/vpu_core_sliced_10ns_tinyvit_saif_power \
  DC_REPORT_DIR=reports/dc/tsmc28/vpu_core_sliced_10ns_tinyvit_saif_power
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
- Power is vectorless DC power unless SAIF/VCD activity is explicitly provided.
- Treat the numbers as early ASIC synthesis evidence, not final silicon PPA.
- On the current local DC L-2016.03-SP1 installation, TSMC28 mapping now has a
  complete 10 ns standalone VPU checkpoint under
  `vpu_core_sliced_10ns_nopower`. The local `.db` still emits an `LDB-4`
  library-view warning during load; keep that warning with the report package.
- SAIF power runs may emit `PWR-452` partial annotation warnings. They are not
  the same as a total annotation failure, but the unmatched-object count must be
  reported with any activity-power number.

## Local Checkpoint

Current local TSMC28 `tt0p9v85c`, 10 ns, standalone `sap_vpu_core` evidence:

| Activity source | Internal power | Switching power | Leakage power | Total power |
| --- | ---: | ---: | ---: | ---: |
| Vectorless DC | 0.3952 mW | 3.5926e-03 mW | 7.1120e+04 nW | 0.4699 mW |
| Standalone VPU smoke SAIF | 0.4127 mW | 1.9090e-02 mW | 7.2433e+04 nW | 0.5042 mW |
| TinyViT smoke VPU-instance SAIF | 0.4065 mW | 1.4669e-02 mW | 7.2839e+04 nW | 0.4940 mW |

These are local reproducibility checkpoints. Re-generate the reports before
using them in paper tables, and keep the run directory, command line, library
corner, clock period, and SAIF annotation warnings with the cited number.

## Clock Sweep Status

Local tighter-clock attempts after the 10 ns checkpoint are currently limited
by DC/tool stability rather than by a clean timing report:

| Target period | Settings | Result |
| ---: | --- | --- |
| 8.0 ns | default flow | DC internal crash during WLM backend optimization |
| 5.0 ns | default flow | DC internal crash during Pass 1 mapping |
| 5.0 ns | `COMPILE_ULTRA=0 MAP_EFFORT=low EXACT_MAP=1 USE_DW=0` | DC internal crash during Pass 1 mapping |

Do not cite an ASIC Fmax from the current DC L-2016.03-SP1 setup. The next
credible path for clock sweep evidence is a newer compatible DC installation or
a validated regenerated TSMC28 `.db`; until then, use the 10 ns checkpoint for
area/timing/power and report the tool boundary explicitly.
