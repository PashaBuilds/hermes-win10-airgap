@echo off
setlocal
cd /d "%~dp0"
echo Hermes rollback: restores the installation from before the last install/update.
echo Close the Hermes Desktop window and any terminal running hermes first.
echo.
choice /C YN /M "Continue with rollback"
if errorlevel 2 exit /b 1
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" -Mode Rollback
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
