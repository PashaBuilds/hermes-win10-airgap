<#
.SYNOPSIS
  Windows end-to-end test for HermesKurulumAsistani.exe: real old bundle installed with its own script,
  then the assistant (driven through UI Automation, like a user clicking) upgrades to the new bundle,
  installs a test "company" CA, accepts the Windows certificate prompt, configures a model against an
  HTTPS fake server signed by that CA, and the result is verified.
.NOTES
  Windows PowerShell 5.1. Used by .github/workflows/installer-app.yml (job e2e-upgrade). Destructive for
  the current user's Hermes install: only run on a throw-away machine / CI runner.
  Saved as UTF-8 with BOM so Windows PowerShell 5.1 reads the Turkish UI strings correctly.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$OldZip,
    [Parameter(Mandatory = $true)][string]$NewZip,
    [Parameter(Mandatory = $true)][string]$Python,
    [string]$WorkDir = 'C:\e2e',
    [string]$OutDir = (Join-Path $PWD 'e2e-out'),
    [int]$Port = 18443
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Force -Path $WorkDir, $OutDir | Out-Null
$script:failures = New-Object System.Collections.Generic.List[string]
$script:shot = 0

function Step([string]$m) { Write-Host ('[{0}] == {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Check([string]$name, [bool]$ok, [string]$extra = '') {
    if ($ok) { Write-Host "  PASS  $name" } else { Write-Host "  FAIL  $name  $extra"; $script:failures.Add($name) }
}
function Shot([string]$name) {
    try {
        $script:shot++
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save((Join-Path $OutDir ('{0:00}-{1}.png' -f $script:shot, $name)))
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Warning "screenshot failed: $_" }
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
}
function Hermes-Version {
    Refresh-Path
    $o = & cmd.exe /c 'hermes --version 2>&1'
    return ($o | Out-String).Trim()
}
# Note: WPF Border/Panel elements are not in the UI Automation tree; only controls and TextBlocks are.
function Cond($prop, $val) { New-Object System.Windows.Automation.PropertyCondition($prop, $val) }
function El($win, [string]$id) { $win.FindFirst($TS::Descendants, (Cond $AE::AutomationIdProperty $id)) }
function NameOf($win, [string]$id) { $e = El $win $id; if ($e) { $e.Current.Name } else { $null } }
function Click($win, [string]$id) {
    $e = El $win $id
    if (-not $e) { throw "element $id not found" }
    $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
function SetText($win, [string]$id, [string]$value) {
    $e = El $win $id
    if (-not $e) { throw "element $id not found" }
    $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($value)
}
function Wait-For([scriptblock]$cond, [int]$seconds, [string]$what, [scriptblock]$tick = $null) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $seconds) {
        if ($tick) { & $tick }
        $r = $null
        try { $r = & $cond } catch { }
        if ($r) { return $r }
        Start-Sleep -Milliseconds 700
    }
    Shot ('timeout-' + ($what -replace '[^A-Za-z0-9]', '_'))
    throw "Timeout ($seconds s): $what"
}
function Hermes-Home {
    $h = [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')
    if (-not $h) { $h = Join-Path $env:LOCALAPPDATA 'hermes' }
    return $h
}

Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class E2EWin {
  delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(P cb, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int n);
  public static List<string> List() {
    var r = new List<string>();
    EnumWindows((h, l) => { if (!IsWindowVisible(h)) return true; uint pid; GetWindowThreadProcessId(h, out pid);
      var c = new StringBuilder(64); GetClassName(h, c, 64); var t = new StringBuilder(256); GetWindowText(h, t, 256);
      r.Add(pid + " | " + c + " | " + t); return true; }, IntPtr.Zero);
    return r;
  }
}
"@
function Dump-Windows {
    Write-Host "  visible top-level windows (pid | class | title):"
    foreach ($l in [E2EWin]::List()) { if ($l -notmatch '\| $') { Write-Host "    $l" } }
}

# Clicks "Yes" on the Windows "Security Warning" prompt that adding a root CA to CurrentUser\Root shows.
$script:certPromptAccepted = $false
function Accept-CertPrompt {
    $wins = $AE::RootElement.FindAll($TS::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $wins) {
        $n = $w.Current.Name
        if ($n -match 'Security Warning|Güvenlik Uyarısı') {
            $btns = $w.FindAll($TS::Descendants, (Cond $AE::ControlTypeProperty ([System.Windows.Automation.ControlType]::Button)))
            foreach ($b in $btns) {
                if ($b.Current.Name -match '^&?(Yes|Evet)$') {
                    Shot 'windows-cert-prompt'
                    $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                    $script:certPromptAccepted = $true
                    Write-Host "  (Windows certificate prompt accepted)"
                    return
                }
            }
        }
    }
}

function Save-AppLogs {
    $d = Join-Path $env:LOCALAPPDATA 'HermesKurulumAsistani\logs'
    if (Test-Path $d) { Get-ChildItem $d -Filter *.log | ForEach-Object { Copy-Item $_.FullName $OutDir -Force } }
}
trap { Save-AppLogs; Dump-Windows; break }

# ---------------------------------------------------------------- 1. old version, installed the classic way
Step "Installing old bundle with its own script: $OldZip"
$oldDir = Join-Path $WorkDir 'old'
New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
& tar.exe -xf $OldZip -C $oldDir
if ($LASTEXITCODE -ne 0) { throw "tar failed for $OldZip" }
$oldRoot = (Get-ChildItem $oldDir -Directory | Select-Object -First 1).FullName
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $oldRoot 'InstallOrUpdateHermesAirgapped.ps1') -Mode Auto -CleanVenv *> (Join-Path $OutDir 'old-install.log')
Check 'old bundle installed (script exit 0)' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$oldVer = Hermes-Version
Write-Host "  old: $oldVer"
$oldTag = ([IO.Path]::GetFileName($OldZip) -replace '^HermesAirgapBundle_(v[0-9.]+)_.*$', '$1')
$newTag = ([IO.Path]::GetFileName($NewZip) -replace '^HermesAirgapBundle_(v[0-9.]+)_.*$', '$1')
Check "hermes --version shows $oldTag before the upgrade" ($oldVer -match [regex]::Escape($oldTag.TrimStart('v')))

# user data that must survive the upgrade
$hh = Hermes-Home
foreach ($d in 'sessions', 'memories', 'skills') { New-Item -ItemType Directory -Force -Path (Join-Path $hh $d) | Out-Null }
Set-Content -Path (Join-Path $hh 'sessions\e2e-marker.json') -Value '{"e2e": "session must survive"}' -Encoding UTF8
Set-Content -Path (Join-Path $hh 'memories\e2e-marker.md') -Value 'memory must survive' -Encoding UTF8
Add-Content -Path (Join-Path $hh '.env') -Value 'E2E_KEEP_ME=1' -Encoding UTF8

# ---------------------------------------------------------------- 2. test CA + HTTPS model server
Step 'Creating test CA and HTTPS fake model server'
$caDir = Join-Path $WorkDir 'ca'
& $Python (Join-Path $here 'make_test_ca.py') $caDir
if ($LASTEXITCODE -ne 0) { throw 'make_test_ca.py failed' }
$crt = Join-Path $WorkDir 'indirilenler\Sirket Kok Sertifikasi (1).crt'   # odd name on purpose
New-Item -ItemType Directory -Force -Path (Split-Path $crt) | Out-Null
Copy-Item (Join-Path $caDir 'ca.crt') $crt -Force
$caCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $crt
$env:FAKE_TLS_CERT = Join-Path $caDir 'server.pem'; $env:FAKE_TLS_KEY = Join-Path $caDir 'server.key'
$server = Start-Process -FilePath $Python -ArgumentList @((Join-Path $here '..\python\fake_openai_server.py'), $Port) -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

# ---------------------------------------------------------------- 3. the assistant, like a user
Step 'Starting the assistant next to the new bundle (auto-detect) with --sertifika'
$transfer = Join-Path $WorkDir 'aktarim'
New-Item -ItemType Directory -Force -Path $transfer | Out-Null
Copy-Item $Exe $transfer -Force
Copy-Item $NewZip $transfer -Force
if (Test-Path "$NewZip.sha256") { Copy-Item "$NewZip.sha256" $transfer -Force }
$appExe = Join-Path $transfer ([IO.Path]::GetFileName($Exe))
$app = Start-Process -FilePath $appExe -ArgumentList @('--sertifika', ('"' + $crt + '"')) -PassThru
$win = Wait-For { $AE::RootElement.FindFirst($TS::Children, (Cond $AE::ProcessIdProperty $app.Id)) } 60 'main window'
try { $win.SetFocus() } catch { }

$next = Wait-For { $e = El $win 'NextBtn'; if ($e -and $e.Current.IsEnabled) { $e } } 120 'package page ready (bundle auto-detected)'
$chipInstalled = NameOf $win 'ChipInstalled'; $chipBundle = NameOf $win 'ChipBundle'
Write-Host "  chips: installed='$chipInstalled' bundle='$chipBundle'"
Check 'header shows installed old version' ($chipInstalled -match [regex]::Escape($oldTag))
Check 'header shows bundle new version' ($chipBundle -match [regex]::Escape($newTag))
Shot 'package-page'
Click $win 'NextBtn'

Wait-For { ((NameOf $win 'CertStatus') -match '^(✓|✕)') -and (El $win 'NextBtn').Current.IsEnabled } 30 'certificate page ready' | Out-Null
$certStatus = NameOf $win 'CertStatus'
Write-Host "  cert status: $certStatus"
Check 'certificate accepted by the assistant' ($certStatus -match '^✓')
Shot 'cert-page'
Click $win 'NextBtn'

Step 'Running install (watching progress, accepting the Windows certificate prompt)'
$script:midShot = $false
$script:lastDump = [DateTime]::MinValue
Wait-For {
    $n = El $win 'NextBtn'
    $n -and $n.Current.IsEnabled -and ((El $win 'RunErrorText') -or $n.Current.Name -match 'Model|Özet')
} 1500 'install finished' {
    Accept-CertPrompt
    if (-not $script:midShot) {
        $p = NameOf $win 'OverallPercent'
        if ($p -and [int]($p -replace '[^0-9]', '') -ge 50) { Shot 'install-progress'; $script:midShot = $true; Write-Host "  progress $p, phase: $(NameOf $win 'CurrentPhase')" }
    }
    if (((Get-Date) - $script:lastDump).TotalSeconds -ge 60) {
        $script:lastDump = Get-Date
        Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] $(NameOf $win 'OverallPercent') $(NameOf $win 'CurrentPhase') | $(NameOf $win 'CurrentDetail')"
        if ((NameOf $win 'CurrentPhase') -match 'ertifika') { Dump-Windows }
    }
} | Out-Null
Shot 'install-finished'
$runError = El $win 'RunErrorText'   # Borders have no UIA peer; the TextBlock inside is visible only on error
Check 'install finished without error panel' (-not $runError) $(if ($runError) { NameOf $win 'RunErrorText' })
Check 'overall progress 100%' ((NameOf $win 'OverallPercent') -eq '100%') (NameOf $win 'OverallPercent')
Check 'Windows certificate prompt appeared and was accepted' $script:certPromptAccepted

Step 'Model page'
Click $win 'NextBtn'
Wait-For { El $win 'ModelEnableCheck' } 60 'model page' | Out-Null
$chk = El $win 'ModelEnableCheck'
$tp = $chk.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
if ($tp.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On) { $tp.Toggle() }
Wait-For { El $win 'BaseUrlBox' } 30 'model form' | Out-Null
SetText $win 'BaseUrlBox' "https://localhost:$Port/v1"
$keyBox = El $win 'ApiKeyBox'
try { $keyBox.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('test-key-123456') }
catch { $keyBox.SetFocus(); [System.Windows.Forms.SendKeys]::SendWait('test-key-123456') }
Click $win 'FetchModelsBtn'
$probe = Wait-For { $t = NameOf $win 'ProbeStatus'; if ($t -match '^(✓|✕)') { $t } } 180 'model list'
Write-Host "  probe: $probe"
Check 'models fetched over HTTPS signed by the test CA (Hermes trusts the installed cert)' ($probe -match '^✓ 2 ')
SetText $win 'ModelCombo' 'model-b'
SetText $win 'DisplayNameBox' 'Test LLM'
Shot 'model-page'
Wait-For { (El $win 'NextBtn').Current.IsEnabled } 30 'save button enabled' | Out-Null
Click $win 'NextBtn'

Step 'Summary'
$title = Wait-For { $t = NameOf $win 'SummaryTitle'; if ($t) { $t } } 300 'summary page'
Start-Sleep -Seconds 2
Shot 'summary'
Write-Host "  summary: $title"
Check 'summary says Hermes is ready' ($title -eq 'Hermes hazır') $title
Click $win 'NextBtn'   # Kapat
Start-Sleep -Seconds 2
if (-not $app.HasExited) { Stop-Process -Id $app.Id -Force }
Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 4. verify like a user would
Step 'Verifying'
$newVer = Hermes-Version
Write-Host "  new: $newVer"
Check "hermes --version shows $newTag after the upgrade" ($newVer -match [regex]::Escape($newTag.TrimStart('v')))
Check 'session marker preserved' (Test-Path (Join-Path $hh 'sessions\e2e-marker.json'))
Check 'memory marker preserved' (Test-Path (Join-Path $hh 'memories\e2e-marker.md'))
$envText = Get-Content -Raw -Path (Join-Path $hh '.env')
Check '.env kept existing entries' ($envText -match 'E2E_KEEP_ME=1')
Check '.env holds the API key under a HERMES_CUSTOM_ variable' ($envText -match 'HERMES_CUSTOM_[A-Z0-9_]+_API_KEY=test-key-123456')
$cfg = Get-Content -Raw -Path (Join-Path $hh 'config.yaml')
Check 'config.yaml: default model model-b, provider custom' (($cfg -match 'model-b') -and ($cfg -match 'provider:\s*custom'))
Check 'config.yaml references the key, never contains it' (($cfg -match '\$\{HERMES_CUSTOM_') -and ($cfg -notmatch 'test-key-123456'))
Check 'config.yaml has display name' ($cfg -match 'Test LLM')
$ssl = [Environment]::GetEnvironmentVariable('SSL_CERT_FILE', 'User')
Check 'User SSL_CERT_FILE -> company-ca-bundle.pem' ($ssl -and $ssl -like '*company-ca-bundle.pem' -and (Test-Path $ssl)) "$ssl"
Check 'REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE match' (([Environment]::GetEnvironmentVariable('REQUESTS_CA_BUNDLE', 'User') -eq $ssl) -and ([Environment]::GetEnvironmentVariable('CURL_CA_BUNDLE', 'User') -eq $ssl))
$node = [Environment]::GetEnvironmentVariable('NODE_EXTRA_CA_CERTS', 'User')
Check 'NODE_EXTRA_CA_CERTS -> company-ca.pem' ($node -and (Test-Path $node) -and $node -like '*company-ca.pem')
$inStore = @(Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Thumbprint -eq $caCert.Thumbprint }).Count -gt 0
Check 'test CA in CurrentUser\Root' $inStore
$logs = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'HermesKurulumAsistani\logs') -Filter *.log
$logText = ($logs | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
Check 'assistant log never contains the API key (nor its prefix)' (($logText -notmatch 'test-key-123456') -and ($logText -notmatch 'test-key'))
Check 'assistant log mentions backup folder' ($logText -match 'hermes_backup_before_airgap_')
$logs | ForEach-Object { Copy-Item $_.FullName $OutDir }

# idempotent: re-running only the certificate part must not duplicate the company cert in the bundle
$bundleText = Get-Content -Raw $ssl
$count = ([regex]::Matches($bundleText, 'BEGIN CERTIFICATE')).Count
Write-Host "  CA bundle certificates: $count"

if ($script:failures.Count) { Write-Host "`nE2E FAILED: $($script:failures -join '; ')"; exit 1 }
Write-Host "`nE2E PASSED"
