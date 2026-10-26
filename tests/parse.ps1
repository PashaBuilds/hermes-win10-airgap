# Parse every given .ps1 with the PowerShell parser and flag PowerShell 7-only syntax
# (??, ?., &&, ||, ternary) that Windows PowerShell 5.1 cannot run. Exit code 1 on any problem.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)
$failed = $false
foreach ($f in $Files) {
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$t, [ref]$e)
    if ($e.Count) { $failed = $true; $e | ForEach-Object { "PARSE ERROR $f line $($_.Extent.StartLineNumber): $($_.Message)" } ; continue }
    $bad = @($t | Where-Object { $_.Kind -in 'QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket', 'AndAnd', 'OrOr' -or $_.Kind -eq 'QuestionMark' })
    if ($bad.Count) { $failed = $true; $bad | ForEach-Object { "PS7-ONLY TOKEN $f line $($_.Extent.StartLineNumber): $($_.Text)" }; continue }
    "[PARSE OK] $f"
}
if ($failed) { exit 1 }
