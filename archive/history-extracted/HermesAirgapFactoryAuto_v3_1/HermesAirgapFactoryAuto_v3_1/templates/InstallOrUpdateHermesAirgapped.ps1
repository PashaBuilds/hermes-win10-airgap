param(
    [ValidateSet("Auto","Install","Update")]
    [string]$Mode = "Auto",
    [switch]$CleanVenv
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ("=" * 68)
    Write-Host $Message
    Write-Host ("=" * 68)
}
function Write-Info([string]$Message) { Write-Host "[INFO] $Message" }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Ok([string]$Message)   { Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Ensure-Dir([string]$Path) { New-Item -ItemType Directory -Force $Path | Out-Null }

$BundleRoot = $PSScriptRoot
$BundleRepo = Join-Path $BundleRoot "hermes-agent"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$BuildReq = Join-Path $BundleRoot "requirements-build.txt"
$ExtrasFile = Join-Path $BundleRoot "EXTRAS.txt"

$HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
$InstallDir = Join-Path $HermesHome "hermes-agent"
$PythonRoot = Join-Path $HermesHome "python311"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OldSource = Join-Path $HermesHome "hermes-agent_source_backup_$Timestamp"

$DisabledGatewayFiles = @()
$OldSourceMoved = $false

function Stop-HermesRelatedProcesses {
    Write-Info "Stopping Hermes-related processes and known cache lockers (best effort)..."
    Get-Process TGitCache -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.ExecutablePath -and $_.ExecutablePath -like "$HermesHome*") -or
        ($_.CommandLine -and (
            $_.CommandLine -like "*$HermesHome*" -or
            $_.CommandLine -like "*Hermes_Gateway.vbs*"
        ))
    }
    foreach ($p in $procs) {
        try { taskkill.exe /PID $p.ProcessId /T /F | Out-Null } catch {}
    }
}

function Disable-HermesGatewayStartup {
    $dirs = @(
        [Environment]::GetFolderPath("Startup"),
        [Environment]::GetFolderPath("CommonStartup")
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($dir in $dirs) {
        Get-ChildItem $dir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "Hermes_Gateway.vbs" } |
            ForEach-Object {
                $disabled = "$($_.FullName).disabled-by-hermes-update"
                try {
                    Rename-Item -LiteralPath $_.FullName -NewName ([IO.Path]::GetFileName($disabled)) -Force
                    $script:DisabledGatewayFiles += $disabled
                    Write-Info "Temporarily disabled startup: $($_.FullName)"
                } catch {
                    Write-Warn "Could not disable startup file $($_.FullName): $($_.Exception.Message)"
                }
            }
    }
}
function Restore-HermesGatewayStartup {
    foreach ($disabled in $script:DisabledGatewayFiles) {
        if (Test-Path $disabled) {
            try {
                Rename-Item -LiteralPath $disabled -NewName "Hermes_Gateway.vbs" -Force
                Write-Info "Restored startup: $disabled"
            } catch {
                Write-Warn "Could not restore startup file ${disabled}: $($_.Exception.Message)"
            }
        }
    }
}

function Move-OldSourceWithRetry {
    if (-not (Test-Path $InstallDir)) { return }
    for ($i=1; $i -le 8; $i++) {
        Stop-HermesRelatedProcesses
        Start-Sleep -Milliseconds 700
        try {
            Rename-Item -LiteralPath $InstallDir -NewName ([IO.Path]::GetFileName($OldSource)) -ErrorAction Stop
            $script:OldSourceMoved = $true
            Write-Ok "Old source moved to: $OldSource"
            return
        } catch {
            Write-Warn "Rename attempt $i/8 failed: $($_.Exception.Message)"
            if ($i -lt 8) { Start-Sleep -Seconds 2 }
        }
    }
    throw "Could not rename existing Hermes source after 8 attempts. Check Resource Monitor > CPU > Associated Handles for 'hermes-agent' (TGitCache.exe is a known locker)."
}

function Get-UsablePython {
    $existing = Join-Path $PythonRoot "python.exe"
    if (Test-Path $existing) {
        try {
            $ver = (& $existing -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')").Trim()
            if ($ver -eq "3.11") { return $existing }
        } catch {}
    }
    try {
        $p = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    } catch {}

    $installer = Get-ChildItem (Join-Path $BundleRoot "tools") -Recurse -Filter "python-3.11.*-amd64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $installer) { throw "Python 3.11 not found and bundled Python installer is missing." }

    Write-Info "Installing bundled Python 3.11 into: $PythonRoot"
    Ensure-Dir $PythonRoot
    Start-Process $installer.FullName -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$PythonRoot`"" -Wait
    $p = Join-Path $PythonRoot "python.exe"
    if (-not (Test-Path $p)) { throw "Bundled Python installation failed." }
    return $p
}

Write-Step "Hermes Air-Gapped Install/Update"
Write-Info "Bundle : $BundleRoot"
Write-Info "Target : $InstallDir"

if (-not (Test-Path $BundleRepo)) { throw "Bundle hermes-agent source is missing." }
if (-not (Test-Path $Wheelhouse)) { throw "Bundle wheelhouse is missing." }

$Existing = Test-Path $InstallDir
if ($Mode -eq "Auto") {
    $EffectiveMode = if ($Existing) { "Update" } else { "Install" }
} else {
    $EffectiveMode = $Mode
}
Write-Info "Mode   : $EffectiveMode"

Disable-HermesGatewayStartup
try {
    Stop-HermesRelatedProcesses
    Ensure-Dir $HermesHome

    if ($EffectiveMode -eq "Update" -and $Existing) {
        Write-Step "Backing up current Hermes source"
        Move-OldSourceWithRetry
    } elseif ($Existing) {
        throw "Target already exists. Use Auto or Update mode."
    }

    Write-Step "Copying new Hermes source"
    Copy-Item -LiteralPath $BundleRepo -Destination $InstallDir -Recurse -Force

    $BasePython = Get-UsablePython
    & $BasePython --version

    Write-Step "Creating clean Hermes venv"
    $Venv = Join-Path $InstallDir "venv"
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
    & $BasePython -m venv $Venv
    if ($LASTEXITCODE -ne 0) { throw "venv creation failed." }

    $VenvPy = Join-Path $Venv "Scripts\python.exe"
    $HermesExe = Join-Path $Venv "Scripts\hermes.exe"

    & $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip packaging wheel
    if ($LASTEXITCODE -ne 0) { throw "Offline pip bootstrap failed." }

    if (Test-Path $BuildReq) {
        & $VenvPy -m pip install --no-index --find-links $Wheelhouse -r $BuildReq
        if ($LASTEXITCODE -ne 0) { throw "Offline build requirements install failed." }
    }

    $ExtrasCsv = ""
    if (Test-Path $ExtrasFile) { $ExtrasCsv = (Get-Content $ExtrasFile -Raw).Trim() }
    $Target = $InstallDir
    if ($ExtrasCsv) { $Target = "$InstallDir[$ExtrasCsv]" }

    Write-Step "Installing Hermes from local wheelhouse"
    & $VenvPy -m pip install --no-index --find-links $Wheelhouse -e $Target
    if ($LASTEXITCODE -ne 0) { throw "Offline Hermes package install failed." }
    if (-not (Test-Path $HermesExe)) { throw "hermes.exe was not created." }

    # Some Hermes shell workflows expect python3 even on Windows.
    $Python3 = Join-Path $Venv "Scripts\python3.exe"
    if (-not (Test-Path $Python3)) {
        Copy-Item $VenvPy $Python3 -Force
    }

    Write-Step "Updating user PATH"
    $Scripts = Join-Path $Venv "Scripts"
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPath -notlike "*$Scripts*") {
        [Environment]::SetEnvironmentVariable("Path", "$Scripts;$UserPath", "User")
    }
    $env:Path = "$Scripts;$env:Path"

    # Prefer system Git Bash when available.
    $GitBashCandidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $GitBash = $GitBashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($GitBash) {
        [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $GitBash, "User")
        $env:HERMES_GIT_BASH_PATH = $GitBash
        Write-Info "HERMES_GIT_BASH_PATH=$GitBash"
    }

    Write-Step "Creating Desktop launcher"
    $DesktopExe = Get-ChildItem (Join-Path $InstallDir "apps\desktop\release\win-unpacked") -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($DesktopExe) {
        $Launcher = Join-Path $HermesHome "StartHermesDesktop.bat"
        @"
@echo off
setlocal
"$HermesExe" desktop --skip-build
"@ | Set-Content $Launcher -Encoding ASCII
        Write-Ok "Desktop launcher: $Launcher"
    } else {
        Write-Warn "No prebuilt Desktop EXE found; CLI installation is still usable."
    }

    Write-Step "Verification"
    & $HermesExe --version
    if ($LASTEXITCODE -ne 0) { throw "Hermes verification failed." }

    Write-Ok "Hermes $EffectiveMode completed successfully."
    if ($OldSourceMoved) {
        Write-Info "Rollback source backup kept at: $OldSource"
    }
}
catch {
    Write-Warn "Install/update failed: $($_.Exception.Message)"
    Stop-HermesRelatedProcesses

    if ($OldSourceMoved -and (Test-Path $OldSource)) {
        Write-Warn "Attempting rollback to previous Hermes source..."
        try {
            if (Test-Path $InstallDir) {
                Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
            }
            Rename-Item -LiteralPath $OldSource -NewName "hermes-agent" -ErrorAction Stop
            Write-Ok "Rollback restored previous source."
        } catch {
            Write-Warn "Automatic rollback failed: $($_.Exception.Message)"
            Write-Warn "Previous source is still at: $OldSource"
        }
    }
    throw
}
finally {
    Restore-HermesGatewayStartup
}
