[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$server = '34.22.80.83'
$user = 'zy'
$key = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
$remoteRoot = '/home/zy/work/overclock_sweep_20260719'
$frequencies = @(210, 220, 230, 240, 250)
$archiveRoot = 'F:\JYD2026_Overclock_210_250MHz_20260719'
$artifactRoot = Join-Path $archiveRoot 'artifacts'
$reportRoot = Join-Path $archiveRoot 'reports'
$desktopRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) 'JYD2026_Overclock_Bitstreams_210_250MHz_20260719'
$baseRoot = Join-Path $desktopRoot 'base'

if (-not (Test-Path -LiteralPath $key -PathType Leaf)) {
    throw "SSH key is missing: $key"
}
New-Item -ItemType Directory -Force -Path $artifactRoot, $reportRoot, $baseRoot | Out-Null

$connectionOptions = @('-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=20', '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3', '-i', $key)
$target = "$user@$server"

function Invoke-ScpRetry {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & scp.exe @connectionOptions @Arguments
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($exitCode -eq 0) { return }
        if ($attempt -eq 20) {
            throw "SCP failed for $Label after 20 attempts (exit $exitCode)."
        }
        Start-Sleep -Seconds 15
    }
}

$records = @()
foreach ($frequency in $frequencies) {
    $remoteArtifacts = "$remoteRoot/artifacts/${frequency}MHz"
    $localDestination = $artifactRoot
    Invoke-ScpRetry -Label "${frequency}MHz artifact directory" -Arguments @('-r', "${target}:$remoteArtifacts", $localDestination)

    $localArtifacts = Join-Path $artifactRoot "${frequency}MHz"
    $statusPath = Join-Path $localArtifacts 'build_status.txt'
    $bitPath = Join-Path $localArtifacts "cpu_base_${frequency}MHz_cloud.bit"
    $mmiPath = Join-Path $localArtifacts 'design.mmi'
    $dcpPath = Join-Path $localArtifacts 'postroute_cloud.dcp'
    $timingPath = Join-Path $localArtifacts 'timing_summary.rpt'
    $fullProjectPath = Join-Path $localArtifacts "jyd_writegate_${frequency}MHz_full_project.tar.zst"
    foreach ($required in @($statusPath, $bitPath, $mmiPath, $dcpPath, $timingPath, $fullProjectPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required downloaded artifact is missing: $required"
        }
    }

    $status = @{}
    foreach ($line in Get-Content -LiteralPath $statusPath) {
        if ($line -match '^([^=]+)=(.*)$') {
            $status[$matches[1]] = $matches[2]
        }
    }
    if ($status['Status'] -ne 'SUCCESS') {
        throw "${frequency}MHz build did not succeed: $($status['Reason'])"
    }

    $desktopBase = Join-Path $baseRoot "${frequency}MHz"
    New-Item -ItemType Directory -Force -Path $desktopBase | Out-Null
    $desktopBit = Join-Path $desktopBase "cpu_base_${frequency}MHz_writegate.bit"
    Copy-Item -LiteralPath $bitPath -Destination $desktopBit -Force
    Copy-Item -LiteralPath $mmiPath -Destination (Join-Path $desktopBase 'irom.mmi') -Force
    Copy-Item -LiteralPath $mmiPath -Destination (Join-Path $desktopBase 'dram.mmi') -Force
    Copy-Item -LiteralPath $statusPath -Destination (Join-Path $desktopBase 'build_status.txt') -Force
    Copy-Item -LiteralPath $timingPath -Destination (Join-Path $desktopBase 'timing_summary.rpt') -Force

    $records += [pscustomobject]@{
        Frequency = $frequency
        Status = $status['Status']
        Mode = $status['Mode']
        WNS = $status['WNS']
        WHS = $status['WHS']
        MainVivadoExit = $status['MainVivadoExit']
        RecoveryVivadoExit = $status['RecoveryVivadoExit']
        BitSha256 = (Get-FileHash -LiteralPath $desktopBit -Algorithm SHA256).Hash.ToLowerInvariant()
        BitBytes = (Get-Item -LiteralPath $desktopBit).Length
        FullProjectBytes = (Get-Item -LiteralPath $fullProjectPath).Length
        ArtifactDir = $localArtifacts
    }
}

$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add('# JYD2026 180-250 MHz 最终 WNS 时序报告')
$reportLines.Add('')
$reportLines.Add("生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$reportLines.Add('')
$reportLines.Add('本次 210-250 MHz 均以 200 MHz 写门控版本为基线，显式启用布局前与布线后 `phys_opt_design -directive Explore`，每一频点均完整运行至 bitstream。WNS 为实现后的 setup worst negative slack，WHS 为 hold worst slack。')
$reportLines.Add('')
$reportLines.Add('| 频率 | WNS | WHS | 状态 | 实现模式 |')
$reportLines.Add('| ---: | ---: | ---: | --- | --- |')
$reportLines.Add('| 180 MHz | -0.179 ns | +0.053 ns | 已完成（历史云端复跑） | normal |')
$reportLines.Add('| 190 MHz | -0.279 ns | +0.086 ns | 已完成（历史构建） | normal |')
$reportLines.Add('| 200 MHz | -0.545 ns | +0.079 ns | 已完成（历史构建） | normal |')
foreach ($record in $records | Sort-Object Frequency) {
    $reportLines.Add("| $($record.Frequency) MHz | $($record.WNS) ns | $($record.WHS) ns | $($record.Status) | $($record.Mode) |")
}
$reportLines.Add('')
$reportLines.Add('## 交付物')
$reportLines.Add('')
foreach ($record in $records | Sort-Object Frequency) {
    $reportLines.Add("- $($record.Frequency) MHz：bit SHA-256 `$($record.BitSha256)`，$($record.BitBytes) bytes；完整工程压缩包 $($record.FullProjectBytes) bytes；下载目录 `$($record.ArtifactDir)`。")
}
$reportLines.Add('')
$reportLines.Add('每个下载目录均包含：完整工程 `*.tar.zst`、基础 bitstream、post-route DCP、MMI、时序/关键路径/资源/路由/DRC 报告以及 Vivado 日志。桌面独立替换工具仅使用本次下载的 base bit/MMI。')

$reportPath = Join-Path $archiveRoot '频率扫描最终时序报告.md'
$desktopReportPath = Join-Path $desktopRoot '频率扫描最终时序报告.md'
[System.IO.File]::WriteAllLines($reportPath, $reportLines, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllLines($desktopReportPath, $reportLines, [System.Text.UTF8Encoding]::new($false))

$manifestPath = Join-Path $archiveRoot 'SHA256SUMS.txt'
$manifestLines = @()
foreach ($file in Get-ChildItem -LiteralPath $artifactRoot -Recurse -File) {
    $relative = $file.FullName.Substring($archiveRoot.Length).TrimStart('\').Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestLines += "$hash *$relative"
}
[System.IO.File]::WriteAllLines($manifestPath, ($manifestLines | Sort-Object), [System.Text.UTF8Encoding]::new($false))

Write-Host "OVERCLOCK_COLLECTION_COMPLETE=1"
Write-Host "REPORT=$reportPath"
Write-Host "DESKTOP_REPORT=$desktopReportPath"
