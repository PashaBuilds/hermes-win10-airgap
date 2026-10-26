# Quick Commands

## Internet

```cmd
cd /d C:\HermesUnifiedAirgapFactory
BuildCompleteHermesAirgapBundle.bat
```

Specific tag:

```cmd
BuildCompleteHermesAirgapBundle.bat v2026.5.29.2
```

## Intranet

Extract generated bundle ZIP, then:

```cmd
InstallOrUpdateHermesAirgapped.bat
```

## Desktop

```cmd
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat
```

or:

```powershell
hermes desktop --skip-build
```
