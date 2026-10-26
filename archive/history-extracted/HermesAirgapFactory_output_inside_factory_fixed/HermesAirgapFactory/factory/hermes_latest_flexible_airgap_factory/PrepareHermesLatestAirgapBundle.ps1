
param(
    [string]$VersionRef = "latest",
    [string]$BundleRoot = "",
    [string]$OutputZip = "",
    [string[]]$Extras = @("web","mcp","cron","cli"),
    [switch]$SkipToolsDownload,
    [switch]$SkipSimulation
)

# HermesAirgapFactory local folders
New-Item -ItemType Directory -Force "C:\HermesAirgapFactory\work" | Out-Null
New-Item -ItemType Directory -Force "C:\HermesAirgapFactory\output" | Out-Null


$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Ensure-Dir($path) { if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force $path | Out-Null } }

function Download-File($Url, $OutFile, $Description) {
    Write-Info "Downloading $Description"
    Write-Info "  $Url"
    Write-Info "  -> $OutFile"
    Ensure-Dir (Split-Path $OutFile -Parent)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    } catch {
        Write-Warn "Invoke-WebRequest failed for $Description. Trying curl.exe fallback..."
        & curl.exe -L --fail --retry 3 --output $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed for $Description" }
    }
}

function Resolve-HermesRef([string]$RequestedRef) {
    if ($RequestedRef -and $RequestedRef.ToLowerInvariant() -ne "latest") {
        return [pscustomobject]@{
            Ref = $RequestedRef
            Tag = $RequestedRef
            Name = $RequestedRef
            Url = "manual-ref"
            Source = "user-supplied"
        }
    }

    Write-Step "Resolving latest Hermes Agent release from GitHub"
    try {
        $headers = @{ "User-Agent" = "Hermes-Airgap-Bundler" }
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/NousResearch/hermes-agent/releases/latest" -Headers $headers
        return [pscustomobject]@{
            Ref = $rel.tag_name
            Tag = $rel.tag_name
            Name = $rel.name
            Url = $rel.html_url
            Source = "github-api"
        }
    } catch {
        Write-Warn "Could not query GitHub latest release API. Falling back to known latest tag v2026.5.29.2."
        return [pscustomobject]@{
            Ref = "v2026.5.29.2"
            Tag = "v2026.5.29.2"
            Name = "Hermes Agent v0.15.2 fallback"
            Url = "https://github.com/NousResearch/hermes-agent/releases"
            Source = "fallback"
        }
    }
}

function Get-SafeName([string]$s) {
    return ($s -replace '[^A-Za-z0-9._-]', '_')
}

$release = Resolve-HermesRef $VersionRef
$safeRef = Get-SafeName $release.Ref

if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
    $BundleRoot = Join-Path "C:\HermesAirgapFactory\work" "HermesAirgapBundle_$safeRef"
}
if ([string]::IsNullOrWhiteSpace($OutputZip)) {
    $OutputZip = Join-Path "C:\HermesAirgapFactory\output" "HermesAirgapBundle_$safeRef.zip"
}

$BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
$OutputZip = [System.IO.Path]::GetFullPath($OutputZip)
$TranscriptPath = Join-Path $BundleRoot "prepare_online_transcript.log"

Write-Step "Hermes Agent air-gapped bundle preparation"
Write-Info "Requested ref     : $VersionRef"
Write-Info "Resolved ref      : $($release.Ref)"
Write-Info "Release name      : $($release.Name)"
Write-Info "Release URL       : $($release.Url)"
Write-Info "Bundle root       : $BundleRoot"
Write-Info "Output zip        : $OutputZip"
Write-Info "Extras            : $($Extras -join ', ')"

if (Test-Path $BundleRoot) {
    Write-Warn "Bundle root already exists. Removing: $BundleRoot"
    Remove-Item -Recurse -Force $BundleRoot
}

Ensure-Dir $BundleRoot
Ensure-Dir (Join-Path $BundleRoot "tools")
Ensure-Dir (Join-Path $BundleRoot "wheelhouse")
Ensure-Dir (Join-Path $BundleRoot "logs")

Start-Transcript -Path $TranscriptPath -Force | Out-Null

try {
    Write-Step "Checking required internet-side tools"
    & git --version
    if ($LASTEXITCODE -ne 0) { throw "git is required on the internet machine." }

    try {
        git config --global http.sslBackend schannel
        git config --global http.sslVerify true
    } catch {
        Write-Warn "Could not set git schannel SSL backend. Continuing."
    }

    try {
        py -3.11 --version
    } catch {
        Write-Warn "py -3.11 is not available. The script will still download Python 3.11.9 for the air-gapped machine, but wheelhouse creation needs Python 3.11 on this internet machine."
        throw "Install Python 3.11 on the internet machine before preparing the wheelhouse."
    }

    Write-Step "Cloning Hermes Agent source"
    $RepoDir = Join-Path $BundleRoot "hermes-agent"
    git clone https://github.com/NousResearch/hermes-agent.git $RepoDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }

    Push-Location $RepoDir
    git fetch --tags
    git checkout $release.Ref
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for ref $($release.Ref)" }

    $Commit = (git rev-parse HEAD).Trim()
    $Describe = ""
    try { $Describe = (git describe --tags --always).Trim() } catch { $Describe = $Commit }
    Pop-Location

    @"
Hermes Agent air-gapped bundle
GeneratedAtUtc: $((Get-Date).ToUniversalTime().ToString("s"))Z
RequestedRef: $VersionRef
ResolvedRef: $($release.Ref)
ReleaseName: $($release.Name)
ReleaseUrl: $($release.Url)
ReleaseSource: $($release.Source)
Commit: $Commit
Describe: $Describe
Extras: $($Extras -join ',')
"@ | Set-Content (Join-Path $BundleRoot "VERSION.txt") -Encoding UTF8

    Write-Step "Downloading portable prerequisites"
    $ToolsDir = Join-Path $BundleRoot "tools"

    # Python installer for air-gapped target.
    $PyInstaller = Join-Path $ToolsDir "python-3.11.9-amd64.exe"
    Download-File "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" $PyInstaller "Python 3.11.9 x64 installer"

    # uv
    $UvZip = Join-Path $ToolsDir "uv-x86_64-pc-windows-msvc.zip"
    Download-File "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" $UvZip "uv Windows x64"
    $UvDir = Join-Path $ToolsDir "uv"
    Ensure-Dir $UvDir
    Expand-Archive $UvZip -DestinationPath $UvDir -Force
    $UvExe = Join-Path $UvDir "uv.exe"
    & $UvExe --version

    if (-not $SkipToolsDownload) {
        Write-Step "Downloading optional CLI tools for the target machine"

        # ripgrep latest asset
        try {
            $headers = @{ "User-Agent" = "Hermes-Airgap-Bundler" }
            $rgRel = Invoke-RestMethod -Uri "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -Headers $headers
            $rgAsset = $rgRel.assets | Where-Object { $_.name -match 'x86_64-pc-windows-msvc\.zip$' } | Select-Object -First 1
            if ($rgAsset) {
                $rgZip = Join-Path $ToolsDir $rgAsset.name
                Download-File $rgAsset.browser_download_url $rgZip "ripgrep"
                $rgDir = Join-Path $ToolsDir "ripgrep"
                Ensure-Dir $rgDir
                Expand-Archive $rgZip -DestinationPath $rgDir -Force
            } else {
                Write-Warn "Could not find ripgrep Windows asset. Skipping."
            }
        } catch {
            Write-Warn "Could not download ripgrep. Skipping. $_"
        }

        # ffmpeg essentials build
        try {
            $ffZip = Join-Path $ToolsDir "ffmpeg-release-essentials.zip"
            Download-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $ffZip "FFmpeg release essentials"
            $ffDir = Join-Path $ToolsDir "ffmpeg"
            Ensure-Dir $ffDir
            Expand-Archive $ffZip -DestinationPath $ffDir -Force
        } catch {
            Write-Warn "Could not download FFmpeg. Skipping. $_"
        }

        # PortableGit fallback for targets without Git Bash.
        try {
            $headers = @{ "User-Agent" = "Hermes-Airgap-Bundler" }
            $gitRel = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" -Headers $headers
            $gitAsset = $gitRel.assets | Where-Object { $_.name -match '^PortableGit-.*-64-bit\.7z\.exe$' } | Select-Object -First 1
            if ($gitAsset) {
                $gitExe = Join-Path $ToolsDir $gitAsset.name
                Download-File $gitAsset.browser_download_url $gitExe "PortableGit fallback"
            } else {
                Write-Warn "Could not find PortableGit x64 asset. Skipping."
            }
        } catch {
            Write-Warn "Could not download PortableGit. Skipping. Existing Git Bash on target will still work. $_"
        }

        # Node 22 portable zip for targets without node/npm.
        try {
            $nodeZip = Join-Path $ToolsDir "node-v22-win-x64.zip"
            Download-File "https://nodejs.org/dist/latest-v22.x/node-v22.21.1-win-x64.zip" $nodeZip "Node.js 22 x64 portable zip"
            $nodeDir = Join-Path $ToolsDir "node"
            Ensure-Dir $nodeDir
            Expand-Archive $nodeZip -DestinationPath $nodeDir -Force
        } catch {
            Write-Warn "Could not download Node.js portable zip. Skipping. $_"
        }
    }

    Write-Step "Compiling Python requirements from pyproject.toml"
    $ReqFile = Join-Path $BundleRoot "requirements-hermes-win.txt"
    Push-Location $RepoDir
    $compileArgs = @("pip","compile",".\pyproject.toml")
    foreach ($e in $Extras) { $compileArgs += @("--extra", $e) }
    $compileArgs += @("-o", $ReqFile)

    $env:UV_NATIVE_TLS = "true"
    & $UvExe --system-certs @compileArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "uv --system-certs failed. Trying --native-tls."
        & $UvExe --native-tls @compileArgs
    }
    if ($LASTEXITCODE -ne 0) {
        throw "uv pip compile failed. Check extras and network/certificate settings."
    }
    Pop-Location

    Write-Step "Downloading Python wheels into wheelhouse"
    $Wheelhouse = Join-Path $BundleRoot "wheelhouse"
    py -3.11 -m pip download --use-feature=truststore -r $ReqFile -d $Wheelhouse --only-binary=:all:
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "pip download with truststore failed. Trying trusted-host fallback for corporate TLS interception."
        py -3.11 -m pip download `
            --trusted-host pypi.org `
            --trusted-host files.pythonhosted.org `
            --trusted-host pypi.python.org `
            -r $ReqFile `
            -d $Wheelhouse `
            --only-binary=:all:
    }
    if ($LASTEXITCODE -ne 0) { throw "pip download failed for Hermes requirements" }

    py -3.11 -m pip download --use-feature=truststore pip setuptools wheel -d $Wheelhouse --only-binary=:all:
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "pip/setuptools/wheel truststore download failed. Trying trusted-host fallback."
        py -3.11 -m pip download `
            --trusted-host pypi.org `
            --trusted-host files.pythonhosted.org `
            --trusted-host pypi.python.org `
            pip setuptools wheel `
            -d $Wheelhouse `
            --only-binary=:all:
    }
    if ($LASTEXITCODE -ne 0) { throw "pip download failed for pip/setuptools/wheel" }

    Write-Step "Writing air-gapped target installer into bundle"
    $InstallerPs1 = Join-Path $BundleRoot "InstallOrUpdateHermesAirgapped.ps1"
    $InstallerBat = Join-Path $BundleRoot "InstallOrUpdateHermesAirgapped.bat"
    $StartBat = Join-Path $BundleRoot "StartHermesChat.bat"
    $Readme = Join-Path $BundleRoot "README_AIRGAP_INSTALL_OR_UPDATE.txt"

    Set-Content -Path $InstallerPs1 -Encoding UTF8 -Value @'
param(
    [ValidateSet("Auto","Install","Update")]
    [string]$Mode = "Auto",
    [switch]$CleanVenv,
    [switch]$SkipDoctor
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}
function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Ensure-Dir($path) { if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force $path | Out-Null } }

$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
$InstallDir = Join-Path $HermesHome "hermes-agent"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$SourceDir = Join-Path $BundleRoot "hermes-agent"
$ToolsDir = Join-Path $BundleRoot "tools"

Ensure-Dir $HermesHome
Ensure-Dir (Join-Path $HermesHome "logs")
$LogPath = Join-Path $HermesHome ("install_or_update_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
Start-Transcript -Path $LogPath -Force | Out-Null

try {
    Write-Step "Hermes air-gapped install/update"
    Write-Info "BundleRoot : $BundleRoot"
    Write-Info "HermesHome : $HermesHome"
    Write-Info "InstallDir : $InstallDir"
    Write-Info "Mode       : $Mode"
    Write-Info "CleanVenv  : $CleanVenv"

    if (-not (Test-Path $SourceDir)) { throw "Bundle is missing hermes-agent source folder: $SourceDir" }
    if (-not (Test-Path $Wheelhouse)) { throw "Bundle is missing wheelhouse folder: $Wheelhouse" }

    $ExistingInstall = Test-Path $InstallDir
    if ($Mode -eq "Auto") {
        if ($ExistingInstall) { $EffectiveMode = "Update" } else { $EffectiveMode = "Install" }
    } else {
        $EffectiveMode = $Mode
    }
    Write-Info "Effective mode: $EffectiveMode"

    Write-Step "Ensuring Python 3.11"
    $PythonDir = Join-Path $HermesHome "python311"
    $PythonExe = Join-Path $PythonDir "python.exe"

    if (-not (Test-Path $PythonExe)) {
        $PyInstaller = Join-Path $ToolsDir "python-3.11.9-amd64.exe"
        if (-not (Test-Path $PyInstaller)) {
            throw "Python 3.11 not found and bundle has no python-3.11.9-amd64.exe"
        }
        Write-Info "Installing isolated Python 3.11.9 to $PythonDir"
        Ensure-Dir $HermesHome
        Start-Process $PyInstaller -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$PythonDir`"" -Wait
    }
    if (-not (Test-Path $PythonExe)) { throw "Python install failed or python.exe not found at $PythonExe" }
    & $PythonExe --version
    Copy-Item $PythonExe (Join-Path $PythonDir "python3.exe") -Force -ErrorAction SilentlyContinue

    Write-Step "Backing up current Hermes state"
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    if (Test-Path $HermesHome) {
        $BackupRoot = Join-Path $env:LOCALAPPDATA ("hermes_backup_before_airgap_" + $Timestamp)
        Write-Info "Creating backup: $BackupRoot"
        Copy-Item $HermesHome $BackupRoot -Recurse -Force
    } else {
        Write-Info "No existing Hermes home found. Fresh install."
    }

    Write-Step "Installing Hermes source"
    $OldSourceBackup = $null
    $OldVenv = $null
    if (Test-Path $InstallDir) {
        $OldSourceBackup = Join-Path $HermesHome ("hermes-agent_source_backup_" + $Timestamp)
        Write-Info "Moving old source to: $OldSourceBackup"
        Rename-Item $InstallDir $OldSourceBackup
        if (Test-Path (Join-Path $OldSourceBackup "venv")) {
            $OldVenv = Join-Path $OldSourceBackup "venv"
        }
    }

    Copy-Item $SourceDir $InstallDir -Recurse -Force

    $VenvDir = Join-Path $InstallDir "venv"
    if (($EffectiveMode -eq "Update") -and (-not $CleanVenv) -and $OldVenv -and (Test-Path $OldVenv)) {
        Write-Info "Reusing existing venv from previous install."
        Copy-Item $OldVenv $VenvDir -Recurse -Force
    } else {
        Write-Info "Creating clean venv."
        if (Test-Path $VenvDir) { Remove-Item -Recurse -Force $VenvDir }
        & $PythonExe -m venv $VenvDir
    }

    $VenvPy = Join-Path $VenvDir "Scripts\python.exe"
    if (-not (Test-Path $VenvPy)) { throw "venv python not found: $VenvPy" }
    & $VenvPy --version

    Write-Step "Installing/updating Python packages from offline wheelhouse"
    & $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
    if ($LASTEXITCODE -ne 0) { throw "offline install of pip/setuptools/wheel failed" }

    Push-Location $InstallDir
    & $VenvPy -m pip install --no-index --find-links $Wheelhouse -e ".[web,mcp,cron,cli]"
    if ($LASTEXITCODE -ne 0) { throw "offline install of hermes-agent failed" }
    Pop-Location

    $ScriptsDir = Join-Path $VenvDir "Scripts"
    Copy-Item (Join-Path $ScriptsDir "python.exe") (Join-Path $ScriptsDir "python3.exe") -Force -ErrorAction SilentlyContinue

    Write-Step "Configuring PATH and environment variables"
    $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $AddPaths = New-Object System.Collections.Generic.List[string]
    $AddPaths.Add($ScriptsDir)
    $AddPaths.Add($PythonDir)
    $AddPaths.Add((Join-Path $PythonDir "Scripts"))

    $RgExe = Get-ChildItem (Join-Path $ToolsDir "ripgrep") -Recurse -Filter "rg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($RgExe) { $AddPaths.Add((Split-Path $RgExe.FullName -Parent)) }

    $FfmpegExe = Get-ChildItem (Join-Path $ToolsDir "ffmpeg") -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($FfmpegExe) { $AddPaths.Add((Split-Path $FfmpegExe.FullName -Parent)) }

    $NodeExe = Get-ChildItem (Join-Path $ToolsDir "node") -Recurse -Filter "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($NodeExe) { $AddPaths.Add((Split-Path $NodeExe.FullName -Parent)) }

    $NewUserPath = $CurrentUserPath
    foreach ($p in $AddPaths) {
        if ($p -and (Test-Path $p) -and ($NewUserPath -notlike "*$p*")) {
            $NewUserPath = "$p;$NewUserPath"
        }
        if ($p -and (Test-Path $p)) {
            $env:Path = "$p;$env:Path"
        }
    }
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")

    [Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
    [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
    [Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
    $env:HERMES_HOME = $HermesHome
    $env:PYTHONUTF8 = "1"
    $env:PYTHONIOENCODING = "utf-8"

    Write-Step "Configuring Git Bash for native Windows shell tools"
    $GitCandidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
    )
    $GitBash = $GitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $GitBash) {
        $PortableGit = Get-ChildItem $ToolsDir -Filter "PortableGit-*-64-bit.7z.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($PortableGit) {
            $GitDir = Join-Path $HermesHome "git"
            Ensure-Dir $GitDir
            Write-Info "Extracting bundled PortableGit to $GitDir"
            Start-Process $PortableGit.FullName -ArgumentList "-o`"$GitDir`"", "-y" -Wait
            $GitCandidates = @(
                (Join-Path $GitDir "bin\bash.exe"),
                (Join-Path $GitDir "usr\bin\bash.exe")
            )
            $GitBash = $GitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        }
    }

    if ($GitBash) {
        [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $GitBash, "User")
        $env:HERMES_GIT_BASH_PATH = $GitBash
        Write-Info "Git Bash: $GitBash"
        & $GitBash --version
    } else {
        Write-Warn "Git Bash not found. Hermes shell tools may fail. Install Git for Windows or include PortableGit in the bundle."
    }

    Write-Step "Version and basic checks"
    $HermesExe = Join-Path $ScriptsDir "hermes.exe"
    if (-not (Test-Path $HermesExe)) { throw "hermes.exe not found at $HermesExe" }

    & $HermesExe --version
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "hermes --version returned non-zero exit code. Trying 'hermes version'."
        & $HermesExe version
    }

    try { & $HermesExe config check } catch { Write-Warn "hermes config check failed: $_" }
    try { & $HermesExe config migrate } catch { Write-Warn "hermes config migrate failed or not needed: $_" }

    if (-not $SkipDoctor) {
        try { & $HermesExe doctor } catch { Write-Warn "hermes doctor failed or reported warnings: $_" }
    }

    Write-Step "DONE"
    Write-Host "Hermes install/update completed." -ForegroundColor Green
    Write-Host "Open a NEW PowerShell window, then run:" -ForegroundColor Green
    Write-Host "  hermes --version"
    Write-Host "  hermes model"
    Write-Host "  hermes chat"
    Write-Host ""
    Write-Host "For your company local model, use 'Custom endpoint' rather than 'Custom API'." -ForegroundColor Yellow

} catch {
    Write-Host ""
    Write-Host "FAILED: $_" -ForegroundColor Red
    Write-Host "Log file: $LogPath" -ForegroundColor Yellow
    throw
} finally {
    Stop-Transcript | Out-Null
}
'@

    Set-Content -Path $InstallerBat -Encoding ASCII -Value @'
@echo off
setlocal
cd /d "%~dp0"
echo Hermes Agent air-gapped install/update
echo.
echo Default mode is Auto:
echo   - Updates if Hermes already exists in %%LOCALAPPDATA%%\hermes\hermes-agent
echo   - Fresh installs if it does not exist
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" -Mode Auto
echo.
pause
'@

    Set-Content -Path $StartBat -Encoding ASCII -Value @'
@echo off
setlocal
set "HERMES_HOME=%LOCALAPPDATA%\hermes"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
if exist "C:\Program Files\Git\bin\bash.exe" set "HERMES_GIT_BASH_PATH=C:\Program Files\Git\bin\bash.exe"
chcp 65001 >nul
hermes chat
pause
'@

    Set-Content -Path $Readme -Encoding UTF8 -Value @"
Hermes Agent air-gapped bundle
================================

Generated from:
  Ref      : $($release.Ref)
  Name     : $($release.Name)
  URL      : $($release.Url)
  Commit   : $Commit
  Describe : $Describe

Internet machine:
  This bundle was prepared by PrepareHermesLatestAirgapBundle.ps1.

Air-gapped / intranet machine:
  1. Copy this ZIP to the air-gapped Windows machine.
  2. Extract it to a folder, for example:
       C:\Tools\HermesAirgapBundle
  3. Double-click:
       InstallOrUpdateHermesAirgapped.bat

What it does:
  - If Hermes is not installed: fresh install.
  - If Hermes is already installed: update existing install.
  - Backs up %LOCALAPPDATA%\hermes before changing it.
  - Installs/uses isolated Python 3.11.9.
  - Installs Python packages only from local wheelhouse.
  - Creates python3.exe alias for tools that expect python3.
  - Configures HERMES_GIT_BASH_PATH if Git Bash is present.
  - Adds Hermes venv Scripts to User PATH.
  - Runs basic version/config/doctor checks.

After install/update:
  Open a new PowerShell window:
       hermes --version
       hermes model
       hermes chat

For your company OpenAI-compatible model:
  Choose "Custom endpoint" in hermes model.
  Do NOT choose "Custom API".
  Base URL should include /v1, for example:
       https://your-company-gateway/v1
"@

    if (-not $SkipSimulation) {
        Write-Step "Offline install simulation on internet machine"
        $TestVenv = Join-Path $BundleRoot "_test_venv"
        if (Test-Path $TestVenv) { Remove-Item -Recurse -Force $TestVenv }
        py -3.11 -m venv $TestVenv
        $TestPy = Join-Path $TestVenv "Scripts\python.exe"

        & $TestPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed while installing pip/setuptools/wheel" }

        Push-Location $RepoDir
        & $TestPy -m pip install --no-index --find-links $Wheelhouse -e ".[web,mcp,cron,cli]"
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed while installing hermes-agent" }
        Pop-Location

        $TestHermes = Join-Path $TestVenv "Scripts\hermes.exe"
        if (Test-Path $TestHermes) {
            & $TestHermes --version
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "hermes --version returned non-zero in simulation. Trying hermes version and continuing if install succeeded."
                & $TestHermes version
            }
            & $TestHermes --help | Out-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "hermes --help returned non-zero, but help text may still have been printed. Continuing."
            }
        } else {
            throw "Simulation failed: hermes.exe not found"
        }

        Remove-Item -Recurse -Force $TestVenv -ErrorAction SilentlyContinue
    }

    Write-Step "Creating final ZIP"
    if (Test-Path $OutputZip) { Remove-Item -Force $OutputZip }
    tar -a -cf $OutputZip -C $BundleRoot .
    if (-not (Test-Path $OutputZip)) { throw "ZIP creation failed: $OutputZip" }

    Write-Step "Bundle ready"
    Write-Host "Output ZIP:" -ForegroundColor Green
    Write-Host "  $OutputZip" -ForegroundColor Green
    Write-Host ""
    Write-Host "Copy this ZIP to the air-gapped Windows machine, extract it, and double-click:" -ForegroundColor Green
    Write-Host "  InstallOrUpdateHermesAirgapped.bat" -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "Preparation failed: $_" -ForegroundColor Red
    Write-Host "Transcript: $TranscriptPath" -ForegroundColor Yellow
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
