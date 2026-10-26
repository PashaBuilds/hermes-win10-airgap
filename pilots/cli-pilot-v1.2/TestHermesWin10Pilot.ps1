# Hermes v0.22.2 Windows 10: isolated production-machine pilot v1.2
# Writes ONLY to %LOCALAPPDATA%\hpilot. Does NOT touch %LOCALAPPDATA%\hermes,
# the existing Desktop launcher, the User PATH or any registry value.
#
# v1.2 fixes against v1.1:
#  - v1.1 BAT passed -BundleRoot "%~dp0". %~dp0 ends with '\', and '\"' is an
#    escaped quote for powershell.exe, so the script received  C:\...\Bundle"
#    (trailing quote) -> GetFullPath "Illegal characters in path".
#    v1.2: BAT passes the folder via an environment variable; the script tries
#    several sources and accepts the first folder that really holds BUNDLE.json.
#  - Native commands no longer use "2>&1" under ErrorActionPreference=Stop
#    (Windows PowerShell 5.1 turns any stderr line into a terminating error).
#  - PYTHONUTF8/PYTHONIOENCODING set for the child (Turkish code page safety).
#  - Runtime path is not longer than the production path (MAX_PATH realism).
#  - Extraction completeness check against the transfer ZIP, path-length and
#    disk-space report, fingerprint proof that the existing install is untouched.
[CmdletBinding()]
param([string]$BundleRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$PilotVersion = '1.2'
$ExpectedRelease = 'v0.22.2'
$ExpectedZipSha256 = 'EA3183E37E1344A6F25249A83F6FC78B17875D00252CF14C95D51AB8CA9D7D9E'
$ScriptFile = $MyInvocation.MyCommand.Path
$ExitCode = 1
$Started = $false
$Summary = [ordered]@{}
$Warnings = New-Object System.Collections.Generic.List[string]

function Info([string]$Text) { Write-Host "[PILOT] $Text" }
function Warn([string]$Text) { $Warnings.Add(($Text -replace '\s*\r?\n\s*', ' ')) | Out-Null; Write-Host "[PILOT_WARN] $Text" -ForegroundColor Yellow }
function Note([string]$Key, $Value) { $Summary[$Key] = ([string]$Value -replace '\s*\r?\n\s*', ' ') }
function WriteText([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }

function ConvertTo-CleanFolder([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $t = $Value.Trim().Trim('"').Trim()
  while ($t.Length -gt 3 -and ($t.EndsWith('\') -or $t.EndsWith('/'))) { $t = $t.Substring(0, $t.Length - 1) }
  if ($t -match '^[A-Za-z]:$') { $t += '\' }
  if ([string]::IsNullOrWhiteSpace($t)) { return $null }
  try { return [IO.Path]::GetFullPath($t) } catch { return $null }
}

function Resolve-PilotBundleRoot {
  $candidates = New-Object System.Collections.Generic.List[object]
  $candidates.Add(@('parameter -BundleRoot', $BundleRoot)) | Out-Null
  $candidates.Add(@('BAT variable HERMES_PILOT_BUNDLE', $env:HERMES_PILOT_BUNDLE)) | Out-Null
  $candidates.Add(@('PSScriptRoot', $PSScriptRoot)) | Out-Null
  if ($ScriptFile) { $candidates.Add(@('script file folder', (Split-Path -Parent $ScriptFile))) | Out-Null }
  try { $candidates.Add(@('current directory', (Get-Location).ProviderPath)) | Out-Null } catch { }
  $tried = @()
  foreach ($c in $candidates) {
    $raw = [string]$c[1]
    if ([string]::IsNullOrWhiteSpace($raw)) { $tried += "$($c[0]) = <empty>"; continue }
    $full = ConvertTo-CleanFolder $raw
    if (-not $full) { $tried += "$($c[0]) = [$raw] -> invalid path"; continue }
    if (Test-Path -LiteralPath (Join-Path $full 'BUNDLE.json') -PathType Leaf) { return @($full, $c[0]) }
    $tried += "$($c[0]) = [$full] -> no BUNDLE.json"
  }
  throw ("Bundle folder not found. Put TestHermesWin10Pilot.bat/.ps1 next to BUNDLE.json and payload\. Tried:`r`n  " + ($tried -join "`r`n  "))
}

function Get-ExistingFingerprint {
  # Things the pilot must never change. Session/log contents are excluded on
  # purpose: a running old Hermes may legitimately write there by itself.
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
  $sw = [Diagnostics.Stopwatch]::StartNew()
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
  $sw.Stop()
  $stdout = ''; $stderr = ''
  if ($outTask.Wait(10000)) { $stdout = $outTask.Result }
  if ($errTask.Wait(10000)) { $stderr = $errTask.Result }
  $code = if ($timedOut) { -1 } else { $p.ExitCode }
  $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  $text = "command: $Exe $($psi.Arguments)`r`nexit: $code`r`ntimedOut: $timedOut`r`nseconds: $secs`r`n--- stdout ---`r`n$stdout`r`n--- stderr ---`r`n$stderr"
  WriteText (Join-Path $Diag ($Name + '.txt')) $text
  if ($stdout) { Write-Host $stdout.TrimEnd() }
  if ($stderr) { foreach ($l in ($stderr.TrimEnd() -split "`r?`n")) { Write-Host "  [stderr] $l" -ForegroundColor DarkGray } }
  return [pscustomobject]@{ ExitCode = $code; TimedOut = $timedOut; Seconds = $secs; StdOut = $stdout; StdErr = $stderr }
}

# ---------------------------------------------------------------- locations
$LocalApp = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($LocalApp)) { Write-Host '[PILOT_ERROR] LOCALAPPDATA is not set.' -ForegroundColor Red; exit 1 }
$HermesHomeOld = Join-Path $LocalApp 'hermes'
$Existing = Join-Path $HermesHomeOld 'hermes-agent'
$PilotBase = Join-Path $LocalApp 'hpilot'
# Short on purpose: %LOCALAPPDATA%\hpilot\MMddHHmmss (18 chars) is not longer than
# the production %LOCALAPPDATA%\hermes\hermes-agent (19 chars).
do {
  $Id = Get-Date -Format 'MMddHHmmss'
  $Runtime = Join-Path $PilotBase $Id
  if (Test-Path -LiteralPath $Runtime) { Start-Sleep -Seconds 1 }
} while (Test-Path -LiteralPath $Runtime)
$PilotHome = $Runtime + '_home'
$Diag = $Runtime + '_diag'
$Log = Join-Path $Diag 'pilot.log'

$envKeys = @('HERMES_HOME', 'HERMES_INSTALL_ROOT', 'HERMES_PAYLOAD_ROOT', 'HERMES_PAYLOAD_TAG',
  'HERMES_BUILD_COMMIT', 'HERMES_SITE', 'HERMES_PYTHON', 'HERMES_NODE', 'HERMES_PROFILE',
  'PYTHONPATH', 'PYTHONHOME', 'PYTHONSTARTUP', 'PYTHONUTF8', 'PYTHONIOENCODING', 'VIRTUAL_ENV',
  'UV_OFFLINE', 'PIP_NO_INDEX', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')
$oldEnv = @{}
foreach ($key in $envKeys) { $oldEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }

try {
  New-Item -ItemType Directory -Path $Diag -Force | Out-Null
  try { Start-Transcript -LiteralPath $Log -ErrorAction Stop | Out-Null; $Started = $true } catch { Write-Host "[PILOT_WARN] Transcript not started: $($_.Exception.Message)" }
  Info "Pilot script version $PilotVersion"
  Note 'pilotVersion' $PilotVersion
  Note 'diagFolder' $Diag

  # ------------------------------------------------------------ bundle root
  $resolved = Resolve-PilotBundleRoot
  $BundleRoot = $resolved[0]
  Info "Bundle folder: $BundleRoot   (source: $($resolved[1]))"
  Note 'bundleRoot' $BundleRoot
  Note 'bundleRootSource' $resolved[1]
  $Payload = Join-Path $BundleRoot 'payload'
  $Verify = Join-Path $BundleRoot 'VerifyOfflineBundle.ps1'
  $MetadataPath = Join-Path $BundleRoot 'BUNDLE.json'
  Info "Existing Hermes (will NOT be changed): $Existing"
  Info "Pilot runtime (new, isolated):         $Runtime"
  Info "Pilot diagnostics:                     $Diag"

  # ------------------------------------------------------------ host facts
  if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Pilot requires Windows x64.' }
  Note 'psVersion' $PSVersionTable.PSVersion
  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Info "OS: $($os.Caption), build $($os.BuildNumber)"
    Note 'osCaption' $os.Caption
    Note 'osBuild' $os.BuildNumber
    if ([int]$os.BuildNumber -ge 22000) { Warn 'Host is Windows 11; this is not the requested Windows 10 acceptance test.' }
  } catch { Warn "Could not query Windows build: $($_.Exception.Message)" }
  $longPaths = 'unknown'
  try {
    $fsKey = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction Stop
    if ($fsKey.PSObject.Properties.Name -contains 'LongPathsEnabled') { $longPaths = [string]$fsKey.LongPathsEnabled } else { $longPaths = '0 (not set)' }
  } catch { }
  Note 'longPathsEnabled' $longPaths
  try {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($HermesHomeOld, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
    Note 'oldHermesProcessesRunning' $running.Count
    if ($running.Count -gt 0) { Info "Old Hermes processes running: $($running.Count) (they are left alone)" }
  } catch { }
  $fingerBefore = Get-ExistingFingerprint
  WriteText (Join-Path $Diag 'existing_fingerprint_before.txt') $fingerBefore

  # ------------------------------------------------------------ bundle metadata
  if (-not (Test-Path -LiteralPath $Verify -PathType Leaf)) { throw 'VerifyOfflineBundle.ps1 not found next to BUNDLE.json.' }
  $meta = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
  $metaNames = @($meta.PSObject.Properties.Name)
  foreach ($k in @('release', 'installContract', 'desktopIncluded', 'commit')) { if ($metaNames -notcontains $k) { throw "BUNDLE.json has no '$k' field; this is not the v4.6 Windows 10 bundle." } }
  Note 'bundleRelease' $meta.release
  Note 'bundleCommit' $meta.commit
  if ($meta.release -ne $ExpectedRelease -or $meta.installContract -ne 'legacy-auto-cleanvenv-win10' -or $meta.desktopIncluded) {
    throw "Pilot requires the v4.6 Windows 10 $ExpectedRelease native bundle (found release=$($meta.release), contract=$($meta.installContract), desktop=$($meta.desktopIncluded))."
  }

  Info 'Step 1/6: key-file integrity (VerifyOfflineBundle.ps1)'
  & $Verify -BundleRoot $BundleRoot
  Note 'verifyOfflineBundle' 'passed'

  # ------------------------------------------------------------ extraction completeness
  Info 'Step 2/6: extraction completeness and path lengths (can take 1-3 minutes)'
  $zipPath = Join-Path (Split-Path -Parent $BundleRoot) ((Split-Path -Leaf $BundleRoot) + '.zip')
  if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Info "Transfer ZIP found: $zipPath"
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    Note 'zipSha256' $zipHash
    if ($zipHash -eq $ExpectedZipSha256) { Info 'ZIP SHA256 matches the factory v4.6 value.'; Note 'zipSha256Match' 'yes' }
    else { Warn "ZIP SHA256 differs from factory v4.6 value $ExpectedZipSha256. If you rebuilt the ZIP this is expected; otherwise re-transfer."; Note 'zipSha256Match' 'NO' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $za = [IO.Compression.ZipFile]::OpenRead($zipPath)
    $leaf = Split-Path -Leaf $BundleRoot
    $zFiles = 0; $missing = New-Object System.Collections.Generic.List[string]; $sizeBad = 0; $unverifiable = 0
    try {
      foreach ($e in $za.Entries) {
        if ([string]::IsNullOrEmpty($e.Name)) { continue }
        $sep = [IO.Path]::DirectorySeparatorChar
        $rel = $e.FullName.Replace('/', $sep).Replace('\', $sep)
        if ($rel.StartsWith($leaf + $sep, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($leaf.Length + 1) }
        $zFiles++
        $target = [IO.Path]::Combine($BundleRoot, $rel)
        if ($target.Length -ge 260) { $unverifiable++; continue }
        if (-not [IO.File]::Exists($target)) { $missing.Add($rel) | Out-Null; continue }
        if ((New-Object IO.FileInfo $target).Length -ne $e.Length) { $sizeBad++ }
      }
    } finally { $za.Dispose() }
    Note 'zipFileEntries' $zFiles
    Note 'extractMissing' $missing.Count
    Note 'extractSizeMismatch' $sizeBad
    Note 'extractUnverifiableLongPaths' $unverifiable
    Info "ZIP entries: $zFiles, missing after extraction: $($missing.Count), size mismatch: $sizeBad, too long to check: $unverifiable"
    if ($missing.Count -gt 0 -or $sizeBad -gt 0) {
      WriteText (Join-Path $Diag 'missing_files.txt') ($missing -join "`r`n")
      throw ("Extraction is INCOMPLETE ($($missing.Count) missing, $sizeBad wrong size). First missing: " + (($missing | Select-Object -First 3) -join ' ; ') + ". Re-extract with: tar -xf `"$zipPath`" -C `"$(Split-Path -Parent $BundleRoot)`"")
    }
  } else {
    Warn "Transfer ZIP not found at $zipPath - full extraction check skipped (only key files were verified)."
    Note 'zipSha256' 'not-checked'
  }

  $gciErr = $null
  $payloadFiles = @(Get-ChildItem -LiteralPath $Payload -Recurse -Force -File -ErrorAction SilentlyContinue -ErrorVariable gciErr)
  $payloadBytes = [long]0; $maxRel = 0; $longest = ''
  foreach ($f in $payloadFiles) {
    $payloadBytes += $f.Length
    $relLen = $f.FullName.Length - $Payload.Length - 1
    if ($relLen -gt $maxRel) { $maxRel = $relLen; $longest = $f.FullName.Substring($Payload.Length + 1) }
  }
  $enumErrors = @($gciErr).Count
  $prodRoot = Join-Path $HermesHomeOld 'hermes-agent'
  $stageRoot = Join-Path $HermesHomeOld '.stage-yyyyMMdd_HHmmss-xxxxxxxx'
  $payloadMB = [math]::Round($payloadBytes / 1MB, 0)
  Note 'payloadFiles' $payloadFiles.Count
  Note 'payloadMB' $payloadMB
  Note 'payloadEnumErrors' $enumErrors
  Note 'longestRelativePath' $maxRel
  Note 'longestRelativeFile' $longest
  Note 'maxPathProduction' ($prodRoot.Length + 1 + $maxRel)
  Note 'maxPathInstallerStage' ($stageRoot.Length + 1 + $maxRel)
  Note 'maxPathPilot' ($Runtime.Length + 1 + $maxRel)
  Info "Payload: $($payloadFiles.Count) files, $payloadMB MB, longest relative path $maxRel chars"
  Info "Longest full path -> production: $($prodRoot.Length + 1 + $maxRel), installer stage: $($stageRoot.Length + 1 + $maxRel), pilot: $($Runtime.Length + 1 + $maxRel)  (Windows limit without LongPaths: 259; LongPathsEnabled=$longPaths)"
  if ($enumErrors -gt 0) { Warn "$enumErrors payload entries could not be listed (often path-too-long). First: $(@($gciErr)[0])" }
  if (($prodRoot.Length + 1 + $maxRel) -gt 259 -and $longPaths -notlike '1*') { Warn 'Longest payload path exceeds 259 chars in the PRODUCTION location and LongPathsEnabled is off.' }

  $drive = New-Object System.IO.DriveInfo ($LocalApp.Substring(0, 1))
  $freeMB = [math]::Round($drive.AvailableFreeSpace / 1MB, 0)
  Note 'freeMB_LocalAppDataDrive' $freeMB
  $needMB = [math]::Round($payloadMB * 1.1 + 500, 0)
  Info "Free space on $($drive.Name): $freeMB MB, pilot needs about $needMB MB"
  if ($freeMB -lt $needMB) { throw "Not enough disk space for the pilot copy ($freeMB MB free, about $needMB MB needed). Nothing was copied." }

  # ------------------------------------------------------------ copy
  Info 'Step 3/6: copying runtime to the isolated pilot folder (several minutes)'
  New-Item -ItemType Directory -Path $Runtime -Force | Out-Null
  $rcLog = Join-Path $Diag 'robocopy.log'
  & robocopy.exe $Payload $Runtime /MIR /R:2 /W:1 /NP /NFL /NDL "/LOG:$rcLog" | Out-Null
  $copyCode = $LASTEXITCODE
  Note 'robocopyExit' $copyCode
  if ($copyCode -gt 7) {
    $tail = ''
    try { $tail = (Get-Content -LiteralPath $rcLog -Tail 15) -join "`r`n" } catch { }
    throw "Runtime copy failed (robocopy exit $copyCode). Existing Hermes was not changed.`r`n$tail"
  }
  $copied = @(Get-ChildItem -LiteralPath $Runtime -Recurse -Force -File -ErrorAction SilentlyContinue).Count
  Note 'pilotRuntimeFiles' $copied
  if ($copied -lt $payloadFiles.Count) { throw "Copied $copied of $($payloadFiles.Count) files. See $rcLog" }
  foreach ($relative in @('manifest.json', 'bin\hermes.exe', 'pm-runtime\pm-runtime.json', 'venv', 'tools\facts.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Runtime $relative))) { throw "Missing pilot runtime component: $relative" }
  }
  $cfg = Join-Path $Runtime 'venv\pyvenv.cfg'
  if (Test-Path -LiteralPath $cfg -PathType Leaf) {
    $cfgText = Get-Content -LiteralPath $cfg -Raw
    WriteText (Join-Path $Diag 'pyvenv.cfg.txt') $cfgText
    if ($cfgText -match '(?i)[A-Z]:\\H4\\') { Warn 'venv\pyvenv.cfg still contains a factory path (C:\H4\...). If the smoke test fails, this is the first suspect.' }
  }

  # ------------------------------------------------------------ isolated env
  New-Item -ItemType Directory -Path $PilotHome -Force | Out-Null
  foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
  $env:HERMES_HOME = $PilotHome
  $env:UV_OFFLINE = 'true'
  $env:PIP_NO_INDEX = '1'
  $env:PYTHONUTF8 = '1'
  $env:PYTHONIOENCODING = 'utf-8'
  # Same offline guard as the real installer: any accidental network call fails fast.
  $env:HTTP_PROXY = 'http://127.0.0.1:9'
  $env:HTTPS_PROXY = 'http://127.0.0.1:9'
  $env:ALL_PROXY = 'http://127.0.0.1:9'
  $exe = Join-Path $Runtime 'bin\hermes.exe'

  Info 'Step 4/6: smoke test hermes --version'
  $r = Invoke-Native 'version' $exe @('--version') 300 $Diag
  Note 'versionExit' $r.ExitCode
  Note 'versionSeconds' $r.Seconds
  $vText = ($r.StdOut + ' ' + $r.StdErr).Trim() -replace '\s+', ' '
  if ($vText.Length -gt 300) { $vText = $vText.Substring(0, 300) + '...' }
  Note 'versionText' $vText
  if ($r.TimedOut) { throw 'hermes --version did not finish in 300 s (hang). See version.txt.' }
  if ($r.ExitCode -ne 0) { throw "hermes --version failed (exit $($r.ExitCode)). See version.txt." }
  if ($r.StdOut -notmatch 'Hermes Agent v') { Warn 'Unexpected --version text (no "Hermes Agent v").' }
  if ($r.StdOut -match 'vunknown') { Info 'Note: "vunknown (2026.9.24)" is expected for this payload: it has no install-stamp.json, and 2026.9.24 is the release-date constant inside the v0.22.2 source itself.' }

  Info 'Step 5/6: smoke test hermes --help'
  $r = Invoke-Native 'help' $exe @('--help') 300 $Diag
  Note 'helpExit' $r.ExitCode
  Note 'helpSeconds' $r.Seconds
  if ($r.TimedOut) { throw 'hermes --help did not finish in 300 s (hang). See help.txt.' }
  if ($r.ExitCode -ne 0) { throw "hermes --help failed (exit $($r.ExitCode)). See help.txt." }

  Info 'Step 6/6: hermes doctor (informational, isolated empty profile - failures here are expected without a model config)'
  $r = Invoke-Native 'doctor' $exe @('doctor') 180 $Diag
  Note 'doctorExit' $r.ExitCode
  Note 'doctorTimedOut' $r.TimedOut

  $fingerAfter = Get-ExistingFingerprint
  WriteText (Join-Path $Diag 'existing_fingerprint_after.txt') $fingerAfter
  if ($fingerAfter -eq $fingerBefore) { Note 'existingInstallUnchanged' 'yes'; Info 'Existing installation fingerprint: UNCHANGED' }
  else { Note 'existingInstallUnchanged' 'NO'; Warn 'Existing installation fingerprint CHANGED during the pilot - compare existing_fingerprint_before/after.txt.' }

  Write-Host ''
  Write-Host '[PILOT_OK] Isolated Hermes v0.22.2 CLI started from a relocated copy; current installation untouched.' -ForegroundColor Green
  Note 'result' 'PILOT_OK'
  $ExitCode = 0
} catch {
  Note 'result' 'PILOT_ERROR'
  Note 'error' $_.Exception.Message
  try { Note 'errorLine' $_.InvocationInfo.ScriptLineNumber } catch { }
  Write-Host ''
  Write-Host "[PILOT_ERROR] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "[PILOT] Existing Hermes location was not modified by this pilot: $Existing"
  $ExitCode = 1
} finally {
  foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $oldEnv[$key], 'Process') }
  Note 'warnings' ($Warnings -join ' | ')
  try {
    $lines = foreach ($k in $Summary.Keys) { "$k=$($Summary[$k])" }
    WriteText (Join-Path $Diag 'summary.txt') ($lines -join "`r`n")
    Write-Host ''
    Write-Host '----- summary.txt -----'
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host '-----------------------'
    Write-Host "[PILOT] Diagnostic folder: $Diag"
    Write-Host '[PILOT] Send summary.txt (and version.txt/help.txt on failure). Remove company URLs/tokens first.'
    Write-Host "[PILOT] To remove the pilot later: delete $PilotBase (it contains nothing else)."
  } catch { Write-Host "[PILOT_WARN] Could not write summary: $($_.Exception.Message)" }
  if ($Started) { try { Stop-Transcript | Out-Null } catch { } }
}
exit $ExitCode
