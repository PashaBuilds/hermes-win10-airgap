# Factory Auto v3.1 — pip download fix + resume

**v3.1 fixes:** `Invoke-PipDownload` used PowerShell's reserved `$Args` automatic variable; renamed to `$DownloadArgs`, with mandatory named arguments and validation. The script no longer retries with insecure `--trusted-host` (TLS verification stays enabled). The build now **resumes from a previously created work directory**, so it will reuse an existing Hermes checkout/tools when you restart it after this bug. `-Fresh` performs a new clean checkout if needed.

**For an existing v3 installation:** Replace only `C:\HermesAirgapFactoryAuto_v3\BuildHermesAirgapBundle.ps1` with the patched `BuildHermesAirgapBundle.ps1` from this package. Then run `BuildHermesAirgapBundle.bat v0.22.0` from the original v3 folder; no factory directory renaming is needed.

---

# Hermes Airgap Factory Auto v3

Bu paket, daha önce elle yaptığımız Hermes Windows + air-gap işlemlerini tek akışta otomatikleştirir.

## Neleri otomatik handle eder?

- GitHub `latest` release tag'ini çözer veya verilen tag'i kullanır.
- Release tag'i shallow clone eder.
- Python 3.11.9 build ortamını hazırlar.
- `pyproject.toml` içindeki mevcut optional extra'ları otomatik keşfeder.
  - Eski factory'deki `cli` gibi artık kaldırılmış extra'ları otomatik atlar.
- `uv pip compile` ile requirements oluşturur.
- **Hem compiled requirements hem de doğrudan project dependency'lerini wheelhouse'a indirir.**
  - Böylece `cryptography==50.0.0` / `50.0.1` gibi uv override + exact project pin çakışmaları otomatik yakalanır.
- `[build-system].requires` listesini (`setuptools==83.0.0`, `wheel`, vb.) pyproject'ten otomatik okur ve wheelhouse'a ekler.
- Tamamen `--no-index` test venv kurarak bundle'ın gerçekten offline kurulabildiğini doğrular.
- Desktop build için güncel Node 24 portable indirir.
- `package.json -> engines` değerlerini okur.
- Önce bundled npm'i dener; `Exit handler never called`, EBADENGINE veya başka npm ci hatasında:
  - npm 11.18.0
  - npm 11.17.0
  - npm 10.9.8
  sırasıyla, yalnızca engine aralığına uyanları otomatik dener.
- Kurumsal Windows CA store'u için `NODE_OPTIONS=--use-system-ca` kullanır.
- Desktop `win-unpacked` EXE'yi doğrular.
- Tarihsel `$d:` PowerShell parser bug'ını otomatik patch eder.
- `_test_venv`, build Python, `node_modules`, npm cache gibi build-only dosyaları final ZIP'ten önce temizler.
- Final ZIP'i ve SHA256 dosyasını üretir.
- Build transcript/log kaydeder.

## Internet bilgisayarda

ZIP'i örneğin:

```text
C:\HermesAirgapFactoryAuto_v3
```

altına çıkar.

Latest stable:

```cmd
cd /d C:\HermesAirgapFactoryAuto_v3
BuildHermesAirgapBundle.bat
```

Belirli release:

```cmd
BuildHermesAirgapBundle.bat v2026.9.24
```

Varsayılan output:

```text
C:\HermesUnifiedAirgapFactory\output\
```

Loglar:

```text
C:\HermesUnifiedAirgapFactory\logs\
```

## Intranet bilgisayarda

Üretilen ZIP'i örneğin:

```text
C:\HermesDeploy\bundles\
```

altına koy, tamamen:

```text
C:\HermesDeploy\extracted\<bundle adı>\
```

altına çıkar.

Sonra:

```cmd
cd /d C:\HermesDeploy\extracted\<bundle adı>
InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
```

Installer:

- İlk kurulum / update ayrımını otomatik yapar.
- `Hermes_Gateway.vbs` Startup girişini update boyunca geçici disable eder.
- Hermes proseslerini ve **TGitCache.exe**'yi kapatır.
- Eski `hermes-agent` klasörünü 8 kez retry ile backup adına taşımayı dener.
- Rename lock devam ederse Resource Monitor / Associated Handles yönlendirmesiyle fail eder.
- Yeni source'u kopyalar.
- Python 3.11 yoksa bundle içindeki Python installer'ını user-local olarak kurar.
- Temiz venv oluşturur.
- Wheelhouse'tan tamamen offline kurulum yapar.
- `python3.exe` compatibility kopyasını oluşturur.
- User PATH'i günceller.
- Sistem Git Bash varsa `HERMES_GIT_BASH_PATH` ayarlar.
- Prebuilt Desktop varsa `%LOCALAPPDATA%\hermes\StartHermesDesktop.bat` oluşturur.
- Kurulum başarısız olursa mümkünse eski source'a otomatik rollback yapar.
- Startup'ta disable edilen Hermes Gateway'i sonunda geri açar.

## Bundle doğrulama

```powershell
.\VerifyHermesAirgapBundle.ps1 -ZipPath "C:\...\HermesAirgapBundle_....zip"
```

## Kurumsal npm CA dosyası gerekiyorsa

PowerShell:

```powershell
.\BuildHermesAirgapBundle.ps1 -NpmCafile C:\cert\internet_proxy_ca.pem
```

## Not

Bu factory future-proof olmaya çalışır ama upstream Hermes'in build sistemi kökten değişirse (örneğin npm yerine başka package manager veya Python packaging yapısının değişmesi) yeni bir uyarlama gerekebilir. Buna rağmen bugüne kadar yaşadığımız known edge-case'ler bu sürümde otomatik ele alınmıştır.
