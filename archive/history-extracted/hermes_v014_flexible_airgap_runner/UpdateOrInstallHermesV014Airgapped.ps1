<# 
.SYNOPSIS
  Flexible air-gapped Hermes v0.14.0 installer/updater for Windows native environments.

.DESCRIPTION
  One script for BOTH scenarios:
    - Fresh install if Hermes is not installed yet
    - Update existing Hermes v0.13.x/v0.14.x installation to the bundle contents

  Input is a prepared HermesOfflineBundle_v0.14.0.zip or an already-extracted bundle directory.
  The bundle must contain:
    - hermes-agent\
    - wheelhouse\
    - requirements-hermes-win.txt  (recommended)
    - tools\python-3.11.9-amd64.exe (recommended for fresh install)
    - optional tools\ripgrep, tools\ffmpeg

.EXAMPLES
  powershell -ExecutionPolicy Bypass -File .\UpdateOrInstallHermesV014Airgapped.ps1 -BundleZip "C:\Temp\HermesOfflineBundle_v0.14.0.zip"

  powershell -ExecutionPolicy Bypass -File .\UpdateOrInstallHermesV014Airgapped.ps1 -BundleZip "C:\Temp\HermesOfflineBundle_v0.14.0.zip" -Mode Update

  powershell -ExecutionPolicy Bypass -File .\UpdateOrInstallHermesV014Airgapped.ps1 -BundleZip "C:\Temp\HermesOfflineBundle_v0.14.0.zip" -Mode Install -CleanVenv

.NOTES
  - Run from PowerShell.
  - The .bat wrapper can also be run from CMD.
  - Does not need internet access.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$BundleZip,

    [ValidateSet("Auto","Install","Update","Reinstall")]
    [string]$Mode = "Auto",

    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "hermes"),

    [string]$ExtractRoot = "C:\Tools\HermesOfflineBundle_v0.14.0",

    [switch]$CleanVenv,

    [switch]$SkipConfigMigrate,

    [string]$GitBashPath = "",

    [switch]$KeepExtracted
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn2([string]$Message) {
    Write-Warning $Message
}

function Add-UserPath([string]$PathToAdd) {
    if (-not $PathToAdd -or -not (Test-Path $PathToAdd)) { return }
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $current) { $current = "" }
    $parts = $current -split ";" | Where-Object { $_ -ne "" }
    if ($parts -notcontains $PathToAdd) {
        [Environment]::SetEnvironmentVariable("Path", "$PathToAdd;$current", "User")
        Write-Ok "Added to User PATH: $PathToAdd"
    } else {
        Write-Ok "Already in User PATH: $PathToAdd"
    }
    if (($env:Path -split ";") -notcontains $PathToAdd) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Find-FirstFile([string]$Root, [string]$Filter) {
    if (-not (Test-Path $Root)) { return $null }
    $item = Get-ChildItem $Root -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($item) { return $item.FullName }
    return $null
}

function Resolve-Bundle([string]$BundleInput, [string]$ExtractRoot) {
    Write-Step "Resolving bundle"

    if (-not (Test-Path $BundleInput)) {
        throw "Bundle path not found: $BundleInput"
    }

    $resolved = (Resolve-Path $BundleInput).Path
    $bundleRootCandidate = $resolved

    if ((Get-Item $resolved).PSIsContainer) {
        Write-Ok "Bundle input is already a directory: $resolved"
    } else {
        if (-not ($resolved.ToLower().EndsWith(".zip"))) {
            throw "Bundle input must be a .zip file or an extracted bundle directory."
        }

        if (Test-Path $ExtractRoot) {
            Write-Warn2 "Extract root already exists. Removing: $ExtractRoot"
            Remove-Item -Recurse -Force $ExtractRoot
        }

        New-Item -ItemType Directory -Force $ExtractRoot | Out-Null
        Write-Host "Extracting bundle:"
        Write-Host "  From: $resolved"
        Write-Host "  To  : $ExtractRoot"
        Expand-Archive -Path $resolved -DestinationPath $ExtractRoot -Force
        $bundleRootCandidate = $ExtractRoot
    }

    # Bundle may be rooted directly or inside a single nested folder.
    $candidates = @()
    $candidates += $bundleRootCandidate
    $candidates += (Get-ChildItem $bundleRootCandidate -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

    foreach ($c in $candidates) {
        if ((Test-Path (Join-Path $c "hermes-agent")) -and (Test-Path (Join-Path $c "wheelhouse"))) {
            Write-Ok "Resolved bundle root: $c"
            return $c
        }
    }

    throw "Could not find a valid bundle root. Expected hermes-agent\ and wheelhouse\ under $bundleRootCandidate or one nested directory."
}

function Ensure-Python311([string]$InstallRoot, [string]$BundleRoot) {
    Write-Step "Ensuring isolated Python 3.11"

    $pythonDir = Join-Path $InstallRoot "python311"
    $pythonExe = Join-Path $pythonDir "python.exe"

    if (Test-Path $pythonExe) {
        & $pythonExe --version
        Write-Ok "Using existing isolated Python: $pythonExe"
        return $pythonExe
    }

    $installer = Find-FirstFile (Join-Path $BundleRoot "tools") "python-3.11.*-amd64.exe"
    if (-not $installer) {
        # Fallback: use system py launcher only if available.
        $pyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($pyLauncher) {
            Write-Warn2 "Bundled Python installer not found. Trying system py -3.11."
            & py -3.11 --version
            if ($LASTEXITCODE -eq 0) {
                return "py -3.11"
            }
        }
        throw "No isolated Python found and no bundled Python 3.11 installer found under tools\. Include python-3.11.9-amd64.exe in the bundle."
    }

    New-Item -ItemType Directory -Force $InstallRoot | Out-Null
    Write-Host "Installing isolated Python 3.11:"
    Write-Host "  Installer: $installer"
    Write-Host "  Target   : $pythonDir"

    $args = "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 Include_test=0 TargetDir=`"$pythonDir`""
    Start-Process -FilePath $installer -ArgumentList $args -Wait

    if (-not (Test-Path $pythonExe)) {
        throw "Python installation finished but python.exe was not found: $pythonExe"
    }

    & $pythonExe --version
    Write-Ok "Installed isolated Python: $pythonExe"
    return $pythonExe
}

function Find-GitBash([string]$Provided) {
    Write-Step "Finding Git Bash"

    $candidates = @()
    if ($Provided) { $candidates += $Provided }

    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and ($cmd.Source -notmatch "\\Windows\\System32\\bash.exe$")) {
        $candidates += $cmd.Source
    }

    $candidates += @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
    )

    foreach ($c in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $c) {
            [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $c, "User")
            $env:HERMES_GIT_BASH_PATH = $c
            & $c --version | Select-Object -First 1
            Write-Ok "HERMES_GIT_BASH_PATH = $c"
            return $c
        }
    }

    Write-Warn2 "Git Bash was not found. Hermes may still run, but shell tools may fail. Install Git for Windows or pass -GitBashPath."
    return $null
}

function Ensure-ToolPaths([string]$BundleRoot) {
    Write-Step "Adding optional bundled tools to PATH"

    $rg = Find-FirstFile (Join-Path $BundleRoot "tools") "rg.exe"
    if ($rg) {
        Add-UserPath (Split-Path $rg -Parent)
        & $rg --version | Select-Object -First 1
    } else {
        Write-Warn2 "rg.exe not found in bundle tools. Skipping ripgrep PATH."
    }

    $ffmpeg = Find-FirstFile (Join-Path $BundleRoot "tools") "ffmpeg.exe"
    if ($ffmpeg) {
        Add-UserPath (Split-Path $ffmpeg -Parent)
        & $ffmpeg -version | Select-Object -First 1
    } else {
        Write-Warn2 "ffmpeg.exe not found in bundle tools. Skipping FFmpeg PATH."
    }

    $ffprobe = Find-FirstFile (Join-Path $BundleRoot "tools") "ffprobe.exe"
    if ($ffprobe) {
        Add-UserPath (Split-Path $ffprobe -Parent)
        & $ffprobe -version | Select-Object -First 1
    }
}

function Ensure-HermesDirs([string]$InstallRoot) {
    Write-Step "Ensuring Hermes home directories"

    foreach ($d in @(
        $InstallRoot,
        (Join-Path $InstallRoot "logs"),
        (Join-Path $InstallRoot "sessions"),
        (Join-Path $InstallRoot "skills"),
        (Join-Path $InstallRoot "memories"),
        (Join-Path $InstallRoot "cron")
    )) {
        New-Item -ItemType Directory -Force $d | Out-Null
    }

    if (-not (Test-Path (Join-Path $InstallRoot ".env"))) {
        New-Item -ItemType File -Force (Join-Path $InstallRoot ".env") | Out-Null
    }

    [Environment]::SetEnvironmentVariable("HERMES_HOME", $InstallRoot, "User")
    $env:HERMES_HOME = $InstallRoot

    [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
    [Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
    $env:PYTHONUTF8 = "1"
    $env:PYTHONIOENCODING = "utf-8"

    Write-Ok "HERMES_HOME = $InstallRoot"
}

function Backup-Hermes([string]$InstallRoot) {
    if (-not (Test-Path $InstallRoot)) {
        Write-Ok "No existing Hermes home to back up."
        return $null
    }

    Write-Step "Backing up existing Hermes home"
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backup = "$InstallRoot" + "_backup_before_v014_" + $stamp

    Copy-Item $InstallRoot $backup -Recurse -Force
    Write-Ok "Backup created: $backup"
    return $backup
}

function Install-Or-Update-Source([string]$BundleRoot, [string]$InstallRoot, [string]$Mode, [switch]$CleanVenv) {
    Write-Step "Installing/updating Hermes source"

    $source = Join-Path $BundleRoot "hermes-agent"
    if (-not (Test-Path (Join-Path $source "pyproject.toml"))) {
        throw "Bundle hermes-agent source is invalid. pyproject.toml not found under: $source"
    }

    $installDir = Join-Path $InstallRoot "hermes-agent"
    $exists = Test-Path $installDir

    if ($Mode -eq "Auto") {
        if ($exists) { $Mode = "Update" } else { $Mode = "Install" }
        Write-Ok "Auto mode resolved to: $Mode"
    }

    if ($Mode -eq "Install" -and $exists) {
        Write-Warn2 "Install mode requested but Hermes source already exists. Existing source will be renamed."
    }

    if ($Mode -eq "Update" -and -not $exists) {
        Write-Warn2 "Update mode requested but Hermes source does not exist. Switching to Install."
        $Mode = "Install"
    }

    $oldSourceBackup = $null
    $preserveVenvPath = $null

    if ($exists) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $oldSourceBackup = Join-Path $InstallRoot ("hermes-agent_source_backup_" + $stamp)
        Rename-Item $installDir $oldSourceBackup
        Write-Ok "Old source moved to: $oldSourceBackup"

        if (-not $CleanVenv) {
            $oldVenv = Join-Path $oldSourceBackup "venv"
            if (Test-Path $oldVenv) {
                $preserveVenvPath = $oldVenv
                Write-Ok "Existing venv will be reused: $oldVenv"
            }
        } else {
            Write-Warn2 "CleanVenv requested. Existing venv will not be reused."
        }
    }

    Copy-Item $source $installDir -Recurse -Force
    Write-Ok "New source installed: $installDir"

    if ($preserveVenvPath) {
        Move-Item $preserveVenvPath (Join-Path $installDir "venv") -Force
        Write-Ok "Existing venv moved into new source tree."
    }

    return $installDir
}

function Ensure-VenvAndInstall([string]$InstallDir, [string]$PythonExe, [string]$BundleRoot) {
    Write-Step "Installing Hermes Python packages from offline wheelhouse"

    $wheelhouse = Join-Path $BundleRoot "wheelhouse"
    if (-not (Test-Path $wheelhouse)) {
        throw "Wheelhouse not found: $wheelhouse"
    }

    $venvDir = Join-Path $InstallDir "venv"
    $venvPy = Join-Path $venvDir "Scripts\python.exe"

    if (-not (Test-Path $venvPy)) {
        Write-Host "Creating new venv: $venvDir"
        if ($PythonExe -eq "py -3.11") {
            & py -3.11 -m venv $venvDir
        } else {
            & $PythonExe -m venv $venvDir
        }
    } else {
        Write-Ok "Reusing existing venv: $venvDir"
    }

    if (-not (Test-Path $venvPy)) {
        throw "Venv python was not created/found: $venvPy"
    }

    & $venvPy --version

    Write-Host "Upgrading pip/setuptools/wheel from wheelhouse..."
    & $venvPy -m pip install --no-index --find-links $wheelhouse --upgrade pip setuptools wheel
    if ($LASTEXITCODE -ne 0) { throw "pip/setuptools/wheel offline install failed." }

    Write-Host "Installing Hermes editable package with extras: [web,mcp,cron,cli]"
    Push-Location $InstallDir
    try {
        & $venvPy -m pip install --no-index --find-links $wheelhouse -e ".[web,mcp,cron,cli]"
        if ($LASTEXITCODE -ne 0) { throw "Hermes offline pip install failed." }
    } finally {
        Pop-Location
    }

    $scripts = Join-Path $venvDir "Scripts"
    Add-UserPath $scripts

    # Python aliases for Hermes/Git Bash tools that call python3.
    $python = Join-Path $scripts "python.exe"
    $python3 = Join-Path $scripts "python3.exe"
    if (Test-Path $python) {
        Copy-Item $python $python3 -Force
        Write-Ok "Created python3.exe alias in venv Scripts."
    }

    # Optional: add isolated Python itself if present.
    $python311 = Join-Path $InstallRoot "python311"
    if (Test-Path $python311) {
        Add-UserPath $python311
        Add-UserPath (Join-Path $python311 "Scripts")
    }

    return (Join-Path $scripts "hermes.exe")
}

function Try-HermesPostInstall([string]$HermesExe, [switch]$SkipConfigMigrate) {
    Write-Step "Hermes post-install checks"

    if (-not (Test-Path $HermesExe)) {
        throw "hermes.exe not found: $HermesExe"
    }

    Write-Host "Hermes executable:"
    Write-Host "  $HermesExe"

    & $HermesExe --version
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "hermes --version returned non-zero. Continuing."
    }

    if (-not $SkipConfigMigrate) {
        Write-Host "Running hermes config check..."
        & $HermesExe config check
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "hermes config check returned non-zero. Trying hermes config migrate..."
            & $HermesExe config migrate
            if ($LASTEXITCODE -ne 0) {
                Write-Warn2 "hermes config migrate returned non-zero. Continuing."
            }
        }
    }

    Write-Host "Running hermes doctor..."
    & $HermesExe doctor
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "hermes doctor returned non-zero. This can be normal if optional tools are missing."
    }
}

function Write-StartScript([string]$InstallRoot) {
    Write-Step "Writing helper start script"

    $startScript = Join-Path $InstallRoot "start-hermes.ps1"
    $content = @'
$env:HERMES_HOME = "$env:LOCALAPPDATA\hermes"
$env:HERMES_GIT_BASH_PATH = [Environment]::GetEnvironmentVariable("HERMES_GIT_BASH_PATH", "User")
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:HERMES_STREAM_READ_TIMEOUT = "1800"

chcp 65001 | Out-Null

hermes chat
'@
    Set-Content -Path $startScript -Value $content -Encoding UTF8
    Write-Ok "Start script written: $startScript"
}

# Main
$logDir = Join-Path $InstallRoot "logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$logPath = Join-Path $logDir ("install_or_update_v014_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Warn2 "Could not start transcript: $($_.Exception.Message)"
}

try {
    Write-Host "Hermes v0.14.0 flexible air-gapped installer/updater" -ForegroundColor White
    Write-Host "Mode       : $Mode"
    Write-Host "Bundle     : $BundleZip"
    Write-Host "InstallRoot: $InstallRoot"
    Write-Host "Log        : $logPath"

    $bundleRoot = Resolve-Bundle -BundleInput $BundleZip -ExtractRoot $ExtractRoot

    Ensure-HermesDirs -InstallRoot $InstallRoot
    $pythonExe = Ensure-Python311 -InstallRoot $InstallRoot -BundleRoot $bundleRoot
    $gitBash = Find-GitBash -Provided $GitBashPath
    Ensure-ToolPaths -BundleRoot $bundleRoot

    $existingInstall = Test-Path (Join-Path $InstallRoot "hermes-agent")
    if ($existingInstall) {
        Backup-Hermes -InstallRoot $InstallRoot | Out-Null
    } else {
        Write-Ok "No existing Hermes source found. Fresh install path will be used."
    }

    $installDir = Install-Or-Update-Source -BundleRoot $bundleRoot -InstallRoot $InstallRoot -Mode $Mode -CleanVenv:$CleanVenv

    $hermesExe = Ensure-VenvAndInstall -InstallDir $installDir -PythonExe $pythonExe -BundleRoot $bundleRoot

    Try-HermesPostInstall -HermesExe $hermesExe -SkipConfigMigrate:$SkipConfigMigrate

    Write-StartScript -InstallRoot $InstallRoot

    Write-Step "Completed"
    Write-Host "Hermes was installed/updated successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1) Open a NEW PowerShell window."
    Write-Host "  2) Run: hermes --version"
    Write-Host "  3) Run: hermes model"
    Write-Host "  4) Select: Custom endpoint  (not Custom API)"
    Write-Host "  5) Configure your base URL, API key, and model."
    Write-Host "  6) Run: hermes chat"
    Write-Host ""
    Write-Host "If something fails, check log:"
    Write-Host "  $logPath"
}
catch {
    Write-Host ""
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check log: $logPath" -ForegroundColor Yellow
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
