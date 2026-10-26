# Validate a v4 extracted transfer folder without Internet, installs or changes.
[CmdletBinding()]
param([string]$BundleRoot=$PSScriptRoot,[switch]$Quiet)
$ErrorActionPreference='Stop'
try {
    $BundleRoot=[IO.Path]::GetFullPath($BundleRoot)
    $meta=Join-Path $BundleRoot 'BUNDLE.json'
    if (-not (Test-Path $meta)) { throw "BUNDLE.json is missing: $BundleRoot" }
    $m=Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json
    if ($m.schema -ne 4 -or $m.arch -ne 'win32-x64') { throw 'Unexpected bundle schema or target' }
    if (-not $m.release -or $m.release -notmatch '^v\d+\.\d+\.\d+$') { throw 'Invalid release name' }
    if (-not (Test-Path (Join-Path $BundleRoot 'payload\manifest.json'))) { throw 'Native manifest is missing' }
    if (-not (Test-Path (Join-Path $BundleRoot 'payload\bin\hermes.exe'))) { throw 'Hermes launcher missing' }
    foreach($entry in $m.hashes.PSObject.Properties) {
        $target=Join-Path $BundleRoot $entry.Name
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Missing hashed file: $($entry.Name)" }
        $actual=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $entry.Value.ToLowerInvariant()) { throw "Hash mismatch: $($entry.Name)" }
    }
    $native=Get-Content (Join-Path $BundleRoot 'payload\manifest.json') -Raw | ConvertFrom-Json
    if ($native.target -ne 'win32-x64') { throw 'Native payload has wrong OS/architecture' }
    foreach($rel in @('payload\pm-runtime\pm-runtime.json','payload\venv','payload\uv-cache','payload\enabled-features.json','payload\tools\facts.json')) {
        if (-not (Test-Path (Join-Path $BundleRoot $rel))) { throw "Missing payload component: $rel" }
    }
    if ($m.desktopIncluded -and -not (Test-Path (Join-Path $BundleRoot 'desktop'))) { throw 'Desktop flagged included but desktop folder missing' }
    if (-not $Quiet) { Write-Host "[OK] v4 bundle verified: $($m.release), profile=$($m.profile), desktop=$($m.desktopIncluded)" -ForegroundColor Green }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw "Bundle integrity verification failed: $($_.Exception.Message)"
}
