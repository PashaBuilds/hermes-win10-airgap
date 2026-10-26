@echo off
setlocal
cd /d "%~dp0"

echo Hermes Media Tools Airgapped Installer
echo.
echo Optional:
echo   InstallHermesMediaToolsAirgapped.bat CleanVenv
echo.

set CLEAN=
if /I "%~1"=="CleanVenv" set CLEAN=-CleanVenv

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallHermesMediaToolsAirgapped.ps1" %CLEAN%

if errorlevel 1 (
  echo.
  echo [ERROR] Install failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
