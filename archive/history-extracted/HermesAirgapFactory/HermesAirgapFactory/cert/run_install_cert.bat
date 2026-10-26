@echo off
setlocal
cd /d "%~dp0"
python install_hermes_company_cert.py
if errorlevel 1 (
  echo.
  echo Python command failed. Trying py launcher...
  py -3 install_hermes_company_cert.py
)
pause
