# Hermes air-gapped installer/updater - Windows 10, minimal Desktop bundle (factory v4.7+)
#
#   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv   install or update (same legacy command)
#   InstallOrUpdateHermesAirgapped.bat Pilot            isolated test, changes NOTHING existing
#   RollbackHermesAirgapped.bat                         undo the last install/update
#
# Layout after install:
#   %LOCALAPPDATA%\hermes\                     HERMES_HOME (config, sessions, skills ... untouched)
#   %LOCALAPPDATA%\hermes\app\Hermes Agent.exe Desktop (unpacked Electron, no MSIX)
#   %LOCALAPPDATA%\hermes\app\resources\agent-payload\bin\hermes.exe   CLI (same single runtime)
#   %LOCALAPPDATA%\hermes\StartHermesDesktop.bat (+ copy on the Desktop, + Start menu entry)
#   %LOCALAPPDATA%\hermes\hermes.cmd           CLI shim
# The previous installation is kept as hermes-agent_source_backup_<stamp> / app_backup_<stamp>.
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Install', 'Update', 'Pilot', 'Rollback')][string]$Mode = 'Auto',
    [switch]$CleanVenv,
    [switch]$LaunchDesktop,
    [string]$BundleRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$InstallerVersion = '4.8'
$ExeName = 'Hermes Agent.exe'
$ScriptFile = $MyInvocation.MyCommand.Path
$Sep = [IO.Path]::DirectorySeparatorChar

function Step([string]$t) { Write-Host "`n============================================================`n$t`n============================================================" }
function Info([string]$t) { Write-Host "[INFO] $t" }
function Warn([string]$t) { Write-Host "[WARN] $t" -ForegroundColor Yellow }
function Require([bool]$ok, [string]$reason) { if (-not $ok) { throw $reason } }
function Mk([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function WriteText([string]$Path, [string]$Text, [switch]$Ascii) {
    $enc = if ($Ascii) { New-Object Text.ASCIIEncoding } else { New-Object Text.UTF8Encoding $false }
    [IO.File]::WriteAllText($Path, $Text, $enc)
}
function NativePath([string]$root, [string]$rel) { [IO.Path]::Combine($root, $rel.Replace('\', $Sep)) }
$Hasher = [Security.Cryptography.SHA256]::Create()
function Sha([string]$path) {
    $s = [IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString($Hasher.ComputeHash($s))).Replace('-', '').ToLowerInvariant() } finally { $s.Dispose() }
}
function ConvertTo-CleanFolder([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $t = $Value.Trim().Trim('"').Trim()
    while ($t.Length -gt 3 -and ($t.EndsWith('\') -or $t.EndsWith('/'))) { $t = $t.Substring(0, $t.Length - 1) }
    if ($t -match '^[A-Za-z]:$') { $t += '\' }
    try { return [IO.Path]::GetFullPath($t) } catch { return $null }
}
function Resolve-BundleRoot {
    $cands = @(@('parameter', $BundleRoot), @('BAT variable', $env:HERMES_BUNDLE_ROOT), @('PSScriptRoot', $PSScriptRoot))
    if ($ScriptFile) { $cands += , @('script folder', (Split-Path -Parent $ScriptFile)) }
    foreach ($c in $cands) {
        $full = ConvertTo-CleanFolder ([string]$c[1])
        if ($full -and (Test-Path -LiteralPath (Join-Path $full 'BUNDLE.json') -PathType Leaf)) { return $full }
    }
    throw 'BUNDLE.json not found next to the installer. Extract the whole ZIP and run the BAT from its folder.'
}
function Invoke-Native([string]$Exe, [string[]]$Arguments, [int]$TimeoutSec, [string]$LogFile) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding $false
    $p = [Diagnostics.Process]::Start($psi)
    try { $p.StandardInput.Close() } catch { }
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $timedOut = $true
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & taskkill.exe /PID $p.Id /T /F | Out-Null } catch { } finally { $ErrorActionPreference = $old }
        $p.WaitForExit(10000) | Out-Null
    } else { $p.WaitForExit() }
    $stdout = ''; $stderr = ''
    if ($o.Wait(10000)) { $stdout = $o.Result }
    if ($e.Wait(10000)) { $stderr = $e.Result }
    $code = if ($timedOut) { -1 } else { $p.ExitCode }
    if ($LogFile) { try { WriteText $LogFile "command: $Exe $($psi.Arguments)`r`nexit: $code`r`n--- stdout ---`r`n$stdout`r`n--- stderr ---`r`n$stderr" } catch { } }
    return [pscustomobject]@{ ExitCode = $code; TimedOut = $timedOut; StdOut = $stdout; StdErr = $stderr }
}
function Get-HermesProcesses([string]$Root) {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
}
function Save-File([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return @{ path = $Path; existed = $true; b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) } }
    return @{ path = $Path; existed = $false; b64 = '' }
}
function Restore-File($Saved) {
    $p = [string]$Saved.path
    if ($Saved.existed) { Mk (Split-Path -Parent $p); [IO.File]::WriteAllBytes($p, [Convert]::FromBase64String([string]$Saved.b64)) }
    elseif (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
function Write-State($State) {
    # Atomic: a crash while writing never leaves a half-written state file behind.
    $tmp = $State.statePath + '.tmp'
    WriteText $tmp ($State | ConvertTo-Json -Depth 6)
    Move-Item -LiteralPath $tmp -Destination $State.statePath -Force
}
function Read-Json([string]$Path) {
    # [IO.File] reads BOM-less UTF-8 correctly; Windows PowerShell 5.1 Get-Content would use ANSI.
    return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}
function Move-Retry([string]$From, [string]$To) {
    # Antivirus/indexer can hold a handle for a moment right after a big copy.
    for ($i = 1; $i -le 5; $i++) {
        try { Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop; return }
        catch { if ($i -eq 5) { throw "Cannot move $From -> $To ($($_.Exception.Message)). Close Explorer/terminal windows inside that folder." }; Start-Sleep -Seconds 2 }
    }
}
function ToBatPath([string]$Path) {
    # Keep .bat files ASCII-safe: express paths under %LOCALAPPDATA% through the variable.
    if ($Path.StartsWith($LocalApp + '\', [StringComparison]::OrdinalIgnoreCase)) { return '%LOCALAPPDATA%' + $Path.Substring($LocalApp.Length) }
    return $Path
}

function Install-AppCopy([string]$Dest, [string]$LogDir) {
    # Copy app\ from the bundle, then verify EVERY file against app-manifest.tsv.
    Info "Copying Desktop app to $Dest (several minutes)"
    Mk $Dest
    $log = Join-Path $LogDir 'robocopy_app.log'
    & robocopy.exe (Join-Path $Root 'app') $Dest /E /MT:8 /R:2 /W:1 /NP /NFL /NDL "/LOG:$log" | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -gt 7) { throw "Copy failed (robocopy exit $rc). See $log" }
    Info 'Verifying every file with SHA256 (a few minutes)'
    $bad = 0; $first = ''; $n = 0
    foreach ($line in [IO.File]::ReadAllLines($Manifest)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $p = $line.Split("`t")
        $n++
        if ($n % 10000 -eq 0) { Info "  $n / $($Meta.appFiles)" }
        $f = NativePath $Dest $p[2]
        if (-not [IO.File]::Exists($f) -or (New-Object IO.FileInfo $f).Length -ne [long]$p[1] -or (Sha $f) -ne $p[0]) {
            $bad++; if (-not $first) { $first = $p[2] }
        }
    }
    Require ($n -eq [int]$Meta.appFiles) "Manifest has $n entries, BUNDLE.json says $($Meta.appFiles)."
    $onDisk = @([IO.Directory]::GetFiles($Dest, '*', [IO.SearchOption]::AllDirectories)).Count
    Require ($onDisk -eq $n) "Copied folder has $onDisk files, manifest lists $n. Remove stray files from the extracted app folder."
    Require ($bad -eq 0) "$bad files are missing or damaged (first: $first). Re-extract or re-transfer the ZIP; nothing was activated."
    Info "All $n files verified."
    try {
        if (Get-Item -LiteralPath (NativePath $Dest $ExeName) -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) {
            Info 'Removing the Internet-zone mark (downloaded ZIP) from the copied files'
            Get-ChildItem -LiteralPath $Dest -Recurse -File | Unblock-File
        }
    } catch { }
}
function Test-Cli([string]$AppRoot, [string]$SmokeHome, [string]$LogFile) {
    Mk $SmokeHome
    $saved = @{}
    foreach ($k in @('HERMES_HOME', 'PYTHONPATH', 'PYTHONHOME', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'PYTHONUTF8', 'PYTHONIOENCODING')) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
    try {
        $env:HERMES_HOME = $SmokeHome
        Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue; Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
        $env:HTTP_PROXY = 'http://127.0.0.1:9'; $env:HTTPS_PROXY = 'http://127.0.0.1:9'; $env:ALL_PROXY = 'http://127.0.0.1:9'
        $env:PYTHONUTF8 = '1'; $env:PYTHONIOENCODING = 'utf-8'
        $r = Invoke-Native (NativePath $AppRoot 'resources\agent-payload\bin\hermes.exe') @('--version') 300 $LogFile
    } finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') } }
    Require (-not $r.TimedOut) 'hermes --version did not finish in 300 s.'
    Require ($r.ExitCode -eq 0) "hermes --version failed (exit $($r.ExitCode)). See $LogFile"
    $first = (($r.StdOut -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    Info "CLI: $first"
    Require ($r.StdOut -match [regex]::Escape(([string]$Meta.release).TrimStart('v'))) "CLI does not report $($Meta.release)."
}
function Invoke-ConfigMigrate([string]$AppRoot, [string]$HermesHome, [string]$LogFile) {
    if (-not (Test-Path -LiteralPath (Join-Path $HermesHome 'config.yaml'))) { Info 'No config.yaml yet; configure the model on first Desktop start.'; return }
    $saved = @{ H = $env:HERMES_HOME; U = $env:PYTHONUTF8; E = $env:PYTHONIOENCODING }
    try {
        $env:HERMES_HOME = $HermesHome; $env:PYTHONUTF8 = '1'; $env:PYTHONIOENCODING = 'utf-8'
        $r = Invoke-Native (NativePath $AppRoot 'resources\agent-payload\bin\hermes.exe') @('config', 'migrate') 180 $LogFile
    } finally { $env:HERMES_HOME = $saved.H; $env:PYTHONUTF8 = $saved.U; $env:PYTHONIOENCODING = $saved.E }
    if ($r.ExitCode -eq 0) { Info 'config migrate: OK' } else { Warn "config migrate exit $($r.ExitCode) (see $LogFile). The backup copy of config.yaml is kept." }
}
function New-Launcher([string]$Path, [string]$HermesHome, [string]$Exe) {
    $HermesHome = ToBatPath $HermesHome; $Exe = ToBatPath $Exe
    $text = "@echo off`r`nsetlocal`r`nset `"HERMES_HOME=$HermesHome`"`r`nset PYTHONUTF8=1`r`nset PYTHONIOENCODING=utf-8`r`nset HERMES_STREAM_READ_TIMEOUT=1800`r`nstart `"`" `"$Exe`"`r`n"
    Mk (Split-Path -Parent $Path)
    WriteText $Path $text -Ascii
}

# ---------------------------------------------------------------- common setup
$LocalApp = $env:LOCALAPPDATA
Require (-not [string]::IsNullOrWhiteSpace($LocalApp)) 'LOCALAPPDATA is not set.'
$HomeDir = Join-Path $LocalApp 'hermes'
$UserHome = [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')
$HermesHome = if ([string]::IsNullOrWhiteSpace($UserHome)) { $HomeDir } else { $UserHome }
$AppDir = Join-Path $HomeDir 'app'
$OldSrc = Join-Path $HomeDir 'hermes-agent'
$StartBat = Join-Path $HomeDir 'StartHermesDesktop.bat'
$deskDir = [Environment]::GetFolderPath('Desktop')
$progDir = [Environment]::GetFolderPath('Programs')
$DesktopBat = if ($deskDir) { Join-Path $deskDir 'StartHermesDesktop.bat' } else { Join-Path $HomeDir 'StartHermesDesktop_DesktopCopy.bat' }
$StartMenuLnk = if ($progDir) { Join-Path $progDir 'Hermes Agent.lnk' } else { Join-Path $HomeDir 'Hermes Agent.lnk' }
$Shim = Join-Path $HomeDir 'hermes.cmd'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$procEnv = @{}
foreach ($k in @('HERMES_HOME', 'PYTHONPATH', 'PYTHONHOME', 'PYTHONUTF8', 'PYTHONIOENCODING')) { $procEnv[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
$State = $null
$Stage = $null
$switched = $false
$newActive = $false
$exitCode = 1

try {
    Require ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'Only Windows x64 is supported.'

    # ============================================================ ROLLBACK
    if ($Mode -eq 'Rollback') {
        Step 'Hermes rollback: restore the installation that existed before the last install/update'
        # Newest install that changed something wins; installs already auto-restored are skipped.
        $statePath = $null; $s = $null
        foreach ($d in @(Get-ChildItem -LiteralPath $LocalApp -Directory -Filter 'hermes_backup_before_airgap_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
            $sp = Join-Path $d.FullName 'install-state.json'
            if (-not (Test-Path -LiteralPath $sp)) { continue }
            try { $candidate = Read-Json $sp } catch { throw "Cannot read $sp ($($_.Exception.Message)). Nothing was changed; restore manually from $($d.FullName)." }
            if (@('installed', 'switching', 'failed-partial') -contains [string]$candidate.status) { $statePath = $sp; $s = $candidate; break }
            if ([string]$candidate.status -eq 'rolled-back') { break }   # never undo an older install behind a rollback
        }
        Require ($null -ne $s) 'No install to roll back (the latest one was already rolled back or restored automatically, or none exists).'
        $running = @(Get-HermesProcesses $HomeDir)
        Require ($running.Count -eq 0) ("Close Hermes first (Desktop, CLI, gateway). Running: " + (($running | ForEach-Object { $_.ProcessName }) -join ', '))
        Info "Install being undone: $($s.stamp), state '$($s.status)' (backup $($s.backupRoot))"
        # Check everything BEFORE changing anything.
        $prevApp = [string]$s.movedOldApp; $prevSrc = [string]$s.movedOldSrc
        if ($prevApp) { Require (Test-Path -LiteralPath $prevApp) "The previous app backup is missing: $prevApp. Nothing was changed." }
        if ($prevSrc) {
            Require (Test-Path -LiteralPath $prevSrc) "The previous hermes-agent backup is missing: $prevSrc. Nothing was changed."
            Require (-not (Test-Path -LiteralPath $OldSrc)) "$OldSrc already exists (old installer run again?). Nothing was changed; restore manually from $prevSrc."
        }
        if (Test-Path -LiteralPath $AppDir) {
            $aside = Join-Path $HomeDir ('app_rolledback_' + $stamp)
            Move-Retry $AppDir $aside
            Info "New Desktop app moved to: $aside (delete it later)"
        }
        if ($prevApp) { Move-Retry $prevApp $AppDir; Info 'Previous app restored.' }
        if ($prevSrc) { Move-Retry $prevSrc $OldSrc; Info "Previous hermes-agent restored: $OldSrc" }
        foreach ($f in @('config.yaml', '.env')) {
            $b = Join-Path $s.backupRoot $f
            if (Test-Path -LiteralPath $b) { Copy-Item -LiteralPath $b -Destination (Join-Path $s.hermesHome $f) -Force; Info "$f restored from the pre-install backup." }
        }
        foreach ($prop in $s.userEnv.PSObject.Properties) {
            if ($prop.Name -ne 'Path') { [Environment]::SetEnvironmentVariable($prop.Name, $prop.Value, 'User'); continue }
            # PATH: drop the new app entries, put back the old Hermes entries, keep everything added since.
            $oldHermes = @(([string]$prop.Value) -split ';' | Where-Object { $_.Trim() -and $_.Trim().StartsWith($OldSrc + '\', [StringComparison]::OrdinalIgnoreCase) })
            $now = @(([string][Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith($AppDir + '\', [StringComparison]::OrdinalIgnoreCase) })
            $merged = @($oldHermes) + @($now | Where-Object { $oldHermes -notcontains $_ })
            [Environment]::SetEnvironmentVariable('Path', ($merged -join ';'), 'User')
        }
        Info 'User PATH / HERMES_HOME / HERMES_GIT_BASH_PATH restored.'
        foreach ($f in $s.files) { Restore-File $f }
        Info 'StartHermesDesktop.bat (home + Desktop), hermes.cmd and Start menu entry restored.'
        $s.status = 'rolled-back'; $s | Add-Member -NotePropertyName rolledBackAt -NotePropertyValue (Get-Date).ToString('o') -Force
        $tmp = $statePath + '.tmp'; WriteText $tmp ($s | ConvertTo-Json -Depth 6); Move-Item -LiteralPath $tmp -Destination $statePath -Force
        Write-Host "`n[OK] Rollback finished. Open a NEW terminal. Sessions/skills/memories were never removed; a copy is also in $($s.backupRoot)." -ForegroundColor Green
        $exitCode = 0
        return
    }

    # ============================================================ INSTALL / UPDATE / PILOT
    $Root = Resolve-BundleRoot
    $MetaPath = Join-Path $Root 'BUNDLE.json'
    $Manifest = Join-Path $Root 'app-manifest.tsv'
    $Meta = Read-Json $MetaPath
    $metaNames = @($Meta.PSObject.Properties.Name)
    Require (($metaNames -contains 'schema') -and ($metaNames -contains 'installContract') -and $Meta.schema -eq 5 -and $Meta.installContract -eq 'legacy-auto-cleanvenv-win10-desktop') 'This is not a factory v4.7+ Windows 10 Desktop bundle.'
    Step "Hermes air-gapped install/update - Windows 10 Desktop (installer $InstallerVersion)"
    Info "Bundle      : $Root"
    Info "Release     : $($Meta.release) ($($Meta.profile): tools $(@($Meta.tools) -join ', '))"
    Info "Hermes home : $HermesHome"
    Info "Mode        : $Mode$(if ($CleanVenv) { ' (CleanVenv: always a fresh sealed runtime in this bundle type)' })"
    Require (Test-Path -LiteralPath $Manifest -PathType Leaf) 'app-manifest.tsv missing.'
    Require ((Sha $Manifest) -eq ([string]$Meta.manifestSha256).ToLowerInvariant()) 'app-manifest.tsv does not match BUNDLE.json (damaged transfer).'
    Require (Test-Path -LiteralPath (NativePath (Join-Path $Root 'app') $ExeName) -PathType Leaf) "app\$ExeName missing; extract the whole ZIP."
    Require (-not $Root.StartsWith($HomeDir + '\', [StringComparison]::OrdinalIgnoreCase)) 'Do not extract the bundle inside %LOCALAPPDATA%\hermes.'
    $needMB = [math]::Round(([long]$Meta.appBytes) / 1MB * 1.1 + 500, 0)
    $freeMB = [math]::Round((New-Object IO.DriveInfo ($LocalApp.Substring(0, 1))).AvailableFreeSpace / 1MB, 0)
    Info "Disk        : $freeMB MB free, about $needMB MB needed"
    Require ($freeMB -ge $needMB) 'Not enough disk space. Nothing was changed.'

    # ------------------------------------------------------------ PILOT
    if ($Mode -eq 'Pilot') {
        $pBase = Join-Path $LocalApp 'hpilot'
        do { $pDir = Join-Path $pBase ('P' + (Get-Date -Format 'MMddHHmmss')); if (Test-Path $pDir) { Start-Sleep 1 } } while (Test-Path $pDir)
        $pDiag = $pDir + '_diag'; $pCfg = $pDir + '_cfg'
        Mk $pDiag
        Step 'PILOT: isolated copy, your installation is NOT changed'
        Install-AppCopy $pDir $pDiag
        Test-Cli $pDir ($pDir + '_smoke') (Join-Path $pDiag 'cli_version.txt')
        Mk $pCfg
        foreach ($f in @('config.yaml', '.env', 'company-ca-bundle.pem')) {
            $src = Join-Path $HermesHome $f
            if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination (Join-Path $pCfg $f) }
        }
        Info "Pilot profile (COPY of your config): $pCfg"
        Invoke-ConfigMigrate $pDir $pCfg (Join-Path $pDiag 'config_migrate.txt')
        $pBat = $pDir + '_StartDesktop.bat'
        New-Launcher $pBat $pCfg (NativePath $pDir $ExeName)
        Write-Host "`n[OK] Pilot ready. Start it with:`n     $pBat`n     Remove later: the folders $pDir, ${pDir}_cfg, ${pDir}_diag, ${pDir}_smoke" -ForegroundColor Green
        if ($LaunchDesktop) { Start-Process -FilePath $pBat }
        $exitCode = 0
        return
    }

    # ------------------------------------------------------------ INSTALL / UPDATE
    $exists = (Test-Path -LiteralPath $OldSrc) -or (Test-Path -LiteralPath $AppDir)
    if ($Mode -eq 'Auto') { $Mode = if ($exists) { 'Update' } else { 'Install' } }
    Require ($Mode -ne 'Update' -or $exists) 'Update was requested but no existing Hermes installation was found.'
    Info "Resolved    : $Mode"
    $running = @(Get-HermesProcesses $HomeDir)
    Require ($running.Count -eq 0) ("Close Hermes first (Desktop window, terminals running hermes, gateway). Still running: " +
        (($running | ForEach-Object { "$($_.ProcessName) [$($_.Id)]" }) -join ', ') + '. Nothing was changed.')
    foreach ($old in @(Get-ChildItem -LiteralPath $HomeDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\.st\d{8}$' })) {
        try { Remove-Item -LiteralPath $old.FullName -Recurse -Force; Info "Removed leftover temporary folder $($old.Name)" } catch { }
    }

    Step 'Backup of settings (originals stay in place)'
    Mk $HomeDir
    $BackupRoot = Join-Path $LocalApp ('hermes_backup_before_airgap_' + $stamp)
    Mk $BackupRoot
    foreach ($f in @('config.yaml', '.env', 'company-ca-bundle.pem')) {
        $src = Join-Path $HermesHome $f
        if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination (Join-Path $BackupRoot $f) -Force }
    }
    foreach ($d in @('sessions', 'skills', 'memories', 'cron')) {
        $src = Join-Path $HermesHome $d
        if (Test-Path -LiteralPath $src -PathType Container) {
            try { Copy-Item -LiteralPath $src -Destination (Join-Path $BackupRoot $d) -Recurse -Force -ErrorAction Stop }
            catch { Warn "Could not fully back up ${d}: $($_.Exception.Message)" }
        }
    }
    $userEnv = [ordered]@{}
    foreach ($k in @('Path', 'HERMES_HOME', 'PYTHONUTF8', 'PYTHONIOENCODING', 'HERMES_GIT_BASH_PATH')) { $userEnv[$k] = [Environment]::GetEnvironmentVariable($k, 'User') }
    $State = [ordered]@{
        schema = 1; installer = $InstallerVersion; release = $Meta.release; stamp = $stamp; mode = $Mode; status = 'started'
        statePath = (Join-Path $BackupRoot 'install-state.json'); backupRoot = $BackupRoot; hermesHome = $HermesHome
        movedOldSrc = $null; movedOldApp = $null; userEnv = $userEnv
        files = @((Save-File $StartBat), (Save-File $DesktopBat), (Save-File $Shim), (Save-File $StartMenuLnk))
    }
    Write-State $State
    Info "Backup: $BackupRoot"

    Step 'Preparing the new Desktop app beside the current installation'
    $Stage = Join-Path $HomeDir ('.st' + (Get-Date -Format 'MMddHHmm'))
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    Install-AppCopy $Stage $BackupRoot
    Test-Cli $Stage (Join-Path $BackupRoot 'smoke-home') (Join-Path $BackupRoot 'cli_version_stage.txt')

    Step 'Switching to the new version (previous one is kept)'
    $switched = $true
    $State.status = 'switching'
    if (Test-Path -LiteralPath $OldSrc) {
        $State.movedOldSrc = Join-Path $HomeDir ('hermes-agent_source_backup_' + $stamp)
        Write-State $State                     # recorded BEFORE the move, so rollback always knows
        Move-Retry $OldSrc $State.movedOldSrc
        Info "Previous hermes-agent kept at: $($State.movedOldSrc)"
    }
    if (Test-Path -LiteralPath $AppDir) {
        $State.movedOldApp = Join-Path $HomeDir ('app_backup_' + $stamp)
        Write-State $State
        Move-Retry $AppDir $State.movedOldApp
        Info "Previous app kept at: $($State.movedOldApp)"
    }
    Write-State $State
    Move-Retry $Stage $AppDir
    $newActive = $true
    Test-Cli $AppDir (Join-Path $BackupRoot 'smoke-home') (Join-Path $BackupRoot 'cli_version_active.txt')

    Step 'Commands, launchers and user settings'
    $bin = NativePath $AppDir 'resources\agent-payload\bin'
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($part in @(([string]$userEnv['Path']) -split ';')) {
        $c = $part.Trim()
        if (-not $c) { continue }
        if ($c.StartsWith($OldSrc + '\', [StringComparison]::OrdinalIgnoreCase) -or $c -ieq $OldSrc) { continue }   # old venv\Scripts
        if ($c.StartsWith($AppDir + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($c -ieq $bin) { continue }
        $parts.Add($c) | Out-Null
    }
    [Environment]::SetEnvironmentVariable('Path', ((@($bin) + $parts) -join ';'), 'User')
    if ([string]::IsNullOrWhiteSpace($userEnv['HERMES_HOME'])) { [Environment]::SetEnvironmentVariable('HERMES_HOME', $HomeDir, 'User') }
    [Environment]::SetEnvironmentVariable('PYTHONUTF8', '1', 'User')
    [Environment]::SetEnvironmentVariable('PYTHONIOENCODING', 'utf-8', 'User')
    $gitBash = [string]$userEnv['HERMES_GIT_BASH_PATH']
    if ($gitBash -and -not (Test-Path -LiteralPath $gitBash)) {
        [Environment]::SetEnvironmentVariable('HERMES_GIT_BASH_PATH', $null, 'User')
        Info "HERMES_GIT_BASH_PATH pointed to a missing file ($gitBash); cleared so the bundled Git Bash is used."
    }
    WriteText $Shim ("@echo off`r`n`"%~dp0app\resources\agent-payload\bin\hermes.exe`" %*`r`n") -Ascii
    $exe = NativePath $AppDir $ExeName
    New-Launcher $StartBat $HermesHome $exe
    try { New-Launcher $DesktopBat $HermesHome $exe; Info "Desktop launcher: $DesktopBat" } catch { Warn "Could not write the Desktop copy: $($_.Exception.Message)" }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($StartMenuLnk)
        $lnk.TargetPath = $StartBat; $lnk.WorkingDirectory = $HomeDir; $lnk.WindowStyle = 7; $lnk.IconLocation = "$exe,0"; $lnk.Description = 'Hermes Agent (offline)'
        $lnk.Save()
        Info "Start menu: $StartMenuLnk"
    } catch { Warn "Start menu entry not created: $($_.Exception.Message)" }

    Step 'Config migration (backup copy taken before)'
    Invoke-ConfigMigrate $AppDir $HermesHome (Join-Path $BackupRoot 'config_migrate.txt')

    $State.status = 'installed'; $State['installedAt'] = (Get-Date).ToString('o'); Write-State $State
    Step 'Done'
    Write-Host "[OK] Hermes $($Meta.release) Desktop installed." -ForegroundColor Green
    Write-Host "     Start   : Desktop > StartHermesDesktop.bat  (or Start menu > Hermes Agent)"
    Write-Host "     CLI     : open a NEW terminal, then: hermes --version"
    Write-Host "     Undo    : RollbackHermesAirgapped.bat (in this folder)"
    Write-Host "     Backups : $BackupRoot"
    Write-Host '     Note    : the very first start can take longer; if the window closes once, start it again.'
    if ($LaunchDesktop) { Start-Process -FilePath $StartBat }
    $exitCode = 0
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($State -and $switched) {
        Warn 'Restoring the previous installation...'
        try {
            if ($newActive -and (Test-Path -LiteralPath $AppDir)) { Move-Retry $AppDir (Join-Path $HomeDir ('app_failed_' + $stamp)); Info "Failed new app kept for diagnosis: app_failed_$stamp (delete it later)" }
            elseif ($Stage -and (Test-Path -LiteralPath $Stage)) { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue }
            if ($State.movedOldApp -and (Test-Path -LiteralPath $State.movedOldApp)) { Move-Retry $State.movedOldApp $AppDir }
            if ($State.movedOldSrc -and (Test-Path -LiteralPath $State.movedOldSrc) -and -not (Test-Path -LiteralPath $OldSrc)) { Move-Retry $State.movedOldSrc $OldSrc }
            foreach ($k in $State.userEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $State.userEnv[$k], 'User') }
            foreach ($f in $State.files) { Restore-File $f }
            $cfgBackup = Join-Path $State.backupRoot 'config.yaml'
            if (Test-Path -LiteralPath $cfgBackup) { Copy-Item -LiteralPath $cfgBackup -Destination (Join-Path $HermesHome 'config.yaml') -Force }
            $State.status = 'failed-restored'; Write-State $State
            Write-Host '[OK] Previous installation restored.' -ForegroundColor Green
        } catch {
            Warn "Automatic restore incomplete: $($_.Exception.Message). Run RollbackHermesAirgapped.bat or restore from $($State.backupRoot)."
            try { $State.status = 'failed-partial'; Write-State $State } catch { }
        }
    } elseif ($State) {
        if ($Stage -and (Test-Path -LiteralPath $Stage)) {
            try { Remove-Item -LiteralPath $Stage -Recurse -Force; Info 'Temporary copy removed.' } catch { Warn "Remove the temporary folder manually: $Stage" }
        }
        try { $State.status = 'failed-nothing-changed'; Write-State $State } catch { }
        Info 'The current installation was not changed.'
    }
} finally {
    foreach ($k in $procEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $procEnv[$k], 'Process') }
    $Hasher.Dispose()
}
exit $exitCode
