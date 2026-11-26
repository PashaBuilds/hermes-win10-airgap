<#
.SYNOPSIS
  Builds HermesKurulumAsistani.exe (.NET Framework 4.8 WPF) on Windows.
.DESCRIPTION
  Needs the .NET 8 SDK (or newer). The produced exe only needs .NET Framework 4.8,
  which ships with Windows 10 1903+ and Windows 11. Output: installer-app\dist\.
  -Test also runs the unit tests (tests\CoreTests).
#>
[CmdletBinding()]
param([switch]$Test)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet SDK 8+ gerekli (https://dot.net)' }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'; $env:DOTNET_NOLOGO = '1'
& dotnet build (Join-Path $here 'src\HermesKurulumAsistani.csproj') -c Release
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed ($LASTEXITCODE)" }
$dist = Join-Path $here 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$exe = Join-Path $dist 'HermesKurulumAsistani.exe'
Copy-Item (Join-Path $here 'src\bin\Release\net48\HermesKurulumAsistani.exe') $exe -Force
$hash = (Get-FileHash -Algorithm SHA256 $exe).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$exe.sha256", "$hash  HermesKurulumAsistani.exe`n", (New-Object Text.UTF8Encoding $false))
Write-Host "$hash  HermesKurulumAsistani.exe"
if ($Test) {
  & dotnet run --project (Join-Path $here 'tests\CoreTests\CoreTests.csproj') -c Release
  if ($LASTEXITCODE -ne 0) { throw "tests failed ($LASTEXITCODE)" }
}
