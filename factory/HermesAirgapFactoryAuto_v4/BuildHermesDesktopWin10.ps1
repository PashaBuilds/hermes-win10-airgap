# HermesAirgapFactoryAuto v4.8 - MINIMAL Windows 10 Desktop bundle (Internet PC side)
#
# Output: C:\H4\output\HermesAirgapBundle_<tag>_Win10_Desktop.zip  (~0.9 GB expected)
#   app\                      unpacked Electron Desktop ("Hermes Agent.exe", no MSIX)
#                             with ONE runtime in app\resources\agent-payload
#   app-manifest.tsv          SHA256 of every app file (installer verifies all)
#   InstallOrUpdateHermesAirgapped.bat  Auto CleanVenv | Pilot   (same legacy command)
#   RollbackHermesAirgapped.bat
#
# -VersionRef latest (default) resolves the newest stable GitHub release; the
# checkout is cloned into C:\H4\jobs\<tag>_Slim\src when missing. The Desktop
# download cache is shared across versions (C:\H4\desktop-cache, or the newest
# existing jobs\*\desktop-cache) so Electron/Python/tools are not re-downloaded.
# Upstream source is NOT modified: the official desktop preparation runs with an
# external worker that only selects Python extras (web+mcp) and a tool allowlist.
# Packaging runs the official desktop.py (+ "--dir"). Upstream always passes "--win msix", so an
# MSIX is still produced as a by-product in release\; it is NOT packaged and is removed next run.
[CmdletBinding()]
param(
    [string]$VersionRef = 'latest',
    [string]$FactoryRoot = 'C:\H4',
    [switch]$PackageOnly,
    [string]$CaFile = '',
    [string]$HostPython = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FactoryVersion = '4.8.1'
$ExeName = 'Hermes Agent.exe'
# Keep in sync with helpers\desktop_minimal_worker.py (ALLOWLIST).
$ToolAllowlist = @('python', 'uv', 'node', 'npm', 'ffmpeg', 'ripgrep', 'git', 'chromium', 'agent-browser')
$ToolForbidden = @('llamacpp-', 'cua-driver', 'gh-', 'bws-', 'whispercpp', 'iron-proxy')

function Say([string]$s) { Write-Host "[H4.8] $s" }
function Good([string]$s) { Write-Host "[OK] $s" -ForegroundColor Green }
function Warn([string]$s) { Write-Warning $s }
function Require([bool]$ok, [string]$message) { if (-not $ok) { throw $message } }
function Mk([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function ShortRoot([string]$p) {
    $full = [IO.Path]::GetFullPath($p).TrimEnd('\')
    Require ($full.Length -le 24) "Windows native staging needs a SHORT factory root (<=24 chars). Given: $full"
    Require ($full -match '^[A-Za-z]:\\') 'Use an absolute local Windows drive path; avoid junctions, UNC and network shares.'
    return $full
}
function Run([string]$exe, [string[]]$argv, [string]$cwd = '') {
    Say ("$exe " + ($argv -join ' '))
    $saved = (Get-Location).Path
    if ($cwd) { Set-Location -LiteralPath $cwd }
    try {
        & $exe @argv | Out-Host
        $exit = $LASTEXITCODE
        if ($null -eq $exit -or $exit -ne 0) { throw "Command failed (exit $exit): $exe $($argv -join ' ')" }
    } finally { if ($cwd) { Set-Location -LiteralPath $saved } }
}
function Exec([string]$exe, [string[]]$argv, [string]$cwd = '') {
    $saved = (Get-Location).Path
    if ($cwd) { Set-Location -LiteralPath $cwd }
    try {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $all = @(& $exe @argv 2>&1) } finally { $ErrorActionPreference = $old }
        $code = $LASTEXITCODE
        $stdout = @($all | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        if ($code -ne 0) { throw "Command failed: $exe $($argv -join ' ') :: $(($all | ForEach-Object { "$_" }) -join ' ')" }
        return ($stdout -join "`n").Trim()
    } finally { if ($cwd) { Set-Location -LiteralPath $saved } }
}
function Download([string]$url, [string]$destination) {
    Mk (Split-Path $destination -Parent)
    if ((Test-Path $destination) -and (Get-Item $destination).Length -gt 0) { Say "Using cached $destination"; return }
    $part = "$destination.partial"
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    Say "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 1200 -Headers @{'User-Agent' = 'HermesAirgapFactoryAuto/4.8' }
    Require ((Get-Item $part).Length -gt 1000) "Download unexpectedly small: $url"
    Move-Item -LiteralPath $part -Destination $destination -Force
}
function PythonChoice([string]$explicit) {
    if ($explicit) {
        Require (Test-Path $explicit) "Host Python not found: $explicit"
        return (Get-Item $explicit).FullName
    }
    foreach ($minor in @('3.14', '3.13', '3.12', '3.11')) {
        try {
            $result = & py "-$minor" -c 'import sys;print(sys.executable)' 2>$null
            if ($LASTEXITCODE -eq 0 -and $result -and (Test-Path "$result")) { return ([string]$result).Trim() }
        } catch {}
    }
    try {
        $result = & python -c 'import sys;print(sys.executable if sys.version_info >= (3,11) else str())' 2>$null
        if ($LASTEXITCODE -eq 0 -and $result -and (Test-Path "$result")) { return ([string]$result).Trim() }
    } catch {}
    throw 'Python >=3.11 is required as a factory bootstrap. Hermes PM ships the pinned Python 3.14 runtime itself.'
}
function WriteUtf8([string]$file, [string]$content) {
    Mk (Split-Path -Path $file -Parent)
    [IO.File]::WriteAllText($file, $content, (New-Object Text.UTF8Encoding($false)))
}
function GetNode([string]$root) {
    # Same pinned portable Node as v4.6 (tools\node-selected.txt); no new download when cached.
    $choice = Join-Path $root 'tools\node-selected.txt'
    Require (Test-Path $choice) "Portable Node pin not found ($choice). Run the v4.6 factory once first."
    $nodeVersion = (Get-Content $choice -Raw).Trim()
    Require ($nodeVersion -match '^v24\.\d+\.\d+$') "Invalid persisted Node 24 pin in $choice"
    $zipName = "node-$nodeVersion-win-x64.zip"
    $zip = Join-Path $root ("tools\" + $zipName)
    Download "https://nodejs.org/dist/$nodeVersion/$zipName" $zip
    $shas = Join-Path $root ("tools\SHASUMS256-$nodeVersion.txt")
    Download "https://nodejs.org/dist/$nodeVersion/SHASUMS256.txt" $shas
    $escaped = [regex]::Escape($zipName)
    $matchLine = @(Get-Content $shas | Where-Object { $_ -match "^([0-9a-fA-F]{64})\s+$escaped`$" })
    Require ($matchLine.Count -eq 1) "Official Node SHASUMS missing an unambiguous hash for $zipName"
    $expected = ($matchLine[0] -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    Require ($expected -eq $actual) "Node ZIP failed official SHA256 check: $zipName"
    $nodeBin = Join-Path $root ("tools\node-$nodeVersion-win-x64")
    if (-not (Test-Path (Join-Path $nodeBin 'node.exe'))) { Expand-Archive -Path $zip -DestinationPath (Join-Path $root 'tools') -Force }
    Require (Test-Path (Join-Path $nodeBin 'node.exe')) 'node.exe missing after extraction'
    $env:Path = "$nodeBin;$env:Path"
    $npmPrefix = Join-Path $root 'tools\npm-11.18.0'
    if (Test-Path (Join-Path $npmPrefix 'node_modules\npm\bin\npm-cli.js')) { $env:Path = "$npmPrefix;$env:Path" }
    Say "Portable Node $nodeVersion"
    return $nodeBin
}
function Remove-Tree([string]$p) {
    # PM seals payload files read-only; Python's shutil.rmtree cannot delete those on
    # Windows (WinError 5). Clear the attribute and remove stale build output first.
    if (-not (Test-Path -LiteralPath $p)) { return }
    Say "Removing stale build output: $p"
    try { & attrib.exe -R "$p\*" /S /D | Out-Null } catch { }
    try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
    catch {
        $empty = Join-Path $env:TEMP ('empty_' + [guid]::NewGuid().ToString('N'))
        Mk $empty
        & robocopy.exe $empty $p /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    }
    Require (-not (Test-Path -LiteralPath $p)) "Could not remove $p. Close Explorer windows or programs started from it (e.g. Hermes Agent.exe) and retry."
}
$Hasher = [Security.Cryptography.SHA256]::Create()
function Sha([string]$path) {
    $s = [IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString($Hasher.ComputeHash($s))).Replace('-', '').ToLowerInvariant() } finally { $s.Dispose() }
}
function DirMB([string]$p) { [math]::Round(((Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB, 1) }

function Assert-MinimalApp([string]$unpacked, [string]$root, [string]$tag) {
    Require (Test-Path -LiteralPath (Join-Path $unpacked $ExeName) -PathType Leaf) "$ExeName missing in $unpacked"
    $agent = Join-Path $unpacked 'resources\agent-payload'
    foreach ($name in @('manifest.json', 'bin\hermes.exe', 'tools\facts.json', 'venv', 'pm-runtime\pm-runtime.json', 'enabled-features.json', 'hermes-agent\install-stamp.json')) {
        Require (Test-Path -LiteralPath (Join-Path $agent $name)) "agent-payload missing $name"
    }
    $toolDirs = @(Get-ChildItem -LiteralPath (Join-Path $agent 'tools') -Directory | Where-Object { -not $_.Name.StartsWith('.') })
    $report = [ordered]@{}
    foreach ($d in $toolDirs) {
        foreach ($bad in $ToolForbidden) { Require (-not $d.Name.StartsWith($bad, [StringComparison]::OrdinalIgnoreCase)) "Excluded tool still present: $($d.Name). The allowlist was not applied." }
        $report[$d.Name] = DirMB $d.FullName
    }
    foreach ($want in $ToolAllowlist) {
        if ($want -eq 'uv' -or $want -eq 'python') { continue }
        Require (@($toolDirs | Where-Object { $_.Name.StartsWith($want + '-', [StringComparison]::OrdinalIgnoreCase) }).Count -ge 1) "Expected tool missing from payload: $want"
    }
    $saved = @{ H = $env:HERMES_HOME; P = $env:PYTHONPATH; PH = $env:PYTHONHOME }
    try {
        $env:HERMES_HOME = Join-Path $root 'test-home-desktop'; Mk $env:HERMES_HOME
        $env:PYTHONDONTWRITEBYTECODE = '1'   # the smoke test must not add files to what gets shipped
        Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
        Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
        $ver = Exec (Join-Path $agent 'bin\hermes.exe') @('--version')
        Say "Bundled CLI: $(@($ver -split "`n" | Where-Object { $_ -match 'Hermes Agent' } | Select-Object -First 1))"
        Require ($ver -match [regex]::Escape($tag.TrimStart('v'))) "Bundled hermes --version does not report $tag"
    } finally { $env:HERMES_HOME = $saved.H; $env:PYTHONPATH = $saved.P; $env:PYTHONHOME = $saved.PH; Remove-Item Env:PYTHONDONTWRITEBYTECODE -ErrorAction SilentlyContinue }
    return $report
}

$oldEnv = @{}
foreach ($key in @('TEMP', 'TMP', 'UV_NATIVE_TLS', 'UV_SYSTEM_CERTS', 'SSL_CERT_FILE', 'NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS', 'npm_config_cafile', 'PYTHONPATH', 'PYTHONHOME', 'PATH', 'RELEASE_CLAIM_TAG', 'RELEASE_CLAIM_OBJECT')) { $oldEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
$transcript = $false
$exitCode = 1
try {
    Require ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'Windows x64 only.'
    $FactoryRoot = ShortRoot $FactoryRoot
    Mk (Join-Path $FactoryRoot 'logs')
    $log = Join-Path $FactoryRoot ('logs\desktop_win10_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
    Start-Transcript -Path $log | Out-Null; $transcript = $true
    Say "Factory v$FactoryVersion minimal Windows 10 Desktop, PowerShell $($PSVersionTable.PSVersion), root $FactoryRoot"
    if ($CaFile) {
        Require (Test-Path $CaFile) "CA file missing: $CaFile"
        $env:SSL_CERT_FILE = $CaFile; $env:NODE_EXTRA_CA_CERTS = $CaFile; $env:npm_config_cafile = $CaFile
    }
    foreach ($unsafe in @('UV_INSECURE_HOST', 'PIP_TRUSTED_HOST')) {
        Require (-not [Environment]::GetEnvironmentVariable($unsafe, 'Process')) "Unsafe TLS bypass environment variable detected: $unsafe."
    }
    $env:UV_NATIVE_TLS = 'true'; $env:UV_SYSTEM_CERTS = 'true'; $env:NODE_OPTIONS = '--use-system-ca'
    Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
    Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
    Mk (Join-Path $FactoryRoot 'temp'); $env:TEMP = Join-Path $FactoryRoot 'temp'; $env:TMP = $env:TEMP

    if ($VersionRef -eq 'latest') {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/NousResearch/hermes-agent/releases/latest' -Headers @{ 'User-Agent' = 'HermesAirgapFactoryAuto/4.8' } -TimeoutSec 150
        Require ((-not $rel.draft) -and (-not $rel.prerelease)) 'GitHub latest release is not a stable published release.'
        $VersionRef = [string]$rel.tag_name
        Say "Latest stable Hermes release: $VersionRef (published $($rel.published_at))"
    }
    Require ($VersionRef -match '^v[0-9]+\.[0-9]+\.[0-9]+$') "Stable tag expected, got '$VersionRef'"
    $work = Join-Path $FactoryRoot ("jobs\" + $VersionRef + '_Slim')
    $repo = Join-Path $work 'src'
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
        Require (-not $PackageOnly) "No checkout for $VersionRef; -PackageOnly needs a previous build."
        Mk $work
        Say "Cloning $VersionRef"
        Run 'git' @('-c', 'core.longpaths=true', 'clone', '--depth', '1', '--single-branch', '--branch', $VersionRef, 'https://github.com/NousResearch/hermes-agent.git', $repo)
    }
    $tagSha = Exec 'git' @('rev-parse', 'HEAD') $repo
    $refSha = Exec 'git' @('rev-parse', "$VersionRef^{commit}") $repo
    Require ($tagSha -eq $refSha) "Checkout HEAD $tagSha is not $VersionRef ($refSha)."
    $status = Exec 'git' @('status', '--porcelain', '--untracked-files=no') $repo
    Require (-not $status) "Source checkout is not clean: $status"
    Say "Pinned commit: $tagSha"
    $unpacked = Join-Path $repo 'apps\desktop\release\win-unpacked'

    if (-not $PackageOnly) {
        $python = PythonChoice $HostPython
        Say "Bootstrap Python: $python"
        $null = GetNode $FactoryRoot
        # Official stable tag builds require the published annotated rc.N-vX.Y.Z claim.
        $escaped = [regex]::Escape($VersionRef)
        $raw = Exec 'git' @('ls-remote', '--tags', 'origin', "refs/tags/rc.*-$VersionRef") $repo
        $claims = @()
        foreach ($line in ($raw -split "`n")) {
            if ($line -match "^([0-9a-f]{40})\s+refs/tags/(rc\.(\d+)-$escaped)$") { $claims += [pscustomobject]@{ Tag = $Matches[2]; N = [int]$Matches[3] } }
        }
        Require ($claims.Count -gt 0) 'Official Desktop stable builder requires an rc.N-vX.Y.Z claim tag; none found.'
        $claim = $claims | Sort-Object N -Descending | Select-Object -First 1
        Run 'git' @('fetch', '--depth', '1', 'origin', "refs/tags/$($claim.Tag):refs/tags/$($claim.Tag)") $repo
        $obj = Exec 'git' @('rev-parse', "refs/tags/$($claim.Tag)") $repo
        Require ((Exec 'git' @('cat-file', '-t', $obj) $repo) -eq 'tag') 'Claim ref is not an annotated Git tag'
        $env:RELEASE_CLAIM_TAG = $claim.Tag; $env:RELEASE_CLAIM_OBJECT = $obj
        Say "Claim $($claim.Tag) ($obj)"

        $driver = Join-Path $PSScriptRoot 'helpers\desktop_prepare_driver.py'
        $worker = Join-Path $PSScriptRoot 'helpers\desktop_minimal_worker.py'
        Require (Test-Path -LiteralPath $driver) "Missing $driver"
        Require (Test-Path -LiteralPath $worker) "Missing $worker"
        $deskWork = Join-Path $work 'desktop-work'
        $prepared = Join-Path $deskWork 'prepared.json'
        # Always re-prepare, and clear stale (read-only, sealed) outputs of earlier builds.
        if (Test-Path -LiteralPath $prepared) { Remove-Item -LiteralPath $prepared -Force }
        Remove-Tree (Join-Path $repo 'apps\desktop\build\agent-payload')
        Remove-Tree (Join-Path $repo 'apps\desktop\release')
        $cacheDir = Join-Path $FactoryRoot 'desktop-cache'
        if (-not (Test-Path -LiteralPath $cacheDir)) {
            $prev = @(Get-ChildItem -LiteralPath (Join-Path $FactoryRoot 'jobs') -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'desktop-cache') -ErrorAction SilentlyContinue } |
                    Sort-Object LastWriteTime -Descending)
            if ($prev.Count -gt 0) { $cacheDir = $prev[0].FullName }
        }
        Say "Desktop download cache: $cacheDir (shared across versions)"
        Say 'Step 1/3: official Desktop preparation with minimal worker (web+mcp, tool allowlist)'
        Run $python @('-I', '-S', '-B', $driver, $repo, $worker, '--tag', $VersionRef, '--variant', 'bundled', '--repo', $repo,
            '--work', $deskWork, '--cache', $cacheDir, '--prepare-only') $repo
        Require (Test-Path -LiteralPath $prepared) 'Desktop prepared.json missing after preparation'
        Say 'Step 2/3: official Desktop packaging (win-unpacked is used; the MSIX by-product is ignored)'
        Run $python @('-I', '-S', '-B', (Join-Path $repo 'scripts\bundles\desktop.py'), '--prepared', $prepared, '--', '--dir') $repo
        $status = Exec 'git' @('status', '--porcelain', '--untracked-files=no') $repo
        Require (-not $status) "Source checkout changed during the build: $status"
    } else {
        Say 'Package-only: reusing the existing win-unpacked (it must already be minimal).'
    }

    Say 'Step 3/3: verifying and packaging'
    $toolReport = Assert-MinimalApp $unpacked $work $VersionRef
    Good 'win-unpacked is minimal and its bundled CLI runs'
    foreach ($k in $toolReport.Keys) { Say ('  tool {0,-36} {1,8} MB' -f $k, $toolReport[$k]) }

    $name = "HermesAirgapBundle_${VersionRef}_Win10_Desktop"
    $pkgRoot = Join-Path $FactoryRoot 'pd'
    $pkg = Join-Path $pkgRoot $name
    if (Test-Path -LiteralPath $pkg) { Remove-Item -LiteralPath $pkg -Recurse -Force }
    Mk $pkg
    $app = Join-Path $pkg 'app'
    & robocopy.exe $unpacked $app /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    Require ($LASTEXITCODE -le 7) "robocopy failed (exit $LASTEXITCODE)"
    Say 'Hashing every app file for the offline manifest...'
    $files = @(Get-ChildItem -LiteralPath $app -Recurse -File -Force)
    $lines = New-Object System.Collections.Generic.List[string]
    $total = [long]0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($app.Length + 1)
        # -cnotmatch: case-INsensitive matching on .NET Framework with tr-TR culture folds 'I' to
        # dotless U+0131, which falls outside the ASCII range (false positive on LICENSE.*).
        Require ($rel -cnotmatch '[^\x20-\x7E]') "Non-ASCII file name would not survive tar/Explorer: $rel"
        $lines.Add("$(Sha $f.FullName)`t$($f.Length)`t$rel") | Out-Null
        $total += $f.Length
    }
    $manifest = Join-Path $pkg 'app-manifest.tsv'
    WriteUtf8 $manifest (($lines | Sort-Object) -join "`r`n")
    foreach ($t in @('DesktopInstallOrUpdateHermesAirgapped.ps1', 'DesktopInstallOrUpdateHermesAirgapped.bat', 'DesktopRollbackHermesAirgapped.bat', 'README_KURULUM.txt')) {
        $src = Join-Path $PSScriptRoot ('templates\' + $t)
        Require (Test-Path -LiteralPath $src) "Template missing: $src"
        Copy-Item -LiteralPath $src -Destination (Join-Path $pkg ($t -replace '^Desktop', '')) -Force
    }
    $stamp = [IO.File]::ReadAllText((Join-Path $app 'resources\agent-payload\hermes-agent\install-stamp.json')) | ConvertFrom-Json
    $stampCommit = if (@($stamp.PSObject.Properties.Name) -contains 'commit') { [string]$stamp.commit } else { '' }
    $meta = [ordered]@{
        schema = 5; release = $VersionRef; commit = $tagSha; profile = 'Minimal'; extras = @('web', 'mcp'); tools = $ToolAllowlist
        installContract = 'legacy-auto-cleanvenv-win10-desktop'; arch = 'win32-x64'; exe = $ExeName
        appFiles = $files.Count; appBytes = $total; manifestSha256 = (Sha $manifest); stampCommit = $stampCommit
        factory = $FactoryVersion; createdUtc = [DateTime]::UtcNow.ToString('o')
        security = 'No CA/private secrets, no TLS bypass, no source edits in shipped payload'
    }
    WriteUtf8 (Join-Path $pkg 'BUNDLE.json') ($meta | ConvertTo-Json -Depth 5)

    $outputs = Join-Path $FactoryRoot 'output'; Mk $outputs
    $zip = Join-Path $outputs ($name + '.zip')
    $pending = Join-Path $outputs ('.pending_' + $name + '.zip')
    if (Test-Path $pending) { Remove-Item -LiteralPath $pending -Force }
    $tar = (Get-Command tar.exe -ErrorAction Stop).Source
    Run $tar @('-a', '-cf', $pending, '-C', $pkgRoot, $name)
    if (Test-Path $zip) {
        $prev = Join-Path $outputs ('.previous_' + (Get-Date -Format 'yyyyMMddHHmmss') + '_' + $name + '.zip')
        Move-Item -LiteralPath $zip -Destination $prev
        Say "Previous ZIP kept: $prev"
    }
    Move-Item -LiteralPath $pending -Destination $zip
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    WriteUtf8 "$zip.sha256" "$sha  $name.zip`r`n"
    $zipMB = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
    $report = [ordered]@{ factory = $FactoryVersion; release = $VersionRef; commit = $tagSha; zip = $zip; zipMB = $zipMB; sha256 = $sha
        appFiles = $files.Count; appMB = [math]::Round($total / 1MB, 1); tools = $toolReport; log = $log; createdUtc = [DateTime]::UtcNow.ToString('o') }
    WriteUtf8 (Join-Path $work 'result-desktop-win10.json') ($report | ConvertTo-Json -Depth 5)
    Write-Host ''
    Good "Minimal Windows 10 Desktop bundle ready"
    Write-Host "  ZIP    : $zip"
    Write-Host "  Size   : $zipMB MB (app unpacked: $([math]::Round($total / 1MB, 1)) MB, $($files.Count) files)"
    Write-Host "  SHA256 : $sha"
    $exitCode = 0
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
} finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch {} }
    foreach ($key in $oldEnv.Keys) { [Environment]::SetEnvironmentVariable($key, $oldEnv[$key], 'Process') }
    $Hasher.Dispose()
}
exit $exitCode
