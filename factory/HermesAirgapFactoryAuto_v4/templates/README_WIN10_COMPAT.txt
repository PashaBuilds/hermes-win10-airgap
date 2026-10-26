Hermes Agent v0.22.2 - Windows 10 air-gapped native transfer
===========================================================

INSTALL / UPDATE - SAME COMMAND AS THE PREVIOUS LEGACY BUNDLES:
  InstallOrUpdateHermesAirgapped.bat Auto CleanVenv

The installer runs within the extracted folder, needs no Internet, uses
%LOCALAPPDATA%\hermes\hermes-agent and preserves the previous install in
hermes-agent_source_backup_<timestamp>.  Settings, sessions, memories,
skills, cron files and logs under %LOCALAPPDATA%\hermes are not overwritten.
An additional selective backup is made before activation.

IMPORTANT TECHNICAL DIFFERENCE:
Hermes v0.22.2 uses Python 3.14 and the PM bundle runtime. CleanVenv means
prepare and switch to a freshly staged sealed Python environment. It DOES NOT
run the old Python 3.11 / pip --no-index / wheelhouse steps. It never reuses
the old virtualenv even without CleanVenv (the Python ABI changed).

WINDOWS 10 DESKTOP STATUS:
The current v0.22.2 MSIX requires Windows 11 22H2. This Windows 10 ZIP
EXCLUDES that installer. The legacy Desktop shortcut, if present, is NOT
replaced, and v0.22.2 Desktop GUI support on Windows 10 is NOT established.
The supplied package supports native CLI with staged Web / MCP components;
actual offline usage with your local model must be tested separately.

SAFE TEST FLOW:
1. Record SHA256 on the Internet-connected factory computer; verify after
   transfer to the isolated Windows 10 test PC.
2. Extract to a short local directory, such as C:\H4Transfer.
3. Run VerifyOfflineBundle.ps1; ensure it reports desktop=False.
4. First test on an authorized test PC, not production; exit code must be 0.
5. Run InstallOrUpdateHermesAirgapped.bat Auto CleanVenv.
6. Confirm %LOCALAPPDATA%\hermes\hermes-agent\bin\hermes.exe --version.
7. Do not activate auto-updates, install plugins from the Internet or assume
   that the previous Desktop GUI shortcut targets this new version.

Rollback: if install fails after activation, the installer attempts to restore
the old hermes-agent directory automatically. Previous installations are
retained in hermes-agent_source_backup_<timestamp> even on success.

STATUS: Factory/installer code has not been tested on your Windows 10 PC.
