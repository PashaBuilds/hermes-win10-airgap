@echo off
setlocal
cd /d "%~dp0"

echo Hermes Desktop air-gapped installer/updater for Windows 10/11
echo.
echo Usage:
echo   InstallOrUpdateHermesWithDesktopAirgapped.bat "C:\HermesDeploy\bundles\HermesAirgapBundle_TAG_with_desktop.zip"
echo.
echo Optional:
echo   InstallOrUpdateHermesWithDesktopAirgapped.bat "bundle.zip" Auto CleanVenv
echo   InstallOrUpdateHermesWithDesktopAirgapped.bat "bundle.zip" Update
echo.

if "%~1"=="" (
  echo [ERROR] Please provide the desktop-enabled HermesAirgapBundle ZIP path.
  pause
  exit /b 1
)

set MODE=%~2
if "%MODE%"=="" set MODE=Auto

set CLEAN=
if /I "%~3"=="CleanVenv" set CLEAN=-CleanVenv

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesWithDesktopAirgapped.ps1" -DesktopHermesBundleZip "%~1" -Mode "%MODE%" %CLEAN%

if errorlevel 1 (
  echo.
  echo [ERROR] Install/update failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
