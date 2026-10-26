<#
UpdateHermesV014Airgapped.ps1
Air-gapped updater for Hermes Agent v0.14.0 from an already prepared HermesOfflineBundle_v0.14.0.zip.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\UpdateHermesV014Airgapped.ps1 -ZipPath "C:\Path\HermesOfflineBundle_v0.14.0.zip"

Optional:
  -ExtractRoot "C:\Tools\HermesOfflineBundle_v0.14.0_extracted"
  -HermesHome "$env:LOCALAPPDATA\hermes"
  -CleanVenv
  -Extras "web,mcp,cron,cli"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath,

    [string]$ExtractRoot = "C:\Tools\HermesOfflineBundle_v0.14.0_extracted",

    [string]$HermesHome = "$env:LOCALAPPDATA\hermes",

    [string]$Extras = "web,mcp,cron,cli",

    [string]$GitBashPath = "C:\Program Files\Git\bin\bash.exe",

    [switch]$CleanVenv
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Fail {
    param([string]$Message)
    throw "[FAIL] $Message"
}

function Add-ToUserPathFront {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return }
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($current)) { $current = "" }
    $parts = $current -split ';' | Where-Object { $_ -and $_.Trim() -ne "" }
    $exists = $false
    foreach ($p in $parts) {
        if ($p.TrimEnd('\') -ieq $Dir.TrimEnd('\')) { $exists = $true; break }
    }
    if (-not $exists) {
        [Environment]::SetEnvironmentVariable("Path", "$Dir;$current", "User")
    }
    $env:Path = "$Dir;$env:Path"
}

function Resolve-BundleRoot {
    param([string]$Root)

    if ((Test-Path (Join-Path $Root "hermes-agent\pyproject.toml")) -and (Test-Path (Join-Path $Root "wheelhouse"))) {
        return $Root
    }

    $candidates = Get-ChildItem $Root -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
        (Test-Path (Join-Path $_.FullName "hermes-agent\pyproject.toml")) -and
        (Test-Path (Join-Path $_.FullName "wheelhouse"))
    }

    if ($candidates.Count -gt 0) {
        return $candidates[0].FullName
    }

    Fail "Could not find a valid bundle root. Expected hermes-agent\pyproject.toml and wheelhouse inside extracted ZIP."
}

function Find-Python311 {
    param([string]$HermesHome)

    $candidates = @(
        (Join-Path $HermesHome "python311\python.exe"),
        (Join-Path $HermesHome "hermes-agent\venv\Scripts\python.exe")
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) { return "py -3.11" }

    Fail "Python 3.11 could not be found. Expected $HermesHome\python311\python.exe or an existing Hermes venv."
}

function Invoke-CmdChecked {
    param(
        [string]$Exe,
        [string[]]$Args,
        [string]$WorkingDirectory = $null,
        [switch]$AllowNonZero
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }
    try {
        & $Exe @Args
        $code = $LASTEXITCODE
        if ((-not $AllowNonZero) -and ($code -ne 0)) {
            Fail "Command failed with exit code $code: $Exe $($Args -join ' ')"
        }
        return $code
    }
    finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}

try {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Force $HermesHome | Out-Null
    $LogPath = Join-Path $HermesHome "update_v014_$timestamp.log"
    Start-Transcript -Path $LogPath -Force | Out-Null

    Write-Step "Starting Hermes v0.14.0 air-gapped update"
    Write-Host "ZipPath     : $ZipPath"
    Write-Host "ExtractRoot : $ExtractRoot"
    Write-Host "HermesHome  : $HermesHome"
    Write-Host "Extras      : $Extras"
    Write-Host "CleanVenv   : $CleanVenv"
    Write-Host "LogPath     : $LogPath"

    if (-not (Test-Path $ZipPath)) {
        Fail "ZIP file not found: $ZipPath"
    }

    Write-Step "Extracting bundle"
    if (Test-Path $ExtractRoot) {
        Remove-Item -Recurse -Force $ExtractRoot
    }
    New-Item -ItemType Directory -Force $ExtractRoot | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractRoot -Force

    $BundleRoot = Resolve-BundleRoot -Root $ExtractRoot
    $BundleSource = Join-Path $BundleRoot "hermes-agent"
    $Wheelhouse = Join-Path $BundleRoot "wheelhouse"
    $Requirements = Join-Path $BundleRoot "requirements-hermes-win.txt"

    Write-Ok "Bundle root resolved: $BundleRoot"
    if (-not (Test-Path (Join-Path $BundleSource "pyproject.toml"))) { Fail "pyproject.toml not found in $BundleSource" }
    if (-not (Test-Path $Wheelhouse)) { Fail "wheelhouse not found: $Wheelhouse" }

    $wheelCount = (Get-ChildItem $Wheelhouse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($wheelCount -lt 1) { Fail "wheelhouse is empty: $Wheelhouse" }
    Write-Ok "Wheelhouse contains $wheelCount files."

    Write-Step "Backing up existing Hermes home"
    if (-not (Test-Path $HermesHome)) {
        Fail "HermesHome does not exist: $HermesHome"
    }
    $BackupRoot = Join-Path (Split-Path $HermesHome -Parent) "hermes_backup_before_v014_$timestamp"
    Copy-Item $HermesHome $BackupRoot -Recurse -Force
    Write-Ok "Full backup created: $BackupRoot"

    $InstallDir = Join-Path $HermesHome "hermes-agent"
    if (-not (Test-Path $InstallDir)) {
        Fail "Existing Hermes install not found: $InstallDir"
    }

    $OldSourceBackup = Join-Path $HermesHome "hermes-agent_source_backup_before_v014_$timestamp"

    Write-Step "Replacing Hermes source with v0.14.0 source"
    Rename-Item $InstallDir $OldSourceBackup
    Copy-Item $BundleSource $InstallDir -Recurse -Force
    Write-Ok "Old source backup: $OldSourceBackup"

    $OldVenv = Join-Path $OldSourceBackup "venv"
    $NewVenv = Join-Path $InstallDir "venv"

    if (($CleanVenv) -or (-not (Test-Path $OldVenv))) {
        Write-Step "Creating clean venv"
        $BasePython = Find-Python311 -HermesHome $HermesHome
        Write-Host "Base Python: $BasePython"

        if ($BasePython -like "py -3.11") {
            & py -3.11 -m venv $NewVenv
            if ($LASTEXITCODE -ne 0) { Fail "Failed to create venv using py -3.11" }
        } else {
            & $BasePython -m venv $NewVenv
            if ($LASTEXITCODE -ne 0) { Fail "Failed to create venv using $BasePython" }
        }
    } else {
        Write-Step "Preserving existing venv"
        Move-Item $OldVenv $NewVenv
        Write-Ok "Existing venv moved into new source tree."
    }

    $VenvPy = Join-Path $NewVenv "Scripts\python.exe"
    $HermesExe = Join-Path $NewVenv "Scripts\hermes.exe"
    if (-not (Test-Path $VenvPy)) { Fail "Venv Python not found: $VenvPy" }

    Write-Step "Venv Python version"
    & $VenvPy --version

    Write-Step "Installing/updating pip, setuptools, wheel from offline wheelhouse"
    & $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
    if ($LASTEXITCODE -ne 0) { Fail "pip/setuptools/wheel update failed." }

    Write-Step "Installing Hermes v0.14.0 from source using offline wheelhouse"
    Push-Location $InstallDir
    try {
        $editableSpec = ".[${Extras}]"
        & $VenvPy -m pip install --no-index --find-links $Wheelhouse -e $editableSpec
        if ($LASTEXITCODE -ne 0) { Fail "Hermes editable install failed for extras: $Extras" }
    }
    finally {
        Pop-Location
    }

    Write-Step "Creating python3.exe alias inside Hermes venv"
    $ScriptsDir = Join-Path $NewVenv "Scripts"
    Copy-Item (Join-Path $ScriptsDir "python.exe") (Join-Path $ScriptsDir "python3.exe") -Force
    & (Join-Path $ScriptsDir "python3.exe") --version

    Write-Step "Updating user environment variables"
    [Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
    $env:HERMES_HOME = $HermesHome

    [Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
    [Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
    $env:PYTHONUTF8 = "1"
    $env:PYTHONIOENCODING = "utf-8"

    Add-ToUserPathFront -Dir $ScriptsDir
    Write-Ok "Added Hermes venv Scripts to User PATH: $ScriptsDir"

    if (-not (Test-Path $GitBashPath)) {
        Write-Warn2 "Default Git Bash path not found: $GitBashPath"
        $gitCandidates = @(
            "C:\Program Files\Git\bin\bash.exe",
            "C:\Program Files\Git\usr\bin\bash.exe",
            "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
            "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
        ) | Where-Object { Test-Path $_ }
        if ($gitCandidates.Count -gt 0) {
            $GitBashPath = $gitCandidates[0]
        } else {
            Write-Warn2 "No Git Bash found. Set HERMES_GIT_BASH_PATH manually after update."
            $GitBashPath = $null
        }
    }

    if ($GitBashPath) {
        [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $GitBashPath, "User")
        $env:HERMES_GIT_BASH_PATH = $GitBashPath
        Write-Ok "HERMES_GIT_BASH_PATH set to: $GitBashPath"
        & $GitBashPath --version | Select-Object -First 1
    }

    Write-Step "Checking Hermes executable"
    if (-not (Test-Path $HermesExe)) {
        Fail "hermes.exe not found after install: $HermesExe"
    }

    & $HermesExe --version
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "hermes --version returned non-zero. Trying 'hermes version'."
        & $HermesExe version
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "Hermes version check returned non-zero, but installation completed."
        }
    }

    Write-Step "Running optional config checks"
    & $HermesExe config check
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "hermes config check returned non-zero. Trying config migrate."
        & $HermesExe config migrate
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "hermes config migrate returned non-zero. You can run it manually later."
        }
    }

    Write-Step "Final doctor check"
    & $HermesExe doctor
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "hermes doctor returned non-zero. Optional dependencies may be missing; update still completed."
    }

    Write-Step "Update complete"
    Write-Host "Hermes home       : $HermesHome"
    Write-Host "New install       : $InstallDir"
    Write-Host "Full backup       : $BackupRoot"
    Write-Host "Old source backup : $OldSourceBackup"
    Write-Host "Log               : $LogPath"
    Write-Host ""
    Write-Host "Open a NEW PowerShell window, then run:" -ForegroundColor Green
    Write-Host "  hermes --version" -ForegroundColor Green
    Write-Host "  hermes model" -ForegroundColor Green
    Write-Host "  hermes chat" -ForegroundColor Green
    Write-Host ""
    Write-Host "Reminder: for your company gateway, choose 'Custom endpoint', not 'Custom API'." -ForegroundColor Yellow

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Update failed. Check the log in HermesHome if transcript was started." -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
