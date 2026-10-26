@echo off
setlocal
cd /d "%~dp0"

echo Hermes unified air-gapped installer/updater for Windows 10/11
echo.
echo This installs or updates Hermes from this extracted bundle.
echo.
echo Optional:
echo   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
echo   InstallOrUpdateHermesAirgapped.bat Update
echo   InstallOrUpdateHermesAirgapped.bat Install
echo.

set MODE=%~1
if "%MODE%"=="" set MODE=Auto

set CLEAN=
if /I "%~2"=="CleanVenv" set CLEAN=-CleanVenv

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" -Mode "%MODE%" %CLEAN%

if errorlevel 1 (
  echo.
  echo [ERROR] Install/update failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
