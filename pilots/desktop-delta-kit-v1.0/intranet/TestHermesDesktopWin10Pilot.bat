@echo off
setlocal
cd /d "%~dp0"
set "HERMES_DESKTOP_KIT=%~dp0"
title Hermes v0.22.2 Windows 10 Desktop pilot
echo Hermes v0.22.2 - Windows 10 Desktop pilot (unpacked Electron, no MSIX)
echo The existing Hermes installation is NOT changed by this pilot.
echo.
if not exist "%~dp0TestHermesDesktopWin10Pilot.ps1" (
  echo [ERROR] TestHermesDesktopWin10Pilot.ps1 must be in the same folder as this BAT.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TestHermesDesktopWin10Pilot.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo [OK] Desktop pilot started. Check the Hermes Agent window.
) else (
  echo [ERROR] Desktop pilot failed, exit code %RESULT%. Send summary.txt from the diagnostic folder above.
)
pause
exit /b %RESULT%
