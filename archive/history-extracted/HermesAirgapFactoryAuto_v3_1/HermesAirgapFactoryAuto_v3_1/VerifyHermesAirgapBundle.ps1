param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $ZipPath)) { throw "ZIP not found: $ZipPath" }

$entries = tar -tf $ZipPath
$checks = [ordered]@{
    "Installer BAT" = ($entries | Where-Object { $_ -match '(^|/)InstallOrUpdateHermesAirgapped\.bat$' } | Select-Object -First 1)
    "Installer PS1" = ($entries | Where-Object { $_ -match '(^|/)InstallOrUpdateHermesAirgapped\.ps1$' } | Select-Object -First 1)
    "Wheelhouse" = ($entries | Where-Object { $_ -match '(^|/)wheelhouse/' } | Select-Object -First 1)
    "Build requirements" = ($entries | Where-Object { $_ -match 'requirements-build\.txt$' } | Select-Object -First 1)
    "Hermes source" = ($entries | Where-Object { $_ -match '(^|/)hermes-agent/pyproject\.toml$' } | Select-Object -First 1)
    "Desktop EXE" = ($entries | Where-Object { $_ -match 'apps/desktop/release/win-unpacked/.*\.exe$' } | Select-Object -First 1)
}
$checks.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{ Check=$_.Key; Found=[bool]$_.Value; Entry=$_.Value }
} | Format-Table -AutoSize

Get-FileHash $ZipPath -Algorithm SHA256
