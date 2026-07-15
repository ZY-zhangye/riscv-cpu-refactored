param(
    [switch]$KeepLibrary
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$benchDir = Join-Path $repoRoot "riscv_sim_perf_bench"
$toolchainDir = "F:\Tools\Apps\riscv64-unknown-elf-gcc-13.2\usr\bin"
$library = Join-Path $repoRoot "work\perf_bench"
$modelsimIni = Join-Path $repoRoot "work\modelsim.ini"
$log = Join-Path $repoRoot "results\perf_bench.log"

$portableBenchDir = $benchDir.Replace("\", "/")
$wslBenchDir = & wsl.exe wslpath -a $portableBenchDir
if ($LASTEXITCODE -ne 0 -or -not $wslBenchDir) {
    throw "Unable to translate benchmark path for WSL."
}
$wslBenchDir = $wslBenchDir.Trim()

$portableToolchainDir = $toolchainDir.Replace("\", "/")
$wslToolchainDir = & wsl.exe wslpath -a $portableToolchainDir
if ($LASTEXITCODE -ne 0 -or -not $wslToolchainDir) {
    throw "Unable to translate the F: RISC-V toolchain path for WSL."
}
$wslToolchainDir = $wslToolchainDir.Trim()

Write-Host "[PERF] Building RV32 benchmark image..."
$buildCommand = "cd '$wslBenchDir' && make clean && make " +
    "RISCV_GCC='$wslToolchainDir/riscv64-unknown-elf-gcc' " +
    "RISCV_OBJCOPY='$wslToolchainDir/riscv64-unknown-elf-objcopy' " +
    "RISCV_OBJDUMP='$wslToolchainDir/riscv64-unknown-elf-objdump'"
& wsl.exe sh -lc $buildCommand
if ($LASTEXITCODE -ne 0) {
    throw "Benchmark build failed."
}

New-Item -ItemType Directory -Force (Split-Path $library) | Out-Null
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
if ((Test-Path $library) -and -not $KeepLibrary) {
    $workRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "work")) + [System.IO.Path]::DirectorySeparatorChar
    $libraryPath = [System.IO.Path]::GetFullPath($library)
    if (-not $libraryPath.StartsWith($workRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove Questa library outside the workspace work directory."
    }
    Remove-Item -Recurse -Force $library
}

if (-not (Test-Path $library)) {
    & vlib $library
    if ($LASTEXITCODE -ne 0) {
        throw "Questa library creation failed."
    }
}

Push-Location (Split-Path $modelsimIni)
try {
    if (-not (Test-Path $modelsimIni)) {
        & vmap -c
        if ($LASTEXITCODE -ne 0) {
            throw "Questa modelsim.ini creation failed."
        }
    }
    & vmap perf_bench $library
    if ($LASTEXITCODE -ne 0) {
        throw "Questa library mapping failed."
    }
} finally {
    Pop-Location
}

$cpuSources = Get-ChildItem (Join-Path $repoRoot "rtl\cpu_top") -Filter "*.sv" | ForEach-Object FullName
$socSources = Get-ChildItem (Join-Path $repoRoot "rtl\my_cpu") -Filter "*.sv" | ForEach-Object FullName
$testbench = Join-Path $repoRoot "test\tb_top.sv"

Write-Host "[PERF] Compiling RTL..."
& vlog -modelsimini $modelsimIni -sv -work perf_bench "+incdir+$repoRoot\rtl\cpu_top" "+incdir+$repoRoot\rtl\my_cpu" $cpuSources $socSources $testbench
if ($LASTEXITCODE -ne 0) {
    throw "RTL compilation failed."
}

Write-Host "[PERF] Running benchmark..."
Push-Location $repoRoot
$previousModelsim = $env:MODELSIM
try {
    $env:MODELSIM = $modelsimIni
    & vsim -c -lib perf_bench tb_uart_benchmark -do "run -all; quit -force" 2>&1 |
        Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) {
        throw "RTL benchmark simulation failed. See $log"
    }
} finally {
    $env:MODELSIM = $previousModelsim
    Pop-Location
}

if (-not (Select-String -Path $log -SimpleMatch "[PERF] PASS" -Quiet)) {
    throw "RTL benchmark did not report PASS. See $log"
}

Write-Host "[PERF] Results saved to $log"
