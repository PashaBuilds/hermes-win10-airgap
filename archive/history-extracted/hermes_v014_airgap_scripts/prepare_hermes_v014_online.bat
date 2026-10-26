@echo off
setlocal
REM Hermes Agent v0.14.0 air-gapped bundle preparation wrapper.
REM Run this on the INTERNET-connected Windows PC.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_hermes_v014_online.ps1" %*
if errorlevel 1 (
  echo.
  echo Preparation failed. Check the PowerShell output and prepare_online_transcript.log inside the bundle folder.
  pause
  exit /b 1
)
echo.
echo Done.
pause
