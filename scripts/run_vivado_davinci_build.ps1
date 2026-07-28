param(
  [string]$VivadoRoot = 'D:\Xilinx_2023_02\Vivado\2023.2',
  [string]$OutDir = 'work\fpga\davinci_hello_50',
  [string]$Part = 'xc7a200tfbg484-2',
  [string]$RomHex = 'work\hello\sap_vpu_hello.hex',
  [string]$Image = 'hello',
  [int]$ClockMHz = 50
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$settings = Join-Path $VivadoRoot 'settings64.bat'
foreach ($path in @($OutDir, $RomHex)) {
  if ([IO.Path]::IsPathRooted($path) -or $path -match '(^|[\\/])\.\.([\\/]|$)') {
    throw "Path must be repository-relative: $path"
  }
}
if (!(Test-Path -LiteralPath $settings)) { throw "Missing Vivado settings: $settings" }
if ($Image -notmatch '^[A-Za-z0-9_-]+$') { throw "Invalid image name: $Image" }
if ($ClockMHz -notin @(50, 60, 70, 80, 100)) { throw "ClockMHz must be 50, 60, 70, 80, or 100" }

$outPath = Join-Path $repo $OutDir
$romPath = Join-Path $repo $RomHex
$flistPath = Join-Path $repo 'work\corev_rtl.f'
foreach ($path in @($romPath, $flistPath)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Missing board input: $path" }
}
New-Item -ItemType Directory -Force -Path $outPath | Out-Null
Copy-Item -Force -LiteralPath $romPath -Destination (Join-Path $outPath 'sap_vpu_hello.hex')
$bitPath = Join-Path $outPath "sap_vpu_davinci_$Image.bit"
if (Test-Path -LiteralPath $bitPath) { Remove-Item -Force -LiteralPath $bitPath }

$logRel = Join-Path $OutDir 'board_console.log'
$command = 'pushd "!root!\{0}" && vivado -mode batch -source "!root!\scripts\vivado_davinci_build.tcl" -tclargs "{1}" "!root!\{0}" "!root!\work\corev_rtl.f" "{2}" "{3}" && popd' -f $OutDir, $Part, $Image, $ClockMHz
$line = "pushd `"$repo`" && set `"root=!CD!`" && call `"$settings`" && ($command) > `"!root!\$logRel`" 2>&1 & set `"ec=!errorlevel!`" & popd & exit /b !ec!"
& cmd.exe /V:ON /d /s /c $line
if ($LASTEXITCODE -ne 0) {
  $logPath = Join-Path $repo $logRel
  if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 120 }
  throw "Vivado Davinci build failed with exit code $LASTEXITCODE"
}

foreach ($path in @(
  $bitPath,
  (Join-Path $outPath 'fpga_davinci_summary.csv'),
  (Join-Path $outPath 'checkpoints\post_route.dcp'),
  (Join-Path $outPath 'reports\post_route_timing_summary.rpt')
)) {
  if (!(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) {
    throw "Missing or empty board artifact: $path"
  }
}
Write-Output "Davinci bitstream written to $outPath"
Write-Output (Import-Csv -LiteralPath (Join-Path $outPath 'fpga_davinci_summary.csv') | Format-List | Out-String)
