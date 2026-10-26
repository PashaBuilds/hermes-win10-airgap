# HermesAirgapFactoryAuto v4.1 - Parse all shipped .ps1 files with the host PowerShell parser.
# Fast, offline and read-only: does not invoke Git, npm, Hermes, or any build operation.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$files = @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.ps1')
if ($files.Count -lt 3) { throw "Unexpected factory contents: only $($files.Count) PowerShell files found" }
$failed = $false
foreach ($item in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed = $true
        Write-Host "[PARSE ERROR] $($item.FullName)" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host ("  line {0}, column {1}: {2}" -f $err.Extent.StartLineNumber, $err.Extent.StartColumnNumber, $err.Message) -ForegroundColor Red
        }
    } else {
        Write-Host "[PARSE OK] $($item.FullName)" -ForegroundColor Green
    }
}
if ($failed) { exit 1 }
Write-Host ("[OK] All {0} PowerShell scripts parsed successfully. This does NOT prove a Windows end-to-end build." -f $files.Count) -ForegroundColor Green
