<#
Hermes Agent air-gapped flexible installer/updater
- Works for fresh install and update.
- Designed to avoid Windows MAX_PATH failures during backup by using minimal state backup and renaming/moving venv instead of copying it.

Usage from CMD:
  InstallOrUpdateHermesAirgapped.bat "C:\Path\To\HermesAirgapBundle_<tag>.zip"

Usage from PowerShell:
  powershell -ExecutionPolicy Bypass -File .\InstallOrUpdateHermesAirgapped.ps1 -BundleZip "C:\Path\To\HermesAirgapBundle_<tag>.zip"

Options:
  -Mode Auto|Install|Update
  -CleanVenv     Recreate venv instead of preserving existing one
  -SkipDoctor    Skip hermes doctor/check commands
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$BundleZip,

    [ValidateSet('Auto','Install','Update')]
    [string]$Mode = 'Auto',

    [switch]$CleanVenv,

    [switch]$SkipDoctor,

    [string]$ExtractRoot = 'C:\Tools\HermesAirgapBundle_Extracted',

    [string]$HermesHome = "$env:LOCALAPPDATA\hermes"
)

$ErrorActionPreference = 'Stop'

function Section($msg) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Die($msg) { Write-Host "[FAILED] $msg" -ForegroundColor Red; throw $msg }

function Run-RoboCopyDir {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @()
    )

    if (-not (Test-Path $Source)) {
        Warn "Source directory not found, skipping: $Source"
        return
    }

    New-Item -ItemType Directory -Force $Destination | Out-Null

    $args = @($Source, $Destination, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1')
    if ($ExcludeDirs.Count -gt 0) { $args += '/XD'; $args += $ExcludeDirs }
    if ($ExcludeFiles.Count -gt 0) { $args += '/XF'; $args += $ExcludeFiles }

    & robocopy @args | Out-Null
    $code = $LASTEXITCODE
    # Robocopy exit codes 0..7 are success/warnings. 8+ means failure.
    if ($code -ge 8) {
        Die "robocopy failed with exit code $code. Source=$Source Destination=$Destination"
    }
}

function Add-UserPathFirst {
    param([Parameter(Mandatory=$true)][string]$PathToAdd)
    if (-not (Test-Path $PathToAdd)) { return }
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { $current = '' }
    if ($current -notlike "*$PathToAdd*") {
        [Environment]::SetEnvironmentVariable('Path', "$PathToAdd;$current", 'User')
    }
    $env:Path = "$PathToAdd;$env:Path"
}

function Resolve-GitBash {
    param([string]$BundleRoot)

    $existing = $env:HERMES_GIT_BASH_PATH
    if ($existing -and (Test-Path $existing)) { return $existing }

    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe',
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }

    # Optional PortableGit extraction if the bundle includes it.
    $portable = Get-ChildItem "$BundleRoot\tools" -Filter 'PortableGit-*-64-bit.7z.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($portable) {
        $gitDir = "$HermesHome\git"
        New-Item -ItemType Directory -Force $gitDir | Out-Null
        Info "Extracting PortableGit to $gitDir"
        Start-Process $portable.FullName -ArgumentList "-o`"$gitDir`"", '-y' -Wait
        $portableBash = "$gitDir\bin\bash.exe"
        if (Test-Path $portableBash) { return $portableBash }
    }

    return $null
}

function Ensure-Python311 {
    param([string]$BundleRoot)

    $pythonDir = "$HermesHome\python311"
    $pythonExe = "$pythonDir\python.exe"

    if (Test-Path $pythonExe) {
        Info "Using existing isolated Python: $pythonExe"
        $pyVersion = (& $pythonExe --version 2>&1) -join ' '
        Info "Python version: $pyVersion"
        return $pythonExe
    }

    $installer = Get-ChildItem "$BundleRoot\tools" -Filter 'python-3.11*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $installer) {
        # Fall back to system python only if it is 3.11.
        $sysPy = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
        if ($sysPy) {
            $ver = & $sysPy -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
            if ($ver -eq '3.11') {
                Warn "Bundle Python installer not found; using system Python 3.11: $sysPy"
                return $sysPy
            }
        }
        Die "Python 3.11 installer not found in bundle tools, and no suitable Python 3.11 found."
    }

    Section "Installing isolated Python 3.11"
    New-Item -ItemType Directory -Force $HermesHome | Out-Null
    Start-Process $installer.FullName -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$pythonDir`"" -Wait

    if (-not (Test-Path $pythonExe)) { Die "Python install failed: $pythonExe not found." }
    $pyVersion = (& $pythonExe --version 2>&1) -join ' '
    Info "Python version: $pyVersion"
    return $pythonExe
}

function Backup-HermesState-Minimal {
    param([string]$BackupRoot)

    if (-not (Test-Path $HermesHome)) {
        Warn "HermesHome does not exist yet; skipping backup."
        return
    }

    Section "Backing up current Hermes state (safe/minimal)"
    Info "Backup root: $BackupRoot"
    New-Item -ItemType Directory -Force $BackupRoot | Out-Null

    # Copy common user state/config files. Avoid full venv backup to prevent MAX_PATH issues.
    $files = @('.env', 'config.yaml', 'config.yml', 'settings.json')
    foreach ($f in $files) {
        $src = Join-Path $HermesHome $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $BackupRoot $f) -Force }
    }

    $dirs = @('sessions', 'skills', 'memories', 'memory', 'cron', 'logs', 'profiles', 'plugins', 'hooks')
    foreach ($d in $dirs) {
        $src = Join-Path $HermesHome $d
        if (Test-Path $src) {
            Info "Backing up $d"
            Run-RoboCopyDir -Source $src -Destination (Join-Path $BackupRoot $d)
        }
    }

    # Record inventory, but do not copy venv fully.
    $inventory = Join-Path $BackupRoot 'backup_inventory.txt'
    @(
        "Backup time: $(Get-Date -Format o)",
        "HermesHome: $HermesHome",
        "Note: venv is intentionally not copied to avoid Windows path length problems. It can be rebuilt from wheelhouse.",
        "Existing hermes-agent path: $HermesHome\hermes-agent"
    ) | Set-Content $inventory -Encoding UTF8
}

function Extract-Bundle {
    param([string]$Zip, [string]$OutDir)

    if (-not (Test-Path $Zip)) { Die "Bundle zip not found: $Zip" }

    Section "Extracting bundle"
    Info "Bundle zip: $Zip"
    Info "Extract dir:  $OutDir"

    if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    Expand-Archive $Zip -DestinationPath $OutDir -Force

    # If zip contains a single top-level folder, use that. Otherwise OutDir itself is bundle root.
    $required = @('hermes-agent', 'wheelhouse')
    $hasRoot = $true
    foreach ($r in $required) { if (-not (Test-Path (Join-Path $OutDir $r))) { $hasRoot = $false } }
    if ($hasRoot) { return $OutDir }

    $dirs = Get-ChildItem $OutDir -Directory
    foreach ($d in $dirs) {
        $ok = $true
        foreach ($r in $required) { if (-not (Test-Path (Join-Path $d.FullName $r))) { $ok = $false } }
        if ($ok) { return $d.FullName }
    }

    Die "Extracted bundle does not contain hermes-agent and wheelhouse."
}

# Start transcript
try {
    New-Item -ItemType Directory -Force $HermesHome | Out-Null
    $log = Join-Path $HermesHome ("install_or_update_airgap_v2_{0}.log" -f (Get-Date -Format yyyyMMdd_HHmmss))
    Start-Transcript -Path $log -Force | Out-Null
} catch {
    Warn "Could not start transcript: $($_.Exception.Message)"
}

try {
    Section "Hermes air-gapped install/update"
    Info "BundleZip: $BundleZip"
    Info "HermesHome: $HermesHome"
    Info "Mode: $Mode"
    Info "CleanVenv: $CleanVenv"

    $bundleRoot = Extract-Bundle -Zip $BundleZip -OutDir $ExtractRoot
    Info "Resolved bundle root: $bundleRoot"

    $sourceRoot = Join-Path $bundleRoot 'hermes-agent'
    $wheelhouse = Join-Path $bundleRoot 'wheelhouse'
    if (-not (Test-Path $sourceRoot)) { Die "Missing hermes-agent in bundle: $sourceRoot" }
    if (-not (Test-Path $wheelhouse)) { Die "Missing wheelhouse in bundle: $wheelhouse" }

    $installDir = Join-Path $HermesHome 'hermes-agent'
    $exists = Test-Path $installDir

    if ($Mode -eq 'Auto') {
        if ($exists) { $effectiveMode = 'Update' } else { $effectiveMode = 'Install' }
    } else {
        $effectiveMode = $Mode
    }
    Info "Effective mode: $effectiveMode"

    $timestamp = Get-Date -Format yyyyMMdd_HHmmss
    $backupRoot = "$env:LOCALAPPDATA\hermes_backup_before_airgap_$timestamp"

    if ($exists) {
        Backup-HermesState-Minimal -BackupRoot $backupRoot
    }

    $pythonExe = Ensure-Python311 -BundleRoot $bundleRoot

    Section "Installing/updating Hermes source"
    $oldSource = $null
    $preserveVenv = $false
    $oldVenv = $null

    if ($exists) {
        $oldSource = "$HermesHome\hermes-agent_source_backup_$timestamp"
        Info "Renaming existing source to: $oldSource"
        Rename-Item $installDir $oldSource
        $oldVenv = Join-Path $oldSource 'venv'
        if ((Test-Path $oldVenv) -and (-not $CleanVenv)) { $preserveVenv = $true }
    }

    Info "Copying new Hermes source to: $installDir"
    Run-RoboCopyDir -Source $sourceRoot -Destination $installDir -ExcludeDirs @('.git','__pycache__','.pytest_cache','.mypy_cache','.ruff_cache','node_modules')

    if ($preserveVenv) {
        Info "Preserving existing venv by moving it into new source."
        Move-Item $oldVenv (Join-Path $installDir 'venv') -Force
    }

    $venvDir = Join-Path $installDir 'venv'
    if ((-not (Test-Path (Join-Path $venvDir 'Scripts\python.exe'))) -or $CleanVenv) {
        if (Test-Path $venvDir) { Remove-Item -Recurse -Force $venvDir -ErrorAction SilentlyContinue }
        Section "Creating clean venv"
        & $pythonExe -m venv $venvDir
    }

    $venvPy = Join-Path $venvDir 'Scripts\python.exe'
    if (-not (Test-Path $venvPy)) { Die "Venv Python missing: $venvPy" }
    & $venvPy --version

    Section "Installing Python dependencies from local wheelhouse"
    & $venvPy -m pip install --no-index --find-links $wheelhouse --upgrade pip setuptools wheel
    if ($LASTEXITCODE -ne 0) { Die "pip/setuptools/wheel upgrade failed." }

    Push-Location $installDir
    try {
        & $venvPy -m pip install --no-index --find-links $wheelhouse -e '.[web,mcp,cron,cli]'
        if ($LASTEXITCODE -ne 0) { Die "Hermes editable install failed." }
    } finally {
        Pop-Location
    }

    Section "Final environment setup"
    $scriptsDir = Join-Path $venvDir 'Scripts'
    Add-UserPathFirst $scriptsDir

    # python3 alias for Git Bash / tools that expect python3
    $pyExe = Join-Path $scriptsDir 'python.exe'
    $py3Exe = Join-Path $scriptsDir 'python3.exe'
    if (Test-Path $pyExe) {
        Copy-Item $pyExe $py3Exe -Force
        & $py3Exe --version
    }

    [Environment]::SetEnvironmentVariable('HERMES_HOME', $HermesHome, 'User')
    $env:HERMES_HOME = $HermesHome
    [Environment]::SetEnvironmentVariable('PYTHONUTF8', '1', 'User')
    [Environment]::SetEnvironmentVariable('PYTHONIOENCODING', 'utf-8', 'User')
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'

    $gitBash = Resolve-GitBash -BundleRoot $bundleRoot
    if ($gitBash) {
        [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $gitBash, 'User')
        $env:HERMES_GIT_BASH_PATH = $gitBash
        Info "Git Bash: $gitBash"
    } else {
        Warn "Git Bash was not found. Hermes shell tools may fail until HERMES_GIT_BASH_PATH is set."
    }

    # Add optional tools if present.
    $rg = Get-ChildItem (Join-Path $bundleRoot 'tools') -Recurse -Filter 'rg.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rg) { Add-UserPathFirst (Split-Path $rg.FullName -Parent) }
    $ffmpeg = Get-ChildItem (Join-Path $bundleRoot 'tools') -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ffmpeg) { Add-UserPathFirst (Split-Path $ffmpeg.FullName -Parent) }

    Section "Verification"
    $hermesExe = Join-Path $scriptsDir 'hermes.exe'
    if (-not (Test-Path $hermesExe)) { Die "hermes.exe not found: $hermesExe" }

    & $hermesExe --version
    if ($LASTEXITCODE -ne 0) { Warn "hermes --version returned non-zero exit code." }

    if (-not $SkipDoctor) {
        & $hermesExe config check
        if ($LASTEXITCODE -ne 0) { Warn "hermes config check returned non-zero exit code." }

        & $hermesExe config migrate
        if ($LASTEXITCODE -ne 0) { Warn "hermes config migrate returned non-zero exit code." }

        & $hermesExe doctor
        if ($LASTEXITCODE -ne 0) { Warn "hermes doctor returned non-zero exit code. This can be normal for optional tools."
        }
    }

    Section "DONE"
    Info "Hermes installed/updated successfully."
    Info "Open a NEW PowerShell/CMD window, then run: hermes --version"
    Info "Then run: hermes model"
    Info "Remember: use Custom endpoint, not Custom API."
    if ($exists) { Info "Minimal backup: $backupRoot" }
    if ($oldSource) { Info "Old source backup: $oldSource" }

} catch {
    Write-Host ""
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check log under: $HermesHome" -ForegroundColor Yellow
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
