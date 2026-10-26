# Hermes v0.22.0 source-bundle staging workaround for host Python 3.11 vs staged Python 3.14.
# Restores all temporary source changes, even if staging fails.
# It intentionally DOES NOT create the final air-gapped installer ZIP.
$ErrorActionPreference = 'Stop'

$B = 'C:\HermesUnifiedAirgapFactory\work\HermesAirgapBundle_v0.22.0_with_desktop'
$Repo = Join-Path $B 'hermes-agent'
$Python = Join-Path $B '_test_venv\Scripts\python.exe'
$Native = Join-Path $Repo 'scripts\bundles\native.py'
$Bytecode = Join-Path $Repo 'scripts\bundles\bytecode.py'
$Stage = Join-Path $Repo 'scripts\bundles\stage.py'
$Out = 'C:\H22\P3'
$Cache = 'C:\H22\C'
$TempDir = 'C:\H22\T'

function Replace-ExactlyOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $Count = [regex]::Matches($Text, [regex]::Escape($Old)).Count
    if ($Count -ne 1) {
        throw "Cannot safely patch ${Label}: expected 1 match for '$Old', found $Count. Files are unchanged."
    }
    return $Text.Replace($Old, $New)
}

foreach ($File in @($Python, $Native, $Bytecode, $Stage)) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Required file not found: $File"
    }
}
$Node = Get-ChildItem (Join-Path $B 'tools\node24') -Recurse -Filter 'node.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $Node) { throw 'Portable Node.exe not found under tools\node24.' }

New-Item -ItemType Directory -Force $Cache, $TempDir | Out-Null
if (Test-Path (Join-Path $Out 'manifest.json')) {
    throw "Output already contains a manifest; refusing to overwrite: $Out"
}

# Preflight: make both edits in memory before modifying either source file.
$NativeOriginal = [System.IO.File]::ReadAllBytes($Native)
$BytecodeOriginal = [System.IO.File]::ReadAllBytes($Bytecode)
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$NativeText = [System.IO.File]::ReadAllText($Native)
$BytecodeText = [System.IO.File]::ReadAllText($Bytecode)

$NativeText = Replace-ExactlyOnce $NativeText `
    'env=env, cache=cache, all_extras=True, sealed=True, explicit=True,' `
    'env=env, cache=cache, extras=("web", "mcp"), all_extras=False, sealed=True, explicit=True,' `
    'native.py selected extras'

# Avoid an extra cleanup traceback obscuring the actual build result on Windows.
$NativeText = Replace-ExactlyOnce $NativeText `
    'tempfile.TemporaryDirectory(prefix=".build-", dir=out)' `
    'tempfile.TemporaryDirectory(prefix=".build-", dir=out, ignore_cleanup_errors=True)' `
    'native.py temporary directory cleanup'

# The host (3.11) must validate pycs using the *staged interpreter* (3.14) tag.
$BytecodeText = Replace-ExactlyOnce $BytecodeText `
    'def _uncovered(root: Path) -> tuple[list[Path], int]:' `
    'def _uncovered(root: Path, cache_tag: str) -> tuple[list[Path], int]:' `
    'bytecode.py coverage function'

$BytecodeText = Replace-ExactlyOnce $BytecodeText `
    'if Path(cache_from_source(path)).exists():' `
    'if (path.parent / "__pycache__" / f"{path.stem}.{cache_tag}.pyc").exists():' `
    'bytecode.py pyc path validation'

$CacheTagCode = @'
    cache_tag = subprocess.check_output(
        [str(python), "-I", "-c", "import sys; print(sys.implementation.cache_tag)"],
        text=True,
    ).strip()
    total = 0
'@
$BytecodeText = Replace-ExactlyOnce $BytecodeText '    total = 0' $CacheTagCode 'bytecode.py staged Python tag'
$BytecodeText = Replace-ExactlyOnce $BytecodeText `
    'missing, _unparseable = _uncovered(source_root)' `
    'missing, _unparseable = _uncovered(source_root, cache_tag)' `
    'bytecode.py coverage invocation'

$Keys = @('TEMP', 'TMP', 'UV_NATIVE_TLS', 'UV_SYSTEM_CERTS', 'NODE_OPTIONS', 'Path')
$OldEnvironment = @{}
foreach ($Key in $Keys) {
    $OldEnvironment[$Key] = [Environment]::GetEnvironmentVariable($Key, 'Process')
}
$Patched = $false
$Result = -1

try {
    [Environment]::SetEnvironmentVariable('TEMP', $TempDir, 'Process')
    [Environment]::SetEnvironmentVariable('TMP', $TempDir, 'Process')
    [Environment]::SetEnvironmentVariable('UV_NATIVE_TLS', 'true', 'Process')
    [Environment]::SetEnvironmentVariable('UV_SYSTEM_CERTS', 'true', 'Process')
    [Environment]::SetEnvironmentVariable('NODE_OPTIONS', '--use-system-ca', 'Process')
    $NodeBin = Split-Path $Node.FullName -Parent
    $NpmPrefix = Join-Path $B 'tools\npm-11.18.0'
    $NewPath = "$NodeBin;$($OldEnvironment['Path'])"
    if (Test-Path (Join-Path $NpmPrefix 'npm.cmd')) { $NewPath = "$NpmPrefix;$NewPath" }
    [Environment]::SetEnvironmentVariable('Path', $NewPath, 'Process')

    [System.IO.File]::WriteAllText($Native, $NativeText, $Utf8NoBom)
    $Patched = $true
    [System.IO.File]::WriteAllText($Bytecode, $BytecodeText, $Utf8NoBom)

    Write-Host 'Temporary source patch applied (silk excluded, runtime Python cache tag fixed).' -ForegroundColor Yellow
    Write-Host "Output: $Out"
    Write-Host "Cache : $Cache"
    Write-Host 'Reusing cached packages; staged environments may be rebuilt as needed.'

    Push-Location $Repo
    try {
        & $Python -S -B $Stage --out $Out --ref HEAD --cache $Cache
        $Result = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    if ($Patched) {
        [System.IO.File]::WriteAllBytes($Native, $NativeOriginal)
        [System.IO.File]::WriteAllBytes($Bytecode, $BytecodeOriginal)
        Write-Host 'Original native.py and bytecode.py restored.' -ForegroundColor Cyan
    }
    foreach ($Key in $Keys) {
        [Environment]::SetEnvironmentVariable($Key, $OldEnvironment[$Key], 'Process')
    }
}

Write-Host "Staging exit code: $Result"
$Paths = @('manifest.json', 'pm-runtime', 'venv', 'uv-cache')
foreach ($Name in $Paths) {
    Write-Host ("{0}: {1}" -f $Name, (Test-Path (Join-Path $Out $Name)))
}
if ($Result -ne 0) { throw "Staging failed (exit $Result). Share the last error lines." }
if (-not (Test-Path (Join-Path $Out 'manifest.json'))) { throw 'Manifest is missing despite a zero exit code.' }
Write-Host 'Native payload staging completed. NOT yet a finished offline/desktop installer.' -ForegroundColor Green
