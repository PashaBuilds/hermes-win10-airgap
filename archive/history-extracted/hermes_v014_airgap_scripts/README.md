# Hermes v0.14.0 Air-Gapped Bundle Scripts

Run on the internet-connected Windows PC:

```bat
prepare_hermes_v014_online.bat
```

or:

```powershell
powershell -ExecutionPolicy Bypass -File .\prepare_hermes_v014_online.ps1
```

The script creates:

```text
C:\HermesOfflineBundle_v0.14.0
Desktop\HermesOfflineBundle_v0.14.0.zip
```

Move the ZIP to the offline/intranet PC, extract to:

```text
C:\Tools\HermesOfflineBundle_v0.14.0
```

Then run inside the offline PC:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Tools\HermesOfflineBundle_v0.14.0\install_hermes_v014_offline.ps1 -BundleRoot C:\Tools\HermesOfflineBundle_v0.14.0
```

Then run:

```powershell
hermes model
```

Choose **Custom endpoint** and enter your internal `/v1` OpenAI-compatible endpoint, API key, and model name.
