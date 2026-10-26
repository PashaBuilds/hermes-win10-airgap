param(
    [Parameter(Mandatory=$true)]
    [string]$HermesBundleZip,

    [string]$OutputZip = "",

    [string]$WorkRoot = "C:\HermesDesktopAirgapFactory\work",

    [switch]$KeepWork
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

Write-Step "Hermes Desktop air-gap artifact builder"

if (-not (Test-Path $HermesBundleZip)) {
    throw "Hermes bundle ZIP not found: $HermesBundleZip"
}

Ensure-Dir $WorkRoot

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BuildRoot = Join-Path $WorkRoot "desktop_build_$stamp"
$ExtractRoot = Join-Path $BuildRoot "bundle"
Ensure-Dir $ExtractRoot

Write-Info "Input Hermes bundle : $HermesBundleZip"
Write-Info "Build root          : $BuildRoot"

Write-Step "Extracting Hermes air-gap bundle"
Expand-Archive $HermesBundleZip -DestinationPath $ExtractRoot -Force

$RepoDir = Join-Path $ExtractRoot "hermes-agent"
$Wheelhouse = Join-Path $ExtractRoot "wheelhouse"

if (-not (Test-Path $RepoDir)) {
    throw "Could not find hermes-agent\ inside extracted bundle. ZIP root must contain hermes-agent, wheelhouse, tools, VERSION.txt."
}
if (-not (Test-Path $Wheelhouse)) {
    throw "Could not find wheelhouse\ inside extracted bundle."
}

Write-Info "Hermes source       : $RepoDir"
Write-Info "Wheelhouse          : $Wheelhouse"

Write-Step "Checking Node/npm"
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue

if (-not $nodeCmd -or -not $npmCmd) {
    $PortableNode = Get-ChildItem (Join-Path $ExtractRoot "tools") -Recurse -Filter "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PortableNode) {
        $NodeDir = Split-Path $PortableNode.FullName -Parent
        $env:Path = "$NodeDir;$env:Path"
        Write-Info "Using bundled node: $($PortableNode.FullName)"
    }
}

node --version
npm --version

Write-Step "Finding Python 3.11"
$PythonExe = ""

try {
    $pyPath = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null).Trim()
    if ($pyPath -and (Test-Path $pyPath)) { $PythonExe = $pyPath }
} catch {}

if (-not $PythonExe) {
    try {
        $pyPath = (& python -c "import sys; print(sys.executable if sys.version_info[:2] == (3,11) else '')" 2>$null).Trim()
        if ($pyPath -and (Test-Path $pyPath)) { $PythonExe = $pyPath }
    } catch {}
}

if (-not $PythonExe) {
    $PyInstaller = Get-ChildItem (Join-Path $ExtractRoot "tools") -Recurse -Filter "python-3.11.*-amd64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PyInstaller) {
        $LocalPython = Join-Path $BuildRoot "python311"
        Write-Info "Installing temporary Python 3.11 from bundle to $LocalPython"
        Start-Process $PyInstaller.FullName -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$LocalPython`"" -Wait
        $PythonExe = Join-Path $LocalPython "python.exe"
    }
}

if (-not $PythonExe -or -not (Test-Path $PythonExe)) {
    throw "Could not find/install Python 3.11. Ensure bundle has tools\python-3.11.9-amd64.exe or Python 3.11 is installed."
}

& $PythonExe --version
Write-Info "Python exe: $PythonExe"

Write-Step "Creating temporary Hermes build venv"
$BuildVenv = Join-Path $BuildRoot "venv"
& $PythonExe -m venv $BuildVenv

$VenvPy = Join-Path $BuildVenv "Scripts\python.exe"
$HermesExe = Join-Path $BuildVenv "Scripts\hermes.exe"

& $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel

Push-Location $RepoDir
& $VenvPy -m pip install --no-index --find-links $Wheelhouse -e ".[web,mcp,cron,cli]"
Pop-Location

if (-not (Test-Path $HermesExe)) {
    throw "Hermes console script not found after install: $HermesExe"
}

Write-Step "Building Hermes Desktop artifact"
Push-Location $RepoDir

$env:CI = "1"
$env:NO_COLOR = "1"

& $HermesExe desktop --build-only --force-build --hermes-root $RepoDir

if ($LASTEXITCODE -ne 0) {
    throw "hermes desktop --build-only failed."
}

Pop-Location

Write-Step "Locating desktop release output"
$ReleaseDir = Join-Path $RepoDir "apps\desktop\release"
if (-not (Test-Path $ReleaseDir)) {
    throw "Desktop release directory was not found: $ReleaseDir"
}

$releaseItems = Get-ChildItem $ReleaseDir -Recurse -Force -ErrorAction SilentlyContinue
if (-not $releaseItems -or $releaseItems.Count -eq 0) {
    throw "Desktop release directory is empty: $ReleaseDir"
}

Write-Info "Desktop release directory: $ReleaseDir"
Get-ChildItem $ReleaseDir -Force | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize

Write-Step "Writing desktop air-gap notes into bundle"
$Notes = @"
Hermes Desktop Air-Gap Artifact
===============================

Built at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Built on: $env:COMPUTERNAME
Source bundle: $HermesBundleZip

This bundle contains a prebuilt Hermes Desktop artifact under:
  hermes-agent\apps\desktop\release

On the intranet machine:
  1. Install/update Hermes using InstallOrUpdateHermesWithDesktopAirgapped.bat
  2. Launch Desktop with StartHermesDesktop.bat or:
       hermes desktop --skip-build

Important:
  - Hermes CLI/runtime still uses %LOCALAPPDATA%\hermes.
  - Desktop shares the same config, API keys, sessions, skills, and memory as CLI.
  - Model provider should be Custom endpoint, not Custom API.
"@
$Notes | Set-Content (Join-Path $ExtractRoot "DESKTOP_AIRGAP_NOTES.txt") -Encoding UTF8

if ([string]::IsNullOrWhiteSpace($OutputZip)) {
    $InputName = [System.IO.Path]::GetFileNameWithoutExtension($HermesBundleZip)
    $OutDir = Split-Path $HermesBundleZip -Parent
    $OutputZip = Join-Path $OutDir "$InputName`_with_desktop.zip"
}

Write-Step "Creating desktop-enabled Hermes air-gap bundle"
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }

tar -a -cf $OutputZip -C $ExtractRoot .

if (-not (Test-Path $OutputZip)) {
    throw "Failed to create output ZIP: $OutputZip"
}

Write-Info "Output ZIP: $OutputZip"

if (-not $KeepWork) {
    Write-Step "Cleaning temporary work folder"
    Remove-Item -Recurse -Force $BuildRoot -ErrorAction SilentlyContinue
} else {
    Write-Info "Kept work folder: $BuildRoot"
}

Write-Step "Done"
Write-Host "Desktop-enabled bundle:"
Write-Host "  $OutputZip"
