param(
    [string]$VersionRef = "latest",
    [string]$FactoryRoot = "C:\HermesUnifiedAirgapFactory",
    [string]$RequestedExtras = "web,mcp,cron",
    [string]$PythonVersion = "3.11.9",
    [int]$NodeMajor = 24,
    [string]$NpmFallbackVersions = "11.18.0,11.17.0,10.9.8",
    [string]$NpmCafile = "",
    [switch]$NoDesktop,
    [switch]$KeepWork,
    [switch]$Fresh
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ("=" * 68)
    Write-Host $Message
    Write-Host ("=" * 68)
}
function Write-Info([string]$Message) { Write-Host "[INFO] $Message" }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Ok([string]$Message)   { Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Ensure-Dir([string]$Path) { New-Item -ItemType Directory -Force $Path | Out-Null }

function Invoke-Download([string]$Url, [string]$OutFile) {
    if (Test-Path $OutFile) {
        Write-Info "Already exists: $OutFile"
        return
    }
    Ensure-Dir (Split-Path $OutFile -Parent)
    Write-Info "Downloading: $Url"
    Write-Info "To         : $OutFile"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600 -Headers @{ "User-Agent" = "HermesAirgapFactoryAuto/3" }
    } catch {
        Write-Warn "Invoke-WebRequest failed: $($_.Exception.Message)"
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curl) { throw }
        & $curl.Source -L --retry 3 --fail --output $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    }
}

function Invoke-PipDownload {
    param(
        [Parameter(Mandatory=$true)][string]$PythonExe,
        [Parameter(Mandatory=$true)][string[]]$DownloadArgs
    )
    if (-not $DownloadArgs -or $DownloadArgs.Count -eq 0) {
        throw "Invoke-PipDownload received no download arguments."
    }
    Write-Info "pip download $($DownloadArgs -join ' ')"
    for ($Attempt = 1; $Attempt -le 2; $Attempt++) {
        & $PythonExe -m pip download --retries 5 @DownloadArgs
        if ($LASTEXITCODE -eq 0) { return }
        if ($Attempt -lt 2) {
            Write-Warn "pip download failed (attempt $Attempt/2), retrying after a short delay."
            Start-Sleep -Seconds 3
        }
    }
    throw "pip download failed: $($DownloadArgs -join ' ')"
}

function Get-Python311 {
    try {
        $p = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    } catch {}
    try {
        $p = (& python -c "import sys; print(sys.executable if sys.version_info[:2] == (3,11) else '')" 2>$null).Trim()
        if ($p -and (Test-Path $p)) { return $p }
    } catch {}
    return ""
}

function Get-LatestNodeZipUrl([int]$Major) {
    Write-Info "Resolving latest Node.js $Major.x Windows x64 ZIP..."
    try {
        $idx = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 120 -Headers @{ "User-Agent" = "HermesAirgapFactoryAuto/3" }
        $hit = $idx | Where-Object { $_.version -like "v$Major.*" -and $_.files -contains "win-x64-zip" } | Select-Object -First 1
        if ($hit) { return "https://nodejs.org/dist/$($hit.version)/node-$($hit.version)-win-x64.zip" }
    } catch {
        Write-Warn "Node index lookup failed: $($_.Exception.Message)"
    }
    if ($Major -eq 24) { return "https://nodejs.org/dist/v24.16.0/node-v24.16.0-win-x64.zip" }
    if ($Major -eq 22) { return "https://nodejs.org/dist/v22.23.2/node-v22.23.2-win-x64.zip" }
    throw "Could not resolve a Node.js download URL for major $Major"
}

function Convert-SemVer([string]$Text) {
    $t = ($Text -replace '^[vV]', '') -replace '[-+].*$', ''
    $parts = $t.Split('.')
    while ($parts.Count -lt 3) { $parts += "0" }
    try { return [version]("$($parts[0]).$($parts[1]).$($parts[2])") } catch { return $null }
}
function Test-VersionRange([string]$VersionText, [string]$RangeText) {
    $v = Convert-SemVer $VersionText
    if (-not $v -or -not $RangeText) { return $true }
    foreach ($clause in ($RangeText -split '\|\|')) {
        $ok = $true
        $tokens = $clause.Trim() -split '\s+'
        foreach ($token in $tokens) {
            if (-not $token) { continue }
            if ($token -match '^\^(\d+)\.(\d+)\.(\d+)$') {
                $lo = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
                $hi = [version]"$([int]$Matches[1] + 1).0.0"
                if (-not ($v -ge $lo -and $v -lt $hi)) { $ok = $false; break }
                continue
            }
            if ($token -match '^(>=|<=|>|<|=)?(\d+\.\d+\.\d+)$') {
                $op = $Matches[1]; if (-not $op) { $op = "=" }
                $x = [version]$Matches[2]
                switch ($op) {
                    ">=" { if (-not ($v -ge $x)) { $ok = $false } }
                    "<=" { if (-not ($v -le $x)) { $ok = $false } }
                    ">"  { if (-not ($v -gt $x)) { $ok = $false } }
                    "<"  { if (-not ($v -lt $x)) { $ok = $false } }
                    "="  { if (-not ($v -eq $x)) { $ok = $false } }
                }
                if (-not $ok) { break }
                continue
            }
            # Unknown token (wildcards, prerelease syntax, etc.): don't block;
            # package manager will do the authoritative check.
        }
        if ($ok) { return $true }
    }
    return $false
}

function Install-NpmFallback(
    [string]$Version,
    [string]$NodeBin,
    [string]$ToolsDir,
    [string]$CacheDir,
    [string]$NpmCafile
) {
    $prefix = Join-Path $ToolsDir "npm-$Version"
    Remove-Item -Recurse -Force $prefix -ErrorAction SilentlyContinue
    Ensure-Dir $prefix

    $env:NODE_OPTIONS = "--use-system-ca"
    if ($NpmCafile -and (Test-Path $NpmCafile)) {
        $env:NODE_EXTRA_CA_CERTS = $NpmCafile
        $env:npm_config_cafile = $NpmCafile
    }

    & "$NodeBin\npm.cmd" install -g "npm@$Version" --prefix $prefix --cache $CacheDir --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { return $null }

    $cli = Join-Path $prefix "node_modules\npm\bin\npm-cli.js"
    if (-not (Test-Path $cli)) { return $null }

    return [pscustomobject]@{
        Prefix = $prefix
        Cli = $cli
        Version = (& "$NodeBin\node.exe" $cli --version).Trim()
    }
}

function Invoke-NpmCi(
    [string]$RepoDir,
    [string]$NodeBin,
    [string]$CacheDir,
    [string]$NpmCli = ""
) {
    Remove-Item -Recurse -Force (Join-Path $RepoDir "node_modules") -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $RepoDir "apps\desktop\node_modules") -ErrorAction SilentlyContinue

    Push-Location $RepoDir
    try {
        if ($NpmCli) {
            & "$NodeBin\node.exe" $NpmCli ci --cache $CacheDir --no-audit --no-fund
        } else {
            & "$NodeBin\npm.cmd" ci --cache $CacheDir --no-audit --no-fund
        }
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

Write-Step "Resolving Hermes release"
$ReleaseTag = $VersionRef
$ReleaseName = $VersionRef
$ReleaseUrl = ""
if ($VersionRef -eq "latest") {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/NousResearch/hermes-agent/releases/latest" -TimeoutSec 120 -Headers @{ "User-Agent" = "HermesAirgapFactoryAuto/3" }
    $ReleaseTag = $release.tag_name
    $ReleaseName = $release.name
    $ReleaseUrl = $release.html_url
}
Write-Info "Release tag : $ReleaseTag"
Write-Info "Release name: $ReleaseName"
if ($ReleaseUrl) { Write-Info "Release URL : $ReleaseUrl" }

$WorkRoot = Join-Path $FactoryRoot "work"
$OutputRoot = Join-Path $FactoryRoot "output"
$BundleName = "HermesAirgapBundle_$ReleaseTag"
if (-not $NoDesktop) { $BundleName += "_with_desktop" }
$BundleRoot = Join-Path $WorkRoot $BundleName
$RepoDir = Join-Path $BundleRoot "hermes-agent"
$ToolsDir = Join-Path $BundleRoot "tools"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"
$OutputZip = Join-Path $OutputRoot "$BundleName.zip"
$LogDir = Join-Path $FactoryRoot "logs"

Ensure-Dir $WorkRoot
Ensure-Dir $OutputRoot
Ensure-Dir $LogDir

$Transcript = Join-Path $LogDir ("build_{0}_{1}.log" -f $ReleaseTag, (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $Transcript -Force | Out-Null

try {
    Write-Step "Preparing work directory (resume supported)"
    if (Test-Path $BundleRoot) {
        if ($Fresh) {
            Write-Warn "Fresh was requested; removing previous work directory: $BundleRoot"
            Remove-Item -Recurse -Force $BundleRoot
        } else {
            Write-Info "Resuming existing work directory (no re-clone required): $BundleRoot"
        }
    }
    Ensure-Dir $BundleRoot
    Ensure-Dir $ToolsDir
    Ensure-Dir $Wheelhouse

    Write-Step "Cloning Hermes source"
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
    if (-not $git) { throw "git was not found on the internet-side PC." }

    if (Test-Path (Join-Path $RepoDir "pyproject.toml")) {
        Write-Info "Using source from previous attempt: $RepoDir"
        $CurrentTag = (& $git.Source -C $RepoDir describe --tags --exact-match 2>$null | Out-String).Trim()
        if ($CurrentTag -and $CurrentTag -ne $ReleaseTag) {
            throw "Existing source tag '$CurrentTag' is not the requested tag '$ReleaseTag'. Re-run with -Fresh."
        }
    } else {
        if (Test-Path $RepoDir) {
            Write-Warn "Source checkout is incomplete; cloning again."
            Remove-Item -Recurse -Force $RepoDir
        }
        & $git.Source clone --depth 1 --single-branch --branch $ReleaseTag https://github.com/NousResearch/hermes-agent.git $RepoDir
        if ($LASTEXITCODE -ne 0) { throw "Hermes shallow clone failed." }
    }

    Write-Step "Downloading base tools"
    $PyInstaller = Join-Path $ToolsDir "python-$PythonVersion-amd64.exe"
    Invoke-Download "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" $PyInstaller

    $UvZip = Join-Path $ToolsDir "uv-x86_64-pc-windows-msvc.zip"
    Invoke-Download "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" $UvZip
    $UvDir = Join-Path $ToolsDir "uv"
    Ensure-Dir $UvDir
    Expand-Archive $UvZip -DestinationPath $UvDir -Force
    $UvExe = (Get-ChildItem $UvDir -Recurse -Filter "uv.exe" | Select-Object -First 1).FullName
    if (-not $UvExe) { throw "uv.exe not found after extraction." }
    & $UvExe --version

    # Optional portable helper tools. Failure is non-fatal.
    try {
        $RipZip = Join-Path $ToolsDir "ripgrep-14.1.1-x86_64-pc-windows-msvc.zip"
        Invoke-Download "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-pc-windows-msvc.zip" $RipZip
    } catch { Write-Warn "ripgrep download skipped: $($_.Exception.Message)" }

    Write-Step "Preparing Python 3.11"
    $PythonExe = Get-Python311
    if (-not $PythonExe) {
        $BuildPython = Join-Path $BundleRoot "_build_python311"
        Ensure-Dir $BuildPython
        Start-Process $PyInstaller -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$BuildPython`"" -Wait
        $PythonExe = Join-Path $BuildPython "python.exe"
    }
    if (-not (Test-Path $PythonExe)) { throw "Could not locate Python 3.11." }
    & $PythonExe --version

    Write-Step "Inspecting pyproject.toml and auto-filtering extras"
    $InspectPy = Join-Path $ToolsDir "inspect_pyproject.py"
    @'
import json, sys, tomllib
from pathlib import Path
path = Path(sys.argv[1])
requested = [x.strip() for x in sys.argv[2].split(",") if x.strip()]
with path.open("rb") as f:
    d = tomllib.load(f)
project = d.get("project", {})
opt = project.get("optional-dependencies", {})
valid = [x for x in requested if x in opt]
dropped = [x for x in requested if x not in opt]
direct = list(project.get("dependencies", []))
for x in valid:
    direct.extend(opt.get(x, []))
# Local self-references are handled by pip installing the project itself.
direct = [r for r in direct if not r.lower().startswith("hermes-agent[")]
build = d.get("build-system", {}).get("requires", [])
print(json.dumps({
    "available_extras": sorted(opt.keys()),
    "valid_extras": valid,
    "dropped_extras": dropped,
    "direct_requirements": direct,
    "build_requirements": build,
}))
'@ | Set-Content $InspectPy -Encoding UTF8

    $MetaJson = & $PythonExe $InspectPy (Join-Path $RepoDir "pyproject.toml") $RequestedExtras
    if ($LASTEXITCODE -ne 0) { throw "pyproject inspection failed." }
    $Meta = $MetaJson | ConvertFrom-Json
    $ValidExtras = @($Meta.valid_extras)
    $DroppedExtras = @($Meta.dropped_extras)

    Write-Info "Requested extras: $RequestedExtras"
    Write-Info "Valid extras    : $($ValidExtras -join ',')"
    if ($DroppedExtras.Count -gt 0) {
        Write-Warn "Ignoring extras not present in this release: $($DroppedExtras -join ',')"
    }

    $ExtrasCsv = $ValidExtras -join ","
    $ExtraArgs = @()
    foreach ($e in $ValidExtras) {
        $ExtraArgs += "--extra"
        $ExtraArgs += $e
    }

    $DirectReq = Join-Path $BundleRoot "requirements-direct-win.txt"
    @($Meta.direct_requirements) | Set-Content $DirectReq -Encoding ASCII
    $BuildReq = Join-Path $BundleRoot "requirements-build.txt"
    @($Meta.build_requirements) | Set-Content $BuildReq -Encoding ASCII
    $ReqFile = Join-Path $BundleRoot "requirements-hermes-win.txt"
    $ExtrasFile = Join-Path $BundleRoot "EXTRAS.txt"
    $ExtrasCsv | Set-Content $ExtrasFile -Encoding ASCII

    Write-Step "Compiling Python requirements"
    $env:UV_SYSTEM_CERTS = "true"
    $env:UV_PYTHON = $PythonExe
    Push-Location $RepoDir
    try {
        & $UvExe --system-certs pip compile .\pyproject.toml @ExtraArgs -o $ReqFile
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "uv --system-certs compile failed. Retrying with UV_SYSTEM_CERTS."
            & $UvExe pip compile .\pyproject.toml @ExtraArgs -o $ReqFile
        }
        if ($LASTEXITCODE -ne 0) { throw "uv pip compile failed." }
    } finally {
        Pop-Location
    }

    Write-Step "Building complete wheelhouse"
    Invoke-PipDownload -PythonExe $PythonExe -DownloadArgs @("-r", $ReqFile, "-d", $Wheelhouse, "--only-binary=:all:")
    # Critical robustness step: download the project's direct requirements too.
    # This catches exact pins that uv overrides may otherwise replace in the compiled lock
    # (e.g. cryptography==50.0.0 vs 50.0.1).
    Invoke-PipDownload -PythonExe $PythonExe -DownloadArgs @("-r", $DirectReq, "-d", $Wheelhouse, "--only-binary=:all:")
    Invoke-PipDownload -PythonExe $PythonExe -DownloadArgs @("-r", $BuildReq, "-d", $Wheelhouse, "--only-binary=:all:")
    Invoke-PipDownload -PythonExe $PythonExe -DownloadArgs @("pip", "packaging", "wheel", "-d", $Wheelhouse, "--only-binary=:all:")

    Write-Step "Testing fully offline Python install"
    $TestVenv = Join-Path $BundleRoot "_test_venv"
    Remove-Item -Recurse -Force $TestVenv -ErrorAction SilentlyContinue
    & $PythonExe -m venv $TestVenv
    if ($LASTEXITCODE -ne 0) { throw "Test venv creation failed." }
    $TestPy = Join-Path $TestVenv "Scripts\python.exe"
    $TestHermes = Join-Path $TestVenv "Scripts\hermes.exe"

    & $TestPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip packaging wheel
    if ($LASTEXITCODE -ne 0) { throw "Offline bootstrap package install failed." }
    & $TestPy -m pip install --no-index --find-links $Wheelhouse -r $BuildReq
    if ($LASTEXITCODE -ne 0) { throw "Offline build-system dependency install failed." }

    $EditableTarget = $RepoDir
    if ($ExtrasCsv) { $EditableTarget = "$RepoDir[$ExtrasCsv]" }
    & $TestPy -m pip install --no-index --find-links $Wheelhouse -e $EditableTarget
    if ($LASTEXITCODE -ne 0) { throw "Offline Hermes install test failed." }
    if (-not (Test-Path $TestHermes)) { throw "hermes.exe was not created in the test venv." }

    $VersionOutput = (& $TestHermes --version | Out-String).Trim()
    Write-Host $VersionOutput
    Write-Ok "Offline Python install test passed."

    if (-not $NoDesktop) {
        Write-Step "Building Desktop artifact"
        $NodeUrl = Get-LatestNodeZipUrl $NodeMajor
        $NodeZip = Join-Path $ToolsDir (Split-Path $NodeUrl -Leaf)
        Invoke-Download $NodeUrl $NodeZip

        $NodeRoot = Join-Path $ToolsDir "node$NodeMajor"
        Remove-Item -Recurse -Force $NodeRoot -ErrorAction SilentlyContinue
        Ensure-Dir $NodeRoot
        Expand-Archive $NodeZip -DestinationPath $NodeRoot -Force

        $NodeExe = (Get-ChildItem $NodeRoot -Recurse -Filter "node.exe" | Select-Object -First 1).FullName
        if (-not $NodeExe) { throw "node.exe not found." }
        $NodeBin = Split-Path $NodeExe -Parent
        $env:Path = "$NodeBin;$env:Path"
        $env:NODE_OPTIONS = "--use-system-ca"
        if ($NpmCafile -and (Test-Path $NpmCafile)) {
            $env:NODE_EXTRA_CA_CERTS = $NpmCafile
            $env:npm_config_cafile = $NpmCafile
        }

        $PackageJson = Get-Content (Join-Path $RepoDir "package.json") -Raw | ConvertFrom-Json
        $NodeRange = [string]$PackageJson.engines.node
        $NpmRange = [string]$PackageJson.engines.npm
        $NodeVersion = (& "$NodeBin\node.exe" --version).Trim()
        $BundledNpmVersion = (& "$NodeBin\npm.cmd" --version).Trim()
        Write-Info "Node engine : $NodeRange"
        Write-Info "npm engine  : $NpmRange"
        Write-Info "Node actual : $NodeVersion"
        Write-Info "npm bundled : $BundledNpmVersion"

        if (-not (Test-VersionRange $NodeVersion $NodeRange)) {
            Write-Warn "Selected Node $NodeVersion may not satisfy '$NodeRange'. npm will perform the authoritative engine check."
        }

        $NpmCache = Join-Path $ToolsDir "npm-cache-$ReleaseTag"
        Remove-Item -Recurse -Force $NpmCache -ErrorAction SilentlyContinue
        Ensure-Dir $NpmCache

        Remove-Item -Recurse -Force (Join-Path $RepoDir "apps\desktop\release") -ErrorAction SilentlyContinue

        $NpmOk = $false
        $ActiveNpmPrefix = ""
        $ActiveNpmCli = ""

        if (Test-VersionRange $BundledNpmVersion $NpmRange) {
            Write-Info "Trying bundled npm $BundledNpmVersion first..."
            $NpmOk = Invoke-NpmCi $RepoDir $NodeBin $NpmCache
            if (-not $NpmOk) { Write-Warn "Bundled npm failed; trying known-good fallback versions." }
        } else {
            Write-Warn "Bundled npm $BundledNpmVersion does not satisfy '$NpmRange'; skipping it."
        }

        if (-not $NpmOk) {
            foreach ($candidate in ($NpmFallbackVersions.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                if (-not (Test-VersionRange $candidate $NpmRange)) {
                    Write-Info "Skipping npm $candidate (does not satisfy '$NpmRange')."
                    continue
                }
                Write-Info "Installing isolated npm $candidate..."
                $npmInfo = Install-NpmFallback $candidate $NodeBin $ToolsDir $NpmCache $NpmCafile
                if (-not $npmInfo) {
                    Write-Warn "Could not install npm $candidate."
                    continue
                }
                Write-Info "Retrying npm ci with npm $($npmInfo.Version)..."
                $NpmOk = Invoke-NpmCi $RepoDir $NodeBin $NpmCache $npmInfo.Cli
                if ($NpmOk) {
                    $ActiveNpmPrefix = $npmInfo.Prefix
                    $ActiveNpmCli = $npmInfo.Cli
                    break
                }
            }
        }

        if (-not $NpmOk) {
            throw "Desktop dependency installation failed with bundled npm and all compatible fallbacks."
        }

        if ($ActiveNpmPrefix) {
            $env:Path = "$ActiveNpmPrefix;$NodeBin;$env:Path"
        } else {
            $env:Path = "$NodeBin;$env:Path"
        }

        Write-Info "Running Hermes Desktop build..."
        & $TestHermes desktop --build-only --force-build --hermes-root $RepoDir
        if ($LASTEXITCODE -ne 0) { throw "hermes desktop --build-only failed." }

        $DesktopRelease = Join-Path $RepoDir "apps\desktop\release\win-unpacked"
        $DesktopExe = Get-ChildItem $DesktopRelease -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $DesktopExe) { throw "Desktop build finished but win-unpacked EXE was not found." }
        Write-Ok "Desktop artifact: $($DesktopExe.FullName)"
    }

    Write-Step "Adding robust intranet installer"
    $TemplateRoot = Join-Path $PSScriptRoot "templates"
    Copy-Item (Join-Path $TemplateRoot "InstallOrUpdateHermesAirgapped.ps1") $BundleRoot -Force
    Copy-Item (Join-Path $TemplateRoot "InstallOrUpdateHermesAirgapped.bat") $BundleRoot -Force

    # Belt-and-suspenders patch for the historical PowerShell "$d:" parser bug.
    $InstallScript = Join-Path $BundleRoot "InstallOrUpdateHermesAirgapped.ps1"
    $txt = Get-Content $InstallScript -Raw
    $txt = $txt.Replace('$d:', '${d}:')
    Set-Content $InstallScript $txt -Encoding UTF8

    @"
ReleaseTag=$ReleaseTag
ReleaseName=$ReleaseName
BuiltAt=$(Get-Date -Format o)
PythonVersion=$PythonVersion
Extras=$ExtrasCsv
Desktop=$(-not $NoDesktop)
"@ | Set-Content (Join-Path $BundleRoot "VERSION.txt") -Encoding UTF8

    Write-Step "Cleaning build-only artifacts"
    Remove-Item -Recurse -Force (Join-Path $BundleRoot "_test_venv") -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $BundleRoot "_build_python311") -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $RepoDir "node_modules") -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $RepoDir "apps\desktop\node_modules") -ErrorAction SilentlyContinue

    # npm caches are large and not needed on the intranet runtime.
    Get-ChildItem $ToolsDir -Directory -Filter "npm-cache-*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-Step "Creating final air-gap ZIP"
    if (Test-Path $OutputZip) { Remove-Item -Force $OutputZip }
    tar -a -cf $OutputZip -C $BundleRoot .
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutputZip)) { throw "Final ZIP creation failed." }

    $Hash = (Get-FileHash $OutputZip -Algorithm SHA256).Hash
    "$Hash  $([IO.Path]::GetFileName($OutputZip))" | Set-Content "$OutputZip.sha256" -Encoding ASCII

    Write-Step "Final verification"
    $entries = tar -tf $OutputZip
    $required = @(
        "InstallOrUpdateHermesAirgapped.bat",
        "InstallOrUpdateHermesAirgapped.ps1",
        "requirements-hermes-win.txt",
        "requirements-build.txt",
        "wheelhouse/"
    )
    foreach ($r in $required) {
        if (-not ($entries | Where-Object { $_ -like "*$r*" })) { throw "ZIP verification failed; missing: $r" }
    }
    if (-not $NoDesktop -and -not ($entries | Where-Object { $_ -match 'apps/desktop/release/win-unpacked/.*\.exe$' })) {
        throw "ZIP verification failed; Desktop EXE missing."
    }

    Write-Ok "Bundle ready:"
    Write-Host "  $OutputZip"
    Write-Host "  SHA256: $Hash"
    Write-Host "  Log   : $Transcript"
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
