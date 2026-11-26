#!/usr/bin/env bash
# Builds HermesKurulumAsistani.exe (.NET Framework 4.8 WPF) on Linux/macOS with the .NET 8 SDK.
# Output: installer-app/dist/HermesKurulumAsistani.exe (+ .sha256). Windows'ta build.ps1 kullanın.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
command -v dotnet >/dev/null || { echo "dotnet SDK 8+ gerekli (https://dot.net)"; exit 1; }
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
dotnet build "$here/src/HermesKurulumAsistani.csproj" -c Release -p:EnableWindowsTargeting=true
mkdir -p "$here/dist"
cp "$here/src/bin/Release/net48/HermesKurulumAsistani.exe" "$here/dist/"
( cd "$here/dist" && sha256sum HermesKurulumAsistani.exe > HermesKurulumAsistani.exe.sha256 )
cat "$here/dist/HermesKurulumAsistani.exe.sha256"
if [[ "${1:-}" == "--test" ]]; then
  dotnet run --project "$here/tests/CoreTests/CoreTests.csproj" -c Release
fi
