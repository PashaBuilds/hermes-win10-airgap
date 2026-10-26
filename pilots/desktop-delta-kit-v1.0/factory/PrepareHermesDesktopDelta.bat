@echo off
setlocal
cd /d "%~dp0"
echo Hermes v0.22.2 - Windows 10 Desktop delta kit (factory side)
echo Reads win-unpacked and the Windows 10 bundle; writes only C:\H4\dd and C:\H4\output.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PrepareHermesDesktopDelta.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
