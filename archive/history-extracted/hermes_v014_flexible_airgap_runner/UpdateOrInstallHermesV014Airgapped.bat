@echo off
setlocal

if "%~1"=="" (
  echo Usage:
  echo   UpdateOrInstallHermesV014Airgapped.bat "C:\Path\HermesOfflineBundle_v0.14.0.zip" [Auto^|Install^|Update^|Reinstall]
  echo.
  echo Examples:
  echo   UpdateOrInstallHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip"
  echo   UpdateOrInstallHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip" Update
  echo   UpdateOrInstallHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip" Install
  exit /b 1
)

set BUNDLE=%~1
set MODE=%~2

if "%MODE%"=="" set MODE=Auto

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UpdateOrInstallHermesV014Airgapped.ps1" -BundleZip "%BUNDLE%" -Mode "%MODE%"

set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo Hermes install/update failed with exit code %ERR%.
  pause
  exit /b %ERR%
)

echo.
echo Hermes install/update completed.
pause
