Hermes Air-gapped Flexible Installer/Updater v2
================================================

This runner fixes Windows MAX_PATH backup failures by avoiding a full recursive copy of the Hermes venv.
It backs up only user/config state and renames the old hermes-agent source folder instead.

Usage on the intranet / air-gapped Windows machine:

1) Extract this runner ZIP, for example to:
   C:\HermesRunnerV2

2) Put your prepared Hermes air-gap bundle ZIP somewhere, for example:
   C:\Temp\HermesAirgapBundle_v2026.5.29.2.zip

3) Open CMD:
   cd /d C:\HermesRunnerV2
   InstallOrUpdateHermesAirgapped_v2.bat "C:\Temp\HermesAirgapBundle_v2026.5.29.2.zip"

Optional modes:
   InstallOrUpdateHermesAirgapped_v2.bat "C:\Temp\bundle.zip" Update
   InstallOrUpdateHermesAirgapped_v2.bat "C:\Temp\bundle.zip" Install
   InstallOrUpdateHermesAirgapped_v2.bat "C:\Temp\bundle.zip" Auto CleanVenv

Default mode is Auto:
- If %LOCALAPPDATA%\hermes\hermes-agent exists, it updates.
- Otherwise, it performs a fresh install.

After it finishes:
1) Open a NEW PowerShell/CMD window.
2) Run:
   hermes --version
   hermes model
   hermes chat

Important:
- In hermes model, choose Custom endpoint, not Custom API.
- Base URL should usually end with /v1.
- The runner creates python3.exe alias in the Hermes venv Scripts folder.
