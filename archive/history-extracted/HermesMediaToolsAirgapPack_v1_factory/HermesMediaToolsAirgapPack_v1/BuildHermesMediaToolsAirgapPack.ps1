param(
    [string]$FactoryRoot = "C:\HermesMediaToolsFactory",
    [string]$PackName = "HermesMediaToolsAirgapPack_v1",
    [string]$PythonVersion = "3.11.9",
    [string]$NodeMajor = "24",
    [switch]$SkipGraphviz,
    [switch]$SkipMermaid,
    [switch]$SkipManim,
    [switch]$SkipFFmpeg,
    [switch]$UseNpmInsecure,
    [string]$NpmCafile = "",
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

function Invoke-Download($Url, $OutFile) {
    if (Test-Path $OutFile) {
        Write-Info "Already exists: $OutFile"
        return
    }
    Write-Info "Downloading: $Url"
    Write-Info "To         : $OutFile"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
    } catch {
        Write-Warn "Invoke-WebRequest failed: $($_.Exception.Message)"
        Write-Info "Trying curl.exe..."
        curl.exe -L --retry 3 --output $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    }
}

function Resolve-NodeWindowsZipUrl($Major) {
    try {
        $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 60
        $v = $index |
            Where-Object { $_.version -like "v$Major.*" -and $_.files -contains "win-x64-zip" } |
            Select-Object -First 1
        if ($v -and $v.version) {
            return "https://nodejs.org/dist/$($v.version)/node-$($v.version)-win-x64.zip"
        }
    } catch {
        Write-Warn "Could not resolve latest Node $Major.x dynamically: $($_.Exception.Message)"
    }
    if ($Major -eq "24") { return "https://nodejs.org/dist/v24.11.1/node-v24.11.1-win-x64.zip" }
    return "https://nodejs.org/dist/v22.14.0/node-v22.14.0-win-x64.zip"
}

function Find-Python311 {
    try {
        $candidate = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null).Trim()
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    } catch {}
    try {
        $candidate = (& python -c "import sys; print(sys.executable if sys.version_info[:2] == (3,11) else '')" 2>$null).Trim()
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    } catch {}
    return ""
}

function Configure-NpmForCorporateNetwork($NodeBin, $NpmCafile, [switch]$UseNpmInsecure) {
    $env:Path = "$NodeBin;$env:Path"
    $env:NODE_OPTIONS = "--use-system-ca"
    if ($NpmCafile -and (Test-Path $NpmCafile)) {
        Write-Info "Using npm cafile: $NpmCafile"
        $env:NODE_EXTRA_CA_CERTS = $NpmCafile
        $env:npm_config_cafile = $NpmCafile
        & "$NodeBin\npm.cmd" config set cafile $NpmCafile
        & "$NodeBin\npm.cmd" config set strict-ssl true
    }
    if ($UseNpmInsecure) {
        Write-Warn "Using npm strict-ssl=false. Use only on a controlled build machine."
        & "$NodeBin\npm.cmd" config set strict-ssl false
        $env:npm_config_strict_ssl = "false"
        $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
    }
}

$WorkRoot = Join-Path $FactoryRoot "work"
$OutputRoot = Join-Path $FactoryRoot "output"
$PackRoot = Join-Path $WorkRoot $PackName
$OutputZip = Join-Path $OutputRoot "$PackName.zip"

Ensure-Dir $WorkRoot
Ensure-Dir $OutputRoot

if (Test-Path $PackRoot) {
    Write-Warn "Removing existing pack root: $PackRoot"
    Remove-Item -Recurse -Force $PackRoot
}
Ensure-Dir $PackRoot

$ToolsDir = Join-Path $PackRoot "tools"
$PythonDir = Join-Path $PackRoot "python"
$NpmDir = Join-Path $PackRoot "npm"
$SkillsDir = Join-Path $PackRoot "skills"
$ExamplesDir = Join-Path $PackRoot "examples"

Ensure-Dir $ToolsDir
Ensure-Dir $PythonDir
Ensure-Dir $NpmDir
Ensure-Dir $SkillsDir
Ensure-Dir $ExamplesDir
Ensure-Dir (Join-Path $PythonDir "wheelhouse-media")

Write-Step "Hermes Media Tools Airgap Pack v1"
Write-Info "Factory root: $FactoryRoot"
Write-Info "Pack root   : $PackRoot"
Write-Info "Output ZIP  : $OutputZip"

Write-Step "Copying payload skills/examples/installers"
$Payload = Join-Path $PSScriptRoot "payload"
if (-not (Test-Path $Payload)) { throw "payload folder missing next to this script: $Payload" }
Copy-Item (Join-Path $Payload "*") $PackRoot -Recurse -Force

Write-Step "Downloading Python 3.11 installer"
$PythonInstaller = Join-Path $ToolsDir "python-$PythonVersion-amd64.exe"
Invoke-Download "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" $PythonInstaller

Write-Step "Preparing Python 3.11 for media wheelhouse"
$PythonExe = Find-Python311
if (-not $PythonExe) {
    $BuildPython = Join-Path $PackRoot "_build_python311"
    Ensure-Dir $BuildPython
    Start-Process $PythonInstaller -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$BuildPython`"" -Wait
    $PythonExe = Join-Path $BuildPython "python.exe"
}
if (-not (Test-Path $PythonExe)) { throw "Could not find/install Python 3.11." }
& $PythonExe --version

Write-Step "Downloading FFmpeg/ffprobe"
if (-not $SkipFFmpeg) {
    $FfmpegZip = Join-Path $ToolsDir "ffmpeg-release-essentials.zip"
    try {
        Invoke-Download "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $FfmpegZip
        $FfmpegDir = Join-Path $ToolsDir "ffmpeg"
        Ensure-Dir $FfmpegDir
        Expand-Archive $FfmpegZip -DestinationPath $FfmpegDir -Force
    } catch {
        Write-Warn "FFmpeg download/extract failed: $($_.Exception.Message)"
        Write-Warn "You can manually place a Windows FFmpeg build under tools\ffmpeg later."
    }
}

Write-Step "Downloading Graphviz portable ZIP"
if (-not $SkipGraphviz) {
    $GraphvizDir = Join-Path $ToolsDir "graphviz"
    Ensure-Dir $GraphvizDir
    $GraphvizZip = Join-Path $ToolsDir "graphviz-win64.zip"
    $downloaded = $false
    try {
        $page = Invoke-WebRequest "https://graphviz.org/download/" -UseBasicParsing -TimeoutSec 120
        $html = $page.Content
        $matches = [regex]::Matches($html, 'https://[^"]+graphviz[^"]+win64[^"]+\.zip')
        if ($matches.Count -gt 0) {
            $url = $matches[0].Value -replace '&amp;', '&'
            Invoke-Download $url $GraphvizZip
            $downloaded = $true
        } else {
            Write-Warn "Could not auto-detect Graphviz win64 zip link."
        }
    } catch { Write-Warn "Graphviz auto-download failed: $($_.Exception.Message)" }

    if ($downloaded) {
        try { Expand-Archive $GraphvizZip -DestinationPath $GraphvizDir -Force }
        catch { Write-Warn "Graphviz extraction failed: $($_.Exception.Message)" }
    } else {
        "Place/extract Graphviz portable ZIP contents here. dot.exe should be under a bin folder." |
            Set-Content (Join-Path $GraphvizDir "MANUAL_GRAPHVIZ_DROP_HERE.txt") -Encoding UTF8
    }
}

Write-Step "Downloading Node.js portable and installing Mermaid CLI"
if (-not $SkipMermaid) {
    $NodeZipUrl = Resolve-NodeWindowsZipUrl $NodeMajor
    $NodeZip = Join-Path $ToolsDir (Split-Path $NodeZipUrl -Leaf)
    Invoke-Download $NodeZipUrl $NodeZip

    $NodeRoot = Join-Path $ToolsDir "node"
    Ensure-Dir $NodeRoot
    Expand-Archive $NodeZip -DestinationPath $NodeRoot -Force

    $NodeExe = Get-ChildItem $NodeRoot -Recurse -Filter "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $NodeExe) { throw "node.exe not found after extracting Node." }
    $NodeBin = Split-Path $NodeExe.FullName -Parent

    Configure-NpmForCorporateNetwork $NodeBin $NpmCafile -UseNpmInsecure:$UseNpmInsecure

    & "$NodeBin\node.exe" --version
    & "$NodeBin\npm.cmd" --version

    $MermaidProject = Join-Path $NpmDir "mermaid-cli"
    Ensure-Dir $MermaidProject
    Push-Location $MermaidProject

    @"
{
  "name": "hermes-media-mermaid-cli-offline",
  "private": true,
  "dependencies": {
    "@mermaid-js/mermaid-cli": "latest"
  }
}
"@ | Set-Content "package.json" -Encoding UTF8

    & "$NodeBin\npm.cmd" install
    if ($LASTEXITCODE -ne 0) { throw "npm install for mermaid-cli failed." }
    Pop-Location
}

Write-Step "Downloading Manim Python wheelhouse"
if (-not $SkipManim) {
    $Req = Join-Path $PythonDir "requirements-media.txt"
    "manim" | Set-Content $Req -Encoding UTF8
    $Wheelhouse = Join-Path $PythonDir "wheelhouse-media"

    try {
        & $PythonExe -m pip download --use-feature=truststore -r $Req -d $Wheelhouse --only-binary=:all:
    } catch {
        Write-Warn "pip download with truststore failed. Trying trusted-host fallback."
        & $PythonExe -m pip download --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org -r $Req -d $Wheelhouse --only-binary=:all:
    }
    if ($LASTEXITCODE -ne 0) { throw "pip download for Manim wheelhouse failed." }

    & $PythonExe -m pip download --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org pip setuptools wheel -d $Wheelhouse --only-binary=:all:
    if ($LASTEXITCODE -ne 0) { throw "pip download of pip/setuptools/wheel failed." }
}

Write-Step "Writing version manifest"
@"
PackName: $PackName
BuiltAt: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Includes:
  FFmpeg: $(-not $SkipFFmpeg)
  Graphviz: $(-not $SkipGraphviz)
  MermaidCLI: $(-not $SkipMermaid)
  Manim: $(-not $SkipManim)
"@ | Set-Content (Join-Path $PackRoot "VERSION.txt") -Encoding UTF8

Write-Step "Creating final ZIP"
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }
tar -a -cf $OutputZip -C $PackRoot .
if (-not (Test-Path $OutputZip)) { throw "Output ZIP was not created: $OutputZip" }

Write-Step "Done"
Write-Host "Copy this ZIP to intranet:"
Write-Host "  $OutputZip"
