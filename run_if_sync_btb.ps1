param(
    [string]$BuildDir = (Join-Path $PSScriptRoot "work\if_sync_btb")
)

$ErrorActionPreference = "Stop"

$iverilog = (Get-Command iverilog -ErrorAction Stop).Source
$vvp = (Get-Command vvp -ErrorAction Stop).Source

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$sim = Join-Path $BuildDir "tb_if_sync_btb_single.vvp"

& $iverilog `
    -g2012 `
    -Wall `
    -I (Join-Path $PSScriptRoot "rtl\cpu_top") `
    -s tb_if_sync_btb_single `
    -o $sim `
    (Join-Path $PSScriptRoot "rtl\cpu_top\if_stage.sv") `
    (Join-Path $PSScriptRoot "test\tb_if_sync_btb_single.sv")

if ($LASTEXITCODE -ne 0) {
    throw "iverilog compile failed with exit code $LASTEXITCODE"
}

& $vvp $sim
if ($LASTEXITCODE -ne 0) {
    throw "BTB directed test failed with exit code $LASTEXITCODE"
}
