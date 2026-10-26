@echo off
setlocal

if "%~1"=="" (
  echo Usage:
  echo   %~nx0 "C:\Path\HermesOfflineBundle_v0.14.0.zip"
  echo.
  echo Optional examples:
  echo   %~nx0 "C:\Temp\HermesOfflineBundle_v0.14.0.zip"
  echo.
  pause
  exit /b 1
)

set ZIPPATH=%~1
set SCRIPTDIR=%~dp0

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPTDIR%UpdateHermesV014Airgapped.ps1" -ZipPath "%ZIPPATH%"

set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" (
  echo Update failed with exit code %RC%.
) else (
  echo Update completed successfully.
)
pause
exit /b %RC%
