param(
  [string]$Python = 'python',
  [string]$TinyVitCheckpoint = 'work\models\tiny_vit_5m_224.dist_in22k_ft_in1k\model.safetensors',
  [string]$DeiTCheckpoint = 'work\models\deit_tiny_patch16_224.fb_in1k\deit_tiny_patch16_224-a1311bcf.pth',
  [string]$DatasetRoot = 'work\datasets\imagenette2-160',
  [string]$FixtureImage = '',
  [string]$FixtureDirectory = '',
  [string]$Output = 'work\model_generalization\transformer_generalization.json',
  [string]$Svh = '',
  [int]$ImagesPerClass = 1,
  [int]$BatchSize = 4,
  [int]$DeitOutputPairs = 4,
  [int]$DeitTokens = 2,
  [switch]$CheckOnly,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$repo = (Get-Item (Join-Path $PSScriptRoot '..')).FullName
$script = Join-Path $repo 'scripts\evaluate_transformer_generalization.py'
$checker = Join-Path $repo 'scripts\check_tiled_gemm_reference.py'
$packages = Join-Path $repo 'work\model_python_packages'
$previousPythonPath = $env:PYTHONPATH

if ($ImagesPerClass -lt 0) { throw 'ImagesPerClass must be nonnegative' }
if ($BatchSize -le 0) { throw 'BatchSize must be positive' }
if ($DeitOutputPairs -lt 2 -or $DeitOutputPairs -gt 384) { throw 'DeitOutputPairs must be between 2 and 384' }
if ($DeitTokens -lt 1 -or $DeitTokens -gt 197) { throw 'DeitTokens must be between 1 and 197' }
if ($FixtureImage -and $FixtureDirectory) { throw 'FixtureImage and FixtureDirectory are mutually exclusive' }
if ($SelfTest -and $CheckOnly) { throw 'SelfTest and CheckOnly are mutually exclusive' }
if ($Svh -and !$CheckOnly) { throw 'Svh requires CheckOnly' }
foreach ($path in @($script, $checker, $packages)) {
  if (!(Test-Path -LiteralPath $path)) { throw "Missing required path: $path" }
}

try {
  $env:PYTHONPATH = $packages
  if ($SelfTest) {
    & $Python $script --self-test
  } elseif ($CheckOnly) {
    $outputPath = Join-Path $repo $Output
    if (!(Test-Path -LiteralPath $outputPath)) { throw "Missing fixture: $outputPath" }
    $arguments = @($checker, $outputPath)
    if ($Svh) {
      $svhPath = Join-Path $repo $Svh
      New-Item -ItemType Directory -Force (Split-Path -Parent $svhPath) | Out-Null
      $arguments += @('--svh', $svhPath)
    }
    & $Python @arguments
  } else {
    $tinyvit = Join-Path $repo $TinyVitCheckpoint
    $deit = Join-Path $repo $DeiTCheckpoint
    $input = if ($FixtureImage) { $FixtureImage } elseif ($FixtureDirectory) { $FixtureDirectory } else { $DatasetRoot }
    $inputPath = Join-Path $repo $input
    $outputPath = Join-Path $repo $Output
    foreach ($path in @($tinyvit, $deit, $inputPath)) {
      if (!(Test-Path -LiteralPath $path)) { throw "Missing required input: $path" }
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $outputPath) | Out-Null
    $arguments = @($script, $tinyvit, $deit, $inputPath, $outputPath)
    if ($FixtureImage -or $FixtureDirectory) { $arguments += '--fixture-only' }
    $arguments += @(
      '--images-per-class', $ImagesPerClass,
      '--batch-size', $BatchSize,
      '--deit-output-pairs', $DeitOutputPairs,
      '--deit-tokens', $DeitTokens
    )
    & $Python @arguments
  }
  if ($LASTEXITCODE -ne 0) { throw "Model evaluation failed with exit code $LASTEXITCODE" }
} finally {
  $env:PYTHONPATH = $previousPythonPath
}
