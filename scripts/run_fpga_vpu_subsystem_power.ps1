param(
  [string]$VivadoRoot = 'D:\Xilinx_2023_02\Vivado\2023.2',
  [string]$OutDir = 'work\fpga\vpu_subsystem_140_saif_power',
  [string]$PostSynthDcp = 'work\fpga\vpu_subsystem_140\checkpoints\post_synth.dcp',
  [string]$PostRouteDcp = 'work\fpga\vpu_subsystem_140\checkpoints\post_route.dcp',
  [double]$ClockMhz = 140.0,
  [int]$Iterations = 128,
  [ValidateSet('mlp2_dense', 'fc2_dense', 'fc2_global_l1_6p25', 'fc2_l1_budget_2pct',
               'fc2_k512_dense', 'fc2_k512_global_l1_6p25', 'fc2_k512_l1_budget_2pct',
               'fc2_k512_pairs_dense', 'fc2_k512_pairs_global_l1_6p25',
               'fc2_k512_pairs_l1_budget_1pct', 'fc2_k512_stream_pairs_dense',
               'fc2_k512_stream_pairs_global_l1_12p5',
               'fc2_k512_stream_pairs_l1_budget_5pct')]
  [string]$Policy = 'mlp2_dense'
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$wslDistro = 'Ubuntu-20.04'
$settings = Join-Path $VivadoRoot 'settings64.bat'
$vcd2saif = '/opt/synopsys/syn/L-2016.03-SP1/linux64/syn/bin/vcd2saif'

if ($repo -notmatch '^\\\\wsl\.localhost\\([^\\]+)\\(.+)$') {
  throw "Repository must be opened through \\wsl.localhost: $repo"
}
$detectedDistro = $Matches[1]
$linuxRepo = '/' + ($Matches[2] -replace '\\', '/')
if ($detectedDistro -ne $wslDistro) {
  throw "WSL distro mismatch: expected $wslDistro, got $detectedDistro"
}
if ($ClockMhz -le 0.0) { throw 'ClockMhz must be positive' }
if ($Iterations -le 0) { throw 'Iterations must be positive' }
foreach ($path in @($OutDir, $PostSynthDcp, $PostRouteDcp)) {
  if ([IO.Path]::IsPathRooted($path) -or $path -match '(^|[\\/])\.\.([\\/]|$)') {
    throw "Path must be repository-relative: $path"
  }
}

$netlistDir = Join-Path $OutDir 'netlist'
$xsimDir = Join-Path $OutDir 'xsim'
$powerDir = Join-Path $OutDir 'power'
$fixtureDir = 'work\tinyvit\fixture'
$fc2FixtureDir = 'work\tinyvit_fc1_k128'
$fc2K512FixtureDir = 'work\tinyvit_fc2_k512'
$fixtureMetadataRel = Join-Path $fixtureDir 'tinyvit_mlp2_fixture_metadata.json'
$vcdRel = Join-Path $OutDir 'sap_vpu_subsystem_gate.vcd'
$saifRel = Join-Path $OutDir 'sap_vpu_subsystem_gate.saif'
$netlistRel = Join-Path $netlistDir 'sap_vpu_subsystem_funcsim.v'
$clockHalfNs = (500.0 / $ClockMhz).ToString('0.############', [cultureinfo]::InvariantCulture)

foreach ($path in @(
  $settings,
  (Join-Path $repo $PostSynthDcp),
  (Join-Path $repo $PostRouteDcp),
  (Join-Path $repo (Join-Path $fixtureDir 'tinyvit_mlp2_fixture_tb.svh')),
  (Join-Path $repo (Join-Path $fc2FixtureDir 'tinyvit_fc2_k128_policy_tb.svh')),
  (Join-Path $repo (Join-Path $fc2K512FixtureDir 'tinyvit_fc2_k512_policy_tb.svh')),
  (Join-Path $repo $fixtureMetadataRel),
  (Join-Path $repo 'rtl\sap_vpu_pkg.sv'),
  (Join-Path $repo 'tb\sap_vpu_subsystem_gate_tb.sv'),
  (Join-Path $repo 'scripts\vivado_vpu_write_funcsim.tcl'),
  (Join-Path $repo 'scripts\vivado_vpu_saif_power.tcl')
)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Missing required file: $path" }
}
$fixtureMetadata = Get-Content -Raw -LiteralPath (Join-Path $repo $fixtureMetadataRel) | ConvertFrom-Json
& wsl.exe -d $wslDistro -- test -x $vcd2saif
if ($LASTEXITCODE -ne 0) { throw "Missing vcd2saif: $vcd2saif" }

function Invoke-VivadoCmd([string]$Command, [string]$LogFile) {
  $line = "pushd `"$repo`" && set `"root=!CD!`" && call `"$settings`" && ($Command) > `"!root!\$LogFile`" 2>&1 & set `"ec=!errorlevel!`" & popd & exit /b !ec!"
  & cmd.exe /V:ON /d /s /c $line
  if ($LASTEXITCODE -ne 0) {
    $logPath = Join-Path $repo $LogFile
    if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 80 }
    throw "Vivado/XSim command failed ($LASTEXITCODE): $Command"
  }
}

$directories = @(
  (Join-Path $repo $OutDir),
  (Join-Path $repo $netlistDir),
  (Join-Path $repo $xsimDir),
  (Join-Path $repo $powerDir)
)
New-Item -ItemType Directory -Force -Path $directories | Out-Null

Invoke-VivadoCmd (
  'pushd "{0}" && vivado -mode batch -source "!root!\scripts\vivado_vpu_write_funcsim.tcl" -tclargs "!root!\{1}" "!root!\{0}" sap_vpu_subsystem && popd' -f $netlistDir, $PostSynthDcp
) (Join-Path $OutDir 'netlist_export.log')

$netlistPath = Join-Path $repo $netlistRel
if (!(Test-Path -LiteralPath $netlistPath) -or (Get-Item -LiteralPath $netlistPath).Length -eq 0) {
  throw "Missing or empty functional netlist: $netlistPath"
}

Invoke-VivadoCmd (
  'pushd "{0}" && xvlog -sv -i "!root!\{2}" -i "!root!\{3}" -i "!root!\{4}" "!root!\rtl\sap_vpu_pkg.sv" "!root!\tb\sap_vpu_subsystem_gate_tb.sv" "!root!\{1}" && xelab -debug typical -L unisims_ver sap_vpu_subsystem_gate_tb glbl -s sap_vpu_subsystem_gate_tb_snapshot && popd' -f $xsimDir, $netlistRel, $fixtureDir, $fc2FixtureDir, $fc2K512FixtureDir
) (Join-Path $OutDir 'compile.log')

Invoke-VivadoCmd (
  'pushd "{0}" && xsim --nolog -R --testplusarg "{{vcd=../sap_vpu_subsystem_gate.vcd iterations={1} clock_half_ns={2} policy={3}}}" sap_vpu_subsystem_gate_tb_snapshot && popd' -f $xsimDir, $Iterations, $clockHalfNs, $Policy
) (Join-Path $OutDir 'xsim.log')

$xsimLogPath = Join-Path $repo (Join-Path $OutDir 'xsim.log')
$vcdPath = Join-Path $repo $vcdRel
foreach ($path in @($xsimLogPath, $vcdPath)) {
  if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
    throw "Missing or empty XSim artifact: $path"
  }
}
$xsimLog = Get-Content -LiteralPath $xsimLogPath -Raw
if ($xsimLog -notmatch 'SUBSYSTEM_GATE_PASS' -or $xsimLog -match 'SUBSYSTEM_GATE_FAIL') {
  throw 'Subsystem gate simulation failed'
}

$linuxVcd = "$linuxRepo/" + ($vcdRel -replace '\\', '/')
$linuxSaif = "$linuxRepo/" + ($saifRel -replace '\\', '/')
& wsl.exe -d $wslDistro -- $vcd2saif -input $linuxVcd -output $linuxSaif
if ($LASTEXITCODE -ne 0) { throw 'vcd2saif failed' }
$saifPath = Join-Path $repo $saifRel
if (!(Test-Path -LiteralPath $saifPath) -or (Get-Item -LiteralPath $saifPath).Length -eq 0) {
  throw "Missing or empty SAIF: $saifPath"
}
$saifText = Get-Content -LiteralPath $saifPath -Raw
$durationMatch = [regex]::Match($saifText, '\(DURATION\s+(\d+)\)')
if (!$durationMatch.Success -or [long]$durationMatch.Groups[1].Value -le 0) {
  throw 'Missing or invalid SAIF duration'
}
$durationPs = [long]$durationMatch.Groups[1].Value

$powerCommand = 'pushd "{0}" && vivado -mode batch -source "!root!\scripts\vivado_vpu_saif_power.tcl" -tclargs "!root!\{1}" "!root!\{2}" "!root!\{0}" && popd' -f $powerDir, $PostRouteDcp, $saifRel
$powerLogRel = Join-Path $OutDir 'vivado_power.log'
try {
  Invoke-VivadoCmd $powerCommand $powerLogRel
} catch {
  if ($_.Exception.Message -notmatch '\(-1073741819\)') { throw }
  $powerLogRel = Join-Path $OutDir 'vivado_power_retry.log'
  Write-Warning 'Vivado power process crashed; retrying once with identical inputs'
  Invoke-VivadoCmd $powerCommand $powerLogRel
}

$vivadoLogPath = Join-Path $repo $powerLogRel
$reportPath = Join-Path $repo (Join-Path $powerDir 'reports\post_route_saif_power.rpt')
foreach ($path in @($vivadoLogPath, $reportPath)) {
  if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
    throw "Missing or empty Vivado artifact: $path"
  }
}
$vivadoLog = Get-Content -LiteralPath $vivadoLogPath -Raw
if ($vivadoLog -match 'Power 33-(332|334)') { throw 'Clock/reset activity warning in power run' }
$netMatch = [regex]::Match($vivadoLog, 'Design nets matched = (\d+) of (\d+)')
if (!$netMatch.Success) { throw 'Missing SAIF net-match count' }
$netsMatched = [int]$netMatch.Groups[1].Value
$designNets = [int]$netMatch.Groups[2].Value
if ($designNets -le 0 -or $netsMatched / $designNets -lt 0.99) {
  throw "Less than 99% nets matched: $netsMatched/$designNets"
}

$report = Get-Content -LiteralPath $reportPath -Raw
$fields = @{}
foreach ($field in @('Total On-Chip Power (W)', 'Dynamic (W)', 'Device Static (W)', 'Confidence Level')) {
  $match = [regex]::Match($report, '(?m)^\|\s*' + [regex]::Escape($field) + '\s*\|\s*([^|]+?)\s*\|')
  if (!$match.Success) { throw "Missing power field: $field" }
  $fields[$field] = $match.Groups[1].Value.Trim()
}
$dynamicW = [double]::Parse($fields['Dynamic (W)'], [cultureinfo]::InvariantCulture)
$workload = 'tinyvit_mlp2_2x4x4x2'
$tilesPerIteration = 3
$vdotsPerIteration = 12
$readsPerIteration = 12
$writesPerIteration = 12
switch ($Policy) {
  'fc2_dense' {
    $workload = 'tinyvit_fc2_2x128x2'
    $tilesPerIteration = 16
    $vdotsPerIteration = 128
    $readsPerIteration = 128
    $writesPerIteration = 64
  }
  'fc2_global_l1_6p25' {
    $workload = 'tinyvit_fc2_2x128x2'
    $tilesPerIteration = 16
    $vdotsPerIteration = 120
    $readsPerIteration = 124
    $writesPerIteration = 64
  }
  'fc2_l1_budget_2pct' {
    $workload = 'tinyvit_fc2_2x128x2'
    $tilesPerIteration = 16
    $vdotsPerIteration = 122
    $readsPerIteration = 125
    $writesPerIteration = 64
  }
  'fc2_k512_dense' {
    $workload = 'tinyvit_fc2_2x512x2'
    $tilesPerIteration = 64
    $vdotsPerIteration = 512
    $readsPerIteration = 512
    $writesPerIteration = 256
  }
  'fc2_k512_global_l1_6p25' {
    $workload = 'tinyvit_fc2_2x512x2'
    $tilesPerIteration = 64
    $vdotsPerIteration = 480
    $readsPerIteration = 496
    $writesPerIteration = 256
  }
  'fc2_k512_l1_budget_2pct' {
    $workload = 'tinyvit_fc2_2x512x2'
    $tilesPerIteration = 64
    $vdotsPerIteration = 480
    $readsPerIteration = 496
    $writesPerIteration = 256
  }
  'fc2_k512_pairs_dense' {
    $workload = 'tinyvit_fc2_4pairs_2x512x2'
    $tilesPerIteration = 256
    $vdotsPerIteration = 2048
    $readsPerIteration = 2048
    $writesPerIteration = 1024
  }
  'fc2_k512_pairs_global_l1_6p25' {
    $workload = 'tinyvit_fc2_4pairs_2x512x2'
    $tilesPerIteration = 256
    $vdotsPerIteration = 1868
    $readsPerIteration = 1956
    $writesPerIteration = 1024
  }
  'fc2_k512_pairs_l1_budget_1pct' {
    $workload = 'tinyvit_fc2_4pairs_2x512x2'
    $tilesPerIteration = 256
    $vdotsPerIteration = 1922
    $readsPerIteration = 1985
    $writesPerIteration = 1024
  }
  'fc2_k512_stream_pairs_dense' {
    $workload = 'tinyvit_fc2_4pairs_2x512x2_stream'
    $tilesPerIteration = 256
    $vdotsPerIteration = 2048
    $readsPerIteration = 2064
    $writesPerIteration = 16
  }
  'fc2_k512_stream_pairs_global_l1_12p5' {
    $workload = 'tinyvit_fc2_4pairs_2x512x2_stream'
    $tilesPerIteration = 256
    $vdotsPerIteration = 1740
    $readsPerIteration = 1970
    $writesPerIteration = 16
  }
  'fc2_k512_stream_pairs_l1_budget_5pct' {
    $workload = 'tinyvit_fc2_4pairs_2x512x2_stream'
    $tilesPerIteration = 256
    $vdotsPerIteration = 1730
    $readsPerIteration = 1965
    $writesPerIteration = 16
  }
}
$tiles = $Iterations * $tilesPerIteration
$vdots = $Iterations * $vdotsPerIteration
$ramReads = $Iterations * $readsPerIteration
$ramWrites = $Iterations * $writesPerIteration
$dynamicEnergyPj = $dynamicW * $durationPs
$summary = [pscustomobject]@{
  top = 'sap_vpu_subsystem'
  workload = $workload
  policy = $Policy
  fixture_kind = $fixtureMetadata.provenance.kind
  model_id = $fixtureMetadata.provenance.model_id
  layer_id = $fixtureMetadata.provenance.layer_id
  checkpoint_sha256 = $fixtureMetadata.provenance.checkpoint_sha256
  input_source = $fixtureMetadata.provenance.input_source
  clock_mhz = $ClockMhz.ToString('0.###', [cultureinfo]::InvariantCulture)
  iterations = $Iterations
  tiles = $tiles
  vdots = $vdots
  ram_reads = $ramReads
  ram_writes = $ramWrites
  total_w = $fields['Total On-Chip Power (W)']
  dynamic_w = $fields['Dynamic (W)']
  static_w = $fields['Device Static (W)']
  duration_ps = $durationPs
  dynamic_pj_per_workload = ($dynamicEnergyPj / $Iterations).ToString('0.000', [cultureinfo]::InvariantCulture)
  dynamic_pj_per_mlp2 = if ($Policy -eq 'mlp2_dense') { ($dynamicEnergyPj / $Iterations).ToString('0.000', [cultureinfo]::InvariantCulture) } else { '' }
  dynamic_pj_per_tile = ($dynamicEnergyPj / $tiles).ToString('0.000', [cultureinfo]::InvariantCulture)
  dynamic_pj_per_vdot = ($dynamicEnergyPj / $vdots).ToString('0.000', [cultureinfo]::InvariantCulture)
  confidence = $fields['Confidence Level']
  nets_matched = $netsMatched
  design_nets = $designNets
}
$summaryPath = Join-Path $repo (Join-Path $OutDir 'fpga_vpu_subsystem_power.csv')
$summary | Export-Csv -NoTypeInformation -Encoding UTF8 $summaryPath
if (!(Test-Path -LiteralPath $summaryPath) -or (Get-Item -LiteralPath $summaryPath).Length -eq 0) {
  throw "Missing power summary: $summaryPath"
}
Write-Output "FPGA subsystem power written to $summaryPath"
Write-Output ($summary | Format-List | Out-String)
