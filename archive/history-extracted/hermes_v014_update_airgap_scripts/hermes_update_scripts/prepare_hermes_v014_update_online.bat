@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%prepare_hermes_v014_update_online.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
echo Script finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
