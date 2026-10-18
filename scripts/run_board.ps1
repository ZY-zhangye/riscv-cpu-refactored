[CmdletBinding()]
param(
    [ValidateSet('Gen', 'Build', 'Finish', 'Program')][string]$Mode = 'Build',
    [ValidateSet('smoke', 'coremark')][string]$App = 'smoke',
    [long]$CpuHz = 50000000,
    [ValidateRange(0, 1000000000)][int]$Iterations = 0,
    [string]$BuildDir = '',
    [switch]$SkipFirmware,
    [string]$Python = '',
    [string]$ToolchainBin = '',
    [string]$Vivado = $env:VIVADO_BIN,
    [ValidateRange(1, 32)][int]$Jobs = 4,
    [string]$Target = '',
    [switch]$AllowTimingFailure
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$boardRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$candidatePart = 'xc7z020clg484-2'
$explicitVivado = $PSBoundParameters.ContainsKey('Vivado')

function ConvertTo-BoardTclString([string]$Value) {
    if ($Value -match "[`r`n]") { throw 'Multiline paths are not supported.' }
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$').Replace('[', '\[').Replace(']', '\]') + '"'
}
function Write-BoardJson([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}
function Get-BoardSourceHashes {
    $tracked = @('rtl/board/hellozynq_top.sv', 'rtl/board/rv32_divider_hw.sv', 'board/hellozynq/hellozynq.xdc', 'scripts/vivado_board.tcl', 'scripts/run_board.ps1', 'scripts/build_board_firmware.py')
    $tracked += @(Get-ChildItem -LiteralPath (Join-Path $boardRoot 'rtl/cpu_top'), (Join-Path $boardRoot 'rtl/my_cpu') -File | Where-Object { $_.Extension -in @('.sv', '.svh') -and $_.Name -ne 'divider.sv' } | ForEach-Object { [IO.Path]::GetRelativePath($boardRoot, $_.FullName).Replace('\', '/') })
    $hashes = [ordered]@{}
    foreach ($relative in $tracked) {
        $full = Join-Path $boardRoot $relative
        if (Test-Path -LiteralPath $full -PathType Leaf) { $hashes[$relative] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    return $hashes
}
function ConvertTo-BoardHashMap($Value) {
    $hashes = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) { $hashes[$property.Name] = [string]$property.Value }
    return $hashes
}
function Get-BoardMmcm([long]$RequestedHz) {
    if ($RequestedHz -lt 5000000 -or $RequestedHz -gt 400000000 -or ($RequestedHz % 5000000) -ne 0) {
        throw 'CpuHz must be an exact multiple of 5 MHz between 5 and 400 MHz.'
    }
    $choices = [Collections.Generic.List[object]]::new()
    # 50 MHz / DIVCLK stays within the 10..450 MHz MMCM PFD range.
    # Feedback/output fractions use eighths, with VCO restricted to 600..1200 MHz.
    foreach ($inputDivisor in 1..5) {
        foreach ($multiplierEighths in 16..512) {
            $vcoHz = 50000000.0 * $multiplierEighths / (8 * $inputDivisor)
            if ($vcoHz -lt 600000000 -or $vcoHz -gt 1200000000) { continue }
            $numerator = [long]50000000 * $multiplierEighths
            $denominator = $RequestedHz * $inputDivisor
            if (($numerator % $denominator) -ne 0) { continue }
            $outputEighths = [long]($numerator / $denominator)
            if ($outputEighths -lt 8 -or $outputEighths -gt 1024) { continue }
            $choices.Add([pscustomobject]@{
                input_divisor = $inputDivisor
                multiplier_eighths = $multiplierEighths
                output_divisor_eighths = $outputEighths
                multiplier = $multiplierEighths / 8.0
                output_divisor = $outputEighths / 8.0
                vco_hz = $vcoHz
                pfd_hz = 50000000.0 / $inputDivisor
                actual_cpu_hz = [long]$RequestedHz
                output_fractional = [int](($outputEighths % 8) -ne 0)
                feedback_fractional = [int](($multiplierEighths % 8) -ne 0)
                vco_distance = [math]::Abs($vcoHz - 1000000000)
            })
        }
    }
    if ($choices.Count -eq 0) { throw "No exact legal MMCM configuration for $RequestedHz Hz." }
    return $choices | Sort-Object output_fractional, feedback_fractional, vco_distance, input_divisor | Select-Object -First 1
}
function Resolve-BoardVivado {
    $selected = $Vivado
    if ($selected -and !(Test-Path -LiteralPath $selected) -and !$explicitVivado) { $selected = '' }
    if (!$selected) {
        $command = Get-Command vivado.bat -ErrorAction SilentlyContinue
        if ($command) { $selected = $command.Source }
        elseif (Test-Path -LiteralPath 'W:/APP/Xilinx/Vivado/2023.2/bin/vivado.bat') { $selected = 'W:/APP/Xilinx/Vivado/2023.2/bin/vivado.bat' }
    }
    if (!$selected -or !(Test-Path -LiteralPath $selected -PathType Leaf)) { throw 'Vivado not found; pass -Vivado with its full path.' }
    return [IO.Path]::GetFullPath($selected)
}

$implementationHashes = $null
$reportScriptChanges = @()
$recoveryRecord = $null
if ($Mode -eq 'Finish') {
    if (!$BuildDir) { throw 'Finish requires -BuildDir identifying an existing routed build.' }
    $boardBuild = [IO.Path]::GetFullPath($BuildDir)
    $existingConfig = Get-Content -LiteralPath (Join-Path $boardBuild 'build_config.json') -Raw | ConvertFrom-Json
    if ($existingConfig.part -ne $candidatePart) { throw 'Existing build part differs from the reviewed candidate.' }
    $App = $existingConfig.app
    $CpuHz = [long]$existingConfig.cpu_hz
    $Iterations = [int]$existingConfig.iterations
    $priorSummaryPath = Join-Path $boardBuild 'build_summary.json'
    $priorSummary = if (Test-Path -LiteralPath $priorSummaryPath) { Get-Content -LiteralPath $priorSummaryPath -Raw | ConvertFrom-Json } else { $null }
    $snapshotPath = Join-Path $boardBuild 'source_snapshot.json'
    if (Test-Path -LiteralPath $snapshotPath) { $implementationHashes = ConvertTo-BoardHashMap (Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json) }
    elseif ($priorSummary -and $priorSummary.PSObject.Properties['source_sha256']) { $implementationHashes = ConvertTo-BoardHashMap $priorSummary.source_sha256 }
    else { throw 'Finish requires the original source snapshot or prior summary hashes.' }
    $currentHashes = Get-BoardSourceHashes
    $reportScripts = @('scripts/run_board.ps1', 'scripts/vivado_board.tcl')
    foreach ($key in $implementationHashes.Keys) {
        if (!$currentHashes.Contains($key) -or $implementationHashes[$key] -ne $currentHashes[$key]) {
            if ($key -notin $reportScripts) { throw "Implementation input changed; Finish cannot reuse this route: $key" }
            $reportScriptChanges += $key
        }
    }
    $firmwareManifest = Get-Content -LiteralPath $existingConfig.firmware_manifest -Raw | ConvertFrom-Json
    foreach ($imageName in @('inst.mem', 'data.mem')) {
        $recordedImage = $firmwareManifest.artifacts.PSObject.Properties[$imageName]
        $imagePath = if ($imageName -eq 'inst.mem') { $existingConfig.inst_init_file } else { $existingConfig.data_init_file }
        if (!$recordedImage -or (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $recordedImage.Value.sha256) { throw "Firmware memory changed; Finish refuses the existing route: $imageName" }
    }
    $recoveryDir = Join-Path $boardBuild ('finish_history/' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    New-Item -ItemType Directory -Path $recoveryDir -Force | Out-Null
    foreach ($name in @('build_summary.json', 'vivado_result.json')) {
        $previous = Join-Path $boardBuild $name
        if (Test-Path -LiteralPath $previous) { Copy-Item -LiteralPath $previous -Destination (Join-Path $recoveryDir $name) }
    }
    $recoveryRecord = [ordered]@{ mode = 'Finish'; previous_results = $recoveryDir; permitted_report_script_changes = $reportScriptChanges; synthesis_reused = $true; route_reused = $true }
} elseif ($Mode -eq 'Program') {
    if (!$BuildDir) { throw 'Program requires -BuildDir identifying a reviewed build.' }
    $boardBuild = [IO.Path]::GetFullPath($BuildDir)
    $summaryPath = Join-Path $boardBuild 'build_summary.json'
    if (!(Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Missing build summary: $summaryPath" }
    $built = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
    if (!$built.vivado_result -or !$built.vivado_result.bitstream_written -or !$built.vivado_result.drc_met) { throw 'Build did not produce a DRC-accepted bitstream.' }
    if ($built.PSObject.Properties['source_changed_during_build'] -and @($built.source_changed_during_build).Count -ne 0) { throw 'Build inputs changed during implementation; rebuild before programming.' }
    if (!$built.vivado_result.timing_met -and !$AllowTimingFailure) { throw 'Timing failed. An intentional frequency experiment requires -AllowTimingFailure.' }
    if ($built.part -ne $candidatePart) { throw 'Build part does not match the reviewed board candidate.' }
    $bitfile = Join-Path $boardBuild 'hellozynq.bit'
    if ((Get-FileHash -LiteralPath $bitfile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $built.bitstream_sha256) { throw 'Bitstream SHA-256 changed since the build summary.' }
} else {
    $mmcm = Get-BoardMmcm $CpuHz
    if ($BuildDir) { $boardBuild = [IO.Path]::GetFullPath($BuildDir) }
    else {
        $buildId = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $PID
        $boardBuild = Join-Path $boardRoot "build/hello_zynq/$($App)_$($CpuHz)_$buildId"
    }
    if (Test-Path -LiteralPath (Join-Path $boardBuild 'project')) { throw 'Refusing to replace an existing project; choose a new -BuildDir.' }
    if (Test-Path -LiteralPath (Join-Path $boardBuild 'vivado_result.json')) { throw 'Refusing to reuse a directory containing Vivado results; choose a new -BuildDir.' }
    New-Item -ItemType Directory -Path $boardBuild -Force | Out-Null
    $firmwareDir = Join-Path $boardBuild 'firmware'
    if (!$SkipFirmware) {
        if (!$Python) {
            $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
            if (!$pythonCommand) { $pythonCommand = Get-Command python -ErrorAction SilentlyContinue }
            if (!$pythonCommand) { throw 'Python 3 not found; pass -Python with its full path.' }
            $Python = $pythonCommand.Source
        }
        if (Test-Path -LiteralPath (Join-Path $firmwareDir 'manifest.json')) { throw 'Firmware already exists; use -SkipFirmware to reuse a generated configuration.' }
        $firmwareArgs = @((Join-Path $PSScriptRoot 'build_board_firmware.py'), '--app', $App, '--cpu-hz', "$CpuHz", '--iterations', "$Iterations", '--output', $firmwareDir)
        if ($ToolchainBin) { $firmwareArgs += @('--toolchain-bin', $ToolchainBin) }
        & $Python @firmwareArgs
        if ($LASTEXITCODE -ne 0) { throw "Firmware build failed with exit code $LASTEXITCODE" }
    }
    $firmwareManifestPath = Join-Path $firmwareDir 'manifest.json'
    foreach ($required in @('inst.mem', 'data.mem', 'manifest.json')) {
        if (!(Test-Path -LiteralPath (Join-Path $firmwareDir $required) -PathType Leaf)) { throw "Missing firmware/$required" }
    }
    $firmwareManifest = Get-Content -LiteralPath $firmwareManifestPath -Raw | ConvertFrom-Json
    if ([long]$firmwareManifest.cpu_hz -ne $CpuHz -or $firmwareManifest.app -ne $App -or [int]$firmwareManifest.iterations -ne $Iterations) { throw 'Firmware app/frequency/iterations differ from requested build.' }
    foreach ($imageName in @('inst.mem', 'data.mem')) {
        $recordedImage = $firmwareManifest.artifacts.PSObject.Properties[$imageName]
        if (!$recordedImage) { throw "Firmware manifest has no hash for $imageName" }
        $imageHash = (Get-FileHash -LiteralPath (Join-Path $firmwareDir $imageName) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($imageHash -ne $recordedImage.Value.sha256) { throw "Firmware memory changed since validation: $imageName" }
    }
    $config = [ordered]@{
        schema_version = 1
        generated_at = [DateTimeOffset]::Now.ToString('o')
        root = $boardRoot
        build_dir = $boardBuild
        app = $App
        iterations = $Iterations
        cpu_hz = $CpuHz
        part = $candidatePart
        physical_speed_grade_verified = $false
        physical_temperature_grade_verified = $false
        pcb_revision = 'unknown'
        part_basis = 'HelloZynq tutorial candidate; JTAG identifies xc7z020 only'
        mmcm = $mmcm
        jobs = $Jobs
        firmware_manifest = $firmwareManifestPath
        inst_init_file = (Join-Path $firmwareDir 'inst.mem')
        data_init_file = (Join-Path $firmwareDir 'data.mem')
    }
    Write-BoardJson (Join-Path $boardBuild 'build_config.json') $config
    $tclValues = [ordered]@{
        root = $boardRoot.Replace('\', '/')
        build_dir = $boardBuild.Replace('\', '/')
        part = $candidatePart
        app = $App
        cpu_hz = "$CpuHz"
        mmcm_divclk = "$($mmcm.input_divisor)"
        mmcm_mult = $mmcm.multiplier.ToString('0.000', [Globalization.CultureInfo]::InvariantCulture)
        mmcm_out_div = $mmcm.output_divisor.ToString('0.000', [Globalization.CultureInfo]::InvariantCulture)
        inst_init_file = $config.inst_init_file.Replace('\', '/')
        data_init_file = $config.data_init_file.Replace('\', '/')
        jobs = "$Jobs"
    }
    $tclLines = foreach ($entry in $tclValues.GetEnumerator()) { 'set {0} {1}' -f $entry.Key, (ConvertTo-BoardTclString $entry.Value) }
    $tclLines | Set-Content -LiteralPath (Join-Path $boardBuild 'build_config.tcl') -Encoding utf8
    Write-Host "BOARD_CONFIG_READY build_dir=$boardBuild cpu_hz=$CpuHz actual_cpu_hz=$($mmcm.actual_cpu_hz) candidate_part=$candidatePart physical_grade=unverified"
    if ($Mode -eq 'Gen') { return }
}

$boardVivado = Resolve-BoardVivado
if ($Mode -in @('Build', 'Finish')) {
    $sourceHashes = Get-BoardSourceHashes
    $snapshotName = if ($Mode -eq 'Finish') { 'finish_source_snapshot.json' } else { 'source_snapshot.json' }
    Write-BoardJson (Join-Path $boardBuild $snapshotName) $sourceHashes
}
$modeLower = $Mode.ToLowerInvariant()
$logPath = Join-Path $boardBuild ("vivado_{0}_{1}.log" -f $modeLower, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$vendorArgs = @('-mode', 'batch', '-nojournal', '-notrace', '-log', $logPath, '-source', (Join-Path $PSScriptRoot 'vivado_board.tcl'), '-tclargs', $modeLower, (Join-Path $boardBuild 'build_config.tcl'))
if ($Mode -eq 'Program' -and $Target) { $vendorArgs += $Target }
$savedBoardPath = $env:PATH
$vendorExit = -1
$markers = [Collections.Generic.List[string]]::new()
Push-Location $boardBuild
try {
    # This host has an unrelated broken npm junction in PATH that can crash
    # Vivado's executable search. Restrict only the child process environment.
    $env:PATH = @((Split-Path -Parent $boardVivado), "$env:SystemRoot/System32", "$env:SystemRoot", "$env:SystemRoot/System32/Wbem", "$env:SystemRoot/System32/WindowsPowerShell/v1.0") -join ';'
    & $boardVivado @vendorArgs 2>&1 | ForEach-Object {
        $line = "$_"
        Write-Host $line
        if ($line -match '^BOARD_(BUILD_SUCCESS|BUILD_EXPERIMENTAL|PROGRAM_SUCCESS) ') { $markers.Add($line) }
    }
    $vendorExit = $LASTEXITCODE
} finally {
    $env:PATH = $savedBoardPath
    Pop-Location
}

if ($Mode -eq 'Program') {
    if ($vendorExit -ne 0 -or !($markers | Where-Object { $_ -like 'BOARD_PROGRAM_SUCCESS *' })) { throw "Programming did not finish with its success marker (exit=$vendorExit)." }
    Write-BoardJson (Join-Path $boardBuild ("program_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))) ([ordered]@{ timestamp = [DateTimeOffset]::Now.ToString('o'); bitstream_sha256 = $built.bitstream_sha256; target_requested = $Target; success_marker = @($markers); vivado_log = $logPath; physical_grade_verified = $false })
    return
}

$finalConfig = Get-Content -LiteralPath (Join-Path $boardBuild 'build_config.json') -Raw | ConvertFrom-Json
$resultPath = Join-Path $boardBuild 'vivado_result.json'
$vendorResult = if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json } else { $null }
$builtBit = Join-Path $boardBuild 'hellozynq.bit'
$bitHash = if (Test-Path -LiteralPath $builtBit) { (Get-FileHash -LiteralPath $builtBit -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$finalSourceHashes = Get-BoardSourceHashes
$changedSources = @($sourceHashes.Keys | Where-Object { !$finalSourceHashes.Contains($_) -or $sourceHashes[$_] -ne $finalSourceHashes[$_] })
$summary = [ordered]@{
    schema_version = 1
    completed_at = [DateTimeOffset]::Now.ToString('o')
    part = $candidatePart
    physical_speed_grade_verified = $false
    physical_temperature_grade_verified = $false
    pcb_revision = 'unknown'
    config = $finalConfig
    firmware = (Get-Content -LiteralPath $finalConfig.firmware_manifest -Raw | ConvertFrom-Json)
    vivado_result = $vendorResult
    vivado_exit_code = $vendorExit
    success_markers = @($markers)
    bitstream_sha256 = $bitHash
    source_sha256 = $sourceHashes
    implementation_source_sha256 = $implementationHashes
    report_recovery = $recoveryRecord
    source_changed_during_build = $changedSources
    vivado_log = $logPath
}
Write-BoardJson (Join-Path $boardBuild 'build_summary.json') $summary
if ($vendorExit -ne 0 -or !$vendorResult -or !$vendorResult.bitstream_written -or $markers.Count -eq 0) { throw "Board build failed; inspect $boardBuild/build_summary.json (exit=$vendorExit)." }
if ($changedSources.Count -ne 0) { throw 'Inputs changed while Vivado was running; inspect source_changed_during_build and rebuild in a new directory.' }
if (!$vendorResult.timing_met -and $CpuHz -le 50000000) { throw 'Baseline timing gate failed.' }
Write-Host "BOARD_SUMMARY_READY path=$boardBuild/build_summary.json timing_met=$($vendorResult.timing_met) status=$($vendorResult.status) sha256=$bitHash"
