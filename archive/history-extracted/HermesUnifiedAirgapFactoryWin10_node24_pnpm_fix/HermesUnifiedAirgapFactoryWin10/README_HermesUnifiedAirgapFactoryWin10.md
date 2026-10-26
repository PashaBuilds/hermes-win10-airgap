# Hermes Unified Air-Gap Factory for Windows 10/11

Bu paket tek merkezden yönetim için hazırlandı.

## Internet tarafı

Bu ZIP'i örneğin şuraya aç:

```text
C:\HermesUnifiedAirgapFactory
```

Sonra:

```cmd
cd /d C:\HermesUnifiedAirgapFactory
BuildCompleteHermesAirgapBundle.bat
```

Bu komut:
- En güncel erişilebilir Hermes release/tag'i alır.
- Shallow git clone yapar.
- Python 3.11.9 installer, uv, wheelhouse ve gerekli kaynakları hazırlar.
- Desktop artifact'i internetli makinede build eder.
- Tek bir intranet bundle ZIP'i üretir.

Çıktı:

```text
C:\HermesUnifiedAirgapFactory\output\HermesAirgapBundle_<tag>_with_desktop.zip
```

## Intranet tarafı

Bu output ZIP'i intranet makineye taşı. Örneğin:

```text
C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>_with_desktop.zip
```

ZIP'i bir klasöre aç:

```text
C:\HermesDeploy\HermesAirgapBundle_<tag>_with_desktop
```

İçinden çalıştır:

```cmd
InstallOrUpdateHermesAirgapped.bat
```

Bu script:
- Hermes yoksa sıfırdan kurar.
- Hermes varsa update eder.
- Python 3.11.9 izole kurar/kullanır.
- Paketleri wheelhouse'tan offline kurar.
- Desktop artifact varsa `StartHermesDesktop.bat` oluşturur.

## Sertifika

Şirket sertifikası gerekiyorsa:
1. `cert\my_company.crt` dosyasını koy.
2. `cert\run_install_cert.bat` çalıştır.
3. PowerShell/CMD kapatıp yeniden aç.

## Notlar

- Model ayarında `Custom endpoint` seçilecek, `Custom API` değil.
- Base URL `/v1` ile bitmeli.
- CLI kullanımın devam eder:
  - `hermes chat`
  - `hermes model`
  - `hermes doctor`
- Desktop için:
  - `%LOCALAPPDATA%\hermes\StartHermesDesktop.bat`
  - veya `hermes desktop --skip-build`


## Node.js / npm Notu

Desktop artifact build aşamasında internetli makinede `node`/`npm` bulunmazsa bu sürüm otomatik olarak portable Node.js 24.x Windows x64 ZIP'ini indirip bundle içindeki `tools\node` altına açar. Bu yüzden internetli makinede Node.js'in önceden kurulu olması şart değildir.


## Node.js 24 / pnpm 10 Notu

Hermes v0.16 Desktop dependency ağacında bazı paketler Node.js `>=24` ve `pnpm >=10` bekliyor. Bu paket internet tarafında Desktop build öncesi:

- Node.js 24.x portable Windows x64 ZIP indirir.
- Node 24'ü geçici PATH'e ekler.
- `pnpm@10` paketini bundle-local npm prefix içine kurar.

Bu yüzden internetli bilgisayarda admin yetkisiyle MSI Node kurmak zorunlu değildir.
