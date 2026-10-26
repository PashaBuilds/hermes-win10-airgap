@echo off
setlocal
cd /d "%~dp0"

set "VER=%~1"
if "%VER%"=="" set "VER=latest"

echo ============================================================
echo Hermes Airgap Factory Auto v3
echo Release: %VER%
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0BuildHermesAirgapBundle.ps1" ^
  -VersionRef "%VER%"

if errorlevel 1 (
  echo.
  echo [ERROR] Bundle build failed.
  echo See C:\HermesUnifiedAirgapFactory\logs for the transcript.
  pause
  exit /b 1
)

echo.
echo [OK] Bundle build completed.
pause
