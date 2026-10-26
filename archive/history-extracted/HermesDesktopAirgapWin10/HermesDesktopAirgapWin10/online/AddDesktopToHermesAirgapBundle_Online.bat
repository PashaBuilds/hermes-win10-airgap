@echo off
setlocal
cd /d "%~dp0"

echo Hermes Desktop air-gap bundle builder for Windows 10/11
echo.
echo Usage:
echo   AddDesktopToHermesAirgapBundle_Online.bat "C:\HermesAirgapFactory\output\HermesAirgapBundle_TAG.zip"
echo.
echo Output:
echo   Creates HermesAirgapBundle_TAG_with_desktop.zip next to the input ZIP.
echo.

if "%~1"=="" (
  echo [ERROR] Please provide the existing HermesAirgapBundle ZIP path.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0AddDesktopToHermesAirgapBundle_Online.ps1" -HermesBundleZip "%~1"

if errorlevel 1 (
  echo.
  echo [ERROR] Desktop bundle preparation failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
