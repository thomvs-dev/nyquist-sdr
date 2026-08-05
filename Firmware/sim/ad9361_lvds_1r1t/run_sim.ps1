param(
    [string]$IverilogBin = "C:\iverilog\bin"
)

$ErrorActionPreference = "Stop"
$simRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $simRoot "build"
$resultsDir = Join-Path $simRoot "results"
$iverilogExe = Join-Path $IverilogBin "iverilog.exe"
$vvpExe = Join-Path $IverilogBin "vvp.exe"

if (-not (Test-Path -LiteralPath $iverilogExe)) {
    throw "Icarus Verilog compiler not found at $iverilogExe"
}
if (-not (Test-Path -LiteralPath $vvpExe)) {
    throw "Icarus Verilog runtime not found at $vvpExe"
}

New-Item -ItemType Directory -Force -Path $buildDir, $resultsDir | Out-Null

$compiledModel = Join-Path $buildDir "ad9361_lvds_1r1t.vvp"
$rtlFile = Join-Path $simRoot "rtl\nyquist_ad9361_lvds_1r1t_demo.sv"
$tbFile = Join-Path $simRoot "tb\tb_nyquist_ad9361_lvds_1r1t.sv"

& $iverilogExe -g2012 -Wall -s tb_nyquist_ad9361_lvds_1r1t `
    -o $compiledModel $rtlFile $tbFile
if ($LASTEXITCODE -ne 0) {
    throw "Icarus Verilog compilation failed with exit code $LASTEXITCODE"
}

$nominalVcd = Join-Path $resultsDir "nominal.vcd"
$nominalTranscript = Join-Path $resultsDir "nominal_transcript.txt"
$nominalOutput = @(& $vvpExe $compiledModel "+VCD=$nominalVcd")
$nominalExitCode = $LASTEXITCODE
$nominalOutput | ForEach-Object { Write-Host $_ }
[IO.File]::WriteAllLines(
    $nominalTranscript, [string[]]$nominalOutput, [Text.UTF8Encoding]::new($false))
if ($nominalExitCode -ne 0) {
    throw "Nominal simulation failed with exit code $nominalExitCode"
}

$faultVcd = Join-Path $resultsDir "frame_error.vcd"
$faultTranscript = Join-Path $resultsDir "frame_error_transcript.txt"
$faultOutput = @(& $vvpExe $compiledModel "+VCD=$faultVcd" +INJECT_FRAME_ERROR)
$faultExitCode = $LASTEXITCODE
$faultOutput | ForEach-Object { Write-Host $_ }
[IO.File]::WriteAllLines(
    $faultTranscript, [string[]]$faultOutput, [Text.UTF8Encoding]::new($false))
if ($faultExitCode -ne 0) {
    throw "Fault-injection simulation failed with exit code $faultExitCode"
}

Write-Host "Simulation complete."
Write-Host "Nominal waveform: $nominalVcd"
Write-Host "Fault waveform:   $faultVcd"
