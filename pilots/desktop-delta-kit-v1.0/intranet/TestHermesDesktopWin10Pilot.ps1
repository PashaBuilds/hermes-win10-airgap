# Hermes v0.22.2 - Windows 10 Desktop pilot (INTRANET side)
# Rebuilds the unpacked Electron app (no MSIX) from:
#   - the already transferred, verified HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\payload
#   - this small delta kit (Electron shell + differing files)
# verifies EVERY file against desktop-manifest.tsv (SHA256) and starts
# "Hermes Agent.exe" with an isolated HERMES_HOME (copy of your config).
# Writes only to %LOCALAPPDATA%\hpilot (plus Electron's own %APPDATA%\Hermes Agent).
# Does NOT touch %LOCALAPPDATA%\hermes, User PATH, registry or the old Desktop shortcut.
[CmdletBinding()]
param([string]$KitRoot, [string]$BundleDir, [int]$ObserveSeconds = 60)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$PilotVersion = '1.0'
$ExeName = 'Hermes Agent.exe'
$ScriptFile = $MyInvocation.MyCommand.Path
$Sep = [IO.Path]::DirectorySeparatorChar
$ExitCode = 1
$Started = $false
$Summary = [ordered]@{}
$Warnings = New-Object System.Collections.Generic.List[string]

function Info([string]$Text) { Write-Host "[DPILOT] $Text" }
function Warn([string]$Text) { $Warnings.Add(($Text -replace '\s*\r?\n\s*', ' ')) | Out-Null; Write-Host "[DPILOT_WARN] $Text" -ForegroundColor Yellow }
function Note([string]$Key, $Value) { $Summary[$Key] = ([string]$Value -replace '\s*\r?\n\s*', ' ') }
function WriteText([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }
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
  if ([string]::IsNullOrWhiteSpace($t)) { return $null }
  try { return [IO.Path]::GetFullPath($t) } catch { return $null }
}

function Resolve-Folder([object[]]$Candidates, [string]$MarkerFile, [string]$What) {
  $tried = @()
  foreach ($c in $Candidates) {
    $raw = [string]$c[1]
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $full = ConvertTo-CleanFolder $raw
    if (-not $full) { $tried += "$($c[0]) = [$raw] -> invalid"; continue }
    if (Test-Path -LiteralPath (Join-Path $full $MarkerFile) -PathType Leaf) { return @($full, $c[0]) }
    $tried += "$($c[0]) = [$full] -> no $MarkerFile"
  }
  throw ("$What not found. Tried:`r`n  " + ($tried -join "`r`n  "))
}

function Get-ExistingFingerprint {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('UserPath=' + [Environment]::GetEnvironmentVariable('Path', 'User')) | Out-Null
  $lines.Add('UserHermesHome=' + [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')) | Out-Null
  foreach ($f in @('config.yaml', '.env', 'hermes.cmd', 'company-ca-bundle.pem')) {
    $p = Join-Path $HermesHomeOld $f
    if (Test-Path -LiteralPath $p -PathType Leaf) { $lines.Add("$f=" + (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash) | Out-Null }
    else { $lines.Add("$f=absent") | Out-Null }
  }
  if (Test-Path -LiteralPath $Existing -PathType Container) {
    foreach ($i in @(Get-ChildItem -LiteralPath $Existing -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
      $lines.Add('hermes-agent\' + $i.Name + '|' + $i.LastWriteTimeUtc.Ticks) | Out-Null
    }
  } else { $lines.Add('hermes-agent=absent') | Out-Null }
  return ($lines -join "`n")
}

function Invoke-Native([string]$Name, [string]$Exe, [string[]]$Arguments, [int]$TimeoutSec, [string]$WorkDir) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $quoted = foreach ($a in $Arguments) { if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
  $psi.Arguments = ($quoted -join ' ')
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
  $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding $false
  $psi.WorkingDirectory = $WorkDir
  $p = [Diagnostics.Process]::Start($psi)
  try { $p.StandardInput.Close() } catch { }
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  $timedOut = $false
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    $timedOut = $true
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & taskkill.exe /PID $p.Id /T /F | Out-Null } catch { } finally { $ErrorActionPreference = $old }
    $p.WaitForExit(10000) | Out-Null
  } else { $p.WaitForExit() }
  $stdout = ''; $stderr = ''
  if ($outTask.Wait(10000)) { $stdout = $outTask.Result }
  if ($errTask.Wait(10000)) { $stderr = $errTask.Result }
  $code = if ($timedOut) { -1 } else { $p.ExitCode }
  WriteText (Join-Path $Diag ($Name + '.txt')) "command: $Exe $($psi.Arguments)`r`nexit: $code`r`ntimedOut: $timedOut`r`n--- stdout ---`r`n$stdout`r`n--- stderr ---`r`n$stderr"
  if ($stdout) { Write-Host $stdout.TrimEnd() }
  if ($stderr) { foreach ($l in ($stderr.TrimEnd() -split "`r?`n")) { Write-Host "  [stderr] $l" -ForegroundColor DarkGray } }
  return [pscustomobject]@{ ExitCode = $code; TimedOut = $timedOut; StdOut = $stdout; StdErr = $stderr }
}

function Invoke-Robocopy([string]$From, [string]$To, [string[]]$Extra, [string]$LogName) {
  $log = Join-Path $Diag $LogName
  $rcArgs = @($From, $To, '/E', '/R:2', '/W:1', '/NP', '/NFL', '/NDL', "/LOG:$log") + $Extra
  & robocopy.exe @rcArgs | Out-Null
  $rc = $LASTEXITCODE
  if ($rc -gt 7) {
    $tail = ''
    try { $tail = (Get-Content -LiteralPath $log -Tail 15) -join "`r`n" } catch { }
    throw "robocopy $From -> $To failed (exit $rc).`r`n$tail"
  }
  return $rc
}

# ---------------------------------------------------------------- locations
$LocalApp = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($LocalApp)) { Write-Host '[DPILOT_ERROR] LOCALAPPDATA is not set.' -ForegroundColor Red; exit 1 }
$HermesHomeOld = Join-Path $LocalApp 'hermes'
$Existing = Join-Path $HermesHomeOld 'hermes-agent'
$PilotBase = Join-Path $LocalApp 'hpilot'
do {
  $Id = 'D' + (Get-Date -Format 'MMddHHmmss')
  $Dest = Join-Path $PilotBase $Id
  if (Test-Path -LiteralPath $Dest) { Start-Sleep -Seconds 1 }
} while (Test-Path -LiteralPath $Dest)
$Diag = $Dest + '_diag'
$Log = Join-Path $Diag 'desktop_pilot.log'
$envKeys = @('HERMES_HOME', 'PYTHONPATH', 'PYTHONHOME', 'PYTHONSTARTUP', 'PYTHONUTF8', 'PYTHONIOENCODING', 'VIRTUAL_ENV',
  'HERMES_DESKTOP_HERMES_ROOT', 'HERMES_DESKTOP_CWD', 'ELECTRON_RUN_AS_NODE', 'ELECTRON_ENABLE_LOGGING')
$oldEnv = @{}
foreach ($key in $envKeys) { $oldEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }

try {
  New-Item -ItemType Directory -Path $Diag -Force | Out-Null
  try { Start-Transcript -LiteralPath $Log -ErrorAction Stop | Out-Null; $Started = $true } catch { Write-Host "[DPILOT_WARN] Transcript not started: $($_.Exception.Message)" }
  Info "Desktop pilot script version $PilotVersion"
  Note 'pilotVersion' $PilotVersion
  Note 'diagFolder' $Diag

  # ------------------------------------------------------------ kit + bundle
  $kc = @(@('parameter -KitRoot', $KitRoot), @('BAT variable HERMES_DESKTOP_KIT', $env:HERMES_DESKTOP_KIT), @('PSScriptRoot', $PSScriptRoot))
  if ($ScriptFile) { $kc += , @('script file folder', (Split-Path -Parent $ScriptFile)) }
  $r = Resolve-Folder $kc 'DESKTOP_DELTA.json' 'Desktop delta kit folder'
  $KitRoot = $r[0]
  Info "Kit folder   : $KitRoot   (source: $($r[1]))"
  $kit = Get-Content -LiteralPath (Join-Path $KitRoot 'DESKTOP_DELTA.json') -Raw | ConvertFrom-Json
  $manifestPath = Join-Path $KitRoot 'desktop-manifest.tsv'
  if ((Sha $manifestPath) -ne ([string]$kit.manifestSha256).ToLowerInvariant()) { throw 'desktop-manifest.tsv does not match DESKTOP_DELTA.json (kit damaged in transfer).' }
  Note 'kitRelease' $kit.release
  Note 'kitFiles' $kit.files

  $parent = Split-Path -Parent $KitRoot
  $bc = @(@('parameter -BundleDir', $BundleDir), @('BAT variable HERMES_PILOT_BUNDLE', $env:HERMES_PILOT_BUNDLE),
    @('next to kit', (Join-Path $parent ([IO.Path]::GetFileNameWithoutExtension([string]$kit.bundleZip)))),
    @('C:\H4Transfer', 'C:\H4Transfer\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv'))
  $r = Resolve-Folder $bc 'BUNDLE.json' 'Extracted Windows 10 bundle (HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv)'
  $BundleDir = $r[0]
  $bmeta = Get-Content -LiteralPath (Join-Path $BundleDir 'BUNDLE.json') -Raw | ConvertFrom-Json
  if ($bmeta.commit -ne $kit.bundleCommit -or $bmeta.createdUtc -ne $kit.bundleCreatedUtc) {
    throw "Bundle at $BundleDir is not the one this kit was made from (createdUtc $($bmeta.createdUtc) vs kit $($kit.bundleCreatedUtc))."
  }
  $Payload = Join-Path $BundleDir 'payload'
  Info "Bundle       : $BundleDir   (source: $($r[1]))"
  Info "Existing Hermes (NOT changed): $Existing"
  Info "Desktop pilot (new, isolated): $Dest"

  # ------------------------------------------------------------ manifest
  $entries = New-Object System.Collections.Generic.List[object]
  $relSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($line in [IO.File]::ReadAllLines($manifestPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $p = $line.Split("`t")
    if ($p.Count -ne 4) { throw "Bad manifest line: $line" }
    $entries.Add([pscustomobject]@{ Hash = $p[0]; Size = [long]$p[1]; Src = $p[2]; Rel = $p[3] }) | Out-Null
    $null = $relSet.Add($p[3])
  }
  if ($entries.Count -ne [int]$kit.files) { throw "Manifest has $($entries.Count) entries, kit says $($kit.files)." }
  $missingKit = @($entries | Where-Object { $_.Src -eq 'D' -and -not [IO.File]::Exists((NativePath (Join-Path $KitRoot 'files') $_.Rel)) })
  if ($missingKit.Count -gt 0) { throw "Kit is incomplete: $($missingKit.Count) files missing, first: $($missingKit[0].Rel). Re-extract the kit ZIP." }

  # ------------------------------------------------------------ disk
  $needMB = [math]::Round(([long]$kit.totalBytes) / 1MB * 1.05 + 500, 0)
  $drive = New-Object System.IO.DriveInfo ($LocalApp.Substring(0, 1))
  $freeMB = [math]::Round($drive.AvailableFreeSpace / 1MB, 0)
  Note 'freeMB' $freeMB
  Info "Free space: $freeMB MB, Desktop pilot needs about $needMB MB"
  if ($freeMB -lt $needMB) { throw "Not enough disk space ($freeMB MB free, about $needMB MB needed). Tip: delete the older CLI pilot runtime %LOCALAPPDATA%\hpilot\<number> (keep the _cfg folder)." }

  # ------------------------------------------------------------ assemble
  Info 'Step 1/5: copying the runtime from the transferred payload (several minutes)'
  $agentDest = NativePath $Dest 'resources\agent-payload'
  New-Item -ItemType Directory -Path $agentDest -Force | Out-Null
  Note 'robocopyPayload' (Invoke-Robocopy $Payload $agentDest @('/MT:8') 'robocopy_payload.log')
  Info 'Step 2/5: overlaying Electron shell and delta files'
  Note 'robocopyDelta' (Invoke-Robocopy (Join-Path $KitRoot 'files') $Dest @('/IS', '/IT') 'robocopy_delta.log')
  $removed = 0
  $agentPrefixLen = $Dest.Length + 1
  foreach ($f in @(Get-ChildItem -LiteralPath $agentDest -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($agentPrefixLen).Replace('/', '\')
    if (-not $relSet.Contains($rel)) { Remove-Item -LiteralPath $f.FullName -Force; $removed++ }
  }
  Note 'payloadFilesNotUsedRemoved' $removed
  Info "Removed $removed payload files that the Desktop build does not contain"

  Info 'Step 3/5: verifying every file with SHA256 (a few minutes)'
  $bad = New-Object System.Collections.Generic.List[string]
  $n = 0
  foreach ($e in $entries) {
    $n++
    if ($n % 5000 -eq 0) { Info "  $n / $($entries.Count)" }
    $f = NativePath $Dest $e.Rel
    if (-not [IO.File]::Exists($f)) { $bad.Add("missing $($e.Rel)") | Out-Null; continue }
    if ((New-Object IO.FileInfo $f).Length -ne $e.Size -or (Sha $f) -ne $e.Hash) { $bad.Add("mismatch $($e.Rel)") | Out-Null }
  }
  Note 'verifiedFiles' ($entries.Count - $bad.Count)
  Note 'verifyErrors' $bad.Count
  if ($bad.Count -gt 0) {
    WriteText (Join-Path $Diag 'verify_errors.txt') ($bad -join "`r`n")
    throw "Verification failed for $($bad.Count) files, first: $($bad[0])"
  }
  Info "All $($entries.Count) files verified."

  # ------------------------------------------------------------ isolated profile
  $cfg = $null
  $cfgCands = @(Get-ChildItem -LiteralPath $PilotBase -Directory -Filter '*_cfg' -ErrorAction SilentlyContinue |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'config.yaml') } | Sort-Object LastWriteTime -Descending)
  if ($cfgCands.Count -gt 0) { $cfg = $cfgCands[0].FullName; Info "Using the tested pilot profile: $cfg" }
  else {
    $cfg = $Dest + '_cfg'
    New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    foreach ($f in @('config.yaml', '.env', 'company-ca-bundle.pem')) {
      $s = Join-Path $HermesHomeOld $f
      if (Test-Path -LiteralPath $s -PathType Leaf) { Copy-Item -LiteralPath $s -Destination (Join-Path $cfg $f) }
    }
    Info "Created a pilot profile from COPIES of your config: $cfg"
  }
  Note 'pilotHermesHome' $cfg

  foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
  $env:HERMES_HOME = $cfg
  $env:PYTHONUTF8 = '1'
  $env:PYTHONIOENCODING = 'utf-8'

  Info 'Step 4/5: bundled CLI check (stamped build, should now show v0.22.2)'
  $cli = NativePath $agentDest 'bin\hermes.exe'
  $rv = Invoke-Native 'bundled_version' $cli @('--version') 300 $Diag
  Note 'bundledVersionExit' $rv.ExitCode
  $vt = ($rv.StdOut -replace '\s+', ' ').Trim(); if ($vt.Length -gt 200) { $vt = $vt.Substring(0, 200) }
  Note 'bundledVersionText' $vt
  if ($rv.ExitCode -ne 0) { Warn 'Bundled hermes --version failed; Desktop backend may fail too (see bundled_version.txt).' }
  $rm = Invoke-Native 'config_migrate' $cli @('config', 'migrate') 120 $Diag
  Note 'configMigrateExit' $rm.ExitCode

  # ------------------------------------------------------------ launch
  Info 'Step 5/5: starting Hermes Agent Desktop (Electron, no MSIX)'
  $others = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @('Hermes', 'Hermes Agent') })
  if ($others.Count -gt 0) { Warn "Another Hermes desktop process is running ($($others.Count)). If the new window misbehaves, close the old Hermes app and run this pilot again." }
  $fingerBefore = Get-ExistingFingerprint
  $exe = Join-Path $Dest $ExeName
  $startAt = Get-Date
  $proc = Start-Process -FilePath $exe -WorkingDirectory $Dest -PassThru
  $null = $proc.Handle   # keeps ExitCode readable after exit (PowerShell 5.1 quirk)
  Note 'desktopPid' $proc.Id
  $fromPilot = { @(Get-Process -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -and $_.Path.StartsWith($Dest, [StringComparison]::OrdinalIgnoreCase) } catch { $false } }) }
  $alive = $true
  for ($s = 0; $s -lt $ObserveSeconds; $s += 5) {
    Start-Sleep -Seconds 5
    # Electron may relaunch itself; count the pilot as alive while any process runs from the pilot folder.
    if ($proc.HasExited -and @(& $fromPilot).Count -eq 0) { $alive = $false; break }
  }
  $children = @(& $fromPilot)
  Note 'processesFromPilotFolder' $children.Count
  $logsDir = Join-Path $cfg 'logs'
  $recent = @()
  if (Test-Path -LiteralPath $logsDir) {
    $recent = @(Get-ChildItem -LiteralPath $logsDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $startAt.AddSeconds(-5) })
    $logCopy = Join-Path $Diag 'hermes_logs'
    New-Item -ItemType Directory -Path $logCopy -Force | Out-Null
    foreach ($l in $recent) { Copy-Item -LiteralPath $l.FullName -Destination (Join-Path $logCopy $l.Name) -Force -ErrorAction SilentlyContinue }
  }
  Note 'newLogFiles' (($recent | ForEach-Object { $_.Name }) -join ',')
  Note 'electronUserData' $(if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Hermes Agent')) { Join-Path $env:APPDATA 'Hermes Agent' } else { 'not created' })
  $fingerAfter = Get-ExistingFingerprint
  if ($fingerAfter -eq $fingerBefore) { Note 'existingInstallUnchanged' 'yes'; Info 'Existing installation fingerprint: UNCHANGED' }
  else { Note 'existingInstallUnchanged' 'NO'; Warn 'Existing installation fingerprint CHANGED while Desktop was running.'; WriteText (Join-Path $Diag 'fingerprint_diff.txt') ("BEFORE`r`n$fingerBefore`r`n`r`nAFTER`r`n$fingerAfter") }

  # Re-launch helper for later tests (same isolation as this pilot).
  $starter = $Dest + '_StartDesktop.bat'
  WriteText $starter ("@echo off`r`nset `"HERMES_HOME=$cfg`"`r`nset PYTHONUTF8=1`r`nstart `"`" `"$exe`"`r`n")
  Note 'relaunchBat' $starter

  if (-not $alive) {
    try { Note 'desktopExitCode' $proc.ExitCode } catch { }
    throw "Hermes Agent.exe exited after a few seconds (exit $($proc.ExitCode)). Logs copied to $Diag\hermes_logs."
  }
  Write-Host ''
  Write-Host "[DPILOT_OK] Hermes Agent Desktop is running from the pilot folder after $ObserveSeconds s (no MSIX)." -ForegroundColor Green
  Write-Host '[DPILOT] Now check the window: does it open, connect to the backend, answer with your local DeepSeek?'
  Write-Host "[DPILOT] To start it again later: $starter"
  Note 'result' 'DPILOT_OK'
  $ExitCode = 0
} catch {
  Note 'result' 'DPILOT_ERROR'
  Note 'error' $_.Exception.Message
  try { Note 'errorLine' $_.InvocationInfo.ScriptLineNumber } catch { }
  Write-Host ''
  Write-Host "[DPILOT_ERROR] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "[DPILOT] Existing Hermes location was not modified by this pilot: $Existing"
  $ExitCode = 1
} finally {
  foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $oldEnv[$key], 'Process') }
  $Hasher.Dispose()
  Note 'warnings' ($Warnings -join ' | ')
  try {
    $lines = foreach ($k in $Summary.Keys) { "$k=$($Summary[$k])" }
    WriteText (Join-Path $Diag 'summary.txt') ($lines -join "`r`n")
    Write-Host ''
    Write-Host '----- summary.txt -----'
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host '-----------------------'
    Write-Host "[DPILOT] Diagnostic folder: $Diag"
  } catch { Write-Host "[DPILOT_WARN] Could not write summary: $($_.Exception.Message)" }
  if ($Started) { try { Stop-Transcript | Out-Null } catch { } }
}
exit $ExitCode
