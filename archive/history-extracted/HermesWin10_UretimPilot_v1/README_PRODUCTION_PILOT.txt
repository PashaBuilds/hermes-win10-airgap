HERMES v0.22.2 - WINDOWS 10 PRODUCTION PILOT (SEPARATE ADD-ON)
==================================================================

PURPOSE
Run a careful test on the actual intranet PC without modifying an existing
%LOCALAPPDATA%\hermes\hermes-agent installation, the existing Desktop shortcut,
or the persistent PATH/registry variables. The pilot writes only to a new
%LOCALAPPDATA%\HermesWin10Pilot\v0.22.2_* directory.

INSTALL PILOT FILES (NO FACTORY REBUILD)
1) Transfer and extract the original HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip.
2) Copy the two files in this small ZIP into the EXTRACTED bundle root,
   next to InstallOrUpdateHermesAirgapped.bat and BUNDLE.json.
3) Double-click TestHermesWin10Pilot.bat. This verifies bundle inputs,
   copies the bundled native runtime beside your existing Hermes installation,
   and runs hermes --version and --help with isolated HERMES_HOME.
4) Send the last output lines and %LOCALAPPDATA%\HermesWin10Pilot\...\pilot.log
   if it fails (review logs for company-sensitive details before sharing).

NOT A DESKTOP GUI TEST
The v0.22.2 MSIX requires Windows 11 22H2, so this Windows 10 bundle
contains NO compatible MSIX. Your existing Desktop shortcut is not tested.

UPGRADE ONLY AFTER PLANNING A MAINTENANCE WINDOW AND CONFIRMING BACKUP
The REAL v4.6 upgrade command remains EXACTLY:
   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv

However, an upgrade replaces the old active hermes-agent source directory.
An old StartHermesDesktop.bat referencing venv\Scripts\hermes.exe may BREAK,
since v0.22.2 stores bin\hermes.exe instead. Existing sessions/services
should be stopped, data backed up, and a rollback window scheduled BEFORE
executing the real update on the production profile. The pilot deliberately
DOES NOT do this risky upgrade.

HOW TO REMOVE A SUCCESSFUL PILOT LATER
Close its processes and remove ONLY its individual
%LOCALAPPDATA%\HermesWin10Pilot\v0.22.2_* folder. Do not remove
%LOCALAPPDATA%\hermes or the original source backup directories.

LIMITATIONS
- Script has been reviewed but has not run on your Windows 10 host.
- The bundle verifier checks selected key files, not every payload file.
- Pilot verifies CLI startup, not all optional features, GUI, DeepSeek or MCP.
- No Internet download/install or global environment writes are performed.
