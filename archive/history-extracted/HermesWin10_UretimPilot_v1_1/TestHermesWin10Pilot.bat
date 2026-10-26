@echo off
setlocal
cd /d "%~dp0"
echo Hermes v0.22.2 - Windows 10 production-machine isolated pilot
echo Existing Hermes installation is NOT updated by this pilot.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TestHermesWin10Pilot.ps1" -BundleRoot "%~dp0"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (echo [ERROR] Pilot failed. See the printed diagnostic folder.) else (echo [OK] Pilot completed.)
pause
exit /b %RESULT%
