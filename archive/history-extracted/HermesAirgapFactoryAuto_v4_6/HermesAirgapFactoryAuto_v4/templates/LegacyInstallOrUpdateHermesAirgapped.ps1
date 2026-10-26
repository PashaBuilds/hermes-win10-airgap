# Legacy-command compatible Windows 10 air-gapped installer for Hermes PM native payload.
# UX: InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
# State: %LOCALAPPDATA%\hermes; existing install preserved in timestamped backup.
# This is NOT the old Python 3.11/pip wheelhouse implementation; Hermes 0.22.2
# owns a Python 3.14/PM runtime. CleanVenv provisions a fresh sealed generation.
[CmdletBinding()]
param(
    [ValidateSet('Auto','Install','Update')][string]$Mode='Auto',
    [switch]$CleanVenv,
    [switch]$LaunchDesktop
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
function Step([string]$value) { Write-Host "`n============================================================`n$value`n============================================================" }
function Info([string]$value) { Write-Host "[INFO] $value" }
function Require([bool]$ok,[string]$reason) { if (-not $ok) { throw $reason } }
function Mk([string]$path) { if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null } }
function SetProcess([string]$key,[string]$value) { [Environment]::SetEnvironmentVariable($key,$value,'Process') }

$BundleRoot=$PSScriptRoot
$HomeDir=Join-Path $env:LOCALAPPDATA 'hermes'
$InstallDir=Join-Path $HomeDir 'hermes-agent'
$Payload=Join-Path $BundleRoot 'payload'
$verifier=Join-Path $BundleRoot 'VerifyOfflineBundle.ps1'
$metadata=Join-Path $BundleRoot 'BUNDLE.json'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$StageDir=Join-Path $HomeDir ('.stage-'+$stamp+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$OldDir=Join-Path $HomeDir ('hermes-agent_source_backup_'+$stamp)
$BackupRoot=Join-Path $env:LOCALAPPDATA ('hermes_backup_before_airgap_'+$stamp)
$SmokeHome=Join-Path $HomeDir ('.install-smoke-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$hadOld=$false
$newActive=$false
$initialProcess=@{}
$envKeys=@('HERMES_HOME','PYTHONPATH','PYTHONHOME','UV_OFFLINE','PIP_NO_INDEX','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')
foreach($key in $envKeys) { $initialProcess[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$oldUserPath=[Environment]::GetEnvironmentVariable('Path','User')
$oldUserHome=[Environment]::GetEnvironmentVariable('HERMES_HOME','User')
$oldUserUtf8=[Environment]::GetEnvironmentVariable('PYTHONUTF8','User')
$oldUserEncoding=[Environment]::GetEnvironmentVariable('PYTHONIOENCODING','User')
$oldUserGitBash=[Environment]::GetEnvironmentVariable('HERMES_GIT_BASH_PATH','User')
$oldShim=Join-Path $HomeDir 'hermes.cmd'
$oldShimBytes=if(Test-Path -LiteralPath $oldShim){[IO.File]::ReadAllBytes($oldShim)}else{$null}
$settingsWritten=$false
try {
    Step 'Hermes unified air-gapped install/update - Windows 10 / legacy command'
    Info "Bundle root : $BundleRoot"
    Info "Hermes home : $HomeDir"
    Info "Mode        : $Mode"
    Info "Clean venv  : $CleanVenv (fresh pinned Python 3.14 runtime; no reuse of old venv)"
    Require ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'Only Windows x64 is supported.'
    Require (-not $LaunchDesktop) 'Win10 package has no compatible Desktop installer. Existing Desktop launcher was not modified.'
    Require ((Test-Path -LiteralPath $metadata -PathType Leaf) -and (Test-Path -LiteralPath $verifier -PathType Leaf)) 'Extract the ZIP before running the installer.'
    Require ($BundleRoot.Length -le 90) 'Extract package to a short local directory, e.g. C:\H4Transfer.'
    & $verifier -BundleRoot $BundleRoot
    $meta=Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
    Require ($meta.arch -eq 'win32-x64') 'Unsupported bundle architecture.'
    Require (($meta.installContract -eq 'legacy-auto-cleanvenv-win10') -and (-not $meta.desktopIncluded)) 'Expected an explicit Windows 10 legacy-compatible native bundle. Do not use the v4.5 Desktop ZIP.'
    foreach($part in @('manifest.json','bin\hermes.exe','venv','pm-runtime\pm-runtime.json','tools\facts.json')) {
        Require (Test-Path -LiteralPath (Join-Path $Payload $part)) "Missing payload component: $part"
    }
    $exists=Test-Path -LiteralPath $InstallDir
    if ($Mode -eq 'Auto') { if($exists){$Mode='Update'}else{$Mode='Install'} }
    Require ($Mode -ne 'Update' -or $exists) 'Update was requested but there is no existing Hermes installation.'
    Info "Resolved mode: $Mode"
    Mk $HomeDir
    Step 'Selective backup of user settings (originals remain untouched)'
    Mk $BackupRoot
    foreach($f in @('config.yaml','.env','company-ca-bundle.pem')) {
        $src=Join-Path $HomeDir $f
        if(Test-Path -LiteralPath $src -PathType Leaf){Copy-Item -LiteralPath $src -Destination (Join-Path $BackupRoot $f) -Force}
    }
    foreach($d in @('sessions','skills','memories','cron','logs')) {
        $src=Join-Path $HomeDir $d
        if(Test-Path -LiteralPath $src -PathType Container) {
            try{Copy-Item -LiteralPath $src -Destination (Join-Path $BackupRoot $d) -Recurse -Force -ErrorAction Stop}
            catch{Write-Warning "Could not fully back up ${d}: $($_.Exception.Message)"}
        }
    }
    Info "User backup: $BackupRoot"
    Step 'Preparing fresh pinned Hermes PM payload (offline)'
    Mk $StageDir
    & robocopy.exe $Payload $StageDir /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc=$LASTEXITCODE
    Require ($rc -le 7) "Offline payload copy failed (robocopy $rc). Existing installation unchanged."
    foreach($part in @('manifest.json','bin\hermes.exe','venv','pm-runtime\pm-runtime.json','tools\facts.json')) {
        Require (Test-Path -LiteralPath (Join-Path $StageDir $part)) "Incomplete staged payload: $part"
    }
    Mk $SmokeHome
    SetProcess 'HERMES_HOME' $SmokeHome
    SetProcess 'PYTHONPATH' $null
    SetProcess 'PYTHONHOME' $null
    SetProcess 'UV_OFFLINE' 'true'
    SetProcess 'PIP_NO_INDEX' '1'
    SetProcess 'HTTP_PROXY' 'http://127.0.0.1:9'
    SetProcess 'HTTPS_PROXY' 'http://127.0.0.1:9'
    SetProcess 'ALL_PROXY' 'http://127.0.0.1:9'
    & (Join-Path $StageDir 'bin\hermes.exe') --version
    Require ($LASTEXITCODE -eq 0) 'Staged Hermes runtime failed offline smoke test. Existing installation unchanged.'
    Step 'Switching active Hermes source/runtime (old version is kept)'
    if ($exists) {
        Require (-not (Test-Path -LiteralPath $OldDir)) "Backup destination already exists: $OldDir"
        Move-Item -LiteralPath $InstallDir -Destination $OldDir
        $hadOld=$true
        Info "Previous Hermes retained at: $OldDir"
    }
    Move-Item -LiteralPath $StageDir -Destination $InstallDir
    $newActive=$true
    & (Join-Path $InstallDir 'bin\hermes.exe') --version
    Require ($LASTEXITCODE -eq 0) 'Hermes launcher failed after activating new runtime; restoring previous installation.'
    Step 'Restoring legacy user paths and command availability'
    # Keep the established Hermes home; do not replace user configuration or model settings.
    $bin=Join-Path $InstallDir 'bin'
    # Keep the bundled Node available for MCP tools, as the old wheelhouse installer did.
    $nodeDir=$null
    foreach($dir in @(Get-ChildItem -LiteralPath (Join-Path $InstallDir 'tools') -Directory -Filter 'node-*-win32-x64' -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'node.exe')) { $nodeDir=$dir.FullName; break }
    }
    $prepend=@($bin)
    if($nodeDir){$prepend+= $nodeDir}
    $parts=@()
    foreach($part in @($oldUserPath -split ';')) {
        $candidate=$part.Trim()
        if (-not $candidate) { continue }
        if (@($prepend | Where-Object { $_ -ieq $candidate }).Count -gt 0) { continue }
        $parts+= $candidate
    }
    $newPath=((@($prepend)+@($parts)) -join ';').TrimEnd(';')
    $settingsWritten=$true
    [Environment]::SetEnvironmentVariable('Path',$newPath,'User')
    # Existing custom HERMES_HOME is respected; the standard home is used if unset.
    if ([string]::IsNullOrWhiteSpace($oldUserHome)) {
        [Environment]::SetEnvironmentVariable('HERMES_HOME',$HomeDir,'User')
    }
    [Environment]::SetEnvironmentVariable('PYTHONUTF8','1','User')
    [Environment]::SetEnvironmentVariable('PYTHONIOENCODING','utf-8','User')
    # Respect any working Git Bash setting; otherwise use the staged portable Git.
    if([string]::IsNullOrWhiteSpace($oldUserGitBash)) {
        $portableBash=Get-ChildItem -LiteralPath (Join-Path $InstallDir 'tools') -Directory -Filter 'git-*-win32-x64' -ErrorAction SilentlyContinue | ForEach-Object {
            @((Join-Path $_.FullName 'bin\bash.exe'),(Join-Path $_.FullName 'usr\bin\bash.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        } | Select-Object -First 1
        if($portableBash) { [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH',$portableBash,'User') }
    }
    $shim='@echo off' + "`r`n" + '"%~dp0hermes-agent\bin\hermes.exe" %*' + "`r`n"
    [IO.File]::WriteAllText($oldShim,$shim,(New-Object System.Text.ASCIIEncoding))
    # No MSIX, no desktop script rewrite. Never replace a pre-existing legacy Desktop launcher.
    Step 'Done'
    Write-Host "[OK] Hermes $($meta.release) installed using legacy Auto/CleanVenv command." -ForegroundColor Green
    Write-Host "     $oldShim --version"
    Write-Host "     $bin\hermes.exe --help"
    Write-Host 'Open a NEW terminal before using the updated user PATH.'
    Write-Warning 'This Windows 10 package contains the native CLI/Web/MCP payload. The legacy Desktop shortcut is not replaced; v0.22.2 Windows 10 Desktop is NOT yet certified.'
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($newActive -and (Test-Path -LiteralPath $InstallDir)) {
        $failed=Join-Path $HomeDir ('hermes-agent_failed_'+$stamp+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
        try { Move-Item -LiteralPath $InstallDir -Destination $failed; Write-Warning "Failed generation retained at: $failed" }
        catch { Write-Warning "Could not quarantine new runtime: $($_.Exception.Message)" }
    }
    if ($hadOld -and -not (Test-Path -LiteralPath $InstallDir)) {
        try { Move-Item -LiteralPath $OldDir -Destination $InstallDir; Write-Host '[OK] Previous Hermes restored.' }
        catch { Write-Warning "Manual rollback required from $OldDir : $($_.Exception.Message)" }
    }
    if ($settingsWritten) {
        try {
            [Environment]::SetEnvironmentVariable('Path',$oldUserPath,'User')
            [Environment]::SetEnvironmentVariable('HERMES_HOME',$oldUserHome,'User')
            [Environment]::SetEnvironmentVariable('PYTHONUTF8',$oldUserUtf8,'User')
            [Environment]::SetEnvironmentVariable('PYTHONIOENCODING',$oldUserEncoding,'User')
            [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH',$oldUserGitBash,'User')
            if($null -eq $oldShimBytes){Remove-Item -LiteralPath $oldShim -Force -ErrorAction SilentlyContinue}
            else{[IO.File]::WriteAllBytes($oldShim,$oldShimBytes)}
        } catch { Write-Warning "Some user settings may need manual rollback: $($_.Exception.Message)" }
    }
    throw
} finally {
    foreach($key in $envKeys) { SetProcess $key $initialProcess[$key] }
    # Staging is retained on failure for diagnostics; it is not an installed environment.
}
