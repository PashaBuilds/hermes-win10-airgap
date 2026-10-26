@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ValidateFactoryScripts.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (echo [ERROR] PowerShell syntax validation failed.) else (echo [OK] PowerShell syntax validation passed.)
pause
exit /b %RC%
