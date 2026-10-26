Hermes v0.14.0 Air-Gapped Update Runner
======================================

Purpose
-------
This package updates an existing Hermes v0.13.x native Windows installation to v0.14.0 using a prebuilt offline ZIP bundle:

  HermesOfflineBundle_v0.14.0.zip

It is designed for the intranet / air-gapped computer. It does NOT download anything from the internet.

Files
-----
- UpdateHermesV014Airgapped.ps1
- UpdateHermesV014Airgapped.bat

Basic usage from CMD
--------------------
1. Put these two files in a folder, for example:

   C:\HermesUpdateRunner

2. Put or keep the prepared bundle ZIP anywhere, for example:

   C:\Temp\HermesOfflineBundle_v0.14.0.zip

3. Open CMD and run:

   cd /d C:\HermesUpdateRunner
   UpdateHermesV014Airgapped.bat "C:\Temp\HermesOfflineBundle_v0.14.0.zip"

Basic usage from PowerShell
---------------------------

   powershell -NoProfile -ExecutionPolicy Bypass -File .\UpdateHermesV014Airgapped.ps1 -ZipPath "C:\Temp\HermesOfflineBundle_v0.14.0.zip"

What the script does
--------------------
- Extracts the ZIP to C:\Tools\HermesOfflineBundle_v0.14.0_extracted by default.
- Finds the extracted bundle root automatically.
- Validates hermes-agent source and wheelhouse.
- Creates a full backup of %LOCALAPPDATA%\hermes.
- Replaces the Hermes source tree with the v0.14.0 source.
- Preserves the existing venv by default.
- Installs/updates Hermes from local wheelhouse only.
- Recreates python3.exe alias inside the venv.
- Updates HERMES_HOME, HERMES_GIT_BASH_PATH, PYTHONUTF8, PYTHONIOENCODING.
- Adds the Hermes venv Scripts directory to User PATH.
- Runs version/config/doctor checks.

Important
---------
After update, open a NEW PowerShell window and run:

  hermes --version
  hermes model
  hermes chat

For the company model gateway, select:

  Custom endpoint

Do NOT select:

  Custom API

Rollback
--------
The script creates a full backup folder next to HermesHome, for example:

  %LOCALAPPDATA%\hermes_backup_before_v014_YYYYMMDD_HHMMSS

It also keeps the old source tree as:

  %LOCALAPPDATA%\hermes\hermes-agent_source_backup_before_v014_YYYYMMDD_HHMMSS

If the update fails, inspect the transcript log:

  %LOCALAPPDATA%\hermes\update_v014_YYYYMMDD_HHMMSS.log
