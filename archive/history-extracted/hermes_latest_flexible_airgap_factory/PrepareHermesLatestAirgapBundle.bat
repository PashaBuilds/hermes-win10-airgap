@echo off
setlocal
cd /d "%~dp0"
echo Hermes Agent latest patch air-gapped bundle builder
echo.
echo Default: builds the latest GitHub release.
echo Optional: pass a tag, branch, or commit as first argument.
echo Example:
echo   PrepareHermesLatestAirgapBundle.bat v2026.5.29.2
echo.
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PrepareHermesLatestAirgapBundle.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PrepareHermesLatestAirgapBundle.ps1" -VersionRef "%~1"
)
echo.
pause
