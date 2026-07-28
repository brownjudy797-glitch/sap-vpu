param(
  [string]$VivadoRoot = 'D:\Xilinx_2023_02\Vivado\2023.2',
  [string]$Bitstream = 'work\fpga\davinci_hello_50\sap_vpu_davinci_hello.bit',
  [string]$SerialPort = 'COM5',
  [int]$Baud = 115200,
  [int]$CaptureSeconds = 5,
  [string]$ExpectedText = "SAP-VPU hello`n",
  [switch]$DiscardAfterProgram
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$settings = Join-Path $VivadoRoot 'settings64.bat'
if ([IO.Path]::IsPathRooted($Bitstream) -or $Bitstream -match '(^|[\\/])\.\.([\\/]|$)') {
  throw "Bitstream must be repository-relative: $Bitstream"
}
$bitPath = Join-Path $repo $Bitstream
foreach ($path in @($settings, $bitPath)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Missing board input: $path" }
}

$available = [IO.Ports.SerialPort]::GetPortNames()
if ($available -notcontains $SerialPort) {
  throw "Serial port $SerialPort not found; available: $($available -join ', ')"
}

$port = [IO.Ports.SerialPort]::new($SerialPort, $Baud, 'None', 8, 'One')
$port.Encoding = [Text.Encoding]::ASCII
$port.ReadTimeout = 200
$transcript = ''
$stageDir = Join-Path ([IO.Path]::GetTempPath()) ("sap-vpu-board-smoke-{0}" -f [guid]::NewGuid().ToString('N'))
$stageBit = Join-Path $stageDir 'design.bit'
$stageTcl = Join-Path $stageDir 'program.tcl'
$stageLog = Join-Path $stageDir 'board_smoke.log'
$logRel = Join-Path (Split-Path -Parent $Bitstream) 'board_smoke.log'
$logPath = Join-Path $repo $logRel

try {
  New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
  Copy-Item -Force -LiteralPath $bitPath -Destination $stageBit
  Copy-Item -Force -LiteralPath (Join-Path $repo 'scripts\vivado_davinci_program.tcl') -Destination $stageTcl

  $port.Open()
  $port.DiscardInBuffer()

  $command = 'pushd "{0}" && vivado -mode batch -source "{1}" -tclargs "{2}" > "{3}" 2>&1 & set "ec=!errorlevel!" & popd & exit /b !ec!' -f ([IO.Path]::GetTempPath()), $stageTcl, $stageBit, $stageLog
  $line = "call `"$settings`" && $command"
  & cmd.exe /V:ON /d /s /c $line
  if (Test-Path -LiteralPath $stageLog) { Copy-Item -Force -LiteralPath $stageLog -Destination $logPath }
  if ($LASTEXITCODE -ne 0) {
    if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 80 }
    throw "Vivado JTAG programming failed with exit code $LASTEXITCODE"
  }
  if ($DiscardAfterProgram) { $port.DiscardInBuffer() }

  $deadline = (Get-Date).AddSeconds($CaptureSeconds)
  while ((Get-Date) -lt $deadline -and !$transcript.Contains($ExpectedText)) {
    if ($port.BytesToRead -gt 0) { $transcript += $port.ReadExisting() }
    Start-Sleep -Milliseconds 50
  }
} finally {
  if ($port.IsOpen) { $port.Close() }
  if (Test-Path -LiteralPath $stageDir) {
    try { Remove-Item -Recurse -Force -LiteralPath $stageDir -ErrorAction Stop }
    catch { Write-Warning "Could not remove board smoke staging directory: $stageDir" }
  }
}

if (!$transcript.Contains($ExpectedText)) {
  $hex = ([Text.Encoding]::ASCII.GetBytes($transcript) | ForEach-Object { $_.ToString('X2') }) -join ' '
  throw "UART hello not observed on $SerialPort; captured '$transcript'; hex: $hex"
}
$artifactDir = Split-Path -Parent $bitPath
[IO.File]::WriteAllText((Join-Path $artifactDir 'board_smoke_uart.txt'), $transcript, [Text.Encoding]::ASCII)
[PSCustomObject]@{
  status = 'pass'
  serial_port = $SerialPort
  baud = $Baud
  expected = $ExpectedText.Replace("`n", '\n')
  captured_bytes = [Text.Encoding]::ASCII.GetByteCount($transcript)
  timestamp = (Get-Date).ToString('o')
} | Export-Csv -NoTypeInformation -Encoding ASCII -LiteralPath (Join-Path $artifactDir 'board_smoke_summary.csv')
Write-Output "DAVINCI_BOARD_SMOKE_PASS: $($transcript.TrimEnd())"
