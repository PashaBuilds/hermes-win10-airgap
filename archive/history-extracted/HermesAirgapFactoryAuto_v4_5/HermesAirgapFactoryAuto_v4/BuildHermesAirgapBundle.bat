@echo off
setlocal
set "ROOT=%~dp0"
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%BuildHermesAirgapBundle.ps1" -VersionRef latest
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%BuildHermesAirgapBundle.ps1" -VersionRef "%~1"
)
set "RC=%ERRORLEVEL%"
echo.
echo HermesAirgapFactoryAuto v4 exit code: %RC%
pause
exit /b %RC%
