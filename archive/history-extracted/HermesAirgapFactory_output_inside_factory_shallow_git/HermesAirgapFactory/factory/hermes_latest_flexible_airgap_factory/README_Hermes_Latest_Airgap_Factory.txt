Hermes Agent latest patch air-gapped bundle factory
===================================================

Goal
----
This package is for the INTERNET-CONNECTED Windows machine.

It creates a self-contained Hermes Agent air-gapped ZIP that can be moved to an
intranet/offline Windows machine and used for BOTH cases:

1. Fresh install: Hermes is not installed yet.
2. Update: Hermes is already installed, such as v0.13.0.

The generated bundle includes an offline installer/updater:
  InstallOrUpdateHermesAirgapped.bat

Internet-side usage
-------------------
Extract this ZIP to a folder, for example:

  C:\HermesLatestFactory

Then run from CMD:

  cd /d C:\HermesLatestFactory
  PrepareHermesLatestAirgapBundle.bat

By default it resolves the latest GitHub release of:
  NousResearch/hermes-agent

It will create a ZIP on your Desktop, for example:

  HermesAirgapBundle_v2026.5.29.2.zip

To build a specific tag/commit/branch:

  PrepareHermesLatestAirgapBundle.bat v2026.5.29.2

or:

  PrepareHermesLatestAirgapBundle.bat <commit-hash>

Air-gapped/intranet usage
-------------------------
Copy the generated HermesAirgapBundle_*.zip to the intranet Windows machine.
Extract it to any folder, for example:

  C:\Tools\HermesAirgapBundle

Then double-click:

  InstallOrUpdateHermesAirgapped.bat

or run from CMD:

  cd /d C:\Tools\HermesAirgapBundle
  InstallOrUpdateHermesAirgapped.bat

The intranet script will:
  - Detect whether Hermes is already installed.
  - Fresh install if missing.
  - Update if already installed.
  - Back up %LOCALAPPDATA%\hermes before changing it.
  - Use isolated Python 3.11.9.
  - Install packages from local wheelhouse only.
  - Configure python3.exe alias.
  - Configure Git Bash path if found.
  - Add Hermes to User PATH.
  - Run basic config/version checks.

Notes
-----
For the company local model, in `hermes model`, choose:

  Custom endpoint

not:

  Custom API

The base URL should include `/v1`, for example:

  https://your-company-gateway/v1
