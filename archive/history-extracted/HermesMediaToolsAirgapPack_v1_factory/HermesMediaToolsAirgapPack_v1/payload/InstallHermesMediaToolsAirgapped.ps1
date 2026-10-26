param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\hermes-media-tools",
    [switch]$CleanVenv
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
$ToolsDir = Join-Path $BundleRoot "tools"
$PythonDir = Join-Path $BundleRoot "python"
$NpmDir = Join-Path $BundleRoot "npm"
$SkillsDir = Join-Path $BundleRoot "skills"
$ExamplesDir = Join-Path $BundleRoot "examples"

Write-Step "Hermes Media Tools Airgapped Install"
Write-Info "Bundle root : $BundleRoot"
Write-Info "Install root: $InstallRoot"

Ensure-Dir $InstallRoot

Write-Step "Copying tools/examples/skills to install root"
foreach ($d in @("tools", "python", "npm", "examples", "skills")) {
    $src = Join-Path $BundleRoot $d
    if (Test-Path $src) { Copy-Item $src (Join-Path $InstallRoot $d) -Recurse -Force }
}

$InstallTools = Join-Path $InstallRoot "tools"
$InstallPython = Join-Path $InstallRoot "python"
$InstallNpm = Join-Path $InstallRoot "npm"

Write-Step "Setting tool PATH entries"
$PathEntries = @()

$FfmpegExe = Get-ChildItem (Join-Path $InstallTools "ffmpeg") -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($FfmpegExe) { $PathEntries += (Split-Path $FfmpegExe.FullName -Parent) }

$DotExe = Get-ChildItem (Join-Path $InstallTools "graphviz") -Recurse -Filter "dot.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($DotExe) { $PathEntries += (Split-Path $DotExe.FullName -Parent) }

$NodeExe = Get-ChildItem (Join-Path $InstallTools "node") -Recurse -Filter "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($NodeExe) { $PathEntries += (Split-Path $NodeExe.FullName -Parent) }

$MermaidBin = Join-Path $InstallNpm "mermaid-cli\node_modules\.bin"
if (Test-Path $MermaidBin) { $PathEntries += $MermaidBin }

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
foreach ($p in $PathEntries) {
    if ($p -and (Test-Path $p)) {
        if ($UserPath -notlike "*$p*") { $UserPath = "$p;$UserPath" }
        $env:Path = "$p;$env:Path"
        Write-Info "PATH += $p"
    }
}
[Environment]::SetEnvironmentVariable("Path", $UserPath, "User")

Write-Step "Preparing Manim media venv"
$PythonExe = ""
$HermesPython = Join-Path $env:LOCALAPPDATA "hermes\python311\python.exe"
if (Test-Path $HermesPython) { $PythonExe = $HermesPython }

if (-not $PythonExe) {
    try {
        $candidate = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null).Trim()
        if ($candidate -and (Test-Path $candidate)) { $PythonExe = $candidate }
    } catch {}
}

if (-not $PythonExe) {
    $PyInstaller = Get-ChildItem $InstallTools -Recurse -Filter "python-3.11.*-amd64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PyInstaller) {
        $PyRoot = Join-Path $InstallRoot "python311"
        Start-Process $PyInstaller.FullName -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$PyRoot`"" -Wait
        $PythonExe = Join-Path $PyRoot "python.exe"
    }
}

if (-not $PythonExe -or -not (Test-Path $PythonExe)) { throw "Could not find/install Python 3.11 for Manim." }
& $PythonExe --version

$MediaVenv = Join-Path $InstallRoot "manim-venv"
if ($CleanVenv -and (Test-Path $MediaVenv)) { Remove-Item -Recurse -Force $MediaVenv }
if (-not (Test-Path (Join-Path $MediaVenv "Scripts\python.exe"))) { & $PythonExe -m venv $MediaVenv }

$MediaPy = Join-Path $MediaVenv "Scripts\python.exe"
$Wheelhouse = Join-Path $InstallPython "wheelhouse-media"
$Req = Join-Path $InstallPython "requirements-media.txt"

if (Test-Path $Wheelhouse) {
    & $MediaPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
    if (Test-Path $Req) { & $MediaPy -m pip install --no-index --find-links $Wheelhouse -r $Req }
    $ScriptsPath = Join-Path $MediaVenv "Scripts"
    $env:Path = "$ScriptsPath;$env:Path"
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($UserPath -notlike "*$ScriptsPath*") { [Environment]::SetEnvironmentVariable("Path", "$ScriptsPath;$UserPath", "User") }
    $PathEntries += $ScriptsPath
}

Write-Step "Installing Hermes media skills"
$HermesSkills = Join-Path $env:LOCALAPPDATA "hermes\skills\media-tools"
if (Test-Path $SkillsDir) {
    Ensure-Dir $HermesSkills
    Copy-Item (Join-Path $SkillsDir "*") $HermesSkills -Recurse -Force
    Write-Info "Skills copied to: $HermesSkills"
}

Write-Step "Creating StartHermesMediaShell helper"
$StartBat = Join-Path $InstallRoot "StartHermesMediaShell.bat"
$StartContent = @"
@echo off
setlocal
set PATH=$($PathEntries -join ";");%PATH%
cd /d "%USERPROFILE%"
cmd
"@
$StartContent | Set-Content $StartBat -Encoding ASCII
Write-Info "Helper: $StartBat"

Write-Step "Tool checks"
try { ffmpeg -version | Select-Object -First 1 } catch { Write-Warn "ffmpeg check failed" }
try { ffprobe -version | Select-Object -First 1 } catch { Write-Warn "ffprobe check failed" }
try { dot -V } catch { Write-Warn "Graphviz dot check failed" }
try { mmdc --version } catch { Write-Warn "Mermaid mmdc check failed" }
try { & $MediaPy -m manim --version } catch { Write-Warn "Manim check failed" }

Write-Step "Done"
Write-Host "Open a new PowerShell/CMD and test:"
Write-Host "  ffmpeg -version"
Write-Host "  ffprobe -version"
Write-Host "  dot -V"
Write-Host "  mmdc --version"
Write-Host "  python -m manim --version"
