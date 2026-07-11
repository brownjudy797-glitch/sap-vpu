# FPGA Policy Power Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate and summarize nine 140 MHz standalone SAP-VPU gate-level SAIF power points matching the current TinyViT precision, sparsity, and gating policies.

**Architecture:** The gate testbench now provides nine checked policy activity modes while preserving its default smoke mode. A small Windows PowerShell runner compiles XSim once, captures each policy, converts VCD to SAIF through WSL, invokes the existing Vivado power Tcl, and summarizes dynamic power and dynamic energy per VDOT.

**Tech Stack:** SystemVerilog, XSim/Vivado 2023.2, Synopsys `vcd2saif` in Ubuntu-20.04 WSL, PowerShell 7/Windows PowerShell, GNU Make.

---

## File Map

- Modify `tb/sap_vpu_core_gate_tb.sv`: add parameterized policy activity mode and retain default smoke mode.
- Create `scripts/run_fpga_vpu_policy_matrix.ps1`: orchestrate XSim, WSL SAIF conversion, Vivado power, validation, and summary generation.
- Modify `Makefile`: expose the matrix target and include the runner in `plan-check`.
- Modify `docs/SAP_VPU_FPGA_FLOW.md`: document reproduction, measured matrix, and evidence boundary.

No RTL, CV32E40X, synthesis Tcl, or bare-metal kernel change is part of this plan.

### Task 1: Add Policy Activity Mode to the Gate Testbench

**Status:** Completed by `bb57e34` and tightened after review by `83ff1c0`.
The implementation validates accumulated outputs, drains responses at both VCD
boundaries, and makes an unknown policy exit nonzero.

**Files:**
- Modify: `tb/sap_vpu_core_gate_tb.sv`

- [x] **Step 1: Run a failing policy-mode check**

Use the current compiled snapshot to prove that policy mode does not exist:

```powershell
cmd.exe /V:ON /d /s /c 'pushd "\\wsl.localhost\Ubuntu-20.04\home\rime\Program\sap-vpu" && call "D:\Xilinx_2023_02\Vivado\2023.2\settings64.bat" && pushd work\fpga\vpu_core_sliced_140_funcsim\xsim_gate && xsim --nolog -R sap_vpu_core_gate_tb_snapshot --testplusarg policy=dense_int8 --testplusarg vcd=dense_int8.vcd > policy_red.log 2>&1 & set "ec=!ERRORLEVEL!" & type policy_red.log & popd & popd & exit /b !ec!'
```

Run:

```powershell
Select-String '\\wsl.localhost\Ubuntu-20.04\home\rime\Program\sap-vpu\work\fpga\vpu_core_sliced_140_funcsim\xsim_gate\policy_red.log' 'GATE_POLICY_PASS: dense_int8'
```

Expected: no match because the existing testbench only prints
`GATE_SMOKE_PASS`.

- [x] **Step 2: Add policy configuration and deterministic operands**

Add these testbench state variables:

```systemverilog
  string policy_name;
  string vcd_file;
```

Add a complete policy configuration task. It maps every supported name to the
same precision, bitmap, lane limit, and skipped-product count used by the
bare-metal TinyViT smoke:

```systemverilog
  task automatic policy_config(
    input string       name,
    output logic [1:0] precision,
    output logic [31:0] sparse,
    output logic [31:0] lanes,
    output logic [31:0] expected_skip,
    output logic [31:0] expected_total
  );
    begin
      if (name == "dense_int8") begin
        precision = SAP_PREC_INT8; sparse = 32'h0f; lanes = 4; expected_skip = 0; expected_total = 12096;
      end else if (name == "static_int4") begin
        precision = SAP_PREC_INT4; sparse = 32'hff; lanes = 8; expected_skip = 0; expected_total = 14592;
      end else if (name == "static_int2") begin
        precision = SAP_PREC_INT2; sparse = 32'hffff; lanes = 16; expected_skip = 0; expected_total = 5120;
      end else if (name == "adaptive_int4") begin
        precision = SAP_PREC_INT4; sparse = 32'h0f; lanes = 4; expected_skip = 2048; expected_total = 7296;
      end else if (name == "adaptive_sparse75") begin
        precision = SAP_PREC_INT4; sparse = 32'h03; lanes = 2; expected_skip = 3072; expected_total = 3648;
      end else if (name == "adaptive_unstructured") begin
        precision = SAP_PREC_INT4; sparse = 32'h55; lanes = 8; expected_skip = 2048; expected_total = 7296;
      end else if (name == "no_sparse") begin
        precision = SAP_PREC_INT4; sparse = 32'hff; lanes = 4; expected_skip = 2048; expected_total = 7296;
      end else if (name == "no_lane") begin
        precision = SAP_PREC_INT4; sparse = 32'h0f; lanes = 8; expected_skip = 2048; expected_total = 7296;
      end else if (name == "no_precision") begin
        precision = SAP_PREC_INT8; sparse = 32'h0f; lanes = 4; expected_skip = 0; expected_total = 7296;
      end else begin
        $fatal(1, "GATE_POLICY_FAIL: unknown policy %s", name);
      end
    end
  endtask
```

Add a compact operand task that reproduces the four unique blocks from the
bare-metal tile; the software tile repeats those four blocks twice:

```systemverilog
  task automatic policy_operands(
    input string name,
    input int unsigned index,
    output logic [31:0] rs1,
    output logic [31:0] rs2
  );
    int unsigned block;
    int unsigned op;
    logic [31:0] token0;
    logic [31:0] token1;
    logic [31:0] weight0;
    logic [31:0] weight1;
    begin
      block = (index / 4) % 4;
      op = index % 4;

      if (name == "dense_int8") begin
        case (block)
          0: begin token0 = 32'h04030201; token1 = 32'h01020304; weight0 = 32'h08070605; weight1 = 32'h01010101; end
          1: begin token0 = 32'h02020202; token1 = 32'h03010301; weight0 = 32'h08070605; weight1 = 32'h02020202; end
          2: begin token0 = 32'h01010101; token1 = 32'h02020202; weight0 = 32'h04030201; weight1 = 32'h01010101; end
          default: begin token0 = 32'h03030303; token1 = 32'h01010101; weight0 = 32'h02020202; weight1 = 32'h01010101; end
        endcase
      end else if (name == "static_int2") begin
        token0 = 32'h55555555; token1 = 32'h11111111;
        weight0 = 32'h55555555; weight1 = 32'h11111111;
      end else if (name == "no_precision") begin
        case (block)
          0: begin token0 = 32'h01010101; token1 = 32'h02020202; weight0 = 32'h01010101; weight1 = 32'h02020202; end
          1: begin token0 = 32'h03030303; token1 = 32'h04040404; weight0 = 32'h01010101; weight1 = 32'h02020202; end
          2: begin token0 = 32'h01010101; token1 = 32'h03030303; weight0 = 32'h01010101; weight1 = 32'h02020202; end
          default: begin token0 = 32'h01010101; token1 = 32'h02020202; weight0 = 32'h04040404; weight1 = 32'h01010101; end
        endcase
      end else begin
        case (block)
          0: begin token0 = 32'h11111111; token1 = 32'h22222222; weight0 = 32'h11111111; weight1 = 32'h22222222; end
          1: begin token0 = 32'h33333333; token1 = 32'h44444444; weight0 = 32'h11111111; weight1 = 32'h22222222; end
          2: begin token0 = 32'h11111111; token1 = 32'h33333333; weight0 = 32'h11111111; weight1 = 32'h22222222; end
          default: begin token0 = 32'h11111111; token1 = 32'h22222222; weight0 = 32'h44444444; weight1 = 32'h11111111; end
        endcase
      end

      rs1 = (op < 2) ? token0 : token1;
      rs2 = ((op % 2) == 0) ? weight0 : weight1;
    end
  endtask
```

- [x] **Step 3: Add the isolated 512-VDOT capture**

Add this response-drain helper and policy task after the existing response
helper:

```systemverilog
  task automatic wait_rsp_retired;
    begin
      do begin
        @(negedge clk_i);
      end while (rsp_valid_o !== 1'b0);
    end
  endtask

  task automatic run_policy(input string name, input string activity_file);
    logic [1:0] precision;
    logic [31:0] sparse;
    logic [31:0] lanes;
    logic [31:0] expected_skip;
    logic [31:0] expected_total;
    logic [31:0] total_output;
    logic [31:0] rs1;
    logic [31:0] rs2;
    begin
      policy_config(name, precision, sparse, lanes, expected_skip, expected_total);
      total_output = '0;

      send_cmd(4'h0, SAP_OP_VSETPREC, 32'(precision), 32'h0);
      expect_rsp(4'h0, 1'b1, 32'(precision), 1'b0);
      send_cmd(4'h1, SAP_OP_VSETSPARSE_BMP, sparse, 32'h0);
      expect_rsp(4'h1, 1'b1, sparse, 1'b0);
      send_cmd(4'h2, SAP_OP_VSETLANE, lanes, 32'h0);
      expect_rsp(4'h2, 1'b1, lanes, 1'b0);
      send_cmd(4'h3, SAP_OP_VCLEARCNT, 32'h0, 32'h0);
      expect_rsp(4'h3, 1'b1, 32'h0, 1'b0);
      wait_rsp_retired();

      $dumpfile(activity_file);
      $dumpvars(0, sap_vpu_core_gate_tb);
      for (int unsigned i = 0; i < 512; i++) begin
        policy_operands(name, i, rs1, rs2);
        send_cmd(i[3:0], SAP_OP_VDOT, rs1, rs2);
        expect_rsp(i[3:0], 1'b0, 32'h0, 1'b0);
        total_output = total_output + rsp_data_o;
      end
      wait_rsp_retired();
      $dumpoff;
      if (total_output !== expected_total) begin
        $fatal(1, "GATE_POLICY_FAIL: %s output total mismatch", name);
      end

      send_cmd(4'h4, SAP_OP_VREADCNT, 32'(SAP_CNT_MAC_ACTIVE), 32'h0);
      expect_rsp(4'h4, 1'b1, 32'd512, 1'b0);
      send_cmd(4'h5, SAP_OP_VREADCNT, 32'(SAP_CNT_SKIPPED), 32'h0);
      expect_rsp(4'h5, 1'b1, expected_skip, 1'b0);
      send_cmd(4'h6, SAP_OP_VREADCNT, 32'(SAP_CNT_SPARSE), 32'h0);
      expect_rsp(4'h6, 1'b1, sparse, 1'b0);
      send_cmd(4'h7, SAP_OP_VREADCNT, 32'(SAP_CNT_LANE), 32'h0);
      expect_rsp(4'h7, 1'b1, lanes, 1'b0);
      $display("GATE_POLICY_PASS: %s", name);
    end
  endtask
```

In the initial block, keep the 140 MHz clock and Xilinx startup-reset wait.
After reset release, select policy mode before the current smoke sequence:

```systemverilog
    if ($value$plusargs("policy=%s", policy_name)) begin
      if (!$value$plusargs("vcd=%s", vcd_file)) begin
        vcd_file = "sap_vpu_core_gate_policy.vcd";
      end
      run_policy(policy_name, vcd_file);
      $finish;
    end

    $dumpfile("sap_vpu_core_gate_tb.vcd");
    $dumpvars(0, sap_vpu_core_gate_tb);
```

- [x] **Step 4: Rebuild and verify RED becomes GREEN**

Run Verilator lint:

```bash
verilator --lint-only --timing -sv rtl/sap_vpu_pkg.sv rtl/sap_vpu_core.sv tb/sap_vpu_core_gate_tb.sv
```

Expected: exit 0.

Recompile and run `dense_int8` with XSim:

```powershell
cmd.exe /V:ON /d /s /c 'pushd "\\wsl.localhost\Ubuntu-20.04\home\rime\Program\sap-vpu" && call "D:\Xilinx_2023_02\Vivado\2023.2\settings64.bat" && pushd work\fpga\vpu_core_sliced_140_funcsim\xsim_gate && xvlog -sv ..\..\..\..\rtl\sap_vpu_pkg.sv ..\..\..\..\tb\sap_vpu_core_gate_tb.sv ..\sap_vpu_core_funcsim.v && xelab -debug typical -L unisims_ver sap_vpu_core_gate_tb glbl -s sap_vpu_core_gate_tb_snapshot && xsim --nolog -R sap_vpu_core_gate_tb_snapshot --testplusarg policy=dense_int8 --testplusarg vcd=dense_int8.vcd > dense_int8.log 2>&1 & set "ec=!ERRORLEVEL!" & type dense_int8.log & popd & popd & exit /b !ec!'
```

Expected:

```text
GATE_POLICY_PASS: dense_int8
```

Run the snapshot without plusargs, all nine policies, and one invalid policy.
Verify the smoke and nine policy pass markers, equal VCD durations, and a
nonzero invalid-policy exit containing `GATE_POLICY_FAIL`.

- [x] **Step 5: Commit the testbench**

```bash
git add tb/sap_vpu_core_gate_tb.sv
git commit -m "test: add fpga gate policy activity modes"
```

### Task 2: Add the Windows Policy Matrix Runner

**Files:**
- Create: `scripts/run_fpga_vpu_policy_matrix.ps1`

- [ ] **Step 1: Verify the runner is absent**

Run:

```powershell
Test-Path '\\wsl.localhost\Ubuntu-20.04\home\rime\Program\sap-vpu\scripts\run_fpga_vpu_policy_matrix.ps1'
```

Expected: `False`.

- [ ] **Step 2: Implement inputs, path validation, and command execution**

Create the runner with these public parameters and fixed default policy order:

```powershell
param(
  [string]$VivadoRoot = 'D:\Xilinx_2023_02\Vivado\2023.2',
  [string]$OutDir = 'work\fpga\vpu_core_policy_power_matrix',
  [string[]]$Policies = @(
    'dense_int8', 'static_int4', 'static_int2',
    'adaptive_int4', 'adaptive_sparse75', 'adaptive_unstructured',
    'no_sparse', 'no_lane', 'no_precision'
  )
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$WslDistro = 'Ubuntu-20.04'
$Dcp = 'work\fpga\vpu_core_sliced_140\checkpoints\post_route.dcp'
$Netlist = 'work\fpga\vpu_core_sliced_140_funcsim\sap_vpu_core_funcsim.v'
$settings = Join-Path $VivadoRoot 'settings64.bat'
$vcd2saif = '/opt/synopsys/syn/L-2016.03-SP1/bin/vcd2saif'
```

Require a WSL UNC repository and derive its Linux path:

```powershell
if ($repo -notmatch '^\\\\wsl\.localhost\\([^\\]+)\\(.+)$') {
  throw "Repository must be opened through \\wsl.localhost: $repo"
}
$detectedDistro = $Matches[1]
$linuxRepo = '/' + ($Matches[2] -replace '\\', '/')
if ($detectedDistro -ne $WslDistro) {
  throw "WSL distro mismatch: expected $detectedDistro, got $WslDistro"
}
```

Validate `$settings`, `$Dcp`, `$Netlist`,
`rtl\sap_vpu_pkg.sv`, and `tb\sap_vpu_core_gate_tb.sv` with `Test-Path`.
Validate `vcd2saif` with:

```powershell
& wsl.exe -d $WslDistro -- test -x $vcd2saif
if ($LASTEXITCODE -ne 0) { throw "Missing vcd2saif: $vcd2saif" }
```

Use one helper for Vivado command-shell execution:

```powershell
function Invoke-VivadoCmd([string]$Command, [string]$LogFile) {
  $line = "pushd `"$repo`" && set `"root=!CD!`" && call `"$settings`" && $Command > `"!root!\$LogFile`" 2>&1"
  & cmd.exe /V:ON /d /s /c $line
  if ($LASTEXITCODE -ne 0) {
    Get-Content (Join-Path $repo $LogFile) -Tail 80
    throw "Command failed: $Command"
  }
}
```

- [ ] **Step 3: Compile once and run one XSim capture per policy**

Create `$OutDir\xsim`, compile the package, testbench, and functional netlist,
then elaborate `sap_vpu_core_gate_tb_snapshot` once:

```powershell
$xsimDir = Join-Path $OutDir 'xsim'
New-Item -ItemType Directory -Force (Join-Path $repo $xsimDir) | Out-Null
Invoke-VivadoCmd `
  "pushd `"$xsimDir`" && xvlog -sv `"!root!\rtl\sap_vpu_pkg.sv`" `"!root!\tb\sap_vpu_core_gate_tb.sv`" `"!root!\$Netlist`" && xelab -debug typical -L unisims_ver sap_vpu_core_gate_tb glbl -s sap_vpu_core_gate_tb_snapshot" `
  "$xsimDir\compile.log"
```

Initialize the result list once before the policy loop:

```powershell
$rows = @()
```

Then run this body for every policy in `$Policies`:

```powershell
$policyDir = Join-Path $OutDir $policy
$vcdRel = Join-Path $policyDir "$policy.vcd"
$xsimLogRel = Join-Path $policyDir 'xsim.log'
New-Item -ItemType Directory -Force (Join-Path $repo $policyDir) | Out-Null

Invoke-VivadoCmd `
  "pushd `"$xsimDir`" && xsim --nolog -R sap_vpu_core_gate_tb_snapshot --testplusarg policy=$policy --testplusarg vcd=`"..\$policy\$policy.vcd`"" `
  $xsimLogRel

$xsimLog = Get-Content (Join-Path $repo $xsimLogRel) -Raw
if ($xsimLog -notmatch "GATE_POLICY_PASS: $policy" -or
    $xsimLog -match 'GATE_(SMOKE|POLICY)_FAIL') {
  throw "Gate policy simulation failed: $policy"
}
```

Require every VCD to be non-empty.

- [ ] **Step 4: Convert SAIF, run Vivado power, and validate evidence**

For each policy, convert paths to Linux by appending their repository-relative
form to `$linuxRepo`, then invoke:

```powershell
$linuxVcd = "$linuxRepo/" + ($vcdRel -replace '\\', '/')
$saifRel = Join-Path $policyDir "$policy.saif"
$linuxSaif = "$linuxRepo/" + ($saifRel -replace '\\', '/')
& wsl.exe -d $WslDistro -- $vcd2saif `
  -input $linuxVcd `
  -output $linuxSaif
if ($LASTEXITCODE -ne 0) { throw "vcd2saif failed: $policy" }

$saifText = Get-Content (Join-Path $repo $saifRel) -Raw
if ($saifText -notmatch '\(TIMESCALE 1 ps\)') {
  throw "Unexpected SAIF timescale: $policy"
}
$durationMatch = [regex]::Match($saifText, '\(DURATION (\d+)\)')
if (-not $durationMatch.Success) { throw "Missing SAIF duration: $policy" }
$durationPs = [long]$durationMatch.Groups[1].Value
```

Run the existing Tcl:

```powershell
Invoke-VivadoCmd `
  "vivado -mode batch -source scripts\vivado_vpu_saif_power.tcl -tclargs `"$Dcp`" `"$policyDir\$policy.saif`" `"$policyDir\power`"" `
  "$policyDir\vivado_power.log"
```

Validate each log:

```powershell
$log = Get-Content (Join-Path $repo "$policyDir\vivado_power.log") -Raw
if ($log -match 'Power 33-(332|334)') {
  throw "Clock/reset activity warning: $policy"
}
$matched = [regex]::Match($log, 'Design nets matched = (\d+) of (\d+)')
if (-not $matched.Success) { throw "Missing net-match count: $policy" }
$matchedCount = [int]$matched.Groups[1].Value
$designCount = [int]$matched.Groups[2].Value
if (($matchedCount / $designCount) -lt 0.99) {
  throw "Less than 99% nets matched: $policy"
}
```

Parse `Total On-Chip Power`, `Dynamic`, `Device Static`, and `Confidence Level`
from `power\reports\post_route_saif_power.rpt`:

```powershell
$report = Get-Content (Join-Path $repo "$policyDir\power\reports\post_route_saif_power.rpt") -Raw
function Read-ReportField([string]$Text, [string]$Label) {
  $escaped = [regex]::Escape($Label)
  $match = [regex]::Match($Text, "(?m)^\|\s*$escaped\s*\|\s*([^|]+?)\s*\|")
  if (-not $match.Success) { throw "Missing power field: $Label" }
  return $match.Groups[1].Value.Trim()
}

$rows += [pscustomobject]@{
  policy = $policy
  total_w = [double](Read-ReportField $report 'Total On-Chip Power (W)')
  dynamic_w = [double](Read-ReportField $report 'Dynamic (W)')
  static_w = [double](Read-ReportField $report 'Device Static (W)')
  confidence = Read-ReportField $report 'Confidence Level'
  nets_matched = $matchedCount
  design_nets = $designCount
  duration_ps = $durationPs
}
```

- [ ] **Step 5: Write deterministic CSV and Markdown summaries**

Write:

```text
work/fpga/vpu_core_policy_power_matrix/fpga_vpu_policy_power_matrix.csv
work/fpga/vpu_core_policy_power_matrix/fpga_vpu_policy_power_matrix.md
```

CSV columns:

```text
policy,total_w,dynamic_w,static_w,dynamic_vs_dense,duration_ps,dynamic_pj_per_vdot,confidence,nets_matched,design_nets
```

Require all nine `duration_ps` values to match. Compute `dynamic_vs_dense` as
`row.dynamic_w / dense_int8.dynamic_w` and `dynamic_pj_per_vdot` as
`row.dynamic_w * row.duration_ps / 512`. The Markdown table uses the same row
order as `$Policies` and includes the standalone VPU evidence warning below the
table.

Use:

```powershell
$denseDynamic = $rows[0].dynamic_w
$durationPs = $rows[0].duration_ps
if ($rows.Where({ $_.duration_ps -ne $durationPs })) {
  throw 'Policy SAIF durations do not match'
}
$summaryRows = foreach ($row in $rows) {
  [pscustomobject]@{
    policy = $row.policy
    total_w = $row.total_w.ToString('0.000')
    dynamic_w = $row.dynamic_w.ToString('0.000')
    static_w = $row.static_w.ToString('0.000')
    dynamic_vs_dense = ($row.dynamic_w / $denseDynamic).ToString('0.000')
    duration_ps = $row.duration_ps
    dynamic_pj_per_vdot = ($row.dynamic_w * $row.duration_ps / 512).ToString('0.000')
    confidence = $row.confidence
    nets_matched = $row.nets_matched
    design_nets = $row.design_nets
  }
}

$csvPath = Join-Path $repo "$OutDir\fpga_vpu_policy_power_matrix.csv"
$mdPath = Join-Path $repo "$OutDir\fpga_vpu_policy_power_matrix.md"
$summaryRows | Export-Csv -NoTypeInformation -Encoding UTF8 $csvPath

$md = @(
  '# SAP-VPU FPGA Policy Power Matrix', '',
  '| Policy | Total W | Dynamic W | Static W | Dynamic vs dense | Dynamic pJ/VDOT | Confidence | Nets matched |',
  '| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |'
)
foreach ($row in $summaryRows) {
  $md += "| $($row.policy) | $($row.total_w) | $($row.dynamic_w) | $($row.static_w) | $($row.dynamic_vs_dense) | $($row.dynamic_pj_per_vdot) | $($row.confidence) | $($row.nets_matched)/$($row.design_nets) |"
}
$md += ''
$md += 'Standalone 140 MHz SAP-VPU runtime-policy activity; not a hardware-removal ablation, full-SoC, board-measured, or end-to-end TinyViT result.'
$md | Set-Content -Encoding UTF8 $mdPath
```

- [ ] **Step 6: Run a focused one-policy verification**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_fpga_vpu_policy_matrix.ps1 -Policies dense_int8 -OutDir work\fpga\vpu_core_policy_power_single
```

Expected:

- `GATE_POLICY_PASS: dense_int8` in the XSim log.
- `Design nets matched = 4673 of 4691` in the Vivado log.
- No `Power 33-332` or `Power 33-334`.
- A one-row CSV and Markdown summary.

- [ ] **Step 7: Commit the runner**

```bash
git add scripts/run_fpga_vpu_policy_matrix.ps1
git commit -m "feat: automate fpga policy power runs"
```

### Task 3: Add the Make Entry Point

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Verify the target is absent**

Run:

```bash
make -n fpga-vpu-policy-power-matrix
```

Expected: failure with `No rule to make target`.

- [ ] **Step 2: Add variables and target**

Add:

```make
POWERSHELL ?= powershell.exe
VIVADO_ROOT_WINDOWS ?= D:\Xilinx_2023_02\Vivado\2023.2
FPGA_POLICY_POWER_DIR ?= work\fpga\vpu_core_policy_power_matrix
```

Add `fpga-vpu-policy-power-matrix` to `.PHONY`, add it to `help`, and add this
recipe:

```make
fpga-vpu-policy-power-matrix:
	$(POWERSHELL) -NoProfile -ExecutionPolicy Bypass \
	  -File scripts/run_fpga_vpu_policy_matrix.ps1 \
	  -VivadoRoot '$(VIVADO_ROOT_WINDOWS)' \
	  -OutDir '$(FPGA_POLICY_POWER_DIR)'
```

Add this `plan-check` assertion:

```make
	test -f scripts/run_fpga_vpu_policy_matrix.ps1
```

- [ ] **Step 3: Verify Make integration**

Run:

```bash
make plan-check
make -n fpga-vpu-policy-power-matrix
```

Expected: both exit 0; the dry run shows one PowerShell runner invocation.

- [ ] **Step 4: Commit Make integration**

```bash
git add Makefile
git commit -m "build: add fpga policy power matrix target"
```

### Task 4: Generate and Record the Full Matrix

**Files:**
- Modify: `docs/SAP_VPU_FPGA_FLOW.md`
- Generated, ignored: `work/fpga/vpu_core_policy_power_matrix/**`

- [ ] **Step 1: Run all nine policies**

Run from WSL:

```bash
make fpga-vpu-policy-power-matrix
```

Expected: nine policy pass markers and nine successful Vivado power reports.

- [ ] **Step 2: Validate the generated matrix**

Run:

```powershell
$csv = Import-Csv '\\wsl.localhost\Ubuntu-20.04\home\rime\Program\sap-vpu\work\fpga\vpu_core_policy_power_matrix\fpga_vpu_policy_power_matrix.csv'
if ($csv.Count -ne 9) { throw "Expected 9 policy rows, got $($csv.Count)" }
if (($csv.policy -join ',') -ne 'dense_int8,static_int4,static_int2,adaptive_int4,adaptive_sparse75,adaptive_unstructured,no_sparse,no_lane,no_precision') { throw 'Unexpected policy order' }
if ($csv.Where({ [double]$_.nets_matched / [double]$_.design_nets -lt 0.99 })) { throw 'Low net annotation' }
if (($csv.duration_ps | Select-Object -Unique).Count -ne 1) { throw 'Mismatched capture durations' }
```

Expected: exit 0.

- [ ] **Step 3: Update FPGA evidence documentation**

In `docs/SAP_VPU_FPGA_FLOW.md`:

- Add `make fpga-vpu-policy-power-matrix` to the command section.
- Add the generated CSV and Markdown paths to the artifact list.
- Add the nine-row generated Markdown table under the local checkpoint.
- State that captures exclude reset and policy setup, use 512 VDOT operations,
  and report standalone VPU runtime-policy switching activity.
- Report dynamic power, normalized dynamic power, and estimated dynamic pJ/VDOT
  as the primary comparison; retain total/static power for context.
- Label `no_sparse`, `no_lane`, and `no_precision` as runtime policy ablations,
  not synthesized hardware-removal ablations.
- Keep the explicit non-full-SoC, non-board, non-end-to-end boundary.
- Do not claim energy per inference.

- [ ] **Step 4: Run final verification**

Run:

```bash
git diff --check
make plan-check
make lint
make sim
make encoding-check
```

Run the existing no-plusarg gate smoke and verify `GATE_SMOKE_PASS`.

Check every matrix Vivado log:

```powershell
Get-ChildItem '\\wsl.localhost\Ubuntu-20.04\home\rime\Program\sap-vpu\work\fpga\vpu_core_policy_power_matrix' -Filter vivado_power.log -Recurse |
  Select-String 'Power 33-(332|334)'
```

Expected: no matches.

- [ ] **Step 5: Commit and push the completed matrix flow**

```bash
git add docs/SAP_VPU_FPGA_FLOW.md
git commit -m "docs: record fpga policy power matrix"
git push origin codex/ieee-paper-v0
```

Generated `work/` artifacts remain ignored and must not be staged.
