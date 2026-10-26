@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
echo Hermes v4 installer exit code: %RC%
pause
exit /b %RC%
