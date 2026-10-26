@echo off
setlocal
cd /d "%~dp0"

echo Hermes unified air-gapped bundle factory for Windows 10/11
echo.
echo Default:
echo   Builds latest known/reachable Hermes release and includes Desktop artifact.
echo.
echo Usage:
echo   BuildCompleteHermesAirgapBundle.bat
echo   BuildCompleteHermesAirgapBundle.bat v2026.5.29.2
echo   BuildCompleteHermesAirgapBundle.bat ^<commit-hash^>
echo.

set REF=%~1
if "%REF%"=="" set REF=latest

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildCompleteHermesAirgapBundle.ps1" -VersionRef "%REF%" -IncludeDesktop $true

if errorlevel 1 (
  echo.
  echo [ERROR] Bundle build failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
