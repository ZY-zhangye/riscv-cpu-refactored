[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$server = '34.22.80.83'
$user = 'zy'
$key = Join-Path $env:USERPROFILE '.ssh\id_ed25519'
$remoteRoot = '/home/zy/work/overclock_sweep_20260719'
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateRoot = Join-Path 'F:\Tools' 'JYD2026_Overclock_Sweep_State'
New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
$stateFile = Join-Path $stateRoot 'launcher_state.txt'

function Write-State {
    param([string]$Text)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Text" | Add-Content -LiteralPath $stateFile -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $key -PathType Leaf)) {
        throw "SSH key is missing: $key"
    }

    $connectionOptions = @('-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3', '-i', $key)
    $baseSsh = @('-T', '-n') + $connectionOptions
    $baseScp = $connectionOptions
    $target = "$user@$server"

    function Invoke-RemoteWithRetry {
        param([Parameter(Mandatory = $true)][string]$Command)

        for ($attempt = 1; $attempt -le 120; $attempt++) {
            Write-State "SSH_COMMAND attempt=$attempt command=$Command"
            $output = & ssh.exe @baseSsh $target $Command 2>&1
            if ($LASTEXITCODE -eq 0) { return ,$output }
            if ($attempt -eq 120) {
                throw "Remote command failed after 120 attempts: $Command"
            }
            Start-Sleep -Seconds 15
        }
    }

    for ($attempt = 1; $attempt -le 120; $attempt++) {
        Write-State "SSH_CHECK attempt=$attempt"
        & ssh.exe @baseSsh $target 'date' *> $null
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -eq 120) { throw 'SSH remained unavailable after 120 attempts.' }
        Start-Sleep -Seconds 15
    }

    $upload = @(
        (Join-Path $toolRoot 'run_overclock_frequency.sh'),
        (Join-Path $toolRoot 'run_overclock_sweep.sh')
    )
    $uploaded = $false
    for ($attempt = 1; $attempt -le 120; $attempt++) {
        Write-State "UPLOADING_BUILD_SCRIPTS attempt=$attempt"
        & scp.exe @baseScp @upload "${target}:$remoteRoot/scripts/"
        if ($LASTEXITCODE -eq 0) {
            $uploaded = $true
            break
        }
        Start-Sleep -Seconds 15
    }
    if (-not $uploaded) { throw 'SCP did not succeed after 120 attempts.' }

    $checkCommand = "bash -n '$remoteRoot/scripts/run_overclock_frequency.sh' && bash -n '$remoteRoot/scripts/run_overclock_sweep.sh'"
    [void](Invoke-RemoteWithRetry -Command $checkCommand)

    $alreadyRunning = Invoke-RemoteWithRetry -Command "pgrep -f '[r]un_overclock_sweep.sh' >/dev/null && echo RUNNING || echo IDLE"
    if (($alreadyRunning -join "`n") -match 'RUNNING') {
        Write-State 'REMOTE_SWEEP_ALREADY_RUNNING'
        exit 0
    }

    $remoteCommand = "bash '$remoteRoot/scripts/run_overclock_sweep.sh' > '$remoteRoot/sweep_driver.log' 2>&1"
    $sweepArgs = $baseSsh + @($target, $remoteCommand)
    $process = Start-Process -FilePath 'ssh.exe' -ArgumentList $sweepArgs -WindowStyle Hidden -PassThru
    Write-State "REMOTE_SWEEP_STARTED local_ssh_pid=$($process.Id)"
}
catch {
    Write-State "FAILED $($_.Exception.Message)"
    exit 1
}
