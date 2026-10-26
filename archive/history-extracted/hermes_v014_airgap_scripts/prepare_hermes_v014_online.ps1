param(
    [string]$BundleRoot = "C:\HermesOfflineBundle_v0.14.0",
    [string]$HermesTag = "v0.14.0",
    [string]$PythonVersion = "3.11.9",
    [switch]$SkipToolDownloads,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Require-Command {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Required command not found: $Name. Please install it or add it to PATH, then run this script again."
    }
    return $cmd.Source
}

function Invoke-Download {
    param(
        [string]$Url,
        [string]$OutFile
    )
    Write-Host "Downloading:`n  $Url`n  -> $OutFile"
    New-Item -ItemType Directory -Force (Split-Path $OutFile -Parent) | Out-Null
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

function Remove-IfExists {
    param([string]$Path)
    if (Test-Path $Path) {
        Remove-Item -Recurse -Force $Path
    }
}

function Run-OrThrow {
    param(
        [scriptblock]$Script,
        [string]$Message
    )
    & $Script
    if ($LASTEXITCODE -ne 0) {
        throw "$Message. Exit code: $LASTEXITCODE"
    }
}

$StartTime = Get-Date
$ToolsDir = Join-Path $BundleRoot "tools"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$RepoDir = Join-Path $BundleRoot "hermes-agent"
$Transcript = Join-Path $BundleRoot "prepare_online_transcript.log"

Write-Step "Preparing Hermes Agent $HermesTag air-gapped bundle"
Write-Host "BundleRoot : $BundleRoot"
Write-Host "HermesTag  : $HermesTag"

New-Item -ItemType Directory -Force $BundleRoot, $ToolsDir, $Wheelhouse | Out-Null
Start-Transcript -Path $Transcript -Force | Out-Null

try {
    Write-Step "Checking required internet-PC commands"
    Require-Command git | Out-Null
    Write-Ok "git found: $(git --version)"
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"

    Write-Step "Configuring Git TLS for corporate SSL inspection if needed"
    git config --global http.sslBackend schannel
    git config --global http.sslVerify true
    Write-Ok "Git http.sslBackend=$(git config --global --get http.sslBackend)"

    Write-Step "Downloading Python $PythonVersion installer for the offline bundle"
    $PythonInstaller = Join-Path $ToolsDir "python-$PythonVersion-amd64.exe"
    $PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
    if (-not (Test-Path $PythonInstaller)) {
        Invoke-Download -Url $PythonUrl -OutFile $PythonInstaller
    } else {
        Write-Ok "Python installer already exists: $PythonInstaller"
    }

    Write-Step "Preparing Python 3.11 executable for bundle generation"
    $PythonExe = $null
    $pyCmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyCmd) {
        try {
            $ver = & py -3.11 --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver -match "Python 3\.11") {
                $PythonExe = "py -3.11"
                Write-Ok "Using system launcher: py -3.11 ($ver)"
            }
        } catch {}
    }

    if (-not $PythonExe) {
        $PrepPythonDir = Join-Path $env:TEMP "hermes_python311_prepare"
        $PrepPythonExe = Join-Path $PrepPythonDir "python.exe"
        if (-not (Test-Path $PrepPythonExe)) {
            Write-Host "Python 3.11 not found via py launcher. Installing temporary user-local Python for bundle preparation..."
            Start-Process $PythonInstaller -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$PrepPythonDir`"" -Wait
        }
        if (-not (Test-Path $PrepPythonExe)) {
            throw "Temporary Python install failed: $PrepPythonExe not found"
        }
        $PythonExe = $PrepPythonExe
        Write-Ok "Using temporary Python: $PrepPythonExe"
    }

    Write-Step "Downloading uv for Windows"
    $UvZip = Join-Path $ToolsDir "uv-x86_64-pc-windows-msvc.zip"
    $UvDir = Join-Path $ToolsDir "uv"
    $UvExe = Join-Path $UvDir "uv.exe"
    if (-not (Test-Path $UvExe)) {
        if (-not (Test-Path $UvZip)) {
            Invoke-Download -Url "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" -OutFile $UvZip
        }
        Remove-IfExists $UvDir
        Expand-Archive $UvZip -DestinationPath $UvDir -Force
    }
    if (-not (Test-Path $UvExe)) { throw "uv.exe not found after extraction: $UvExe" }
    Write-Ok "uv found: $(& $UvExe --version)"

    if (-not $SkipToolDownloads) {
        Write-Step "Downloading optional CLI tools: ripgrep and FFmpeg"
        try {
            $RgDir = Join-Path $ToolsDir "ripgrep"
            if (-not (Get-ChildItem $RgDir -Recurse -Filter "rg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                $RgRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" -UseBasicParsing
                $RgAsset = $RgRelease.assets | Where-Object { $_.name -match "x86_64-pc-windows-msvc\.zip$" } | Select-Object -First 1
                if ($RgAsset) {
                    $RgZip = Join-Path $ToolsDir $RgAsset.name
                    Invoke-Download -Url $RgAsset.browser_download_url -OutFile $RgZip
                    Remove-IfExists $RgDir
                    New-Item -ItemType Directory -Force $RgDir | Out-Null
                    Expand-Archive $RgZip -DestinationPath $RgDir -Force
                    Write-Ok "ripgrep downloaded"
                } else {
                    Write-Warn2 "Could not locate ripgrep Windows MSVC asset; skipping."
                }
            } else {
                Write-Ok "ripgrep already exists"
            }
        } catch {
            Write-Warn2 "ripgrep download skipped: $($_.Exception.Message)"
        }

        try {
            $FfmpegDir = Join-Path $ToolsDir "ffmpeg"
            if (-not (Get-ChildItem $FfmpegDir -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                $FfmpegZip = Join-Path $ToolsDir "ffmpeg-release-essentials.zip"
                Invoke-Download -Url "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $FfmpegZip
                Remove-IfExists $FfmpegDir
                New-Item -ItemType Directory -Force $FfmpegDir | Out-Null
                Expand-Archive $FfmpegZip -DestinationPath $FfmpegDir -Force
                Write-Ok "FFmpeg downloaded"
            } else {
                Write-Ok "FFmpeg already exists"
            }
        } catch {
            Write-Warn2 "FFmpeg download skipped: $($_.Exception.Message)"
        }
    }

    Write-Step "Cloning/checking out Hermes Agent source"
    if (-not (Test-Path $RepoDir)) {
        git clone https://github.com/NousResearch/hermes-agent.git $RepoDir
    }
    cd $RepoDir
    git fetch --tags
    git checkout $HermesTag
    git rev-parse HEAD | Set-Content (Join-Path $BundleRoot "VERSION.txt") -Encoding ascii
    git status --short
    Write-Ok "Hermes source ready at $RepoDir"

    Write-Step "Compiling dependency requirements with uv"
    $env:UV_NATIVE_TLS = "true"
    $ReqFile = Join-Path $BundleRoot "requirements-hermes-win.txt"
    $SelectedExtrasFile = Join-Path $BundleRoot "SELECTED_EXTRAS.txt"

    $ExtraSets = @(
        @("web","mcp","cron","cli"),
        @("cli","mcp"),
        @()
    )

    $compileSucceeded = $false
    $selectedExtras = @()

    foreach ($extras in $ExtraSets) {
        $extraArgs = @()
        foreach ($ex in $extras) { $extraArgs += @("--extra", $ex) }

        Write-Host "Trying extras: $($extras -join ', ')"
        & $UvExe --system-certs pip compile .\pyproject.toml @extraArgs -o $ReqFile
        if ($LASTEXITCODE -eq 0) {
            $compileSucceeded = $true
            $selectedExtras = $extras
            break
        }

        Write-Warn2 "uv --system-certs failed, trying --native-tls..."
        & $UvExe --native-tls pip compile .\pyproject.toml @extraArgs -o $ReqFile
        if ($LASTEXITCODE -eq 0) {
            $compileSucceeded = $true
            $selectedExtras = $extras
            break
        }

        Write-Warn2 "Compile failed for extras: $($extras -join ', ')"
    }

    if (-not $compileSucceeded) {
        throw "Failed to compile requirements with uv for all extras sets."
    }

    ($selectedExtras -join ",") | Set-Content $SelectedExtrasFile -Encoding ascii
    Write-Ok "Requirements compiled. Selected extras: $($selectedExtras -join ', ')"

    Write-Step "Downloading Python wheelhouse"
    New-Item -ItemType Directory -Force $Wheelhouse | Out-Null

    $PipDownloadArgs = @("-m","pip","download","--use-feature=truststore","-r",$ReqFile,"-d",$Wheelhouse,"--only-binary=:all:")
    if ($PythonExe -eq "py -3.11") {
        & py -3.11 @PipDownloadArgs
    } else {
        & $PythonExe @PipDownloadArgs
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "pip download with truststore failed. Trying trusted-host fallback."
        $PipDownloadArgs = @(
            "-m","pip","download",
            "--trusted-host","pypi.org",
            "--trusted-host","files.pythonhosted.org",
            "--trusted-host","pypi.python.org",
            "-r",$ReqFile,
            "-d",$Wheelhouse,
            "--only-binary=:all:"
        )
        if ($PythonExe -eq "py -3.11") {
            & py -3.11 @PipDownloadArgs
        } else {
            & $PythonExe @PipDownloadArgs
        }
        if ($LASTEXITCODE -ne 0) {
            throw "pip download failed even with trusted-host fallback."
        }
    }

    Write-Step "Downloading base packaging wheels"
    $BaseWheelsArgs = @(
        "-m","pip","download",
        "--trusted-host","pypi.org",
        "--trusted-host","files.pythonhosted.org",
        "--trusted-host","pypi.python.org",
        "pip","setuptools","wheel",
        "-d",$Wheelhouse,
        "--only-binary=:all:"
    )
    if ($PythonExe -eq "py -3.11") {
        & py -3.11 @BaseWheelsArgs
    } else {
        & $PythonExe @BaseWheelsArgs
    }
    if ($LASTEXITCODE -ne 0) { throw "Base wheel download failed." }

    Write-Ok "Wheelhouse count: $((Get-ChildItem $Wheelhouse | Measure-Object).Count)"

    Write-Step "Writing offline installer script into bundle"
    $OfflineInstallerPath = Join-Path $BundleRoot "install_hermes_v014_offline.ps1"
    $OfflineInstaller = @'
param(
    [string]$BundleRoot = "C:\Tools\HermesOfflineBundle_v0.14.0",
    [switch]$KeepOldSource
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

$HermesHome = "$env:LOCALAPPDATA\hermes"
$InstallDir = "$HermesHome\hermes-agent"
$PythonDir = "$HermesHome\python311"
$PythonExe = "$PythonDir\python.exe"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$RepoSource = Join-Path $BundleRoot "hermes-agent"
$ExtrasFile = Join-Path $BundleRoot "SELECTED_EXTRAS.txt"

Write-Step "Installing/updating Hermes Agent offline from $BundleRoot"

if (-not (Test-Path $BundleRoot)) { throw "BundleRoot not found: $BundleRoot" }
if (-not (Test-Path $Wheelhouse)) { throw "Wheelhouse not found: $Wheelhouse" }
if (-not (Test-Path $RepoSource)) { throw "Hermes source not found: $RepoSource" }

New-Item -ItemType Directory -Force $HermesHome | Out-Null

Write-Step "Ensuring isolated Python 3.11.9 exists"
if (-not (Test-Path $PythonExe)) {
    $PythonInstaller = Get-ChildItem (Join-Path $BundleRoot "tools") -Filter "python-3.11.9-amd64.exe" -Recurse | Select-Object -First 1
    if (-not $PythonInstaller) { throw "Python 3.11.9 installer not found in bundle tools folder." }
    Start-Process $PythonInstaller.FullName -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$PythonDir`"" -Wait
}
& $PythonExe --version
if ($LASTEXITCODE -ne 0) { throw "Python check failed." }

Write-Step "Backing up existing Hermes home"
$BackupRoot = "$env:LOCALAPPDATA\hermes_backup_before_v014_$(Get-Date -Format yyyyMMdd_HHmmss)"
if (Test-Path $HermesHome) {
    Copy-Item $HermesHome $BackupRoot -Recurse -Force
    Write-Ok "Backup created: $BackupRoot"
}

Write-Step "Replacing Hermes source"
if (Test-Path $InstallDir) {
    if ($KeepOldSource) {
        $OldName = "$HermesHome\hermes-agent_old_before_v014_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Rename-Item $InstallDir $OldName
        Write-Ok "Old source renamed to: $OldName"
    } else {
        Remove-Item -Recurse -Force $InstallDir
    }
}
Copy-Item $RepoSource $InstallDir -Recurse -Force

Write-Step "Creating clean venv and installing from wheelhouse"
Remove-Item -Recurse -Force "$InstallDir\venv" -ErrorAction SilentlyContinue
& $PythonExe -m venv "$InstallDir\venv"

$VenvPy = "$InstallDir\venv\Scripts\python.exe"

& $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) { throw "pip/setuptools/wheel offline install failed." }

$Extras = ""
if (Test-Path $ExtrasFile) { $Extras = (Get-Content $ExtrasFile -Raw).Trim() }

cd $InstallDir
if ($Extras) {
    $EditableSpec = ".[{0}]" -f $Extras
} else {
    $EditableSpec = "."
}

Write-Host "Installing editable spec: $EditableSpec"
& $VenvPy -m pip install --no-index --find-links $Wheelhouse -e $EditableSpec
if ($LASTEXITCODE -ne 0) { throw "Hermes offline install failed." }

Write-Step "Ensuring python3 alias and PATH"
$ScriptsDir = "$InstallDir\venv\Scripts"
Copy-Item "$ScriptsDir\python.exe" "$ScriptsDir\python3.exe" -Force

$CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentUserPath -notlike "*$ScriptsDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$ScriptsDir;$CurrentUserPath", "User")
}
$env:Path = "$ScriptsDir;$env:Path"

Write-Step "Setting Git Bash path if available"
$GitBashCandidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
)
$GitBash = $GitBashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($GitBash) {
    [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $GitBash, "User")
    $env:HERMES_GIT_BASH_PATH = $GitBash
    Write-Ok "HERMES_GIT_BASH_PATH=$GitBash"
} else {
    Write-Host "[WARN] Git Bash not found. Set HERMES_GIT_BASH_PATH manually if Hermes shell tools need bash." -ForegroundColor Yellow
}

[Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
[Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
[Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
$env:HERMES_HOME = $HermesHome
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

Write-Step "Version and config checks"
& "$ScriptsDir\hermes.exe" --help | Select-Object -First 20
try { & "$ScriptsDir\hermes.exe" --version } catch {}
try { & "$ScriptsDir\hermes.exe" config check } catch {
    Write-Host "[WARN] hermes config check failed or is unavailable. You can run it manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "Open a NEW PowerShell window, then run:"
Write-Host "  hermes model"
Write-Host "Choose: Custom endpoint"
Write-Host "Then set your internal base URL, API key, and model name."
Write-Host ""
Write-Host "After that:"
Write-Host "  hermes chat"
'@
    Set-Content -Path $OfflineInstallerPath -Value $OfflineInstaller -Encoding UTF8

    Write-Step "Writing README into bundle"
    $Readme = @"
Hermes Agent $HermesTag Air-Gapped Bundle
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Commit: $(Get-Content (Join-Path $BundleRoot "VERSION.txt") -Raw)
Selected extras: $($selectedExtras -join ",")

INTERNET PC:
- This bundle was prepared by prepare_hermes_v014_online.ps1.

INTRANET/OFFLINE PC:
1. Copy HermesOfflineBundle_v0.14.0.zip to the offline PC.
2. Extract it to:
   C:\Tools\HermesOfflineBundle_v0.14.0
3. Run PowerShell:
   powershell -ExecutionPolicy Bypass -File C:\Tools\HermesOfflineBundle_v0.14.0\install_hermes_v014_offline.ps1 -BundleRoot C:\Tools\HermesOfflineBundle_v0.14.0
4. Open a NEW PowerShell window.
5. Run:
   hermes model
6. Choose:
   Custom endpoint
7. Enter your internal OpenAI-compatible base URL, API key, and model name.
   Example:
   Base URL: https://your-internal-gateway/v1
   Model:    Qwen3.5-397B-A17B-FP8
8. Run:
   hermes chat

Notes:
- Do not use 'Custom API' for OpenAI-compatible internal gateways unless your Hermes setup specifically requires it.
- Use 'Custom endpoint'.
- If Hermes says python3 is missing, the offline installer creates venv\Scripts\python3.exe.
- Existing Hermes home is backed up under %LOCALAPPDATA%\hermes_backup_before_v014_*.
"@
    Set-Content -Path (Join-Path $BundleRoot "README_AIRGAP_INSTALL.txt") -Value $Readme -Encoding UTF8

    Write-Step "Offline install simulation"
    $TestVenv = Join-Path $BundleRoot "_test_venv"
    Remove-IfExists $TestVenv

    if ($PythonExe -eq "py -3.11") {
        & py -3.11 -m venv $TestVenv
    } else {
        & $PythonExe -m venv $TestVenv
    }
    if ($LASTEXITCODE -ne 0) { throw "Test venv creation failed." }

    $TestPy = Join-Path $TestVenv "Scripts\python.exe"

    & $TestPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
    if ($LASTEXITCODE -ne 0) { throw "Test install of pip/setuptools/wheel failed." }

    cd $RepoDir
    if ($selectedExtras.Count -gt 0) {
        $EditableSpec = ".[{0}]" -f ($selectedExtras -join ",")
    } else {
        $EditableSpec = "."
    }

    & $TestPy -m pip install --no-index --find-links $Wheelhouse -e $EditableSpec
    if ($LASTEXITCODE -ne 0) { throw "Test install of Hermes failed." }

    & (Join-Path $TestVenv "Scripts\hermes.exe") --help | Select-Object -First 10
    if ($LASTEXITCODE -ne 0) { throw "Test hermes --help failed." }

    Remove-IfExists $TestVenv
    Write-Ok "Offline simulation passed."

    if (-not $NoZip) {
        Write-Step "Creating ZIP"
        $ZipPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "HermesOfflineBundle_v0.14.0.zip"
        if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }

        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if ($tar) {
            & tar.exe -a -cf $ZipPath -C $BundleRoot .
            if ($LASTEXITCODE -ne 0) { throw "tar zip creation failed." }
        } else {
            Compress-Archive -Path "$BundleRoot\*" -DestinationPath $ZipPath -Force
        }
        Write-Ok "ZIP created: $ZipPath"
    }

    $Elapsed = New-TimeSpan -Start $StartTime -End (Get-Date)
    Write-Step "DONE"
    Write-Host "Bundle root : $BundleRoot"
    if (-not $NoZip) { Write-Host "ZIP         : $(Join-Path ([Environment]::GetFolderPath("Desktop")) "HermesOfflineBundle_v0.14.0.zip")" }
    Write-Host "Elapsed     : $($Elapsed.ToString())"
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
