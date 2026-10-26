param(
    [Parameter(Mandatory=$true)]
    [string]$DesktopHermesBundleZip,

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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnerPs1 = Join-Path $ScriptDir "runner\InstallOrUpdateHermesAirgapped.ps1"

if (-not (Test-Path $DesktopHermesBundleZip)) {
    throw "Desktop-enabled Hermes bundle ZIP not found: $DesktopHermesBundleZip"
}
if (-not (Test-Path $RunnerPs1)) {
    throw "Embedded Hermes air-gap runner not found: $RunnerPs1"
}

Write-Step "Installing/updating Hermes runtime from desktop-enabled bundle"

$runnerArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $RunnerPs1,
    "-BundleZip", $DesktopHermesBundleZip,
    "-Mode", $Mode
)

if ($CleanVenv) {
    $runnerArgs += "-CleanVenv"
}

$p = Start-Process powershell -ArgumentList $runnerArgs -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) {
    throw "Hermes runtime install/update runner failed with exit code $($p.ExitCode)"
}

Write-Step "Checking desktop release artifact"

$HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
$InstallDir = Join-Path $HermesHome "hermes-agent"
$ReleaseDir = Join-Path $InstallDir "apps\desktop\release"
$HermesExe = Join-Path $InstallDir "venv\Scripts\hermes.exe"

if (-not (Test-Path $HermesExe)) {
    throw "Hermes executable not found: $HermesExe"
}
if (-not (Test-Path $ReleaseDir)) {
    throw "Desktop release directory not found after install/update: $ReleaseDir"
}

$releaseItems = Get-ChildItem $ReleaseDir -Recurse -Force -ErrorAction SilentlyContinue
if (-not $releaseItems -or $releaseItems.Count -eq 0) {
    throw "Desktop release directory exists but is empty: $ReleaseDir"
}

Write-Info "Hermes executable: $HermesExe"
Write-Info "Desktop release : $ReleaseDir"

Write-Step "Creating StartHermesDesktop helper"

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
Write-Info "Start helper: $StartBat"

try {
    $DesktopStart = Join-Path ([Environment]::GetFolderPath("Desktop")) "StartHermesDesktop.bat"
    Copy-Item $StartBat $DesktopStart -Force
    Write-Info "Desktop shortcut helper copied to: $DesktopStart"
} catch {
    Write-Warn "Could not copy StartHermesDesktop.bat to Desktop: $($_.Exception.Message)"
}

Write-Step "Version check"
& $HermesExe --version

Write-Step "Done"
Write-Host "You can now launch Desktop with:"
Write-Host "  $StartBat"
Write-Host ""
Write-Host "or:"
Write-Host "  hermes desktop --skip-build"

if ($LaunchDesktop) {
    Write-Step "Launching Hermes Desktop"
    & $HermesExe desktop --skip-build
}
