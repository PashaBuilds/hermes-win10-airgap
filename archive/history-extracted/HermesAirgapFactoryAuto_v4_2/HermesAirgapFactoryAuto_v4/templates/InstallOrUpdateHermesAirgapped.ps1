# Installs v4 native payload side-by-side. Does NOT overwrite existing legacy Hermes,
# company configs, connected model endpoints, gateway startup or user secrets.
[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\HAgent",
    [switch]$Force,
    [switch]$NoLauncher,
    [switch]$AllowLongPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProgressPreference='SilentlyContinue'
function Require([bool]$v,[string]$msg) { if (-not $v) { throw $msg } }
function Mk([string]$p) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
$BundleRoot=$PSScriptRoot
$BundleMeta=Join-Path $BundleRoot 'BUNDLE.json'
Require (Test-Path $BundleMeta) 'Run this installer from the EXTRACTED bundle folder, not inside the ZIP.'
Require ($AllowLongPath -or $BundleRoot.Length -le 90) 'Transfer folder path is too long. Extract the ZIP to a short local path such as C:\H4Transfer.'
Require ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'Bundle supports Windows x64 only.'
$InstallRoot=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
Require ($AllowLongPath -or $InstallRoot.Length -le 85) "Install path is too long for Windows packaging: $InstallRoot. Select a shorter -InstallRoot."
Require (-not $InstallRoot.StartsWith('\\')) 'Use a local drive (not a UNC share).'
$verifier=Join-Path $BundleRoot 'VerifyOfflineBundle.ps1'
& $verifier -BundleRoot $BundleRoot
# The verifier throws on any failure, preventing installation.
$m=Get-Content $BundleMeta -Raw | ConvertFrom-Json
$version=$m.release
$releases=Join-Path $InstallRoot 'releases'
$dest=Join-Path $releases $version
$stage=Join-Path $InstallRoot ("staging-"+$version+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$backup=Join-Path $InstallRoot ("backup-"+$version+'-'+(Get-Date -Format 'yyyyMMddHHmmss'))
$smokeHome=Join-Path $InstallRoot 'smoke-home'
Mk $InstallRoot; Mk $releases; Mk $smokeHome
$hadBackup=$false
$activeWritten=$false
$priorLauncher=Join-Path $InstallRoot 'hermes.cmd'
$priorContent=if (Test-Path $priorLauncher) {[IO.File]::ReadAllBytes($priorLauncher)}else{$null}
$oldHome=[Environment]::GetEnvironmentVariable('HERMES_HOME','Process')
$oldPythonPath=[Environment]::GetEnvironmentVariable('PYTHONPATH','Process')
$oldPythonHome=[Environment]::GetEnvironmentVariable('PYTHONHOME','Process')
$oldUv=[Environment]::GetEnvironmentVariable('UV_OFFLINE','Process')
$oldProxy=[Environment]::GetEnvironmentVariable('HTTPS_PROXY','Process')
try {
    Write-Host "[H4] Installing Hermes $version side-by-side into $dest"
    Require (-not (Test-Path $stage)) 'Unexpected pre-existing staging directory'
    Mk $stage
    & robocopy.exe (Join-Path $BundleRoot 'payload') $stage /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    Require ($LASTEXITCODE -le 7) "robocopy copy failed: $LASTEXITCODE"
    foreach($f in @('manifest.json','bin\hermes.exe','pm-runtime\pm-runtime.json','uv-cache')) {
        Require (Test-Path (Join-Path $stage $f)) "Incomplete staged payload: $f"
    }
    [Environment]::SetEnvironmentVariable('PYTHONPATH',$null,'Process')
    [Environment]::SetEnvironmentVariable('PYTHONHOME',$null,'Process')
    [Environment]::SetEnvironmentVariable('HERMES_HOME',$smokeHome,'Process')
    [Environment]::SetEnvironmentVariable('UV_OFFLINE','true','Process')
    [Environment]::SetEnvironmentVariable('HTTPS_PROXY','http://127.0.0.1:9','Process')
    Write-Host '[H4] Checking relocated staged binary with offline-only settings'
    & (Join-Path $stage 'bin\hermes.exe') --version
    Require ($LASTEXITCODE -eq 0) 'Offline relocated launcher failed. Old installation was not changed.'
    if (Test-Path $dest) {
        if (-not $Force) { throw "Release already installed at $dest. Use -Force to replace, or choose another InstallRoot." }
        Move-Item -LiteralPath $dest -Destination $backup
        $hadBackup=$true
    }
    Move-Item -LiteralPath $stage -Destination $dest
    Write-Host '[H4] Checking final location'
    & (Join-Path $dest 'bin\hermes.exe') --version
    Require ($LASTEXITCODE -eq 0) 'Installed launcher failed. Rollback attempted.'
    if (-not $NoLauncher) {
        # Stable command shim changes only AFTER a successful install.
        $cmd = "@echo off`r`n`"%~dp0releases\$version\bin\hermes.exe`" %*`r`n"
        $newShim="$priorLauncher.new"
        [IO.File]::WriteAllText($newShim,$cmd,(New-Object System.Text.ASCIIEncoding))
        Move-Item -LiteralPath $newShim -Destination $priorLauncher -Force
        $activeWritten=$true
    }
    $info=[ordered]@{installedRelease=$version;installedCommit=$m.commit;installedAt=[DateTime]::UtcNow.ToString('o');profile=$m.profile;installPath=$dest}
    [IO.File]::WriteAllText((Join-Path $InstallRoot 'current.json'),($info | ConvertTo-Json -Depth 6),(New-Object System.Text.UTF8Encoding($false)))
    Write-Host '[OK] Installed. Use:' -ForegroundColor Green
    Write-Host "     `"$priorLauncher`" --version"
    if ($m.desktopIncluded) {
        Write-Warning 'Desktop package is included but was not auto-installed. MSIX signing/dependencies/company policy must be validated separately.'
        Write-Host "Desktop files are under: $(Join-Path $BundleRoot 'desktop')"
    }
    if ($hadBackup) { Write-Host "Previous same-version release retained at $backup" }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($hadBackup) {
        try {
            if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
            Move-Item -LiteralPath $backup -Destination $dest -Force
            Write-Host '[H4] Previous release restored.'
        } catch { Write-Warning "Rollback needs manual attention: $($_.Exception.Message)" }
    }
    if ($activeWritten) {
        try {
            if ($null -ne $priorContent) { [IO.File]::WriteAllBytes($priorLauncher,$priorContent) }
            else { Remove-Item -LiteralPath $priorLauncher -Force -ErrorAction SilentlyContinue }
        } catch {}
    }
    throw
} finally {
    foreach($key in @('HERMES_HOME','PYTHONPATH','PYTHONHOME','UV_OFFLINE','HTTPS_PROXY')) {
        $value=switch($key){'HERMES_HOME'{$oldHome};'PYTHONPATH'{$oldPythonPath};'PYTHONHOME'{$oldPythonHome};'UV_OFFLINE'{$oldUv};'HTTPS_PROXY'{$oldProxy}}
        [Environment]::SetEnvironmentVariable($key,$value,'Process')
    }
    if (Test-Path $stage) { Write-Warning "Temporary staging folder retained for troubleshooting: $stage" }
}
