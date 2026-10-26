# Hızlı Komutlar

## İnternetli bilgisayarda latest bundle üret

```cmd
cd /d C:\HermesAirgapFactory\factory\hermes_latest_flexible_airgap_factory
PrepareHermesLatestAirgapBundle.bat
```

## Belirli tag/commit ile üret

```cmd
PrepareHermesLatestAirgapBundle.bat v2026.5.29.2
```

veya:

```cmd
PrepareHermesLatestAirgapBundle.bat <commit-hash>
```

## Intranet bilgisayarda kur/update

```cmd
cd /d C:\HermesDeploy\runner
InstallOrUpdateHermesAirgapped.bat "C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>.zip"
```

## Sertifika tanıtma

```cmd
cd /d C:\HermesDeploy\cert
run_install_cert.bat
```

## Test

```powershell
hermes --version
hermes model
hermes chat
```


## Çıktı klasörü

Bundle çıktısı artık burada oluşur:

```text
C:\HermesAirgapFactory\output\HermesAirgapBundle_<tag>.zip
```

Geçici çalışma klasörü:

```text
C:\HermesAirgapFactory\work\HermesAirgapBundle_<tag>
```
