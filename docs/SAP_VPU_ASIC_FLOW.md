# SAP-VPU TSMC ASIC Flow

## Scope

This flow captures a Synopsys Design Compiler evidence path for the standalone
`sap_vpu_core` and the complete `sap_vpu_subsystem`. TSMC remains the paper
target; the local TSMC28 flow is the historical compatibility path.

Use only validated TSMC standard-cell `.db` files for paper-facing ASIC
numbers. Nangate45 results are toolchain diagnostics only.

## Legacy TSMC28 Default

Default Make variables:

```sh
DC_CLOCK_PERIOD=10.0
DC_DESIGN_NAME=sap_vpu_core
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

The runner also accepts process-neutral overrides. These take precedence over
the legacy names:

```sh
STD_CELL_DB=/path/to/compiled/library.db
PROCESS_CORNER=corner_name
```

## School-Server Toolchain

The validated server toolchain is:

```sh
DC_SHELL=/data/synopsys/syn/T-2022.03-SP5-2/bin/dc_shell
SNPS_LICENSE=27020@gl01
```

The installed `CORE65LPSVT` library is STMicroelectronics CMOS065_LP, not
TSMC. It is valid only for toolchain diagnostics. The server TSMC65 PDK
contains SPICE and technology views, but no verified TSMC standard-cell timing
`.db` has been found. Do not label `CORE65LPSVT` results as TSMC PPA.

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

Generate a clean gate-simulation checkpoint, then run the gate-SAIF smoke:

```sh
make dc-vpu-gate-synth
make dc-vpu-gate-saif-power
```

The first command uses `COMPILE_ULTRA=0` and writes a separate DDC/netlist
under `netlist/dc/tsmc28/vpu_core_gate/`. The second command requires that
checkpoint, runs the TSMC28 gate smoke with VCS-MX, records only DUT-top-level
VCD signals, converts the VCD to SAIF, and rejects `PWR-452` annotation output.

Run DC synthesis:

```sh
make dc-vpu-synth DC_CLOCK_PERIOD=10.0
```

Run post-synthesis setup/hold and power analysis with PrimeTime:

```sh
make pt-vpu-analyze \
  PT_SHELL=/path/to/pt_shell \
  PT_STD_CELL_DB=/path/to/authorized/standard_cell.db \
  PT_PROCESS_CORNER=process_corner \
  PT_NETLIST_FILE=/path/to/sap_vpu_subsystem.v \
  PT_SDC_FILE=/path/to/sap_vpu_subsystem.sdc \
  PT_REPORT_DIR=reports/pt/process_corner/subsystem
```

For activity-aware power, also pass `PT_SAIF_FILE` and, when the SAIF includes
the testbench hierarchy, `PT_SAIF_STRIP_PATH=sap_vpu_subsystem_gate_tb/dut`.
The generated `pt.log` must show successful timing checks and SAIF annotation
coverage before any result is used.

Run the complete subsystem front-end precheck and synthesis in isolated output
directories:

```sh
make dc-vpu-precheck \
  DC_DESIGN_NAME=sap_vpu_subsystem \
  DC_CLOCK_PERIOD=10.0 \
  DC_WORK_DIR=work/dc/tsmc28/vpu_subsystem_10ns \
  DC_REPORT_DIR=reports/dc/tsmc28/vpu_subsystem_10ns \
  DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_subsystem_10ns

make dc-vpu-synth \
  DC_DESIGN_NAME=sap_vpu_subsystem \
  DC_CLOCK_PERIOD=10.0 \
  DC_WORK_DIR=work/dc/tsmc28/vpu_subsystem_10ns \
  DC_REPORT_DIR=reports/dc/tsmc28/vpu_subsystem_10ns \
  DC_NETLIST_DIR=netlist/dc/tsmc28/vpu_subsystem_10ns
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

Run the nine-policy standalone activity matrix:

```sh
make dc-vpu-policy-power-matrix
```

After `make dc-vpu-gate-synth`, this runs the policy testbench against the
clean TSMC28 gate netlist for every policy. Every row must have zero
`PWR-452` annotations; it writes a CSV and Markdown table under
`work/dc/tsmc28/vpu_policy_matrix/`.

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

- The accepted PPA target is the standalone VPU core, not the full CV32E40X
  SoC. Complete-subsystem mapping is currently blocked as recorded below.
- The subsystem's two 128-bit four-word scratchpads are inferred as flip-flops,
  not foundry SRAM macros. Any later SRAM-macro result must state its separate
  memory assumptions.
- Power is vectorless DC power unless SAIF/VCD activity is explicitly provided.
- Treat the numbers as early ASIC synthesis evidence, not final silicon PPA.
- The legacy `vpu_core_sliced_10ns_nopower` Verilog contains
  `SYNOPSYS_UNCONNECTED_1/2` in a DesignWare adder `SUM` connection. It remains
  unsuitable for functional gate simulation and must not be used for a
  gate-level SAIF claim.
- A separate accepted `COMPILE_ULTRA=0` checkpoint passes
  `dc-vpu-gate-netlist-check`. VCS-MX O-2018.09-SP2, launched with
  `VCS_ARCH_OVERRIDE=linux` and `-full64`, passes `GATE_SMOKE_PASS` on this
  TSMC28 gate netlist.
- Gate VCD capture is limited to one DUT hierarchy level. This excludes
  behavioral standard-cell-model internals that are not DDC objects. The
  resulting gate SAIF annotates the clean DDC without `PWR-452`.
- DC L-2016.03-SP1 remains intermittently unstable under WSL during startup or
  mapping. A failed synthesis produces no evidence; keep a successful run's
  DDC, netlist, reports, and command log together rather than retrying power
  analysis against a partial artifact.
- The local `.db` can emit an `LDB-4` library-view warning during load; keep
  that warning with the report package.
- A 2026-07-12 operand-isolation trial reached analyze/elaborate but triggered
  an internal DC L-2016.03-SP1 Pass 1 mapping failure under both the default
  and low-map configurations. It produced no mapped DDC, so no post-change ASIC
  PPA comparison is available from this installation.

## Complete Subsystem Status

On 2026-07-21, `sap_vpu_subsystem` passed analyze, elaborate, link,
`check_design`, and `check_timing` at TSMC28 `tt0p9v85c`, 10 ns. This confirms
that DC can read the complete RTL hierarchy and constraints.

Mapping did not produce a valid DDC or PPA report:

| Settings | Furthest completed stage | Result |
| --- | --- | --- |
| `COMPILE_ULTRA=0` | Pass 1 mapping start | DC internal fatal error |
| `COMPILE_ULTRA=0 MAP_EFFORT=low EXACT_MAP=1 USE_DW=0 SKIP_POWER_REPORT=1` | Pass 1 mapping start | DC internal fatal error |
| `COMPILE_ULTRA=0 MAP_EFFORT=low EXACT_MAP=0 USE_DW=0 SKIP_POWER_REPORT=1` | delay optimization, then design-rule fixing | DC internal fatal error while reloading the TSMC28 `.db` |

The repeated `DB-1`/`LDB-4` library-view errors and crashes make this DC
L-2016.03-SP1 installation unsuitable for complete-subsystem paper PPA. Do not
derive area, timing, or power from partial logs. The bounded next solution is a
newer compatible Design Compiler release or a validated regenerated TSMC28
`.db`; only then should the 10 ns subsystem run and matched core comparison be
repeated.

### 2026-07-24 Toolchain Audit

The installed Synopsys set contains only DC `L-2016.03-SP1`, PrimeTime
`M-2016.12-SP1`, and VCS/VCS-MX `O-2018.09-SP2`. No newer compiler or Library
Compiler is installed. DC rejects the Nangate45 Liberty input with `LCSH-3`, so
that library cannot be converted into a timing `.db` locally.

A controlled current-core run using TSMC28 `tt0p9v85c`, 10 ns,
`COMPILE_ULTRA=0`, `USE_DW=0`, and power reporting disabled still emitted
`DB-1`/`LDB-4` while loading the library and then crashed in Pass 1 mapping.
Therefore the problem is not limited to subsystem size. Further retries on this
installation are stopped; a compatible DC/Library Compiler installation or a
validated regenerated `.db` is required before current-RTL ASIC evidence can
resume.

### 2026-07-25 Compatibility Audit

DC `L-2016.03-SP1` was also launched in a CentOS 7 user space with its required
legacy runtime libraries. The shell and license checkout completed, but the
current TSMC28 library still emitted `DB-1`/`LDB-4` and mapping crashed. This
rules out the Ubuntu 20.04 user space as the sole cause.

The compiled `NangateOpenCellLibrary_typical.db` from the legacy `nutvpu`
workspace loaded without library errors and passed analyze, elaborate, link,
`check_design`, and `check_timing` for the current core. Mapping still failed
inside Pass 1, both normally and with address randomization disabled. Reducing
the precision datapath from three parallel products to one product per lane did
not make mapping reproducible. The remaining blocker is therefore the old DC
mapping engine on the current host, not subsystem size or one specific `.db`.

Do not retry parameter combinations on this installation. Resume current-RTL
ASIC PPA only with a newer compatible Design Compiler release. The Nangate45
test above is a compatibility diagnostic and produced no PPA evidence.

### 2026-07-25 School-Server Toolchain Validation

The school server provides DC `T-2022.03-SP5-2`, PrimeTime
`W-2024.09-SP4-1`, VCS `V-2023.12-SP2`, and license service
`27020@gl01`. The shared STMicroelectronics `CORE65LPSVT` CMOS065_LP delivery
contains compiled Synopsys timing libraries and matching Verilog models.

Current core and subsystem RTL passed analyze, elaborate, link, `compile_ultra`,
report generation, and DDC/netlist/SDC export with this diagnostic library:

| Design | Corner | Slack ns | Cell area | Cells | Vectorless DC power |
| --- | --- | ---: | ---: | ---: | ---: |
| `sap_vpu_core` | nominal 1.00 V, 25 C | +1.712 | 27,589.639 | 5,784 | 0.6181 mW |
| `sap_vpu_subsystem` | nominal 1.00 V, 25 C | +0.0228 | 45,834.879 | 9,327 | 1.2319 mW |
| `sap_vpu_subsystem` | worst 0.90 V, 125 C | +0.0003 | 46,870.199 | 9,809 | 1.0523 mW |

The runs contain no DC `Error` or internal fatal message. They prove that the
new compiler can map the current subsystem, but the library is not TSMC and the
power is vectorless. None of these numbers belongs in the paper PPA table.
Obtain an authorized TSMC timing `.db`, then repeat mapping, setup/hold, SAIF,
and PrimeTime analysis. Nangate45 is also not a paper target.

The same ST diagnostic checkpoint also passed a VCS gate simulation for
`fc2_k512_stream_dense` and a complete VCD-to-SAIF-to-PrimeTime run. PrimeTime
annotated 10,258 nets (100%) and 9,323 leaf cells (99.99%), with setup slack
`+0.0228 ns`, hold slack `+0.0663 ns`, and no Error/Fatal. Its `0.7253 mW`
activity-aware total power is a flow diagnostic only; it is not TSMC evidence
and must not enter a paper comparison.

## Local Checkpoint

Historical local TSMC28 `tt0p9v85c`, 10 ns, standalone `sap_vpu_core`
evidence from before the shared-multiplier precision-datapath change:

| Activity source | Internal power | Switching power | Leakage power | Total power |
| --- | ---: | ---: | ---: | ---: |
| Vectorless DC | 0.3952 mW | 3.5926e-03 mW | 7.1120e+04 nW | 0.4699 mW |
| Standalone VPU smoke SAIF | 0.4127 mW | 1.9090e-02 mW | 7.2433e+04 nW | 0.5042 mW |
| TinyViT smoke VPU-instance SAIF | 0.4065 mW | 1.4669e-02 mW | 7.2839e+04 nW | 0.4940 mW |
| Clean gate smoke SAIF | 0.5820 mW | 3.5651e-02 mW | 7.2731e-02 mW | 0.6904 mW |

These are no longer current-RTL checkpoints and must not be used in the final
paper table. Re-generate the reports with a compatible newer DC release, and
keep the run directory, command line, library corner, clock period, and SAIF
annotation warnings with any replacement number.

The clean gate row is a 275.044 ns functional smoke with `PWR-452` absent. It
is a valid gate-level annotation smoke, not a policy comparison, full-SoC
power number, or end-to-end TinyViT energy result.

## Gate-Level SAIF Preflight

Run this check on every emitted Verilog netlist before using it to generate a
gate-level VCD or SAIF:

```sh
make dc-vpu-gate-synth
make dc-vpu-gate-saif-power
```

`dc-vpu-gate-synth` rejects `SYNOPSYS_UNCONNECTED` markers before it creates a
gate checkpoint. `dc-vpu-gate-saif-power` additionally requires a passing gate
smoke and zero `PWR-452` annotations. The legacy checkpoint still intentionally
fails `dc-vpu-gate-netlist-check`; this prevents it from being mislabelled as
gate-level activity power.

## Policy Activity Matrix

The current matrix uses VCS-MX gate-level activity from the clean standalone
TSMC28 `tt0p9v85c` 10 ns checkpoint. Each policy executes the same
512-`VDOT` window of 18,295,784 ps; all nine SAIF runs have zero `PWR-452` and
no `PWR-362` total-annotation failure.

| Policy | Dynamic power | Total power | Dynamic energy / VDOT |
| --- | ---: | ---: | ---: |
| `dense_int8` | 654.2315 uW | 727.0549 uW | 23.3783 pJ |
| `static_int4` | 665.3819 uW | 738.4317 uW | 23.7767 pJ |
| `static_int2` | 645.8332 uW | 719.0030 uW | 23.0782 pJ |
| `adaptive_int4` | 652.1932 uW | 725.0756 uW | 23.3054 pJ |
| `adaptive_sparse75` | 646.1122 uW | 718.8912 uW | 23.0881 pJ |
| `adaptive_unstructured` | 652.8008 uW | 725.7202 uW | 23.3272 pJ |
| `no_sparse` | 652.2072 uW | 725.1568 uW | 23.3059 pJ |
| `no_lane` | 652.1925 uW | 725.0790 uW | 23.3054 pJ |
| `no_precision` | 654.1928 uW | 726.9947 uW | 23.3769 pJ |

The 19.5487 uW dynamic range is 2.99% of the dense reference. This short,
fixed-latency activity window is valid gate-level policy-path evidence, but it
does not yet demonstrate a material power reduction. It does not remove
hardware blocks, model the full SoC or memory system, validate a board, or
measure TinyViT end-to-end energy. The CSV and generated Markdown table remain
ignored local artifacts and must be regenerated for a paper result.

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

## Corner Expansion Status

Local non-TT corner attempts on the current DC L-2016.03-SP1 setup also hit the
same mapping-stage tool limitation:

| Corner | Target period | Settings | Result |
| --- | ---: | --- | --- |
| `ssg0p72v125c` | 10.0 ns | default flow | DC internal crash during Pass 1 mapping |
| `ssg0p72v125c` | 10.0 ns | `COMPILE_ULTRA=0 MAP_EFFORT=low EXACT_MAP=1 USE_DW=0` | DC internal crash during Pass 1 mapping |
| `ffg1p05vm40c` | 10.0 ns | default flow | DC internal crash during Pass 1 mapping |

Do not present SS/FF corner PPA from this setup. The current publishable ASIC
checkpoint is TT `tt0p9v85c` at 10 ns, plus the documented vectorless and SAIF
power variants. SS/FF evidence needs either a newer compatible DC installation,
validated regenerated `.db` files, or a different synthesis tool flow.
