# SAP-VPU TSMC28 ASIC Flow

## Scope

This flow captures a Synopsys Design Compiler evidence path for the standalone
`sap_vpu_core` and a front-end/mapping path for the complete
`sap_vpu_subsystem`. The accepted PPA checkpoint remains core-only until the
complete subsystem maps successfully.

Use only the local TSMC28 standard-cell `.db` files for this flow. Do not use
open PDK or Nangate-style libraries for paper-facing ASIC numbers.

## Default Target

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

## Local Checkpoint

Current local TSMC28 `tt0p9v85c`, 10 ns, standalone `sap_vpu_core` evidence:

| Activity source | Internal power | Switching power | Leakage power | Total power |
| --- | ---: | ---: | ---: | ---: |
| Vectorless DC | 0.3952 mW | 3.5926e-03 mW | 7.1120e+04 nW | 0.4699 mW |
| Standalone VPU smoke SAIF | 0.4127 mW | 1.9090e-02 mW | 7.2433e+04 nW | 0.5042 mW |
| TinyViT smoke VPU-instance SAIF | 0.4065 mW | 1.4669e-02 mW | 7.2839e+04 nW | 0.4940 mW |
| Clean gate smoke SAIF | 0.5820 mW | 3.5651e-02 mW | 7.2731e-02 mW | 0.6904 mW |

These are local reproducibility checkpoints. Re-generate the reports before
using them in paper tables, and keep the run directory, command line, library
corner, clock period, and SAIF annotation warnings with the cited number.

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
