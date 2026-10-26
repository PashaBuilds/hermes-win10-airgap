param(
    [ValidateSet("Auto", "Install", "Update")]
    [string]$Mode = "Auto",

    [switch]$CleanVenv,

    [switch]$LaunchDesktop
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $msg
    Write-Host "============================================================"
}
function Write-Info($msg) { Write-Host "[INFO] $msg" }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Ensure-Dir($p) { New-Item -ItemType Directory -Force $p | Out-Null }

$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
$InstallDir = Join-Path $HermesHome "hermes-agent"
$SourceDir = Join-Path $BundleRoot "hermes-agent"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$ToolsDir = Join-Path $BundleRoot "tools"

Write-Step "Hermes unified air-gapped install/update"
Write-Info "Bundle root : $BundleRoot"
Write-Info "Hermes home : $HermesHome"
Write-Info "Mode        : $Mode"
Write-Info "Clean venv  : $CleanVenv"

if (-not (Test-Path $SourceDir)) { throw "hermes-agent folder not found in bundle root." }
if (-not (Test-Path $Wheelhouse)) { throw "wheelhouse folder not found in bundle root." }

Ensure-Dir $HermesHome

$Exists = Test-Path $InstallDir
if ($Mode -eq "Auto") {
    if ($Exists) { $Mode = "Update" } else { $Mode = "Install" }
}
Write-Info "Resolved mode: $Mode"

Write-Step "Selective backup"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $env:LOCALAPPDATA "hermes_backup_before_airgap_$stamp"
Ensure-Dir $BackupRoot

foreach ($f in @("config.yaml", ".env", "company-ca-bundle.pem")) {
    $src = Join-Path $HermesHome $f
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $BackupRoot $f) -Force
    }
}

foreach ($d in @("sessions", "skills", "memories", "cron", "logs")) {
    $src = Join-Path $HermesHome $d
    if (Test-Path $src) {
        try {
            Copy-Item $src (Join-Path $BackupRoot $d) -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warn "Could not fully backup $d: $($_.Exception.Message)"
        }
    }
}
Write-Info "Backup root: $BackupRoot"

Write-Step "Finding or installing isolated Python 3.11"
$PythonDir = Join-Path $HermesHome "python311"
$PythonExe = Join-Path $PythonDir "python.exe"

if (-not (Test-Path $PythonExe)) {
    $PyInstaller = Get-ChildItem $ToolsDir -Recurse -Filter "python-3.11.*-amd64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $PyInstaller) { throw "Python 3.11 installer not found in tools." }

    Write-Info "Installing Python 3.11 to: $PythonDir"
    Ensure-Dir $PythonDir
    Start-Process $PyInstaller.FullName -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$PythonDir`"" -Wait
}

if (-not (Test-Path $PythonExe)) { throw "Python 3.11 was not found after install: $PythonExe" }
& $PythonExe --version

Write-Step "Installing/updating Hermes source"
$OldSource = ""
$OldVenv = ""

if (Test-Path $InstallDir) {
    $OldSource = Join-Path $HermesHome "hermes-agent_source_backup_$stamp"
    Rename-Item $InstallDir $OldSource
    Write-Info "Old source moved to: $OldSource"

    $CandidateVenv = Join-Path $OldSource "venv"
    if ((-not $CleanVenv) -and (Test-Path $CandidateVenv)) {
        $OldVenv = $CandidateVenv
        Write-Info "Existing venv will be reused: $OldVenv"
    }
}

Copy-Item $SourceDir $InstallDir -Recurse -Force

if ($OldVenv) {
    Move-Item $OldVenv (Join-Path $InstallDir "venv") -Force
}

Write-Step "Creating/updating venv"
$VenvDir = Join-Path $InstallDir "venv"
if ($CleanVenv -and (Test-Path $VenvDir)) {
    Remove-Item -Recurse -Force $VenvDir
}

if (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    & $PythonExe -m venv $VenvDir
}

$VenvPy = Join-Path $VenvDir "Scripts\python.exe"
$HermesExe = Join-Path $VenvDir "Scripts\hermes.exe"

& $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel

Push-Location $InstallDir
& $VenvPy -m pip install --no-index --find-links $Wheelhouse -e ".[web,mcp,cron,cli]"
Pop-Location

if (-not (Test-Path $HermesExe)) { throw "Hermes executable not found after install: $HermesExe" }

Write-Step "Creating python3 alias"
$ScriptsDir = Join-Path $VenvDir "Scripts"
Copy-Item (Join-Path $ScriptsDir "python.exe") (Join-Path $ScriptsDir "python3.exe") -Force

Write-Step "Setting PATH and tool paths"
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$ScriptsDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$ScriptsDir;$UserPath", "User")
}
$env:Path = "$ScriptsDir;$env:Path"

# Git Bash
$GitBash = "C:\Program Files\Git\bin\bash.exe"
if (-not (Test-Path $GitBash)) {
    $PortableGit = Get-ChildItem $ToolsDir -Recurse -Filter "PortableGit-*-64-bit.7z.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PortableGit) {
        $GitDir = Join-Path $HermesHome "git"
        Ensure-Dir $GitDir
        Write-Info "Extracting PortableGit to $GitDir"
        Start-Process $PortableGit.FullName -ArgumentList "-o`"$GitDir`"", "-y" -Wait
        if (Test-Path (Join-Path $GitDir "bin\bash.exe")) {
            $GitBash = Join-Path $GitDir "bin\bash.exe"
        } elseif (Test-Path (Join-Path $GitDir "usr\bin\bash.exe")) {
            $GitBash = Join-Path $GitDir "usr\bin\bash.exe"
        }
    }
}

if (Test-Path $GitBash) {
    [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $GitBash, "User")
    $env:HERMES_GIT_BASH_PATH = $GitBash
    Write-Info "HERMES_GIT_BASH_PATH=$GitBash"
} else {
    Write-Warn "Git Bash not found. Hermes shell tools may not work until Git Bash is installed."
}

[Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
[Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
[Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")


Write-Step "Setting bundled Node.js PATH if present"
$BundledNode = Get-ChildItem $ToolsDir -Recurse -Filter "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($BundledNode) {
    $NodeDir = Split-Path $BundledNode.FullName -Parent
    $UserPathNode = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPathNode -notlike "*$NodeDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$NodeDir;$UserPathNode", "User")
    }
    $env:Path = "$NodeDir;$env:Path"
    Write-Info "Bundled Node added to PATH: $NodeDir"
    try { & (Join-Path $NodeDir "node.exe") --version } catch {}
}

Write-Step "Creating Desktop launcher if artifact exists"
$ReleaseDir = Join-Path $InstallDir "apps\desktop\release"
if (Test-Path $ReleaseDir) {
    $items = Get-ChildItem $ReleaseDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($items -and $items.Count -gt 0) {
        $StartBat = Join-Path $HermesHome "StartHermesDesktop.bat"
        $StartContent = @"
@echo off
setlocal
set HERMES_HOME=%LOCALAPPDATA%\hermes
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8
set HERMES_STREAM_READ_TIMEOUT=1800

if exist "C:\Program Files\Git\bin\bash.exe" (
  set HERMES_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe
)

"%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe" desktop --skip-build
pause
"@
        $StartContent | Set-Content $StartBat -Encoding ASCII
        Write-Info "Desktop launcher: $StartBat"

        try {
            $DesktopStart = Join-Path ([Environment]::GetFolderPath("Desktop")) "StartHermesDesktop.bat"
            Copy-Item $StartBat $DesktopStart -Force
            Write-Info "Desktop launcher copied to: $DesktopStart"
        } catch {
            Write-Warn "Could not copy Desktop launcher to Desktop."
        }
    } else {
        Write-Warn "Desktop release directory exists but is empty."
    }
} else {
    Write-Warn "No desktop artifact found. CLI/runtime is still installed."
}

Write-Step "Config check / migrate / doctor"
try { & $HermesExe config check } catch { Write-Warn "config check failed: $($_.Exception.Message)" }
try { & $HermesExe config migrate } catch { Write-Warn "config migrate skipped/failed: $($_.Exception.Message)" }
try { & $HermesExe doctor } catch { Write-Warn "doctor failed: $($_.Exception.Message)" }

Write-Step "Version"
& $HermesExe --version

Write-Step "Done"
Write-Host "Open a new PowerShell/CMD, then test:"
Write-Host "  hermes --version"
Write-Host "  hermes model"
Write-Host "  hermes chat"
Write-Host ""
Write-Host "If desktop artifact was included:"
Write-Host "  %LOCALAPPDATA%\hermes\StartHermesDesktop.bat"
Write-Host "or:"
Write-Host "  hermes desktop --skip-build"

if ($LaunchDesktop) {
    & $HermesExe desktop --skip-build
}
