# Hermes Desktop Air-Gap for Windows 10/11

Bu paket, Hermes Desktop'ı internet olmayan Windows 10/11 makinelerinde kullanabilmek için hazırlanmıştır.

## Mantık

1. Internetli bilgisayarda önce normal Hermes air-gap bundle üretilir.
2. Bu paketle o bundle içine prebuilt Desktop artifact eklenir.
3. Intranet bilgisayarda desktop-enabled bundle ile Hermes kurulur/update edilir.
4. Desktop `hermes desktop --skip-build` ile açılır; intranet tarafında build/download yapılmaz.

## Internetli bilgisayarda

Önce normal bundle üret:

```cmd
cd /d C:\HermesAirgapFactory\factory\hermes_latest_flexible_airgap_factory
PrepareHermesLatestAirgapBundle.bat
```

Sonra Desktop artifact ekle:

```cmd
cd /d C:\HermesDesktopAirgapWin10\online
AddDesktopToHermesAirgapBundle_Online.bat "C:\HermesAirgapFactory\output\HermesAirgapBundle_<tag>.zip"
```

Çıktı:

```text
C:\HermesAirgapFactory\output\HermesAirgapBundle_<tag>_with_desktop.zip
```

## Intranet bilgisayarda

Desktop-enabled bundle'ı intranet makineye taşı:

```text
C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>_with_desktop.zip
```

Bu paketin `intranet` klasörünü örneğin buraya aç:

```text
C:\HermesDeploy\desktop_runner
```

Çalıştır:

```cmd
cd /d C:\HermesDeploy\desktop_runner
InstallOrUpdateHermesWithDesktopAirgapped.bat "C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>_with_desktop.zip"
```

Script sonunda helper oluşturur:

```text
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat
```

## Notlar

- Model ayarında `Custom endpoint` seçilecek, `Custom API` seçilmeyecek.
- Base URL `/v1` ile bitmeli.
- Sertifika gerekiyorsa önce `HermesSertifika.zip` içindeki sertifika installer'ı çalıştır.
- Desktop artifact build'i internetli bilgisayarda npm/electron paketleri indirebilir; bu normaldir.
- Intranet tarafında `hermes desktop --skip-build` kullanılır.
