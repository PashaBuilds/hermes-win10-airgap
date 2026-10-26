@echo off
setlocal
cd /d "%~dp0"
rem v1.2: the folder is handed over through a variable, NOT as -BundleRoot "%~dp0".
rem "%~dp0" ends with a backslash and \" is an escaped quote for powershell.exe.
set "HERMES_PILOT_BUNDLE=%~dp0"
title Hermes v0.22.2 Windows 10 pilot v1.2
echo Hermes v0.22.2 - Windows 10 isolated pilot v1.2
echo The existing Hermes installation is NOT changed by this pilot.
echo.
if not exist "%~dp0TestHermesWin10Pilot.ps1" (
  echo [ERROR] TestHermesWin10Pilot.ps1 must be in the same folder as this BAT.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TestHermesWin10Pilot.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo [OK] Pilot completed.
) else (
  echo [ERROR] Pilot failed, exit code %RESULT%. Send summary.txt from the diagnostic folder above.
)
pause
exit /b %RESULT%
