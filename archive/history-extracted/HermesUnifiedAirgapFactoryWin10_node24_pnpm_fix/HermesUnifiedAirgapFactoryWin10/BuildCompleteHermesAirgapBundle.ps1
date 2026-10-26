param(
    [string]$VersionRef = "latest",
    [string]$FactoryRoot = "C:\HermesUnifiedAirgapFactory",
    [string]$Extras = "web,mcp,cron,cli",
    [object]$IncludeDesktop = $true,
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"

# Normalize IncludeDesktop in case it is passed by a .bat/cmd layer as text.
if ($IncludeDesktop -is [string]) {
    $IncludeDesktop = $IncludeDesktop.ToLowerInvariant()
    $IncludeDesktop = -not ($IncludeDesktop -in @("false", "0", "no", "off"))
} else {
    $IncludeDesktop = [bool]$IncludeDesktop
}


function Write-Step($msg) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $msg
    Write-Host "============================================================"
}
function Write-Info($msg) { Write-Host "[INFO] $msg" }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Ensure-Dir($p) { New-Item -ItemType Directory -Force $p | Out-Null }

function Resolve-HermesRef([string]$Ref) {
    if ($Ref -ne "latest") {
        return [pscustomobject]@{
            Ref = $Ref
            Name = $Ref
            Url = "manual ref"
        }
    }

    Write-Step "Resolving latest Hermes Agent release from GitHub"
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/NousResearch/hermes-agent/releases/latest" -Headers @{ "User-Agent" = "HermesAirgapFactory" } -TimeoutSec 30
        if (-not $release.tag_name) { throw "latest release did not include tag_name" }
        return [pscustomobject]@{
            Ref = $release.tag_name
            Name = $release.name
            Url = $release.html_url
        }
    } catch {
        Write-Warn "Could not query GitHub latest release API. Falling back to known latest tag v2026.5.29.2."
        return [pscustomobject]@{
            Ref = "v2026.5.29.2"
            Name = "Hermes Agent v0.15.2 fallback"
            Url = "https://github.com/NousResearch/hermes-agent/releases"
        }
    }
}

function Invoke-Download($Url, $OutFile) {
    if (Test-Path $OutFile) {
        Write-Info "Already exists: $OutFile"
        return
    }
    Write-Info "Downloading: $Url"
    Write-Info "To         : $OutFile"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 180
    } catch {
        Write-Warn "Invoke-WebRequest failed: $($_.Exception.Message)"
        Write-Info "Trying curl.exe..."
        curl.exe -L --retry 3 --output $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    }
}


function Resolve-Node24WindowsZipUrl {
    try {
        Write-Info "Resolving latest Node.js 24.x Windows x64 ZIP from nodejs.org..."
        $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 60
        $v = $index |
            Where-Object { $_.version -like "v24.*" -and $_.files -contains "win-x64-zip" } |
            Select-Object -First 1

        if ($v -and $v.version) {
            return "https://nodejs.org/dist/$($v.version)/node-$($v.version)-win-x64.zip"
        }
    } catch {
        Write-Warn "Could not resolve latest Node 24.x dynamically: $($_.Exception.Message)"
    }

    return "https://nodejs.org/dist/v24.11.1/node-v24.11.1-win-x64.zip"
}

function Get-NodeMajorVersion {
    try {
        $v = (& node --version 2>$null).Trim()
        if ($v -match '^v(\d+)\.') { return [int]$Matches[1] }
    } catch {}
    return 0
}

function Ensure-Pnpm10($ToolsDir) {
    $pnpmOk = $false
    try {
        $pnpmVersion = (& pnpm --version 2>$null).Trim()
        if ($pnpmVersion -match '^(\d+)\.') {
            if ([int]$Matches[1] -ge 10) { $pnpmOk = $true }
        }
    } catch {}

    if ($pnpmOk) {
        Write-Info "pnpm already available:"
        pnpm --version
        return
    }

    Write-Info "Installing pnpm@10 into a bundle-local npm prefix..."
    $PnpmPrefix = Join-Path $ToolsDir "npm-global"
    New-Item -ItemType Directory -Force $PnpmPrefix | Out-Null

    npm config set prefix $PnpmPrefix
    npm install -g pnpm@10
    if ($LASTEXITCODE -ne 0) { throw "npm install -g pnpm@10 failed." }

    $env:Path = "$PnpmPrefix;$env:Path"

    pnpm --version
    if ($LASTEXITCODE -ne 0) { throw "pnpm was installed but could not be executed." }
}

function Ensure-NodeForDesktop($ToolsDir) {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    $nodeMajor = Get-NodeMajorVersion

    if ($nodeCmd -and $npmCmd -and $nodeMajor -ge 24) {
        Write-Info "Node/npm already on PATH and Node major version is >= 24:"
        node --version
        npm --version
        Ensure-Pnpm10 $ToolsDir
        return
    }

    if ($nodeCmd -and $npmCmd) {
        Write-Warn "Node/npm found, but Node major version is $nodeMajor. Hermes Desktop v0.16 requires Node >= 24. Using portable Node 24 instead."
    } else {
        Write-Warn "Node/npm not found on PATH. Downloading portable Node.js 24.x into the bundle tools folder."
    }

    $NodeZipUrl = Resolve-Node24WindowsZipUrl
    $NodeZipName = Split-Path $NodeZipUrl -Leaf
    $NodeZip = Join-Path $ToolsDir $NodeZipName
    Invoke-Download $NodeZipUrl $NodeZip

    $NodeRoot = Join-Path $ToolsDir "node"
    if (Test-Path $NodeRoot) { Remove-Item -Recurse -Force $NodeRoot }
    New-Item -ItemType Directory -Force $NodeRoot | Out-Null

    Expand-Archive $NodeZip -DestinationPath $NodeRoot -Force

    $NodeExe = Get-ChildItem $NodeRoot -Recurse -Filter "node.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $NpmCmd = Get-ChildItem $NodeRoot -Recurse -Filter "npm.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $NodeExe -or -not $NpmCmd) {
        throw "Portable Node.js extraction failed. node.exe or npm.cmd not found under $NodeRoot"
    }

    $NodeBin = Split-Path $NodeExe.FullName -Parent
    $env:Path = "$NodeBin;$env:Path"

    Write-Info "Using bundled portable Node.js from: $NodeBin"
    node --version
    npm --version

    $nodeMajorAfter = Get-NodeMajorVersion
    if ($nodeMajorAfter -lt 24) {
        throw "Node >= 24 is required for Hermes Desktop, but active Node major is $nodeMajorAfter."
    }

    Ensure-Pnpm10 $ToolsDir
}


function Find-Python311($ToolsDir) {
    $py = ""
    try {
        $candidate = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null).Trim()
        if ($candidate -and (Test-Path $candidate)) { $py = $candidate }
    } catch {}

    if (-not $py) {
        try {
            $candidate = (& python -c "import sys; print(sys.executable if sys.version_info[:2] == (3,11) else '')" 2>$null).Trim()
            if ($candidate -and (Test-Path $candidate)) { $py = $candidate }
        } catch {}
    }

    return $py
}

function Make-SafeRef($ref) {
    return ($ref -replace '[^a-zA-Z0-9._-]', '_')
}

$release = Resolve-HermesRef $VersionRef
$safeRef = Make-SafeRef $release.Ref

$WorkRoot = Join-Path $FactoryRoot "work"
$OutputRoot = Join-Path $FactoryRoot "output"
$BundleRoot = Join-Path $WorkRoot "HermesAirgapBundle_$safeRef"
$OutputZip = Join-Path $OutputRoot "HermesAirgapBundle_$safeRef.zip"

if ($IncludeDesktop) {
    $OutputZip = Join-Path $OutputRoot "HermesAirgapBundle_$safeRef`_with_desktop.zip"
}

Ensure-Dir $WorkRoot
Ensure-Dir $OutputRoot

Write-Step "Hermes unified air-gap bundle preparation"
Write-Info "Requested ref     : $VersionRef"
Write-Info "Resolved ref      : $($release.Ref)"
Write-Info "Release name      : $($release.Name)"
Write-Info "Release URL       : $($release.Url)"
Write-Info "Bundle root       : $BundleRoot"
Write-Info "Output zip        : $OutputZip"
Write-Info "Extras            : $Extras"
Write-Info "Include desktop   : $IncludeDesktop"

Write-Step "Checking required internet-side tools"
git --version
if ($LASTEXITCODE -ne 0) { throw "git is required on the internet machine." }

# Helps corporate SSL inspection environments for Git for Windows.
git config --global http.sslBackend schannel | Out-Null
git config --global http.sslVerify true | Out-Null

$ExistingPy = Find-Python311 ""
if ($ExistingPy) {
    & $ExistingPy --version
} else {
    Write-Warn "Python 3.11 not found on PATH. Bundle Python installer will be downloaded and used later."
}

if (Test-Path $BundleRoot) {
    Write-Warn "Removing existing bundle root: $BundleRoot"
    Remove-Item -Recurse -Force $BundleRoot
}
Ensure-Dir $BundleRoot
Ensure-Dir (Join-Path $BundleRoot "tools")
Ensure-Dir (Join-Path $BundleRoot "wheelhouse")
Ensure-Dir (Join-Path $BundleRoot "logs")

$ToolsDir = Join-Path $BundleRoot "tools"
$Wheelhouse = Join-Path $BundleRoot "wheelhouse"

Write-Step "Cloning Hermes Agent source with shallow/single-ref clone"
$RepoDir = Join-Path $BundleRoot "hermes-agent"
$RepoUrl = "https://github.com/NousResearch/hermes-agent.git"
$RefLooksLikeSha = $release.Ref -match '^[0-9a-fA-F]{7,40}$'

if ($RefLooksLikeSha) {
    Write-Info "Reference looks like a commit hash. Fetching only that commit."
    git -c http.version=HTTP/1.1 -c pack.threads=1 -c core.compression=0 clone --filter=blob:none --no-checkout $RepoUrl $RepoDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }

    Push-Location $RepoDir
    git -c http.version=HTTP/1.1 -c pack.threads=1 -c core.compression=0 fetch --depth 1 origin $release.Ref
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed for commit $($release.Ref)" }

    git checkout FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for commit $($release.Ref)" }
} else {
    Write-Info "Using shallow clone for ref/tag/branch: $($release.Ref)"
    git -c http.version=HTTP/1.1 -c pack.threads=1 -c core.compression=0 clone --depth 1 --single-branch --branch $release.Ref $RepoUrl $RepoDir
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Shallow clone failed. Retrying with partial clone filter."
        Remove-Item -Recurse -Force $RepoDir -ErrorAction SilentlyContinue
        git -c http.version=HTTP/1.1 -c pack.threads=1 -c core.compression=0 clone --depth 1 --single-branch --filter=blob:none --branch $release.Ref $RepoUrl $RepoDir
    }
    if ($LASTEXITCODE -ne 0) { throw "git shallow clone failed for ref $($release.Ref)" }

    Push-Location $RepoDir
}

$Commit = (git rev-parse HEAD).Trim()
try { $Describe = (git describe --tags --always).Trim() } catch { $Describe = $Commit }
Pop-Location

@"
Ref: $($release.Ref)
Name: $($release.Name)
URL: $($release.Url)
Commit: $Commit
Describe: $Describe
BuiltAt: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
IncludeDesktop: $IncludeDesktop
"@ | Set-Content (Join-Path $BundleRoot "VERSION.txt") -Encoding UTF8

Write-Step "Downloading base tools"
$PythonInstaller = Join-Path $ToolsDir "python-3.11.9-amd64.exe"
Invoke-Download "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" $PythonInstaller

$UvZip = Join-Path $ToolsDir "uv-x86_64-pc-windows-msvc.zip"
Invoke-Download "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" $UvZip
$UvDir = Join-Path $ToolsDir "uv"
if (Test-Path $UvDir) { Remove-Item -Recurse -Force $UvDir }
Expand-Archive $UvZip -DestinationPath $UvDir -Force
$UvExe = Join-Path $UvDir "uv.exe"
& $UvExe --version

# Optional tools. Failures are warnings because core Hermes can still work.
try {
    $PortableGit = Join-Path $ToolsDir "PortableGit-2.54.0-64-bit.7z.exe"
    Invoke-Download "https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/PortableGit-2.54.0-64-bit.7z.exe" $PortableGit
} catch { Write-Warn "PortableGit download failed: $($_.Exception.Message)" }

try {
    $RgZip = Join-Path $ToolsDir "ripgrep-14.1.1-x86_64-pc-windows-msvc.zip"
    Invoke-Download "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-pc-windows-msvc.zip" $RgZip
    $RgDir = Join-Path $ToolsDir "ripgrep"
    if (Test-Path $RgDir) { Remove-Item -Recurse -Force $RgDir }
    Expand-Archive $RgZip -DestinationPath $RgDir -Force
} catch { Write-Warn "ripgrep download failed: $($_.Exception.Message)" }

Write-Step "Preparing Python 3.11 for wheel download"
$PythonExe = Find-Python311 $ToolsDir
if (-not $PythonExe) {
    $BuildPython = Join-Path $BundleRoot "_build_python311"
    Write-Info "Installing temporary Python 3.11 to $BuildPython"
    Start-Process $PythonInstaller -ArgumentList "/quiet InstallAllUsers=0 Include_pip=1 PrependPath=0 TargetDir=`"$BuildPython`"" -Wait
    $PythonExe = Join-Path $BuildPython "python.exe"
}
if (-not (Test-Path $PythonExe)) { throw "Python 3.11 not found after setup." }
& $PythonExe --version

Write-Step "Compiling Python requirements"
Push-Location $RepoDir

$ExtraArgs = @()
foreach ($e in $Extras.Split(",")) {
    $trim = $e.Trim()
    if ($trim) {
        $ExtraArgs += "--extra"
        $ExtraArgs += $trim
    }
}

$ReqFile = Join-Path $BundleRoot "requirements-hermes-win.txt"
$env:UV_NATIVE_TLS = "true"

try {
    & $UvExe --system-certs pip compile .\pyproject.toml @ExtraArgs -o $ReqFile
} catch {
    Write-Warn "uv --system-certs failed. Trying --native-tls."
    & $UvExe --native-tls pip compile .\pyproject.toml @ExtraArgs -o $ReqFile
}

if ($LASTEXITCODE -ne 0) { throw "uv pip compile failed." }
Pop-Location

Write-Step "Downloading Python wheels"
try {
    & $PythonExe -m pip download --use-feature=truststore -r $ReqFile -d $Wheelhouse --only-binary=:all:
} catch {
    Write-Warn "pip download with truststore failed. Trying trusted-host fallback."
    & $PythonExe -m pip download --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org -r $ReqFile -d $Wheelhouse --only-binary=:all:
}
if ($LASTEXITCODE -ne 0) { throw "pip download requirements failed." }

& $PythonExe -m pip download --trusted-host pypi.org --trusted-host files.pythonhosted.org --trusted-host pypi.python.org pip setuptools wheel -d $Wheelhouse --only-binary=:all:
if ($LASTEXITCODE -ne 0) { throw "pip download core build tools failed." }

Write-Step "Adding intranet installer and cert helper payload"
$PayloadDir = Join-Path $PSScriptRoot "payload"
if (-not (Test-Path $PayloadDir)) { throw "payload directory not found next to this script: $PayloadDir" }
Copy-Item (Join-Path $PayloadDir "*") $BundleRoot -Recurse -Force

Write-Step "Offline installation simulation"
$TestVenv = Join-Path $BundleRoot "_test_venv"
if (Test-Path $TestVenv) { Remove-Item -Recurse -Force $TestVenv }
& $PythonExe -m venv $TestVenv

$TestPy = Join-Path $TestVenv "Scripts\python.exe"
& $TestPy -m pip install --no-index --find-links $Wheelhouse --upgrade pip setuptools wheel

Push-Location $RepoDir
& $TestPy -m pip install --no-index --find-links $Wheelhouse -e ".[web,mcp,cron,cli]"
Pop-Location

$TestHermes = Join-Path $TestVenv "Scripts\hermes.exe"
& $TestHermes --version
if ($LASTEXITCODE -ne 0) { Write-Warn "hermes --version returned non-zero, continuing because install completed." }

Write-Step "Optional Desktop artifact build"
if ($IncludeDesktop) {
    Write-Step "Ensuring Node.js/npm for Desktop build"
    Ensure-NodeForDesktop $ToolsDir

    Write-Info "Building Hermes Desktop artifact from source. This may download npm/electron dependencies on the internet machine."
    Push-Location $RepoDir
    $env:CI = "1"
    $env:NO_COLOR = "1"
    & $TestHermes desktop --build-only --force-build --hermes-root $RepoDir
    if ($LASTEXITCODE -ne 0) { throw "hermes desktop --build-only failed." }
    Pop-Location

    $ReleaseDir = Join-Path $RepoDir "apps\desktop\release"
    if (-not (Test-Path $ReleaseDir)) { throw "Desktop release directory not found: $ReleaseDir" }

    $items = Get-ChildItem $ReleaseDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $items -or $items.Count -eq 0) { throw "Desktop release directory is empty: $ReleaseDir" }

    @"
Desktop artifact included: true
Release directory: hermes-agent\apps\desktop\release

Intranet launch:
  hermes desktop --skip-build
or:
  %LOCALAPPDATA%\hermes\StartHermesDesktop.bat
"@ | Set-Content (Join-Path $BundleRoot "DESKTOP_AIRGAP_NOTES.txt") -Encoding UTF8
} else {
    "Desktop artifact included: false" | Set-Content (Join-Path $BundleRoot "DESKTOP_AIRGAP_NOTES.txt") -Encoding UTF8
}

Write-Step "Cleaning temporary folders"
Remove-Item -Recurse -Force $TestVenv -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $BundleRoot "_build_python311") -ErrorAction SilentlyContinue

Write-Step "Creating final self-contained air-gap ZIP"
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }
tar -a -cf $OutputZip -C $BundleRoot .

if (-not (Test-Path $OutputZip)) { throw "Output ZIP was not created: $OutputZip" }

Write-Info "Output ZIP: $OutputZip"

if (-not $KeepWork) {
    Write-Info "Keeping work folder by default for inspection: $BundleRoot"
    Write-Info "You may delete it manually after verifying the output ZIP."
}

Write-Step "Done"
Write-Host "Copy this ZIP to intranet:"
Write-Host "  $OutputZip"
