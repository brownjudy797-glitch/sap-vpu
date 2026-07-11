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
$repo = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$WslDistro = 'Ubuntu-20.04'
$Dcp = 'work\fpga\vpu_core_sliced_140\checkpoints\post_route.dcp'
$Netlist = 'work\fpga\vpu_core_sliced_140_funcsim\sap_vpu_core_funcsim.v'
$settings = Join-Path $VivadoRoot 'settings64.bat'
$vcd2saif = '/opt/synopsys/syn/L-2016.03-SP1/bin/vcd2saif'

if ($repo -notmatch '^\\\\wsl\.localhost\\([^\\]+)\\(.+)$') {
  throw "Repository must be opened through \\wsl.localhost: $repo"
}
$detectedDistro = $Matches[1]
$linuxRepo = '/' + ($Matches[2] -replace '\\', '/')
if ($detectedDistro -ne $WslDistro) {
  throw "WSL distro mismatch: expected $WslDistro, got $detectedDistro"
}
if ([IO.Path]::IsPathRooted($OutDir) -or $OutDir -match '(^|[\\/])\.\.([\\/]|$)') {
  throw "OutDir must be repository-relative: $OutDir"
}
if (!$Policies -or $Policies -cnotcontains 'dense_int8') {
  throw 'Policies must include dense_int8 for normalization'
}
if (@($Policies | Select-Object -Unique).Count -ne $Policies.Count) {
  throw 'Policies must not contain duplicates'
}
foreach ($policy in $Policies) {
  if ($policy -notmatch '^[A-Za-z0-9_]+$') { throw "Invalid policy name: $policy" }
}
foreach ($path in @(
  $settings,
  (Join-Path $repo $Dcp),
  (Join-Path $repo $Netlist),
  (Join-Path $repo 'rtl\sap_vpu_pkg.sv'),
  (Join-Path $repo 'tb\sap_vpu_core_gate_tb.sv'),
  (Join-Path $repo 'scripts\vivado_vpu_saif_power.tcl')
)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Missing required file: $path" }
}
& wsl.exe -d $WslDistro -- test -x $vcd2saif
if ($LASTEXITCODE -ne 0) { throw "Missing vcd2saif: $vcd2saif" }

function Invoke-VivadoCmd([string]$Command, [string]$LogFile) {
  $line = "pushd `"$repo`" && set `"root=!CD!`" && call `"$settings`" && ($Command) > `"!root!\$LogFile`" 2>&1 & set `"ec=!errorlevel!`" & popd & exit /b !ec!"
  & cmd.exe /V:ON /d /s /c $line
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $logPath = Join-Path $repo $LogFile
    if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 80 }
    throw "Vivado/XSim command failed ($exitCode): $Command"
  }
}

$outPath = Join-Path $repo $OutDir
$xsimDir = Join-Path $OutDir 'xsim'
New-Item -ItemType Directory -Force $outPath, (Join-Path $repo $xsimDir) | Out-Null
Invoke-VivadoCmd (
  'pushd "{0}" && xvlog -sv "!root!\rtl\sap_vpu_pkg.sv" "!root!\tb\sap_vpu_core_gate_tb.sv" "!root!\{1}" && xelab -debug typical -L unisims_ver sap_vpu_core_gate_tb glbl -s sap_vpu_core_gate_tb_snapshot' -f $xsimDir, $Netlist
) (Join-Path $xsimDir 'compile.log')

$rows = @()
foreach ($policy in $Policies) {
  $policyDir = Join-Path $OutDir $policy
  $policyPath = Join-Path $repo $policyDir
  $vcdRel = Join-Path $policyDir "$policy.vcd"
  $saifRel = Join-Path $policyDir "$policy.saif"
  $xsimLogRel = Join-Path $policyDir 'xsim.log'
  $vivadoLogRel = Join-Path $policyDir 'vivado_power.log'
  New-Item -ItemType Directory -Force $policyPath | Out-Null

  Invoke-VivadoCmd (
    'pushd "{0}" && xsim --nolog -R --testplusarg "{{policy={1} vcd=../{1}/{1}.vcd}}" sap_vpu_core_gate_tb_snapshot' -f $xsimDir, $policy
  ) $xsimLogRel
  foreach ($path in @((Join-Path $repo $vcdRel), (Join-Path $repo $xsimLogRel))) {
    if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
      throw "Missing or empty XSim artifact: $path"
    }
  }
  $xsimLog = Get-Content -LiteralPath (Join-Path $repo $xsimLogRel) -Raw
  if ($xsimLog -notmatch ('GATE_POLICY_PASS: ' + [regex]::Escape($policy)) -or $xsimLog -match 'GATE_.*_FAIL') {
    throw "Gate policy simulation failed: $policy"
  }

  $linuxVcd = "$linuxRepo/" + ($vcdRel -replace '\\', '/')
  $linuxSaif = "$linuxRepo/" + ($saifRel -replace '\\', '/')
  & wsl.exe -d $WslDistro -- $vcd2saif -input $linuxVcd -output $linuxSaif
  if ($LASTEXITCODE -ne 0) { throw "vcd2saif failed: $policy" }
  $saifPath = Join-Path $repo $saifRel
  if (!(Test-Path -LiteralPath $saifPath) -or (Get-Item -LiteralPath $saifPath).Length -eq 0) {
    throw "Missing or empty SAIF: $saifPath"
  }
  $saifText = Get-Content -LiteralPath $saifPath -Raw
  if ($saifText -notmatch '\(TIMESCALE 1 ps\)') { throw "Unexpected SAIF timescale: $policy" }
  $durationMatch = [regex]::Match($saifText, '\(DURATION\s+(\d+)\)')
  if (!$durationMatch.Success -or [long]$durationMatch.Groups[1].Value -le 0) {
    throw "Missing or invalid SAIF duration: $policy"
  }
  $durationPs = [long]$durationMatch.Groups[1].Value

  Invoke-VivadoCmd (
    'vivado -mode batch -source scripts\vivado_vpu_saif_power.tcl -tclargs "{0}" "{1}\{2}.saif" "{1}\power"' -f $Dcp, $policyDir, $policy
  ) $vivadoLogRel
  $reportPath = Join-Path $policyPath 'power\reports\post_route_saif_power.rpt'
  foreach ($path in @((Join-Path $repo $vivadoLogRel), $reportPath)) {
    if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
      throw "Missing or empty Vivado artifact: $path"
    }
  }
  $vivadoLog = Get-Content -LiteralPath (Join-Path $repo $vivadoLogRel) -Raw
  if ($vivadoLog -match 'Power 33-(332|334)') { throw "Clock/reset activity warning: $policy" }
  $netMatch = [regex]::Match($vivadoLog, 'Design nets matched = (\d+) of (\d+)')
  if (!$netMatch.Success) { throw "Missing net-match count: $policy" }
  $netsMatched = [int]$netMatch.Groups[1].Value
  $designNets = [int]$netMatch.Groups[2].Value
  if ($designNets -le 0 -or $netsMatched / $designNets -lt 0.99) {
    throw "Less than 99% nets matched: $policy"
  }

  $report = Get-Content -LiteralPath $reportPath -Raw
  $fields = @{}
  foreach ($field in @('Total On-Chip Power (W)', 'Dynamic (W)', 'Device Static (W)', 'Confidence Level')) {
    $match = [regex]::Match($report, '(?m)^\|\s*' + [regex]::Escape($field) + '\s*\|\s*([^|]+?)\s*\|')
    if (!$match.Success) { throw "Missing power field for ${policy}: $field" }
    $fields[$field] = $match.Groups[1].Value.Trim()
  }
  $rows += [pscustomobject]@{
    policy = $policy
    total_w = [double]::Parse($fields['Total On-Chip Power (W)'], [cultureinfo]::InvariantCulture)
    dynamic_w = [double]::Parse($fields['Dynamic (W)'], [cultureinfo]::InvariantCulture)
    static_w = [double]::Parse($fields['Device Static (W)'], [cultureinfo]::InvariantCulture)
    duration_ps = $durationPs
    confidence = $fields['Confidence Level']
    nets_matched = $netsMatched
    design_nets = $designNets
  }
}

$dense = @($rows | Where-Object { $_.policy -ceq 'dense_int8' })
if ($dense.Count -ne 1 -or $dense[0].dynamic_w -le 0) { throw 'Invalid dense_int8 dynamic power' }
$durationPs = $rows[0].duration_ps
if ($rows | Where-Object { $_.duration_ps -ne $durationPs }) { throw 'Policy SAIF durations do not match' }
$summaryRows = foreach ($row in $rows) {
  [pscustomobject]@{
    policy = $row.policy
    total_w = $row.total_w.ToString('0.000', [cultureinfo]::InvariantCulture)
    dynamic_w = $row.dynamic_w.ToString('0.000', [cultureinfo]::InvariantCulture)
    static_w = $row.static_w.ToString('0.000', [cultureinfo]::InvariantCulture)
    dynamic_vs_dense = ($row.dynamic_w / $dense[0].dynamic_w).ToString('0.000', [cultureinfo]::InvariantCulture)
    duration_ps = $row.duration_ps
    dynamic_pj_per_vdot = ($row.dynamic_w * $row.duration_ps / 512).ToString('0.000', [cultureinfo]::InvariantCulture)
    confidence = $row.confidence
    nets_matched = $row.nets_matched
    design_nets = $row.design_nets
  }
}

$csvPath = Join-Path $outPath 'fpga_vpu_policy_power_matrix.csv'
$mdPath = Join-Path $outPath 'fpga_vpu_policy_power_matrix.md'
$summaryRows | Export-Csv -NoTypeInformation -Encoding UTF8 $csvPath
$md = @(
  '# SAP-VPU FPGA Policy Power Matrix', '',
  '| Policy | Total W | Dynamic W | Static W | Dynamic vs dense | Duration ps | Dynamic pJ/VDOT | Confidence | Nets matched |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |'
)
foreach ($row in $summaryRows) {
  $md += "| $($row.policy) | $($row.total_w) | $($row.dynamic_w) | $($row.static_w) | $($row.dynamic_vs_dense) | $($row.duration_ps) | $($row.dynamic_pj_per_vdot) | $($row.confidence) | $($row.nets_matched)/$($row.design_nets) |"
}
$md += ''
$md += 'Standalone 140 MHz SAP-VPU runtime-policy activity, not a hardware-removal ablation, full-SoC, board, or end-to-end result.'
$md | Set-Content -Encoding UTF8 $mdPath
foreach ($path in @($csvPath, $mdPath)) {
  if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
    throw "Missing or empty summary: $path"
  }
}
Write-Output "FPGA policy power matrix written to $outPath"
