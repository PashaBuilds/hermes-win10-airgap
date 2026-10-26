# Hermes v0.22.2 Windows 10: isolated production-machine pilot.
# Only writes to %LOCALAPPDATA%\HermesWin10Pilot; does NOT activate or update
# %LOCALAPPDATA%\hermes\hermes-agent, the existing Desktop launcher or User PATH.
[CmdletBinding()]
param([string]$BundleRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Always resolve from this script file if the caller did not explicitly pass a
# bundle root. A parameter default based on $PSScriptRoot may be empty on some
# PowerShell 5.1 call paths, causing GetFullPath('') to throw before logging.
if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
  $scriptFile = $MyInvocation.MyCommand.Path
  if ([string]::IsNullOrWhiteSpace($scriptFile)) {
    throw '[PILOT_SETUP_ERROR] Script path not available. Run TestHermesWin10Pilot.bat from the extracted bundle.'
  }
  $BundleRoot = Split-Path -Parent $scriptFile
}
if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
  throw '[PILOT_SETUP_ERROR] Bundle folder is empty. Put the 3 pilot files next to BUNDLE.json and payload.'
}
try { $BundleRoot = [IO.Path]::GetFullPath($BundleRoot) }
catch { throw "[PILOT_SETUP_ERROR] Invalid bundle folder '$BundleRoot': $($_.Exception.Message)" }
Write-Host "[PILOT] Bundle folder: $BundleRoot"
$Payload = Join-Path $BundleRoot 'payload'
$Verify = Join-Path $BundleRoot 'VerifyOfflineBundle.ps1'
$MetadataPath = Join-Path $BundleRoot 'BUNDLE.json'
$Existing = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent'
$PilotBase = Join-Path $env:LOCALAPPDATA 'HermesWin10Pilot'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Pilot = Join-Path $PilotBase ('v0.22.2_'+$Stamp+'_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$Runtime = Join-Path $Pilot 'runtime'
$PilotHome = Join-Path $Pilot 'home'
$Log = Join-Path $Pilot 'pilot.log'
$Started = $false
$oldEnv = @{}
$envKeys = @('HERMES_HOME','HERMES_INSTALL_ROOT','HERMES_PAYLOAD_ROOT','HERMES_PAYLOAD_TAG',
  'HERMES_BUILD_COMMIT','HERMES_SITE','HERMES_PYTHON','HERMES_NODE','HERMES_PROFILE',
  'PYTHONPATH','PYTHONHOME','UV_OFFLINE','PIP_NO_INDEX')
foreach ($key in $envKeys) { $oldEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
  New-Item -ItemType Directory -Path $Pilot -ErrorAction Stop | Out-Null
  Start-Transcript -LiteralPath $Log -ErrorAction Stop | Out-Null
  $Started = $true
  Write-Host '[PILOT] This tests v0.22.2 beside the existing Windows 10 Hermes installation.'
  Write-Host "[PILOT] Existing (UNCHANGED): $Existing"
  Write-Host "[PILOT] New isolated location: $Pilot"
  if (-not (Test-Path -LiteralPath $Verify -PathType Leaf)) { throw 'VerifyOfflineBundle.ps1 not found; put the pilot BAT+PS1 inside the extracted bundle root.' }
  if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { throw 'BUNDLE.json missing; extract the complete factory ZIP first.' }
  $meta = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
  if ($meta.release -ne 'v0.22.2' -or $meta.installContract -ne 'legacy-auto-cleanvenv-win10' -or $meta.desktopIncluded) {
    throw 'Pilot requires the v4.6 Windows 10 v0.22.2 native bundle; refuses MSIX/Desktop bundle.'
  }
  if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Pilot requires Windows x64.' }
  # On Windows 11, kernel version still starts with 10.0. Build >= 22000 means Win11.
  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Host "[PILOT] OS: $($os.Caption), build $($os.BuildNumber)"
    if ([int]$os.BuildNumber -ge 22000) { Write-Warning 'Target host is not Windows 10; pilot still runs, but this is not the requested Win10 acceptance test.' }
  } catch { Write-Warning "Could not query Windows build: $($_.Exception.Message)" }
  Write-Host '[PILOT] Checking package integrity...'
  & $Verify -BundleRoot $BundleRoot
  # Copy to a NEW unique folder only. Existing Hermes directories are never mirrored/deleted.
  Write-Host '[PILOT] Copying prepared runtime to the isolated pilot folder. This may take minutes.'
  New-Item -ItemType Directory -Path $Runtime -Force | Out-Null
  & robocopy.exe $Payload $Runtime /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  $copyCode = $LASTEXITCODE
  if ($copyCode -gt 7) { throw "Runtime copy failed (robocopy exit $copyCode). Existing Hermes was not changed." }
  foreach ($relative in @('manifest.json','bin\hermes.exe','pm-runtime\pm-runtime.json','venv','tools\facts.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Runtime $relative))) { throw "Missing pilot runtime component: $relative" }
  }
  New-Item -ItemType Directory -Path $PilotHome -Force | Out-Null
  foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
  $env:HERMES_HOME = $PilotHome
  $env:UV_OFFLINE = 'true'
  $env:PIP_NO_INDEX = '1'
  $exe = Join-Path $Runtime 'bin\hermes.exe'
  Write-Host '[PILOT] Smoke test 1: hermes --version'
  & $exe --version 2>&1 | Tee-Object -FilePath (Join-Path $Pilot 'version.txt')
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Pilot hermes --version failed (exit $code)." }
  Write-Host '[PILOT] Smoke test 2: hermes --help'
  & $exe --help 2>&1 | Tee-Object -FilePath (Join-Path $Pilot 'help.txt')
  $code = $LASTEXITCODE
  if ($code -ne 0) { throw "Pilot hermes --help failed (exit $code)." }
  Write-Host ''
  Write-Host '[PILOT_OK] Isolated Hermes CLI started without changing the current installation.' -ForegroundColor Green
  Write-Host "[PILOT] Runtime: $exe"
  Write-Host "[PILOT] Log: $Log"
  Write-Warning 'This is not a Desktop GUI test, nor a guarantee that updating the active installation is safe.'
  Write-Warning 'To test a local DeepSeek/MCP connection, arrange a separate pilot profile and do not change the existing Hermes configuration.'
} catch {
  Write-Host "[PILOT_ERROR] $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "[PILOT] Existing Hermes location was not modified by this pilot: $Existing"
  Write-Host "[PILOT] Diagnostic folder: $Pilot"
  exit 1
} finally {
  foreach ($key in $envKeys) { [Environment]::SetEnvironmentVariable($key, $oldEnv[$key], 'Process') }
  if ($Started) { Stop-Transcript | Out-Null }
}
