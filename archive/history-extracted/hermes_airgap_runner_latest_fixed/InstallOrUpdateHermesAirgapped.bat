@echo off
setlocal

if "%~1"=="" (
  echo Usage:
  echo   %~nx0 ^<HermesAirgapBundleZip^> [Auto^|Install^|Update] [CleanVenv]
  echo.
  echo Examples:
  echo   %~nx0 "C:\Temp\HermesAirgapBundle_v2026.5.29.2.zip"
  echo   %~nx0 "C:\Temp\HermesAirgapBundle_v2026.5.29.2.zip" Update
  echo   %~nx0 "C:\Temp\HermesAirgapBundle_v2026.5.29.2.zip" Auto CleanVenv
  exit /b 1
)

set BUNDLEZIP=%~1
set MODE=%~2
set CLEAN=%~3
if "%MODE%"=="" set MODE=Auto

set PS1=%~dp0InstallOrUpdateHermesAirgapped.ps1

if /I "%CLEAN%"=="CleanVenv" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -BundleZip "%BUNDLEZIP%" -Mode "%MODE%" -CleanVenv
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -BundleZip "%BUNDLEZIP%" -Mode "%MODE%"
)

if errorlevel 1 (
  echo.
  echo Hermes air-gapped install/update FAILED.
  pause
  exit /b 1
)

echo.
echo Hermes air-gapped install/update completed.
echo Open a NEW terminal and run: hermes --version
pause
