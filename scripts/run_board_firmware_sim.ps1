param(
    [Parameter(Mandatory=$true)][string]$FirmwareDir,
    [string]$PassText = 'SMOKE_PASS',
    [int]$MaxCycles = 20000000,
    [string]$BuildDir = ''
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$FirmwareDir=[System.IO.Path]::GetFullPath($FirmwareDir)
if (!$BuildDir) { $BuildDir=Join-Path $repoRoot ('build/hello_zynq/firmware_sim_'+[guid]::NewGuid().ToString('N').Substring(0,8)) }
$BuildDir=[System.IO.Path]::GetFullPath($BuildDir)
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
$inst=(Join-Path $FirmwareDir 'inst.mem').Replace('\','/')
$data=(Join-Path $FirmwareDir 'data.mem').Replace('\','/')
if (!(Test-Path -LiteralPath $inst) -or !(Test-Path -LiteralPath $data)) { throw 'Firmware images missing.' }
$sources=@(Get-ChildItem (Join-Path $repoRoot 'rtl/cpu_top') -Filter *.sv | Where-Object Name -ne 'divider.sv' | ForEach-Object FullName)
$sources+=@(Get-ChildItem (Join-Path $repoRoot 'rtl/my_cpu') -Filter *.sv | ForEach-Object FullName)
$sources+=Join-Path $repoRoot 'rtl/board/rv32_divider_hw.sv'
$sources+=Join-Path $repoRoot 'test/tb_board_firmware.sv'
Push-Location $BuildDir
try {
    & vlib.exe work
    if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & vmap.exe -c
    & vmap.exe firmware_sim work
    & vlog.exe -sv -work work "+incdir+$repoRoot/rtl/cpu_top" "+incdir+$repoRoot/rtl/my_cpu" $sources
    if ($LASTEXITCODE -ne 0) { throw 'Firmware RTL compile failed' }
    & vsim.exe -c -lib firmware_sim tb_board_firmware "-gINST_FILE=$inst" "-gDATA_FILE=$data" "-gPASS_TEXT=$PassText" "-gMAX_CYCLES=$MaxCycles" -do 'run -all; quit -force' -l firmware.log
    if ($LASTEXITCODE -ne 0) { throw 'Firmware simulation process failed' }
    $log=Get-Content firmware.log -Raw
    if ($log -notmatch 'BOARD_FIRMWARE_PASS' -or $log -match '\*\* (Fatal|Error):') { throw 'Firmware simulation did not pass; inspect firmware.log' }
} finally { Pop-Location }
Write-Host "FIRMWARE_SIM_VERIFIED $BuildDir"
