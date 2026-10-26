# Quick Commands

## Internet PC

```cmd
cd /d C:\HermesDesktopAirgapWin10\online
AddDesktopToHermesAirgapBundle_Online.bat "C:\HermesAirgapFactory\output\HermesAirgapBundle_<tag>.zip"
```

## Intranet PC

```cmd
cd /d C:\HermesDeploy\desktop_runner
InstallOrUpdateHermesWithDesktopAirgapped.bat "C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>_with_desktop.zip"
```

## Launch desktop after install

```cmd
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat
```

or:

```powershell
hermes desktop --skip-build
```
