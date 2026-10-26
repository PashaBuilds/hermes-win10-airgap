# Hermes v0.22.2 - Windows 10 Desktop delta kit (FACTORY / Internet PC side)
#
# The official MSIX needs Windows 11 22H2 only because of its manifest schema.
# The unpacked Electron app (release\win-unpacked) carries its own runtime in
# resources\agent-payload, which should be (almost) the same as the native
# payload already transferred to the intranet in
# HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip.
#
# This script hashes every win-unpacked file, compares agent-payload files with
# that already-transferred payload and packs ONLY the Electron shell plus the
# agent-payload files that differ. The intranet pilot rebuilds win-unpacked from
# payload + delta and verifies every file against desktop-manifest.tsv (SHA256).
#
# Read-only for win-unpacked and the bundle; writes only to -WorkDir and -OutDir.
[CmdletBinding()]
param(
  [string]$Unpacked = 'C:\H4\jobs\v0.22.2_Slim\src\apps\desktop\release\win-unpacked',
  [string]$BundleDir = '',
  [string]$OutDir = 'C:\H4\output',
  [string]$WorkDir = 'C:\H4\dd'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$KitVersion = '1.0'
$Name = 'HermesDesktopWin10_v0.22.2_delta'
$ExeName = 'Hermes Agent.exe'
$Sep = [IO.Path]::DirectorySeparatorChar
$AgentPrefix = 'resources\agent-payload\'

function Info([string]$t) { Write-Host "[DELTA] $t" }
function NativePath([string]$root, [string]$rel) { [IO.Path]::Combine($root, $rel.Replace('\', $Sep)) }
function RelOf([string]$root, [string]$full) { $full.Substring($root.Length).TrimStart('\', '/').Replace('/', '\') }
$Hasher = [Security.Cryptography.SHA256]::Create()
function Sha([string]$path) {
  $s = [IO.File]::OpenRead($path)
  try { return ([BitConverter]::ToString($Hasher.ComputeHash($s))).Replace('-', '').ToLowerInvariant() } finally { $s.Dispose() }
}
function WriteText([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }

try {
  Info "Desktop delta kit v$KitVersion"
  # ------------------------------------------------------------ inputs
  $Unpacked = [IO.Path]::GetFullPath($Unpacked.TrimEnd('\', '/'))
  $exe = Join-Path $Unpacked $ExeName
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Not found: $exe" }
  $agentRoot = NativePath $Unpacked 'resources\agent-payload'
  if (-not (Test-Path -LiteralPath (Join-Path $agentRoot 'manifest.json') -PathType Leaf)) { throw "agent-payload\manifest.json missing under $Unpacked" }
  Info "win-unpacked : $Unpacked"

  if ([string]::IsNullOrWhiteSpace($BundleDir)) {
    $pkgRoot = NativePath (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Unpacked))))) 'package'
    # ...\v0.22.2_Slim\src\apps\desktop\release\win-unpacked -> ...\v0.22.2_Slim\package
    $cands = @(Get-ChildItem -LiteralPath $pkgRoot -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'BUNDLE.json') -PathType Leaf })
    $BundleDir = $null
    foreach ($c in $cands) {
      $m = Get-Content -LiteralPath (Join-Path $c.FullName 'BUNDLE.json') -Raw | ConvertFrom-Json
      if (@($m.PSObject.Properties.Name) -contains 'installContract' -and $m.installContract -eq 'legacy-auto-cleanvenv-win10') { $BundleDir = $c.FullName; break }
    }
    if (-not $BundleDir) { throw "Windows 10 bundle folder not found under $pkgRoot. Pass -BundleDir <folder that holds BUNDLE.json and payload>." }
  }
  $BundleDir = [IO.Path]::GetFullPath($BundleDir.TrimEnd('\', '/'))
  $payload = Join-Path $BundleDir 'payload'
  $meta = Get-Content -LiteralPath (Join-Path $BundleDir 'BUNDLE.json') -Raw | ConvertFrom-Json
  if ($meta.release -ne 'v0.22.2' -or $meta.installContract -ne 'legacy-auto-cleanvenv-win10') { throw "Bundle at $BundleDir is not the v0.22.2 Windows 10 bundle." }
  # Prove this folder still equals what went into the transferred ZIP (key-file hashes).
  foreach ($e in $meta.hashes.PSObject.Properties) {
    $f = NativePath $BundleDir $e.Name
    if ((Sha $f) -ne $e.Value.ToLowerInvariant()) { throw "Bundle folder changed since packaging: $($e.Name). Use the folder that produced the transferred ZIP." }
  }
  Info "bundle       : $BundleDir (created $($meta.createdUtc), key hashes OK)"

  # ------------------------------------------------------------ hash + classify
  Info 'Hashing win-unpacked and comparing agent-payload with the transferred payload (several minutes)...'
  $files = @(Get-ChildItem -LiteralPath $Unpacked -Recurse -File -Force)
  $rows = New-Object System.Collections.Generic.List[object]
  $usedPayload = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $i = 0; $fromPayload = 0; $delta = 0; $deltaBytes = [long]0; $totalBytes = [long]0; $agentDiff = 0; $agentNew = 0
  foreach ($f in $files) {
    $i++
    if ($i % 5000 -eq 0) { Info "  $i / $($files.Count)" }
    $rel = RelOf $Unpacked $f.FullName
    $hash = Sha $f.FullName
    $totalBytes += $f.Length
    $src = 'D'
    if ($rel.StartsWith($AgentPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      $prel = $rel.Substring($AgentPrefix.Length)
      $pf = NativePath $payload $prel
      if ([IO.File]::Exists($pf)) {
        $null = $usedPayload.Add($prel)
        if ((New-Object IO.FileInfo $pf).Length -eq $f.Length -and (Sha $pf) -eq $hash) { $src = 'P' } else { $agentDiff++ }
      } else { $agentNew++ }
    }
    if ($src -eq 'P') { $fromPayload++ } else { $delta++; $deltaBytes += $f.Length }
    $rows.Add([pscustomobject]@{ Hash = $hash; Size = $f.Length; Src = $src; Rel = $rel }) | Out-Null
  }
  $payloadCount = @(Get-ChildItem -LiteralPath $payload -Recurse -File -Force).Count
  $payloadExtras = $payloadCount - $usedPayload.Count
  Info "files: $($rows.Count), from payload: $fromPayload, in delta: $delta ($([math]::Round($deltaBytes/1MB,1)) MB)"
  Info "agent-payload differing: $agentDiff, agent-payload only: $agentNew, payload files not used by Desktop: $payloadExtras"

  # ------------------------------------------------------------ stage
  $stage = Join-Path $WorkDir $Name
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  $filesDir = Join-Path $stage 'files'
  New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
  foreach ($r in $rows) {
    if ($r.Src -ne 'D') { continue }
    $dst = NativePath $filesDir $r.Rel
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::Copy((NativePath $Unpacked $r.Rel), $dst, $true)
  }
  $manifestPath = Join-Path $stage 'desktop-manifest.tsv'
  $lines = foreach ($r in ($rows | Sort-Object Rel)) { "$($r.Hash)`t$($r.Size)`t$($r.Src)`t$($r.Rel)" }
  WriteText $manifestPath (($lines -join "`r`n") + "`r`n")
  $stampInfo = @{}
  $stampFile = NativePath $Unpacked 'resources\install-stamp.json'
  if (Test-Path -LiteralPath $stampFile) {
    $st = Get-Content -LiteralPath $stampFile -Raw | ConvertFrom-Json
    foreach ($k in @('commit', 'baseVersion', 'updateMechanism', 'payload', 'source')) { if (@($st.PSObject.Properties.Name) -contains $k) { $stampInfo[$k] = [string]$st.$k } }
  }
  $info = [ordered]@{
    kit = $KitVersion; release = 'v0.22.2'; exe = $ExeName
    bundleZip = (Split-Path -Leaf $BundleDir) + '.zip'; bundleCommit = $meta.commit; bundleCreatedUtc = $meta.createdUtc
    files = $rows.Count; fromPayload = $fromPayload; delta = $delta; deltaBytes = $deltaBytes; totalBytes = $totalBytes
    agentPayloadDiffering = $agentDiff; agentPayloadOnly = $agentNew; payloadFilesUnused = $payloadExtras
    desktopStamp = $stampInfo; manifestSha256 = (Sha $manifestPath); createdUtc = [DateTime]::UtcNow.ToString('o')
  }
  WriteText (Join-Path $stage 'DESKTOP_DELTA.json') ($info | ConvertTo-Json -Depth 4)
  foreach ($n in @('TestHermesDesktopWin10Pilot.bat', 'TestHermesDesktopWin10Pilot.ps1', 'README_DESKTOP_PILOT.txt')) {
    $src = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'intranet') $n
    if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $PSScriptRoot $n }
    if (-not (Test-Path -LiteralPath $src)) { throw "Kit file missing: $n (keep the kit folder structure)" }
    Copy-Item -LiteralPath $src -Destination (Join-Path $stage $n) -Force
  }

  # ------------------------------------------------------------ zip
  New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
  $zip = Join-Path $OutDir ($Name + '.zip')
  $pending = Join-Path $OutDir ('.pending_' + $Name + '.zip')
  if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force }
  $tar = (Get-Command tar.exe -ErrorAction Stop).Source
  & $tar -a -cf $pending -C $WorkDir $Name
  if ($LASTEXITCODE -ne 0) { throw "tar failed (exit $LASTEXITCODE)" }
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
  Move-Item -LiteralPath $pending -Destination $zip
  $zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  WriteText ($zip + '.sha256') ("$zipHash  $Name.zip`r`n")
  $zipMB = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)

  Write-Host ''
  Write-Host '[DELTA_OK] Desktop delta kit ready.' -ForegroundColor Green
  Write-Host "  ZIP     : $zip"
  Write-Host "  Size    : $zipMB MB"
  Write-Host "  SHA256  : $zipHash"
  Write-Host "  Files   : $($rows.Count) total, $fromPayload taken from the transferred payload, $delta in the kit"
  Write-Host "  Differ  : $agentDiff agent-payload files differ, $agentNew only in agent-payload, $payloadExtras payload files unused"
  if ($deltaBytes -gt 1500MB) { Write-Warning 'Delta is large: agent-payload differs a lot from the transferred payload. Send this report before transferring.' }
  exit 0
} catch {
  Write-Host "[DELTA_ERROR] $($_.Exception.Message)" -ForegroundColor Red
  try { Write-Host "  line $($_.InvocationInfo.ScriptLineNumber)" } catch { }
  exit 1
} finally {
  $Hasher.Dispose()
}
