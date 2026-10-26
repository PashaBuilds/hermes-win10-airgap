@echo off
setlocal
cd /d "%~dp0"
set "HERMES_BUNDLE_ROOT=%~dp0"

echo Hermes unified air-gapped installer/updater for Windows 10 - Desktop
echo.
echo   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv   install or update
echo   InstallOrUpdateHermesAirgapped.bat Pilot            isolated test, changes nothing
echo   RollbackHermesAirgapped.bat                         undo the last install/update
echo.

set "MODE=%~1"
if "%MODE%"=="" set "MODE=Auto"
set "CLEAN="
if /I "%~2"=="CleanVenv" set "CLEAN=-CleanVenv"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" -Mode "%MODE%" %CLEAN%
if errorlevel 1 (
  echo.
  echo [ERROR] Install/update failed. The messages above say what was restored.
  pause
  exit /b 1
)
echo.
echo Done.
pause
exit /b 0
