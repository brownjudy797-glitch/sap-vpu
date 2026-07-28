param(
  [string]$VivadoRoot = 'D:\Xilinx_2023_02\Vivado\2023.2',
  [string]$OutDir = 'work\fpga\vpu_core',
  [string]$Part = 'xc7a35tcsg324-1',
  [double]$ClockMhz = 100.0,
  [string]$Top = 'sap_vpu_core',
  [ValidateSet(0, 1)]
  [int]$OutOfContext = 0
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$settings = Join-Path $VivadoRoot 'settings64.bat'

if ($repo -notmatch '^\\\\wsl\.localhost\\([^\\]+)\\(.+)$') {
  throw "Repository must be opened through \\wsl.localhost: $repo"
}
if ($ClockMhz -le 0.0) { throw 'ClockMhz must be positive' }
if ([IO.Path]::IsPathRooted($OutDir) -or $OutDir -match '(^|[\\/])\.\.([\\/]|$)') {
  throw "OutDir must be repository-relative: $OutDir"
}
if (!(Test-Path -LiteralPath $settings)) { throw "Missing Vivado settings: $settings" }

$outPath = Join-Path $repo $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null
$clock = $ClockMhz.ToString('0.############', [cultureinfo]::InvariantCulture)
$logRel = Join-Path $OutDir 'synth_console.log'
$command = 'pushd "!root!\{0}" && vivado -mode batch -source "!root!\scripts\vivado_vpu_synth.tcl" -tclargs "{1}" "{2}" "!root!\{0}" "{3}" "{4}" && popd' -f $OutDir, $Part, $clock, $Top, $OutOfContext
$line = "pushd `"$repo`" && set `"root=!CD!`" && call `"$settings`" && ($command) > `"!root!\$logRel`" 2>&1 & set `"ec=!errorlevel!`" & popd & exit /b !ec!"

& cmd.exe /V:ON /d /s /c $line
if ($LASTEXITCODE -ne 0) {
  $logPath = Join-Path $repo $logRel
  if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 100 }
  throw "Vivado synthesis failed with exit code $LASTEXITCODE"
}

$summaryPath = Join-Path $outPath 'fpga_vpu_summary.csv'
foreach ($path in @(
  $summaryPath,
  (Join-Path $outPath 'checkpoints\post_synth.dcp'),
  (Join-Path $outPath 'checkpoints\post_route.dcp'),
  (Join-Path $outPath 'reports\post_route_utilization.rpt'),
  (Join-Path $outPath 'reports\post_route_timing_summary.rpt')
)) {
  if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
    throw "Missing or empty Vivado artifact: $path"
  }
}

$summary = Import-Csv -LiteralPath $summaryPath
Write-Output "FPGA synthesis written to $summaryPath"
Write-Output ($summary | Format-List | Out-String)
