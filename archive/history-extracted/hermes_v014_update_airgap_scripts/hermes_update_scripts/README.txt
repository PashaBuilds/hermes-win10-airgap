Hermes Agent v0.14.0 Air-Gapped UPDATE Script Package
======================================================

Run this on the INTERNET-CONNECTED prep PC:

  1. Extract this zip to a folder, for example:
       C:\HermesV014UpdateScripts

  2. Open CMD:
       cd /d C:\HermesV014UpdateScripts
       prepare_hermes_v014_update_online.bat

     Or from PowerShell:
       cmd /c .\prepare_hermes_v014_update_online.bat

What it creates:
  Desktop\HermesUpdateBundle_v0.14.0.zip

Move that generated zip to the INTRANET/OFFLINE PC and extract it to:
  C:\Tools\HermesUpdateBundle_v0.14.0

Then run on the OFFLINE PC:
  powershell -ExecutionPolicy Bypass -File C:\Tools\HermesUpdateBundle_v0.14.0\install_hermes_v014_update_offline.ps1 -BundleRoot C:\Tools\HermesUpdateBundle_v0.14.0

This is an update bundle. It preserves the existing Hermes venv by default and installs missing/updated packages only from the bundled wheelhouse.

If the in-place venv update fails, run the offline updater with:
  -CleanVenv

Important:
  After update, run `hermes model` and select Custom endpoint, not Custom API.
