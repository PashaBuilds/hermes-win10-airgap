Hermes v0.14.0 Flexible Air-Gapped Installer/Updater
======================================================

Purpose
-------
This runner works in BOTH situations:

1) Fresh install:
   - No Hermes installation exists under %LOCALAPPDATA%\hermes
   - It installs isolated Python 3.11 if the bundle contains python-3.11.x-amd64.exe
   - It creates Hermes home folders and venv
   - It installs Hermes from the offline wheelhouse

2) Update:
   - Existing Hermes installation exists under %LOCALAPPDATA%\hermes\hermes-agent
   - It backs up the current Hermes home
   - It replaces source with v0.14.0 bundle source
   - It reuses the existing venv by default
   - It upgrades/installs only from the offline wheelhouse

Required input
--------------
A prepared bundle zip, for example:

  HermesOfflineBundle_v0.14.0.zip

The bundle must contain:

  hermes-agent\
  wheelhouse\
  requirements-hermes-win.txt       recommended
  tools\python-3.11.9-amd64.exe     recommended for fresh install
  tools\ripgrep\                    optional
  tools\ffmpeg\                     optional

CMD usage
---------
Open CMD in this runner directory:

  cd /d C:\HermesFlexibleRunner

Auto mode, recommended:

  UpdateOrInstallHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip"

Force update:

  UpdateOrInstallHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip" Update

Force fresh install behavior:

  UpdateOrInstallHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip" Install

PowerShell advanced usage
-------------------------
  powershell -ExecutionPolicy Bypass -File .\UpdateOrInstallHermesV014Airgapped.ps1 -BundleZip "C:\Temp\HermesOfflineBundle_v0.14.0.zip"

Clean venv instead of reusing old venv:

  powershell -ExecutionPolicy Bypass -File .\UpdateOrInstallHermesV014Airgapped.ps1 -BundleZip "C:\Temp\HermesOfflineBundle_v0.14.0.zip" -CleanVenv

Specify Git Bash path manually:

  powershell -ExecutionPolicy Bypass -File .\UpdateOrInstallHermesV014Airgapped.ps1 -BundleZip "C:\Temp\HermesOfflineBundle_v0.14.0.zip" -GitBashPath "C:\Program Files\Git\bin\bash.exe"

What it does
------------
- Extracts the bundle to C:\Tools\HermesOfflineBundle_v0.14.0 by default
- Creates/uses %LOCALAPPDATA%\hermes
- Installs isolated Python 3.11 if needed and if bundled
- Finds Git Bash and sets HERMES_GIT_BASH_PATH
- Adds Hermes venv Scripts to User PATH
- Adds python3.exe alias next to python.exe
- Adds bundled ripgrep/ffmpeg to User PATH if present
- Runs offline pip install using --no-index --find-links wheelhouse
- Runs hermes config check/migrate/doctor on best effort
- Writes logs under %LOCALAPPDATA%\hermes\logs
- Writes helper start script to %LOCALAPPDATA%\hermes\start-hermes.ps1

After installation/update
-------------------------
Open a NEW PowerShell and run:

  hermes --version
  hermes model

For your company endpoint, choose:

  Custom endpoint

Do NOT choose:

  Custom API

Then configure:

  Base URL: https://.../v1
  Model   : Qwen3.5-397B-A17B-FP8
  API key : your company key

Then:

  hermes chat

Rollback
--------
The script creates backups like:

  %LOCALAPPDATA%\hermes_backup_before_v014_YYYYMMDD_HHMMSS
  %LOCALAPPDATA%\hermes\hermes-agent_source_backup_YYYYMMDD_HHMMSS

If needed, restore from these backups manually.

Notes
-----
- This script does not need internet access.
- It intentionally uses the bundle wheelhouse only.
- If Hermes cannot find python3, the script creates python3.exe alias in the venv Scripts folder.
- Docker/Chrome/HyperFrames are not handled here; this runner is for Hermes installation/update only.
