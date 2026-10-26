@echo off
setlocal
cd /d "%~dp0"

set "MODE=%~1"
if "%MODE%"=="" set "MODE=Auto"

set "CLEAN="
if /I "%~2"=="CleanVenv" set "CLEAN=-CleanVenv"
if /I "%~1"=="CleanVenv" (
  set "MODE=Auto"
  set "CLEAN=-CleanVenv"
)

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" ^
  -Mode "%MODE%" %CLEAN%

if errorlevel 1 (
  echo.
  echo [ERROR] Hermes install/update failed.
  pause
  exit /b 1
)

echo.
echo [OK] Hermes install/update completed.
pause
