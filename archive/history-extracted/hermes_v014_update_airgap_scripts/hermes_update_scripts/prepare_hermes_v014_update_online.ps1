<#
prepare_hermes_v014_update_online.ps1

Purpose:
  Build an air-gapped UPDATE bundle for Hermes Agent v0.14.0.
  This is designed for a machine WITH internet access. The generated zip is then moved to the offline/intranet PC.

What it creates:
  - Hermes source snapshot for the requested tag/revision
  - Python wheelhouse for offline pip install
  - requirements-hermes-win.txt
  - install_hermes_v014_update_offline.ps1 for the intranet/offline PC
  - README_UPDATE_AIRGAP.md
  - Desktop\HermesUpdateBundle_v0.14.0.zip by default

Notes:
  - This is an UPDATE bundle, not a first-install bundle.
  - The offline updater preserves your existing HERMES_HOME, config, model settings, sessions, skills and memories.
  - The offline updater reuses the existing Hermes venv by default. Use -CleanVenv on the offline script only if needed.
#>

[CmdletBinding()]
param(
    [string]$VersionTag = "v0.14.0",
    [string]$BundleRoot = "C:\HermesUpdateBundle_v0.14.0",
    [string]$OutputZip = "$env:USERPROFILE\Desktop\HermesUpdateBundle_v0.14.0.zip",
    [string[]]$PrimaryExtras = @("web", "mcp", "cron", "cli"),
    [string[]]$FallbackExtras = @("cli", "mcp"),
    [switch]$KeepTempRepo
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Invoke-Logged {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Script,
        [string]$Label = "command"
    )
    Write-Host "-> $Label" -ForegroundColor DarkCyan
    & $Script
}

function Get-CommandOrFail($Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Required command not found in PATH: $Name" }
    return $cmd.Source
}

function Try-Run($Script, $Label) {
    try {
        Write-Host "-> Trying: $Label" -ForegroundColor DarkCyan
        & $Script
        return $true
    } catch {
        Write-Warning "$Label failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-PipDownloadWithFallback {
    param(
        [string]$PythonLauncher,
        [string]$RequirementsFile,
        [string]$Wheelhouse
    )

    $baseArgs = @("-m", "pip", "download", "-r", $RequirementsFile, "-d", $Wheelhouse, "--only-binary=:all:")

    $ok = Try-Run { & $PythonLauncher @("-3.11") @baseArgs "--use-feature=truststore" } "pip download with truststore"
    if ($ok) { return }

    $ok = Try-Run { & $PythonLauncher @("-3.11") @baseArgs "--trusted-host" "pypi.org" "--trusted-host" "files.pythonhosted.org" "--trusted-host" "pypi.python.org" } "pip download with trusted-host fallback"
    if ($ok) { return }

    throw "pip download failed. Corporate TLS/proxy or missing wheels need attention."
}

function Invoke-PipDownloadToolsWithFallback {
    param(
        [string]$PythonLauncher,
        [string]$Wheelhouse
    )

    $tools = @("pip", "setuptools", "wheel")
    $baseArgs = @("-m", "pip", "download") + $tools + @("-d", $Wheelhouse, "--only-binary=:all:")

    $ok = Try-Run { & $PythonLauncher @("-3.11") @baseArgs "--use-feature=truststore" } "pip/setuptools/wheel download with truststore"
    if ($ok) { return }

    $ok = Try-Run { & $PythonLauncher @("-3.11") @baseArgs "--trusted-host" "pypi.org" "--trusted-host" "files.pythonhosted.org" "--trusted-host" "pypi.python.org" } "pip/setuptools/wheel download with trusted-host fallback"
    if ($ok) { return }

    throw "pip/setuptools/wheel download failed."
}

function Invoke-UvCompileWithFallback {
    param(
        [string]$UvExe,
        [string]$PyProject,
        [string[]]$Extras,
        [string]$OutFile
    )

    $extraArgs = @()
    foreach ($e in $Extras) { $extraArgs += @("--extra", $e) }

    $ok = Try-Run { & $UvExe --system-certs pip compile $PyProject @extraArgs -o $OutFile } "uv pip compile with --system-certs: extras=$($Extras -join ',')"
    if ($ok) { return $true }

    $ok = Try-Run { & $UvExe --native-tls pip compile $PyProject @extraArgs -o $OutFile } "uv pip compile with --native-tls: extras=$($Extras -join ',')"
    if ($ok) { return $true }

    $ok = Try-Run { & $UvExe pip compile $PyProject @extraArgs -o $OutFile } "uv pip compile without TLS flag: extras=$($Extras -join ',')"
    return $ok
}

Write-Step "Preflight"
$gitExe = Get-CommandOrFail git
$pyExe = Get-CommandOrFail py
Write-Host "git: $gitExe"
Write-Host "py:  $pyExe"

& py -3.11 --version
if ($LASTEXITCODE -ne 0) { throw "Python 3.11 is required on the online prep PC. Install Python 3.11.x and retry." }

# GitHub behind corporate TLS inspection usually works better with schannel.
try {
    git config --global http.sslBackend schannel | Out-Null
    git config --global http.sslVerify true | Out-Null
} catch {
    Write-Warning "Could not set git TLS backend to schannel: $($_.Exception.Message)"
}

Write-Step "Create clean bundle root"
if (Test-Path $BundleRoot) {
    Write-Host "Removing existing bundle root: $BundleRoot"
    Remove-Item -Recurse -Force $BundleRoot
}
New-Item -ItemType Directory -Force $BundleRoot | Out-Null
New-Item -ItemType Directory -Force "$BundleRoot\tools" | Out-Null
New-Item -ItemType Directory -Force "$BundleRoot\wheelhouse" | Out-Null

Write-Step "Clone Hermes repo and checkout $VersionTag"
$tempRepo = Join-Path $BundleRoot "_repo_tmp"
git clone https://github.com/NousResearch/hermes-agent.git $tempRepo
Push-Location $tempRepo
try {
    git fetch --tags
    git checkout $VersionTag
    $commit = git rev-parse HEAD
    @"
Hermes update bundle
VersionTag=$VersionTag
Commit=$commit
PreparedAt=$(Get-Date -Format o)
PrimaryExtras=$($PrimaryExtras -join ',')
FallbackExtras=$($FallbackExtras -join ',')
"@ | Set-Content "$BundleRoot\VERSION.txt" -Encoding UTF8

    Write-Host "Checked out: $VersionTag / $commit" -ForegroundColor Green

    Write-Step "Create source snapshot without .git"
    $sourceZip = Join-Path $BundleRoot "hermes-agent-source.zip"
    git archive --format=zip --output=$sourceZip HEAD
    New-Item -ItemType Directory -Force "$BundleRoot\hermes-agent" | Out-Null
    Expand-Archive $sourceZip -DestinationPath "$BundleRoot\hermes-agent" -Force
} finally {
    Pop-Location
}

if (-not $KeepTempRepo) {
    Remove-Item -Recurse -Force $tempRepo -ErrorAction SilentlyContinue
}

Write-Step "Prepare uv"
$uvDir = "$BundleRoot\tools\uv"
New-Item -ItemType Directory -Force $uvDir | Out-Null
$uvZip = "$BundleRoot\tools\uv-x86_64-pc-windows-msvc.zip"
$uvExe = "$uvDir\uv.exe"
if (-not (Test-Path $uvExe)) {
    $uvUrl = "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip"
    Write-Host "Downloading uv: $uvUrl"
    Invoke-WebRequest -Uri $uvUrl -OutFile $uvZip
    Expand-Archive $uvZip -DestinationPath $uvDir -Force
}
& $uvExe --version

Write-Step "Compile requirements for v0.14.0"
$requirements = "$BundleRoot\requirements-hermes-win.txt"
$pyProject = "$BundleRoot\hermes-agent\pyproject.toml"
$usedExtras = $null

$okPrimary = Invoke-UvCompileWithFallback -UvExe $uvExe -PyProject $pyProject -Extras $PrimaryExtras -OutFile $requirements
if ($okPrimary) {
    $usedExtras = $PrimaryExtras
} else {
    Write-Warning "Primary extras failed. Trying fallback extras: $($FallbackExtras -join ',')"
    $okFallback = Invoke-UvCompileWithFallback -UvExe $uvExe -PyProject $pyProject -Extras $FallbackExtras -OutFile $requirements
    if ($okFallback) {
        $usedExtras = $FallbackExtras
    } else {
        Write-Warning "Fallback extras failed. Trying core package without extras."
        $okCore = Invoke-UvCompileWithFallback -UvExe $uvExe -PyProject $pyProject -Extras @() -OutFile $requirements
        if (-not $okCore) { throw "Could not compile requirements for Hermes v0.14.0." }
        $usedExtras = @()
    }
}

($usedExtras -join ",") | Set-Content "$BundleRoot\EXTRAS_USED.txt" -Encoding UTF8
Write-Host "Extras used: $($usedExtras -join ',')" -ForegroundColor Green
Get-Content $requirements -TotalCount 25

Write-Step "Download Python wheels for offline update"
Invoke-PipDownloadWithFallback -PythonLauncher "py" -RequirementsFile $requirements -Wheelhouse "$BundleRoot\wheelhouse"
Invoke-PipDownloadToolsWithFallback -PythonLauncher "py" -Wheelhouse "$BundleRoot\wheelhouse"

Write-Host "Wheelhouse count:"
Get-ChildItem "$BundleRoot\wheelhouse" | Measure-Object

Write-Step "Write offline updater script into bundle"
$offlineScript = @'
<#
install_hermes_v014_update_offline.ps1

Purpose:
  Update an existing air-gapped Hermes Agent installation from v0.13.x to v0.14.0 using a prepared offline bundle.

Default behavior:
  - Backs up current source/config/session data
  - Preserves your existing venv and reuses already-installed packages
  - Replaces Hermes source with the bundled v0.14.0 source snapshot
  - Runs pip install from the bundled wheelhouse only
  - Preserves your model configuration; you may need to reselect Custom endpoint via `hermes model`

Common use:
  powershell -ExecutionPolicy Bypass -File .\install_hermes_v014_update_offline.ps1 -BundleRoot C:\Tools\HermesUpdateBundle_v0.14.0

Clean venv option:
  powershell -ExecutionPolicy Bypass -File .\install_hermes_v014_update_offline.ps1 -BundleRoot C:\Tools\HermesUpdateBundle_v0.14.0 -CleanVenv
#>

[CmdletBinding()]
param(
    [string]$BundleRoot = $PSScriptRoot,
    [string]$HermesHome = "$env:LOCALAPPDATA\hermes",
    [string]$GitBashPath = "C:\Program Files\Git\bin\bash.exe",
    [string]$PythonExe = "$env:LOCALAPPDATA\hermes\python311\python.exe",
    [string]$Extras = "",
    [switch]$CleanVenv,
    [switch]$SkipConfigMigrate
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Add-UserPathFront([string]$PathToAdd) {
    if (-not (Test-Path $PathToAdd)) { return }
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($current -notlike "*$PathToAdd*") {
        [Environment]::SetEnvironmentVariable("Path", "$PathToAdd;$current", "User")
    }
    $env:Path = "$PathToAdd;$env:Path"
}

function Invoke-PipInstallExtras($VenvPy, $InstallDir, $Wheelhouse, $ExtrasCsv) {
    Push-Location $InstallDir
    try {
        $extrasExpr = "."
        if ($ExtrasCsv -and $ExtrasCsv.Trim().Length -gt 0) {
            $extrasExpr = ".[" + $ExtrasCsv + "]"
        }
        Write-Host "Installing Hermes with expression: $extrasExpr"
        & $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade -e $extrasExpr
        if ($LASTEXITCODE -ne 0) { throw "pip install failed for $extrasExpr" }
    } finally {
        Pop-Location
    }
}

Write-Step "Resolve paths"
$BundleRoot = (Resolve-Path $BundleRoot).Path
$SourceDir = Join-Path $BundleRoot "hermes-agent"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$InstallDir = Join-Path $HermesHome "hermes-agent"
$VenvDir = Join-Path $InstallDir "venv"
$VenvScripts = Join-Path $VenvDir "Scripts"
$VenvPy = Join-Path $VenvScripts "python.exe"

if (-not (Test-Path $SourceDir)) { throw "Bundled Hermes source not found: $SourceDir" }
if (-not (Test-Path $Wheelhouse)) { throw "Wheelhouse not found: $Wheelhouse" }
if (-not (Test-Path $HermesHome)) { throw "HermesHome not found: $HermesHome. This updater expects an existing Hermes installation." }

if (-not $Extras -or $Extras.Trim().Length -eq 0) {
    $extrasFile = Join-Path $BundleRoot "EXTRAS_USED.txt"
    if (Test-Path $extrasFile) { $Extras = (Get-Content $extrasFile -Raw).Trim() }
    if (-not $Extras) { $Extras = "web,mcp,cron,cli" }
}

Write-Host "BundleRoot: $BundleRoot"
Write-Host "HermesHome: $HermesHome"
Write-Host "InstallDir: $InstallDir"
Write-Host "Wheelhouse:  $Wheelhouse"
Write-Host "Extras:      $Extras"

Write-Step "Backup existing installation/config"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = Join-Path $env:LOCALAPPDATA "hermes_backup_before_v014_$stamp"
New-Item -ItemType Directory -Force $BackupRoot | Out-Null

# Back up user-level configuration and state.
foreach ($name in @("config.yaml", ".env", "sessions", "skills", "memories", "cron", "logs")) {
    $src = Join-Path $HermesHome $name
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $BackupRoot $name) -Recurse -Force
    }
}

# Temporarily preserve venv if requested by default.
$VenvTmp = Join-Path $HermesHome "_venv_preserved_$stamp"
if ((Test-Path $VenvDir) -and (-not $CleanVenv)) {
    Write-Host "Preserving existing venv: $VenvDir"
    Move-Item $VenvDir $VenvTmp
}

# Move old source aside after venv extraction.
$OldSourceBackup = Join-Path $BackupRoot "hermes-agent_old_source"
if (Test-Path $InstallDir) {
    Move-Item $InstallDir $OldSourceBackup
}

Write-Host "Backup root: $BackupRoot"

Write-Step "Install bundled v0.14.0 source"
Copy-Item $SourceDir $InstallDir -Recurse -Force

if ((Test-Path $VenvTmp) -and (-not $CleanVenv)) {
    Move-Item $VenvTmp (Join-Path $InstallDir "venv")
}

Write-Step "Prepare Python/venv"
if ($CleanVenv -or (-not (Test-Path $VenvPy))) {
    if (-not (Test-Path $PythonExe)) {
        Write-Warning "Preferred PythonExe not found: $PythonExe"
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd) { $PythonExe = $cmd.Source }
    }
    if (-not (Test-Path $PythonExe)) { throw "No Python executable found. Provide -PythonExe path to Python 3.11." }
    & $PythonExe --version
    & $PythonExe -m venv $VenvDir
    $VenvPy = Join-Path $VenvScripts "python.exe"
}

& $VenvPy --version

Write-Step "Offline pip update from wheelhouse"
& $VenvPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel
if ($LASTEXITCODE -ne 0) { throw "pip/setuptools/wheel update failed." }

try {
    Invoke-PipInstallExtras -VenvPy $VenvPy -InstallDir $InstallDir -Wheelhouse $Wheelhouse -ExtrasCsv $Extras
} catch {
    Write-Warning "Primary install failed: $($_.Exception.Message)"
    if ($Extras -ne "cli,mcp") {
        Write-Warning "Trying fallback extras: cli,mcp"
        Invoke-PipInstallExtras -VenvPy $VenvPy -InstallDir $InstallDir -Wheelhouse $Wheelhouse -ExtrasCsv "cli,mcp"
    } else {
        Write-Warning "Trying core package without extras"
        Invoke-PipInstallExtras -VenvPy $VenvPy -InstallDir $InstallDir -Wheelhouse $Wheelhouse -ExtrasCsv ""
    }
}

Write-Step "PATH, python3 alias, Git Bash"
Add-UserPathFront $VenvScripts

# Some Hermes tools/skills call python3 explicitly. Provide a Windows alias inside the venv.
$py3 = Join-Path $VenvScripts "python3.exe"
$py = Join-Path $VenvScripts "python.exe"
if ((Test-Path $py) -and (-not (Test-Path $py3))) {
    Copy-Item $py $py3 -Force
}
if (Test-Path $py3) { & $py3 --version }

if (Test-Path $GitBashPath) {
    [Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", $GitBashPath, "User")
    $env:HERMES_GIT_BASH_PATH = $GitBashPath
    & $GitBashPath --version
} else {
    Write-Warning "Git Bash path not found: $GitBashPath. Set HERMES_GIT_BASH_PATH manually if Hermes shell tools complain."
}

[Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
[Environment]::SetEnvironmentVariable("PYTHONUTF8", "1", "User")
[Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
$env:HERMES_HOME = $HermesHome
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

Write-Step "Hermes version/help check"
$HermesExe = Join-Path $VenvScripts "hermes.exe"
if (-not (Test-Path $HermesExe)) { throw "hermes.exe was not created in venv Scripts." }
& $HermesExe --help | Select-Object -First 20
try { & $HermesExe --version } catch { Write-Warning "hermes --version failed: $($_.Exception.Message)" }

if (-not $SkipConfigMigrate) {
    Write-Step "Config check/migrate"
    try { & $HermesExe config check } catch { Write-Warning "hermes config check failed or is unavailable: $($_.Exception.Message)" }
    try { & $HermesExe config migrate } catch { Write-Warning "hermes config migrate failed or is unavailable: $($_.Exception.Message)" }
}

Write-Step "Done"
Write-Host "Updated Hermes source to bundled v0.14.0." -ForegroundColor Green
Write-Host "Backup root: $BackupRoot" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open a NEW PowerShell window."
Write-Host "  2. Run: hermes model"
Write-Host "  3. Select: Custom endpoint  (not Custom API)"
Write-Host "  4. Set your company endpoint URL ending with /v1, model name, and API key."
Write-Host "  5. Run: hermes chat"
'@

$offlineScript | Set-Content "$BundleRoot\install_hermes_v014_update_offline.ps1" -Encoding UTF8

Write-Step "Write README"
$readme = @"
# Hermes Agent v0.14.0 Air-Gapped Update Bundle

This bundle updates an existing air-gapped Hermes Agent installation, typically v0.13.x, to v0.14.0.

## Online prep result
Prepared tag: $VersionTag
Prepared at: $(Get-Date -Format o)
Extras used: $($usedExtras -join ',')

## Move to intranet/offline PC
Copy this zip to the offline PC and extract it to:

```text
C:\Tools\HermesUpdateBundle_v0.14.0
```

## Offline update command
Open PowerShell on the offline PC:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Tools\HermesUpdateBundle_v0.14.0\install_hermes_v014_update_offline.ps1 -BundleRoot C:\Tools\HermesUpdateBundle_v0.14.0
```

## Clean venv option
Use only if the in-place update fails:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Tools\HermesUpdateBundle_v0.14.0\install_hermes_v014_update_offline.ps1 -BundleRoot C:\Tools\HermesUpdateBundle_v0.14.0 -CleanVenv
```

## Important model configuration note
After update, run:

```powershell
hermes model
```

For your company OpenAI-compatible model gateway, select:

```text
Custom endpoint
```

Do NOT select `Custom API` for the normal OpenAI-compatible `/v1/chat/completions` path.

Use:

```text
Base URL: https://.../v1
Model:    Qwen3.5-397B-A17B-FP8
Auth:     API key from company gateway
```

## Backup
The offline updater creates a backup under:

```text
%LOCALAPPDATA%\hermes_backup_before_v014_YYYYMMDD_HHMMSS
```

## Notes
- The updater preserves your existing venv by default, so already-installed packages are reused.
- It also ships a wheelhouse so missing or changed dependencies can be installed without internet.
- A `python3.exe` alias is created in the Hermes venv Scripts directory because some Hermes tools call `python3`.
- `HERMES_GIT_BASH_PATH` is set to `C:\Program Files\Git\bin\bash.exe` if it exists.
"@
$readme | Set-Content "$BundleRoot\README_UPDATE_AIRGAP.md" -Encoding UTF8

Write-Step "Offline simulation"
$TestVenv = "$BundleRoot\_test_venv"
Remove-Item -Recurse -Force $TestVenv -ErrorAction SilentlyContinue
py -3.11 -m venv $TestVenv
$TestPy = "$TestVenv\Scripts\python.exe"
& $TestPy -m pip install --no-index --find-links "$BundleRoot\wheelhouse" --upgrade pip setuptools wheel
Push-Location "$BundleRoot\hermes-agent"
try {
    $extrasCsv = ($usedExtras -join ',')
    $expr = "."
    if ($extrasCsv.Length -gt 0) { $expr = ".[" + $extrasCsv + "]" }
    & $TestPy -m pip install --no-index --find-links "$BundleRoot\wheelhouse" -e $expr
    & "$TestVenv\Scripts\hermes.exe" --help | Select-Object -First 15
    try { & "$TestVenv\Scripts\hermes.exe" --version } catch { Write-Warning "Test hermes --version failed: $($_.Exception.Message)" }
} finally {
    Pop-Location
}
Remove-Item -Recurse -Force $TestVenv -ErrorAction SilentlyContinue

Write-Step "Create zip"
if (Test-Path $OutputZip) { Remove-Item -Force $OutputZip }
$parent = Split-Path $OutputZip -Parent
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }

tar -a -cf $OutputZip -C $BundleRoot .

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Created: $OutputZip" -ForegroundColor Green
Write-Host "Move this zip to the intranet/offline PC." -ForegroundColor Yellow
