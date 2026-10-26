@echo off
setlocal
cd /d "%~dp0"
echo HermesAirgapFactoryAuto v4.8 - minimal Windows 10 Desktop bundle (Internet PC)
echo Default: newest stable Hermes release. Output: C:\H4\output\HermesAirgapBundle_^<tag^>_Win10_Desktop.zip
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildHermesDesktopWin10.ps1" %*
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (echo [OK] Factory finished.) else (echo [ERROR] Factory failed, exit code %RESULT%. See C:\H4\logs\desktop_win10_*.log)
pause
exit /b %RESULT%
