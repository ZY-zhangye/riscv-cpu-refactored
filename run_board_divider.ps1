param(
    [string]$BuildDir = (Join-Path $PSScriptRoot 'work\board_divider')
)

$ErrorActionPreference = 'Stop'
$iverilog = (Get-Command iverilog -ErrorAction Stop).Source
$vvp = (Get-Command vvp -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$sim = Join-Path $BuildDir 'tb_board_divider.vvp'

# The board divider deliberately replaces, rather than accompanies, the
# behavioural rtl/cpu_top/divider.sv module. mul.sv keeps its DEBUG_EN word order.
& $iverilog -g2012 -Wall -I (Join-Path $PSScriptRoot 'rtl\cpu_top') `
    -s tb_board_divider -o $sim `
    (Join-Path $PSScriptRoot 'rtl\cpu_top\synth\rv32_divider_hw.sv') `
    (Join-Path $PSScriptRoot 'rtl\cpu_top\mul_pipeline.sv') `
    (Join-Path $PSScriptRoot 'rtl\cpu_top\mul.sv') `
    (Join-Path $PSScriptRoot 'test\tb_board_divider.sv')
if ($LASTEXITCODE -ne 0) { throw "Board divider compile failed ($LASTEXITCODE)." }

& $vvp $sim
if ($LASTEXITCODE -ne 0) { throw "Board divider test failed ($LASTEXITCODE)." }
