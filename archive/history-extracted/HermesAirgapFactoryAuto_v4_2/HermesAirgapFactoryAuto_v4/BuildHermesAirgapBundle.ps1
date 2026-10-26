# HermesAirgapFactoryAuto v4.2 - Windows x64 / PowerShell 5.1+
# Standalone native offline payload, optional official bundled Desktop.
# No implicit TLS bypass, no legacy pip-wheelhouse, no global Python/Node installs.
[CmdletBinding()]
param(
    [string]$VersionRef = 'latest',
    [string]$FactoryRoot = 'C:\H4',
    [Alias('Profile')][ValidateSet('Slim','Full')][string]$HermesProfile = 'Slim',
    [ValidateSet('bundled','light')][string]$DesktopVariant = 'bundled',
    [switch]$NoDesktop,
    [switch]$Fresh,
    [string]$CaFile = '',
    [string]$HostPython = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$RunStarted = Get-Date

function Say([string]$s) { Write-Host "[H4] $s" }
function Good([string]$s) { Write-Host "[OK] $s" -ForegroundColor Green }
function Warn([string]$s) { Write-Warning $s }
function Require([bool]$ok,[string]$message) { if (-not $ok) { throw $message } }
function Mk([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function ShortRoot([string]$p) {
    $full=[IO.Path]::GetFullPath($p).TrimEnd('\')
    Require ($full.Length -le 24) "Windows native staging needs a SHORT factory root (<=24 chars). Given: $full"
    Require ($full -match '^[A-Za-z]:\\') 'Use an absolute local Windows drive path; avoid junctions, UNC and network shares.'
    return $full
}
function Run([string]$exe,[string[]]$argv,[string]$cwd='') {
    Say ("$exe " + ($argv -join ' '))
    $saved=(Get-Location).Path
    if ($cwd) { Set-Location -LiteralPath $cwd }
    try {
        & $exe @argv
        $exit=$LASTEXITCODE
        if ($null -eq $exit -or $exit -ne 0) { throw "Command failed (exit $exit): $exe $($argv -join ' ')" }
    } finally { if ($cwd) { Set-Location -LiteralPath $saved } }
}
function Exec([string]$exe,[string[]]$argv,[string]$cwd='') {
    $saved=(Get-Location).Path
    if ($cwd) { Set-Location -LiteralPath $cwd }
    try {
        $out = & $exe @argv 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Command failed: $exe $($argv -join ' ') :: $out" }
        return (($out | Out-String).Trim())
    } finally { if ($cwd) { Set-Location -LiteralPath $saved } }
}
function Download([string]$url,[string]$destination) {
    Mk (Split-Path $destination -Parent)
    if ((Test-Path $destination) -and (Get-Item $destination).Length -gt 0) { Say "Using cached $destination"; return }
    $part = "$destination.partial"
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    Say "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 1200 -Headers @{'User-Agent'='HermesAirgapFactoryAuto/4.2'}
    Require ((Get-Item $part).Length -gt 1000) "Download unexpectedly small: $url"
    Move-Item -LiteralPath $part -Destination $destination -Force
}
function PatchOnce([string]$s,[string]$old,[string]$new,[string]$label) {
    $count=([regex]::Matches($s,[regex]::Escape($old))).Count
    if ($count -ne 1) { throw "Hermes changed ${label}; expected 1 signature, saw $count. v4 patch needs review; source not modified." }
    return $s.Replace($old,$new)
}
function PythonChoice([string]$explicit) {
    if ($explicit) {
        Require (Test-Path $explicit) "Host Python not found: $explicit"
        return (Get-Item $explicit).FullName
    }
    foreach($minor in @('3.14','3.13','3.12','3.11')) {
        try {
            $result = & py "-$minor" -c 'import sys;print(sys.executable)' 2>$null
            if ($LASTEXITCODE -eq 0 -and $result -and (Test-Path "$result")) { return ([string]$result).Trim() }
        } catch {}
    }
    try {
        $result = & python -c 'import sys;print(sys.executable if sys.version_info >= (3,11) else "")' 2>$null
        if ($LASTEXITCODE -eq 0 -and $result -and (Test-Path "$result")) { return ([string]$result).Trim() }
    } catch {}
    throw 'Python >=3.11 is required as a factory bootstrap. Hermes PM ships the pinned Python 3.14 runtime itself.'
}
function WriteUtf8([string]$file,[string]$content) {
    Mk (Split-Path -Path $file -Parent)
    [IO.File]::WriteAllText($file,$content,(New-Object Text.UTF8Encoding($false)))
}
function ToSafeTag([string]$value) {
    Require ($value -match '^v[0-9]+\.[0-9]+\.[0-9]+$') "Only stable SemVer tags supported in v4, got '$value'"
    return $value
}
function GetNode([string]$root) {
    $choice=Join-Path $root 'tools\node-selected.txt'
    $nodeVersion=''
    if (Test-Path $choice) {
        $nodeVersion=(Get-Content $choice -Raw).Trim()
        Require ($nodeVersion -match '^v24\.\d+\.\d+$') "Invalid persisted Node 24 pin in $choice"
        Say "Reusing pinned portable Node $nodeVersion"
    } else {
        Say 'Checking Node 24 index'
        try {
            $idx=Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 100
            $row=$idx | Where-Object { $_.version -match '^v24\.' -and $_.files -contains 'win-x64-zip' } | Select-Object -First 1
            Require ($null -ne $row) 'Node 24 Windows ZIP not found'
            $nodeVersion=$row.version
        } catch {
            Warn "Node index unavailable: $($_.Exception.Message)"
            $nodeVersion='v24.16.0'
        }
    }
    $zipName="node-$nodeVersion-win-x64.zip"
    $zip=Join-Path $root ("tools\"+$zipName)
    Download "https://nodejs.org/dist/$nodeVersion/$zipName" $zip
    $shas=Join-Path $root ("tools\SHASUMS256-$nodeVersion.txt")
    Download "https://nodejs.org/dist/$nodeVersion/SHASUMS256.txt" $shas
    $escaped=[regex]::Escape($zipName)
    $matchLine=@(Get-Content $shas | Where-Object { $_ -match "^([0-9a-fA-F]{64})\s+$escaped`$" })
    Require ($matchLine.Count -eq 1) "Official Node SHASUMS missing an unambiguous hash for $zipName"
    $expected=($matchLine[0] -split '\s+')[0].ToLowerInvariant()
    $actual=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    Require ($expected -eq $actual) "Node ZIP failed official SHA256 check: $zipName"
    Good 'Portable Node official SHA256 verified'
    $nodeBin=Join-Path $root ("tools\node-$nodeVersion-win-x64")
    if (-not (Test-Path (Join-Path $nodeBin 'node.exe'))) { Expand-Archive -Path $zip -DestinationPath (Join-Path $root 'tools') -Force }
    Require (Test-Path (Join-Path $nodeBin 'node.exe')) 'node.exe missing after extraction'
    $env:Path="$nodeBin;$env:Path"
    $node=Exec (Join-Path $nodeBin 'node.exe') @('--version')
    Say "Portable Node: $node"
    $npmVer=Exec (Join-Path $nodeBin 'npm.cmd') @('--version')
    $rootPackage=Join-Path $script:Repo 'package.json'
    $engines=(Get-Content $rootPackage -Raw | ConvertFrom-Json).engines
    Require (($engines.npm -eq '<11.10.0 || >=11.17.0')) "Hermes npm engine policy changed: $($engines.npm). Review v4 compatibility before proceeding."
    $npmVersion=[version]$npmVer
    if ($npmVersion -ge [version]'11.10.0' -and $npmVersion -lt [version]'11.17.0') {
        Say "Bundled npm $npmVer is in the Hermes excluded range. Installing a portable compatible npm."
        $prefix=Join-Path $root 'tools\npm-11.18.0'
        $cli=Join-Path $prefix 'node_modules\npm\bin\npm-cli.js'
        if (-not (Test-Path $cli)) { Run (Join-Path $nodeBin 'npm.cmd') @('install','-g','npm@11.18.0','--prefix',$prefix,'--no-audit','--no-fund') }
        $env:Path="$prefix;$env:Path"
        Require (Test-Path $cli) 'Compatible npm CLI was not installed'
    }
    if (-not (Test-Path $choice)) { WriteUtf8 $choice "$nodeVersion`n" }
    return $nodeBin
}
function PatchSource([string]$repo,[string]$HermesProfile,[string]$backupDir) {
    $native=Join-Path $repo 'scripts\bundles\native.py'
    $bytecode=Join-Path $repo 'scripts\bundles\bytecode.py'
    $launchers=Join-Path $repo 'scripts\build\launchers.py'
    $files=@($native,$bytecode,$launchers)
    $content=@{}
    foreach($file in $files) { $content[$file]=[IO.File]::ReadAllText($file) }
    if ($HermesProfile -eq 'Slim') {
        $content[$native]=PatchOnce $content[$native] 'env=env, cache=cache, all_extras=True, sealed=True, explicit=True,' 'env=env, cache=cache, extras=("web", "mcp"), all_extras=False, sealed=True, explicit=True,' 'native extra policy'
    }
    $content[$native]=PatchOnce $content[$native] 'tempfile.TemporaryDirectory(prefix=".build-", dir=out)' 'tempfile.TemporaryDirectory(prefix=".build-", dir=out, ignore_cleanup_errors=True)' 'native cleanup'
    $content[$bytecode]=PatchOnce $content[$bytecode] 'def _uncovered(root: Path) -> tuple[list[Path], int]:' 'def _uncovered(root: Path, cache_tag: str) -> tuple[list[Path], int]:' 'bytecode coverage signature'
    $content[$bytecode]=PatchOnce $content[$bytecode] 'if Path(cache_from_source(path)).exists():' 'if (path.parent / "__pycache__" / f"{path.stem}.{cache_tag}.pyc").is_file():' 'bytecode interpreter cache tag'
    $tagCode=@'
    cache_tag = subprocess.check_output(
        [str(python), "-I", "-S", "-c", "import sys; print(sys.implementation.cache_tag)"],
        text=True,
    ).strip()
    total = 0
'@
    $content[$bytecode]=PatchOnce $content[$bytecode] '    total = 0' $tagCode 'bytecode tag probe'
    $content[$bytecode]=PatchOnce $content[$bytecode] 'missing, _unparseable = _uncovered(source_root)' 'missing, _unparseable = _uncovered(source_root, cache_tag)' 'bytecode coverage invocation'
    $content[$launchers]=PatchOnce $content[$launchers] 'run([str(root / python), str(Path(__file__).with_name("mint_launchers.py"))], env=env, check=True)' 'env.pop("PYTHONPATH", None); env.pop("PYTHONHOME", None); run([str(root / python), str(Path(__file__).with_name("mint_launchers.py"))], env=env, check=True)' 'launcher isolated environment'
    # Preflight every signature before writing any file. Backups are only for interruption recovery.
    Mk $backupDir
    $map=@{}
    foreach($file in $files) {
        $dest=Join-Path $backupDir ([IO.Path]::GetFileName($file))
        [IO.File]::WriteAllBytes($dest,[IO.File]::ReadAllBytes($file))
        $map[$file]=$dest
    }
    foreach($file in $files) { WriteUtf8 $file $content[$file] }
    return $map
}
function RestoreSource([hashtable]$map) {
    foreach($entry in $map.GetEnumerator()) { [IO.File]::WriteAllBytes([string]$entry.Key,[IO.File]::ReadAllBytes([string]$entry.Value)) }
}
function NativeStage([string]$python,[string]$repo,[string]$out,[string]$cache,[string]$HermesProfile,[string]$root) {
    $runner=Join-Path $root 'tools\finish-prepared.py'
    $runnerText=@'
import sys
from pathlib import Path
repo = Path(sys.argv[2])
sys.path.insert(0, str(repo))
from scripts.bundles.native import finish_native
raise SystemExit(finish_native(Path(sys.argv[1]), {}))
'@
    WriteUtf8 $runner $runnerText
    $prepared="$out.prepared.json"
    if ((Test-Path $prepared) -and -not (Test-Path (Join-Path $out 'manifest.json'))) {
        Say 'Detected complete prepared native payload; retrying assembly without downloads.'
        try {
            Run $python @('-I','-S','-B',$runner,$prepared,$repo) $repo
            if (Test-Path (Join-Path $out 'manifest.json')) { return }
        } catch { Warn "Resume assembly failed, clean preparation will be attempted: $($_.Exception.Message)" }
    }
    if (Test-Path (Join-Path $out 'manifest.json')) { Say 'Native manifest already exists; validating, not rebuilding.'; return }
    # Hermes stage.py builds Web from a temporary Git snapshot, but the
    # @rolldown/plugin-babel resolver uses the original checkout as its
    # babel-virtual-resolve-base.js location.  Preparing only the temporary
    # snapshot leaves babel-plugin-react-compiler invisible to that resolver.
    # npm ci is locked to upstream package-lock.json; --reuse skips a
    # completed workspace install on subsequent retries.
    Say 'Preflighting original-checkout Node dependencies (Web/Babel resolver base)'
    $nodeExecutable=(Get-Command 'node.exe' -ErrorAction Stop).Source
    Run $nodeExecutable @('scripts/build/node-deps.mjs','--source',$repo,'--workspace','ui-tui','--workspace','web','--reuse') $repo
    # IMPORTANT: Vite/Babel resolves from $repo/babel-virtual-resolve-base.js,
    # not from stage.py's transient hermes-products-*/source directory.
    # Assert the exact module can resolve from $repo before the expensive stage.
    $babelPlugin=Exec $nodeExecutable @('-p',"require.resolve('babel-plugin-react-compiler')") $repo
    Require (($babelPlugin -match 'babel-plugin-react-compiler') -and (Test-Path -LiteralPath $babelPlugin)) "babel-plugin-react-compiler not resolvable from $repo. Check the installed web dev dependencies and package lock."
    Good "Web Babel compiler preflight OK: $babelPlugin"
    $backupDir=Join-Path $root 'tools\source-patch-backups'
    if (Test-Path $backupDir) {
        # Previous interruption may have left temporary changes. Never overwrite a user's checkout:
        # this factory owns the checkout exclusively; restore exact saved original bytes.
        foreach($pair in @(@('native.py','scripts\bundles\native.py'),@('bytecode.py','scripts\bundles\bytecode.py'),@('launchers.py','scripts\build\launchers.py'))) {
            $backup=Join-Path $backupDir $pair[0]
            if (Test-Path $backup) { Copy-Item -LiteralPath $backup -Destination (Join-Path $repo $pair[1]) -Force }
        }
        Remove-Item -LiteralPath $backupDir -Recurse -Force
    }
    $patched=@{}
    try {
        $patched=PatchSource $repo $HermesProfile $backupDir
        Run $python @('-I','-S','-B',(Join-Path $repo 'scripts\bundles\stage.py'),'--out',$out,'--ref','HEAD','--cache',$cache) $repo
    } finally {
        # Even a partial write must roll back source modifications.
        if (Test-Path $backupDir) {
            foreach($pair in @(@('native.py','scripts\bundles\native.py'),@('bytecode.py','scripts\bundles\bytecode.py'),@('launchers.py','scripts\build\launchers.py'))) {
                $backup=Join-Path $backupDir $pair[0]
                if (Test-Path $backup) { Copy-Item -LiteralPath $backup -Destination (Join-Path $repo $pair[1]) -Force }
            }
            Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Require (Test-Path (Join-Path $out 'manifest.json')) 'Stage returned success without manifest.json'
}
function CheckNative([string]$out,[string]$tag,[string]$commit,[string]$HermesProfile,[string]$root) {
    foreach($name in @('manifest.json','pm-runtime\pm-runtime.json','venv','uv-cache','tools\facts.json','bin\hermes.exe','enabled-features.json')) {
        Require (Test-Path (Join-Path $out $name)) "Native payload missing $name"
    }
    $metadata=Get-Content (Join-Path $out 'manifest.json') -Raw | ConvertFrom-Json
    Require ($metadata.target -eq 'win32-x64') "Payload target must be win32-x64, found $($metadata.target)"
    $savedHome=$env:HERMES_HOME; $savedPath=$env:PYTHONPATH; $savedPyHome=$env:PYTHONHOME
    try {
        $env:HERMES_HOME=Join-Path $root 'test-home'; Mk $env:HERMES_HOME
        Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
        Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
        $ver = Exec (Join-Path $out 'bin\hermes.exe') @('--version')
        Say "Hermes launcher: $ver"
        if ($ver -notmatch [regex]::Escape($tag.TrimStart('v'))) {
            Warn "hermes --version did not contain $tag. Native source is pinned to commit $commit, but runtime version label needs manual verification: $ver"
        }
    } finally { $env:HERMES_HOME=$savedHome; $env:PYTHONPATH=$savedPath; $env:PYTHONHOME=$savedPyHome }
    $marker=@{schema=1;release=$tag;commit=$commit;profile=$HermesProfile;target='win32-x64';createdUtc=[DateTime]::UtcNow.ToString('o');artifacts=@{native=$true;desktop=$false}} | ConvertTo-Json -Depth 5
    WriteUtf8 (Join-Path $root 'tools\native-receipt.json') $marker
}
function DesktopBuild([string]$python,[string]$repo,[string]$tag,[string]$variant,[string]$root) {
    # Official stable tag build requires a published annotated rc.N-vX.Y.Z claim.
    Say 'Locating upstream stable release claim tag'
    $escaped=[regex]::Escape($tag)
    $raw=Exec 'git' @('ls-remote','--tags','origin',"refs/tags/rc.*-$tag") $repo
    $matchesList=@()
    foreach($line in ($raw -split "`n")) {
        if ($line -match "^([0-9a-f]{40})\s+refs/tags/(rc\.(\d+)-$escaped)$") {
            $matchesList+= [pscustomobject]@{Tag=$Matches[2];N=[int]$Matches[3];Sha=$Matches[1]}
        }
    }
    Require ($matchesList.Count -gt 0) 'Official Desktop stable builder requires rc.N-vX.Y.Z claim tag; none found.'
    $claim=$matchesList | Sort-Object N -Descending | Select-Object -First 1
    Run 'git' @('fetch','--depth','1','origin',"refs/tags/$($claim.Tag):refs/tags/$($claim.Tag)") $repo
    $obj=Exec 'git' @('rev-parse',"refs/tags/$($claim.Tag)") $repo
    Require ($obj -match '^[a-f0-9]{40}$') 'Claim tag object is invalid'
    Require ((Exec 'git' @('cat-file','-t',$obj) $repo) -eq 'tag') 'Claim ref is not an annotated Git tag'
    $env:RELEASE_CLAIM_TAG=$claim.Tag
    $env:RELEASE_CLAIM_OBJECT=$obj
    Say "Selected claim $($claim.Tag) ($obj)"
    $desktopArgs=@('-I','-S','-B',(Join-Path $repo 'scripts\bundles\desktop.py'),'--tag',$tag,'--variant',$variant,'--repo',$repo,'--work',(Join-Path $root 'desktop-work'),'--cache',(Join-Path $root 'desktop-cache'))
    # official build supports prepare+consume; prepare checkpoint survives compilation failures
    $prepared=Join-Path $root 'desktop-work\prepared.json'
    if (-not (Test-Path $prepared)) { Run $python ($desktopArgs+@('--prepare-only')) $repo }
    Require (Test-Path $prepared) 'Desktop prepared.json missing'
    Run $python @('-I','-S','-B',(Join-Path $repo 'scripts\bundles\desktop.py'),'--prepared',$prepared) $repo
    $releases=Join-Path $repo 'apps\desktop\release'
    Require (Test-Path $releases) 'Desktop release directory missing'
    $msix=@(Get-ChildItem -LiteralPath $releases -File -Recurse -Filter '*.msix' -ErrorAction SilentlyContinue)
    $unpacked=@(Get-ChildItem -LiteralPath $releases -Recurse -Filter '*.exe' -File -ErrorAction SilentlyContinue)
    Require ($msix.Count -gt 0 -or $unpacked.Count -gt 0) 'Official Desktop script returned success but no MSIX or EXE artifact exists'
    return $releases
}
function Bundle([string]$tag,[string]$native,[string]$releaseDir,[string]$root,[string]$commit,[string]$HermesProfile,[string]$variant) {
    $label=($tag -replace '[^A-Za-z0-9._-]','_')+'_'+$HermesProfile
    $package=Join-Path $root "package\HermesAirgap_$label"
    $outputs=Join-Path $script:FactoryRoot 'output'; Mk $outputs
    if (Test-Path $package) { Remove-Item -LiteralPath $package -Recurse -Force }
    Mk $package
    $payload=Join-Path $package 'payload'
    Mk $payload
    Say 'Copying native payload into transfer package (may take several minutes)'
    & robocopy.exe $native $payload /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    Require ($LASTEXITCODE -le 7) "robocopy failed (exit $LASTEXITCODE)"
    $desktopIncluded=$false
    if ($releaseDir -and (Test-Path $releaseDir)) {
        Mk (Join-Path $package 'desktop')
        $desktopArtifacts=@(Get-ChildItem $releaseDir -File -Recurse | Where-Object { $_.Extension -in @('.msix','.exe','.blockmap','.yml','.yaml') })
        foreach($item in $desktopArtifacts) {
            $rel=$item.FullName.Substring($releaseDir.Length).TrimStart('\')
            $dst=Join-Path (Join-Path $package 'desktop') $rel
            Mk (Split-Path $dst -Parent)
            Copy-Item -LiteralPath $item.FullName -Destination $dst -Force
        }
        $desktopIncluded=($desktopArtifacts.Count -gt 0)
    }
    foreach($template in @('InstallOrUpdateHermesAirgapped.ps1','InstallOrUpdateHermesAirgapped.bat','VerifyOfflineBundle.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "templates\$template") -Destination (Join-Path $package $template) -Force
    }
    $files=@{}
    foreach($file in @('payload\manifest.json','payload\bin\hermes.exe','payload\pm-runtime\pm-runtime.json','payload\tools\facts.json')) {
        $files[$file]=(Get-FileHash -LiteralPath (Join-Path $package $file) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($desktopIncluded) {
        foreach($file in (Get-ChildItem -LiteralPath (Join-Path $package 'desktop') -Recurse -File)) {
            $relative=$file.FullName.Substring($package.Length).TrimStart('\')
            $files[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $metadata=[ordered]@{schema=4;release=$tag;commit=$commit;profile=$HermesProfile;desktopVariant=$variant;desktopIncluded=$desktopIncluded;arch='win32-x64';createdUtc=[DateTime]::UtcNow.ToString('o');hashes=$files;security='No CA/private secrets, no TLS bypass, no source edits in shipped payload'}
    WriteUtf8 (Join-Path $package 'BUNDLE.json') ($metadata | ConvertTo-Json -Depth 8)
    # Fail closed if copied/staged payload does not satisfy offline verifier.
    & (Join-Path $package 'VerifyOfflineBundle.ps1') -BundleRoot $package -Quiet
    $zip=Join-Path $outputs ("HermesAirgap_$label" + $(if($desktopIncluded){'_desktop'}else{'_native'}) + '.zip')
    $pending=Join-Path $outputs (".pending_HermesAirgap_$label" + $(if($desktopIncluded){'_desktop'}else{'_native'}) + '.zip')
    if (Test-Path $pending) { Remove-Item -LiteralPath $pending -Force }
    $tar=(Get-Command tar.exe -ErrorAction Stop).Source
    Run $tar @('-a','-cf',$pending,'-C',(Split-Path $package -Parent),(Split-Path $package -Leaf))
    Require ((Get-Item $pending).Length -gt 1MB) 'ZIP is unexpectedly small'
    if (Test-Path $zip) {
        $oldZip=Join-Path $outputs (".previous_"+(Get-Date -Format 'yyyyMMddHHmmss')+'_'+[IO.Path]::GetFileName($zip))
        Move-Item -LiteralPath $zip -Destination $oldZip
        Say "Previous good ZIP preserved: $oldZip"
    }
    Move-Item -LiteralPath $pending -Destination $zip
    $sha=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    WriteUtf8 "$zip.sha256" "$sha  $([IO.Path]::GetFileName($zip))`n"
    Good "Package ready: $zip"
    Say "SHA256: $sha"
    return $zip
}

$oldEnv=@{}
foreach($key in @('TEMP','TMP','UV_NATIVE_TLS','UV_SYSTEM_CERTS','SSL_CERT_FILE','NODE_OPTIONS','NODE_EXTRA_CA_CERTS','npm_config_cafile','PYTHONPATH','PYTHONHOME','PATH','RELEASE_CLAIM_TAG','RELEASE_CLAIM_OBJECT')) { $oldEnv[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$script:Repo=''
$transcript=$false
try {
    Require ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'v4 supports Windows x64 only.'
    $FactoryRoot=ShortRoot $FactoryRoot
    Mk $FactoryRoot
    Mk (Join-Path $FactoryRoot 'logs')
    $log=Join-Path $FactoryRoot ("logs\factory_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
    Start-Transcript -Path $log | Out-Null; $transcript=$true
    Say "Factory v4.2, host PowerShell $($PSVersionTable.PSVersion), root $FactoryRoot"
    if ($CaFile) {
        Require (Test-Path $CaFile) "CA file missing: $CaFile"
        $env:SSL_CERT_FILE=$CaFile
        $env:NODE_EXTRA_CA_CERTS=$CaFile
        $env:npm_config_cafile=$CaFile
    }
    # PM v0.22.1 forwards UV_NATIVE_TLS. Newer uv accepts UV_SYSTEM_CERTS.
    foreach($unsafe in @('UV_INSECURE_HOST','PIP_TRUSTED_HOST')) {
        Require (-not [Environment]::GetEnvironmentVariable($unsafe,'Process')) "Unsafe TLS bypass environment variable detected: $unsafe. Remove it before building."
    }
    $env:UV_NATIVE_TLS='true'; $env:UV_SYSTEM_CERTS='true'
    $env:NODE_OPTIONS='--use-system-ca'
    Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
    Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
    Mk (Join-Path $FactoryRoot 'temp')
    $env:TEMP=Join-Path $FactoryRoot 'temp';$env:TMP=$env:TEMP
    $releaseTag=$VersionRef
    if ($VersionRef -eq 'latest') {
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/NousResearch/hermes-agent/releases/latest' -Headers @{'User-Agent'='HermesAirgapFactoryAuto/4.2'} -TimeoutSec 150
        Require ((-not $release.draft) -and (-not $release.prerelease)) 'Latest release is not a stable published release'
        $releaseTag=$release.tag_name
    }
    $releaseTag=ToSafeTag $releaseTag
    Say "Selected Hermes release $releaseTag"
    $work=Join-Path $FactoryRoot ("jobs\"+$releaseTag+'_'+$HermesProfile)
    if ($Fresh -and (Test-Path $work)) {
        $arch=Join-Path $FactoryRoot ("archive\"+$releaseTag+'_'+$HermesProfile+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
        Mk (Split-Path $arch -Parent)
        Move-Item -LiteralPath $work -Destination $arch
        Say "Archived previous complete job (no deletion): $arch"
    }
    $script:Repo=Join-Path $work 'src'
    $native=Join-Path $work 'native'
    $cache=Join-Path $work 'uv-cache'
    Mk $work; Mk $cache
    if (-not (Test-Path (Join-Path $script:Repo '.git'))) {
        Say 'Cloning exact stable release tag'
        Run 'git' @('-c','core.longpaths=true','clone','--depth','1','--single-branch','--branch',$releaseTag,'https://github.com/NousResearch/hermes-agent.git',$script:Repo)
    }
    $tagSha=Exec 'git' @('rev-parse','HEAD') $script:Repo
    $refSha=Exec 'git' @('rev-parse',"$releaseTag^{commit}") $script:Repo
    Require ($tagSha -eq $refSha) "Existing checkout does not match requested tag ($tagSha != $refSha). Use -Fresh after verifying files."
    Say "Pinned commit: $tagSha"
    $python=PythonChoice $HostPython
    $pyVer=Exec $python @('-c','import sys;print(sys.version.split()[0])')
    Say "Factory bootstrap Python ${pyVer}: $python; Hermes runtime Python comes from PM lock"
    $nodeBin=GetNode $FactoryRoot
    Say "Node location: $nodeBin"
    # NOTE: The source-patch guard deliberately aborts on upstream structural changes.
    NativeStage $python $script:Repo $native $cache $HermesProfile $work
    $status=Exec 'git' @('status','--porcelain','--untracked-files=no') $script:Repo
    Require (-not $status) "Source checkout was not restored cleanly: $status"
    CheckNative $native $releaseTag $tagSha $HermesProfile $work
    Good "Native payload passes launcher test: $native"
    $desktopLocation='';$desktopError=''
    if (-not $NoDesktop) {
        try {
            $desktopLocation=DesktopBuild $python $script:Repo $releaseTag $DesktopVariant $work
            Good "Desktop output: $desktopLocation"
        } catch {
            $desktopError=$_.Exception.Message
            Warn "Desktop failed: $desktopError"
            Warn 'Native bundle WILL still be produced; the ZIP is explicitly marked native-only.'
        }
    }
    $bundleZip=Bundle $releaseTag $native $desktopLocation $work $tagSha $HermesProfile $DesktopVariant
    $report=[ordered]@{release=$releaseTag;commit=$tagSha;native='passed';desktop=$(if($NoDesktop){'not-requested'}elseif($desktopLocation){'passed'}else{'failed'});desktopError=$desktopError;profile=$HermesProfile;outputZip=$bundleZip;sha256=(Get-FileHash $bundleZip -Algorithm SHA256).Hash;log=$log;createdAt=[DateTime]::UtcNow.ToString('o')}
    WriteUtf8 (Join-Path $work 'result.json') ($report | ConvertTo-Json -Depth 8)
    Good 'Factory finished creating an offline transfer ZIP.'
    Write-Host ($report | ConvertTo-Json -Depth 5)
    if ($desktopError) {
        Warn 'Native package is ready but Desktop is not. Inspect the log and do not claim a complete Desktop build.'
        throw "DESKTOP_NOT_BUILT: native ZIP is ready at $bundleZip. Desktop error: $desktopError"
    }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch {} }
    foreach($key in $oldEnv.Keys) { [Environment]::SetEnvironmentVariable($key,$oldEnv[$key],'Process') }
}
