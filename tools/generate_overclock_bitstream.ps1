[CmdletBinding()]
param(
    [ValidateSet('IROM', 'DRAM', 'Both')]
    [string]$Mode = 'IROM',

    [ValidateSet('210', '220', '230', '240', '250')]
    [string]$Frequency,

    [string]$Irom,
    [string]$Dram,
    [string]$Output,
    [switch]$Interactive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseRoot = Join-Path $Root 'base'
$InputRoot = Join-Path $Root 'input'
$OutputRoot = Join-Path $Root 'output'
$IromProc = 'my_cpu/u_inst_ram/u_xpm_inst_rom/xpm_memory_base_inst'
$DramProc = 'my_cpu/u_perip_bridge/dram_driver_inst/u_dram'

function Get-FullUserPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $clean = $Path.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($clean)) {
        throw "$Label path is empty."
    }

    if (-not [System.IO.Path]::IsPathRooted($clean)) {
        $clean = Join-Path $Root $clean
    }

    $full = [System.IO.Path]::GetFullPath($clean)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "$Label file does not exist: $full"
    }
    return $full
}

function Find-UpdateMem {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:XILINX_VIVADO)) {
        $candidates += Join-Path $env:XILINX_VIVADO 'bin\updatemem.bat'
    }
    $candidates += @(
        'F:\Xilinx\Vivado\2023.2\bin\updatemem.bat',
        'C:\Xilinx\Vivado\2023.2\bin\updatemem.bat'
    )

    $fromPath = Get-Command 'updatemem.bat' -ErrorAction SilentlyContinue
    if ($null -ne $fromPath) {
        $candidates += $fromPath.Source
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Vivado updatemem was not found. Expected Vivado 2023.2 under F:\Xilinx\Vivado\2023.2.'
}

function Convert-CoeToMem {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $text = [System.IO.File]::ReadAllText($Source)
    $text = [regex]::Replace($text, '(?m)^\s*;.*$', '')

    $radixMatch = [regex]::Match($text, 'memory_initialization_radix\s*=\s*(\d+)\s*;', 'IgnoreCase')
    if (-not $radixMatch.Success) {
        throw "COE radix declaration was not found: $Source"
    }
    $radix = [int]$radixMatch.Groups[1].Value
    if ($radix -notin @(2, 10, 16)) {
        throw "Unsupported COE radix $radix in $Source. Supported values: 2, 10, 16."
    }

    $vectorMatch = [regex]::Match(
        $text,
        'memory_initialization_vector\s*=\s*(.*?);',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $vectorMatch.Success) {
        throw "COE initialization vector was not found: $Source"
    }

    $tokens = @(
        $vectorMatch.Groups[1].Value -split '[,\s]+' |
            ForEach-Object { $_.Trim().Replace('_', '') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($tokens.Count -eq 0) {
        throw "COE initialization vector is empty: $Source"
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('@00000000')
    foreach ($tokenText in $tokens) {
        $token = $tokenText
        if ($radix -eq 16 -and $token.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
            $token = $token.Substring(2)
        }
        try {
            $value = [Convert]::ToUInt32($token, $radix)
        } catch {
            throw "Invalid radix-$radix word '$tokenText' in $Source"
        }
        $lines.Add(('{0:X8}' -f $value))
    }

    [System.IO.File]::WriteAllLines(
        $Destination,
        $lines,
        [System.Text.UTF8Encoding]::new($false)
    )

    return [pscustomobject]@{
        Path = $Destination
        Words = $tokens.Count
    }
}

function Prepare-MemoryImage {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][int]$MaxWords,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $extension = [System.IO.Path]::GetExtension($Source).ToLowerInvariant()
    if ($extension -eq '.coe') {
        $result = Convert-CoeToMem -Source $Source -Destination $Destination
        if ($result.Words -gt $MaxWords) {
            throw "$Label contains $($result.Words) words; maximum is $MaxWords."
        }
        return $result
    }

    if ($extension -ne '.mem') {
        throw "$Label must be a .coe or .mem file: $Source"
    }

    $wordCount = 0
    foreach ($line in [System.IO.File]::ReadLines($Source)) {
        $clean = ($line -replace '//.*$', '' -replace '#.*$', '').Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) {
            continue
        }
        foreach ($token in ($clean -split '\s+')) {
            if ([string]::IsNullOrWhiteSpace($token) -or $token.StartsWith('@')) {
                continue
            }
            if ($token -notmatch '^[0-9A-Fa-f]{1,8}$') {
                throw "Invalid 32-bit hexadecimal word '$token' in $Source"
            }
            $wordCount++
        }
    }
    if ($wordCount -eq 0) {
        throw "$Label MEM file contains no data words: $Source"
    }
    if ($wordCount -gt $MaxWords) {
        throw "$Label contains $wordCount words; maximum is $MaxWords."
    }

    return [pscustomobject]@{
        Path = $Source
        Words = $wordCount
    }
}

function Invoke-UpdateMem {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][string]$Mmi,
        [Parameter(Mandatory = $true)][string]$Data,
        [Parameter(Mandatory = $true)][string]$InputBit,
        [Parameter(Mandatory = $true)][string]$Proc,
        [Parameter(Mandatory = $true)][string]$OutputBit,
        [Parameter(Mandatory = $true)][string]$WorkDirectory,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Select-String -LiteralPath $Mmi -SimpleMatch $Proc -Quiet)) {
        throw "$Label processor path is absent from MMI: $Mmi"
    }

    Write-Host "Updating $Label..." -ForegroundColor Cyan
    Push-Location $WorkDirectory
    try {
        & $Tool -force -meminfo $Mmi -data $Data -bit $InputBit -proc $Proc -out $OutputBit
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputBit -PathType Leaf)) {
        $failureLog = "$OutputBit.failed.log"
        $toolLog = Join-Path $WorkDirectory 'updatemem.log'
        if (Test-Path -LiteralPath $toolLog) {
            Copy-Item -LiteralPath $toolLog -Destination $failureLog -Force
        }
        throw "updatemem failed while updating $Label (exit code $exitCode)."
    }
}

if ([string]::IsNullOrWhiteSpace($Frequency)) {
    if (-not $Interactive) {
        throw 'Frequency is required. Use -Frequency 210, 220, 230, 240, or 250.'
    }

    Write-Host ''
    Write-Host 'Select base bitstream:'
    Write-Host '  [1] 210 MHz'
    Write-Host '  [2] 220 MHz'
    Write-Host '  [3] 230 MHz'
    Write-Host '  [4] 240 MHz'
    Write-Host '  [5] 250 MHz'
    $selection = (Read-Host 'Enter 1/2/3/4/5 or 210/220/230/240/250').Trim()
    switch ($selection) {
        { $_ -in @('1', '210') } { $Frequency = '210'; break }
        { $_ -in @('2', '220') } { $Frequency = '220'; break }
        { $_ -in @('3', '230') } { $Frequency = '230'; break }
        { $_ -in @('4', '240') } { $Frequency = '240'; break }
        { $_ -in @('5', '250') } { $Frequency = '250'; break }
        default { throw "Invalid frequency selection: $selection" }
    }
}

$versionDir = Join-Path $BaseRoot "${Frequency}MHz"
$baseBit = Join-Path $versionDir "cpu_base_${Frequency}MHz_writegate.bit"
$iromMmi = Join-Path $versionDir 'irom.mmi'
$dramMmi = Join-Path $versionDir 'dram.mmi'

foreach ($required in @($baseBit, $iromMmi, $dramMmi)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required base artifact is missing: $required"
    }
}

if ($Mode -in @('IROM', 'Both')) {
    $defaultIrom = Join-Path $InputRoot 'irom.coe'
    if ([string]::IsNullOrWhiteSpace($Irom)) {
        if ($Interactive) {
            $entered = Read-Host "IROM .coe/.mem path (Enter = $defaultIrom)"
            $Irom = if ([string]::IsNullOrWhiteSpace($entered)) { $defaultIrom } else { $entered }
        } else {
            $Irom = $defaultIrom
        }
    }
    $Irom = Get-FullUserPath -Path $Irom -Label 'IROM'
}

if ($Mode -in @('DRAM', 'Both')) {
    $defaultDram = Join-Path $InputRoot 'dram.coe'
    if ([string]::IsNullOrWhiteSpace($Dram)) {
        if ($Interactive) {
            $entered = Read-Host "DRAM .coe/.mem path (Enter = $defaultDram)"
            $Dram = if ([string]::IsNullOrWhiteSpace($entered)) { $defaultDram } else { $entered }
        } else {
            $Dram = $defaultDram
        }
    }
    $Dram = Get-FullUserPath -Path $Dram -Label 'DRAM'
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
if ([string]::IsNullOrWhiteSpace($Output)) {
    $tag = switch ($Mode) {
        'IROM' { 'irom' }
        'DRAM' { 'dram' }
        'Both' { 'irom_dram' }
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Output = Join-Path $OutputRoot "cpu_${Frequency}MHz_writegate_${tag}_${timestamp}.bit"
} elseif (-not [System.IO.Path]::IsPathRooted($Output)) {
    $Output = Join-Path $Root $Output
}
$Output = [System.IO.Path]::GetFullPath($Output)
if ([System.IO.Path]::GetExtension($Output) -ne '.bit') {
    throw "Output file must use the .bit extension: $Output"
}

$baseRootFull = [System.IO.Path]::GetFullPath($BaseRoot).TrimEnd('\') + '\'
if ($Output.StartsWith($baseRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output may not overwrite anything under the base directory.'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null

$updateMem = Find-UpdateMem
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("JYD2026_BitGen_{0}_{1}" -f $PID, [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $currentBit = $baseBit
    $iromInfo = $null
    $dramInfo = $null

    if ($Mode -in @('IROM', 'Both')) {
        $iromInfo = Prepare-MemoryImage -Source $Irom -Destination (Join-Path $tempRoot 'irom.mem') -MaxWords 4096 -Label 'IROM'
        $nextBit = if ($Mode -eq 'Both') { Join-Path $tempRoot 'after_irom.bit' } else { $Output }
        Invoke-UpdateMem -Tool $updateMem -Mmi $iromMmi -Data $iromInfo.Path -InputBit $currentBit -Proc $IromProc -OutputBit $nextBit -WorkDirectory $tempRoot -Label 'IROM'
        $currentBit = $nextBit
    }

    if ($Mode -in @('DRAM', 'Both')) {
        $dramInfo = Prepare-MemoryImage -Source $Dram -Destination (Join-Path $tempRoot 'dram.mem') -MaxWords 65536 -Label 'DRAM'
        Invoke-UpdateMem -Tool $updateMem -Mmi $dramMmi -Data $dramInfo.Path -InputBit $currentBit -Proc $DramProc -OutputBit $Output -WorkDirectory $tempRoot -Label 'DRAM'
        $currentBit = $Output
    }

    $baseLength = (Get-Item -LiteralPath $baseBit).Length
    $outputInfo = Get-Item -LiteralPath $Output
    if ($outputInfo.Length -ne $baseLength) {
        throw "Unexpected output bitstream size $($outputInfo.Length); expected $baseLength."
    }

    $record = [ordered]@{
        generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        frequency_mhz = [int]$Frequency
        mode = $Mode
        irom_source = if ($null -ne $iromInfo) { $Irom } else { '' }
        irom_words = if ($null -ne $iromInfo) { $iromInfo.Words } else { 0 }
        dram_source = if ($null -ne $dramInfo) { $Dram } else { '' }
        dram_words = if ($null -ne $dramInfo) { $dramInfo.Words } else { 0 }
        base_bit_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $baseBit).Hash.ToLowerInvariant()
        output_bit = $Output
        output_bytes = $outputInfo.Length
        output_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Output).Hash.ToLowerInvariant()
    }
    $recordPath = Join-Path $OutputRoot 'last_generation.json'
    [System.IO.File]::WriteAllText(
        $recordPath,
        ($record | ConvertTo-Json),
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host ''
    Write-Host 'Bitstream generated successfully.' -ForegroundColor Green
    Write-Host "Output : $Output"
    Write-Host "Bytes  : $($outputInfo.Length)"
    Write-Host "SHA256 : $($record.output_sha256)"
    Write-Host "Record : $recordPath"
} finally {
    $tempFull = [System.IO.Path]::GetFullPath($tempRoot)
    $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($tempFull.StartsWith($tempParent, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $tempFull)) {
        Remove-Item -LiteralPath $tempFull -Recurse -Force
    }
}
