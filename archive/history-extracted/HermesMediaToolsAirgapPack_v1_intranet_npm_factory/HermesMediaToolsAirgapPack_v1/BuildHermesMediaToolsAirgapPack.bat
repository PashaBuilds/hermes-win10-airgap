@echo off
setlocal
cd /d "%~dp0"

echo Hermes Media Tools Airgap Pack v1 builder
echo.
echo Includes:
echo   Phase 1: FFmpeg/ffprobe, Graphviz, Mermaid CLI, media skills
echo   Phase 2: Manim Python wheelhouse, demo render files
echo.
echo Usage:
echo   BuildHermesMediaToolsAirgapPack.bat
echo.
echo Optional insecure npm workaround:
echo   powershell -ExecutionPolicy Bypass -File .\BuildHermesMediaToolsAirgapPack.ps1 -UseNpmInsecure
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildHermesMediaToolsAirgapPack.ps1"

if errorlevel 1 (
  echo.
  echo [ERROR] Media tools pack build failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
