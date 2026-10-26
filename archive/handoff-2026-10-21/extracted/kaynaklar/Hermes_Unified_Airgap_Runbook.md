# Hermes Unified Air-Gapped Kurulum / Güncelleme Akışı

Hazırlanma tarihi: 2026-06-16 14:46:09

Bu doküman, Windows 10/11 ortamında Hermes Agent'ı air-gapped / intranet bilgisayarlara taşımak için kullanılan **tek merkezli unified factory** akışını anlatır.

Amaç:

- İnternetli bilgisayarda en güncel Hermes bundle'ını hazırlamak
- Gerekirse Hermes Desktop artifact'ini aynı bundle içine eklemek
- Intranet bilgisayarda aynı ZIP ile hem sıfırdan kurulum hem de eski sürümden update yapmak
- Hermes CLI kullanımını korumak
- Desktop varsa `hermes desktop --skip-build` ile çalıştırmak

---

## 1. Genel Mimari

Bu yapı iki bilgisayar tipi için tasarlanmıştır:

```text
İnternetli bilgisayar
  |
  |  Hermes source + Python wheelhouse + tools + optional Desktop artifact hazırlar
  v
HermesAirgapBundle_<tag>_with_desktop.zip
  |
  |  USB / güvenli dosya transferi / kurumsal transfer yöntemi
  v
Intranet / air-gapped bilgisayar
  |
  |  ZIP içinden offline kurulum veya update
  v
%LOCALAPPDATA%\hermes
```

Hermes'in canlı kurulum alanı:

```text
%LOCALAPPDATA%\hermes
```

Örnek:

```text
C:\Users\<kullanıcı>\AppData\Local\hermes
```

Bu klasörün içinde şunlar bulunur:

```text
%LOCALAPPDATA%\hermes\
├── hermes-agent\
│   ├── venv\
│   └── apps\desktop\release\       varsa Desktop artifact
├── python311\
├── config.yaml
├── .env
├── sessions\
├── skills\
├── memories\
├── company-ca-bundle.pem              gerekiyorsa şirket sertifikası
└── StartHermesDesktop.bat             Desktop artifact varsa
```

---

## 2. Önerilen Klasör Yapısı

### 2.1 İnternetli Bilgisayar

Önerilen ana klasör:

```text
C:\HermesUnifiedAirgapFactoryWin10
```

Bu klasörün içinde:

```text
C:\HermesUnifiedAirgapFactoryWin10\
├── BuildCompleteHermesAirgapBundle.bat
├── BuildCompleteHermesAirgapBundle.ps1
├── payload\
├── docs\
└── README_HermesUnifiedAirgapFactoryWin10.md
```

Script çıktısı varsayılan olarak şu klasöre yazılır:

```text
C:\HermesUnifiedAirgapFactory\output
```

Geçici çalışma klasörü:

```text
C:\HermesUnifiedAirgapFactory\work
```

### 2.2 Intranet Bilgisayar

Önerilen dağıtım klasörü:

```text
C:\HermesDeploy
```

Önerilen yapı:

```text
C:\HermesDeploy\
├── bundles\
│   └── HermesAirgapBundle_<tag>_with_desktop.zip
├── extracted\
│   └── HermesAirgapBundle_<tag>_with_desktop\
├── cert\
│   ├── my_company.crt
│   ├── install_hermes_company_cert.py
│   └── run_install_cert.bat
└── logs\
```

---

## 3. İnternetli Bilgisayarda Yapılacaklar

### 3.1 Factory ZIP'ini Aç

Verilen factory ZIP'i örneğin şuraya aç:

```text
C:\HermesUnifiedAirgapFactoryWin10
```

CMD aç:

```cmd
cd /d C:\HermesUnifiedAirgapFactoryWin10
```

### 3.2 En Güncel Hermes Bundle'ını Üret

Varsayılan olarak latest / erişilebilen en güncel release/tag alınır:

```cmd
BuildCompleteHermesAirgapBundle.bat
```

Belirli tag ile üretmek istersen:

```cmd
BuildCompleteHermesAirgapBundle.bat v2026.5.29.2
```

Commit hash ile üretmek istersen:

```cmd
BuildCompleteHermesAirgapBundle.bat <commit-hash>
```

### 3.3 Script Ne Yapar?

Bu script internetli tarafta şunları yapar:

```text
1. Hermes release/tag bilgisini çözer.
2. GitHub'dan Hermes source kodunu shallow clone ile indirir.
3. Python 3.11.9 installer'ını indirir.
4. uv indirir.
5. Python wheelhouse klasörünü oluşturur.
6. requirements-hermes-win.txt üretir.
7. Gerekli Python paketlerini wheelhouse içine indirir.
8. Offline kurulum simülasyonu yapar.
9. Desktop artifact build etmeye çalışır.
10. Intranet tarafında çalışacak installer/updater scriptlerini bundle içine koyar.
11. Tek ZIP üretir.
```

### 3.4 Üretilen Çıktı

Çıktı şu klasöre gelir:

```text
C:\HermesUnifiedAirgapFactory\output
```

Örnek çıktı:

```text
C:\HermesUnifiedAirgapFactory\output\HermesAirgapBundle_v2026.5.29.2_with_desktop.zip
```

Bu ZIP intranet bilgisayara taşınacak ana dosyadır.

### 3.5 Desktop Artifact Hakkında

Bu unified factory, internetli bilgisayarda Hermes Desktop artifact'ini üretmeye çalışır.

Mantık:

```text
İnternetli bilgisayar:
  hermes desktop --build-only

Intranet bilgisayar:
  hermes desktop --skip-build
```

Yani intranet tarafında Desktop build/download yapılmaz. Hazır artifact kullanılır.

Eğer Desktop artifact build edilemezse, CLI/runtime bundle yine üretilebilir; ancak Desktop çalışmayabilir. Böyle bir durumda CLI kullanımı etkilenmez.

---

## 4. Intranet Bilgisayarda Yapılacaklar

### 4.1 Bundle ZIP'ini Taşı

İnternetli bilgisayarda oluşan ZIP'i intranet bilgisayara taşı:

```text
HermesAirgapBundle_<tag>_with_desktop.zip
```

Önerilen konum:

```text
C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>_with_desktop.zip
```

### 4.2 ZIP'i Aç

Örneğin:

```text
C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop
```

PowerShell veya Explorer ile açabilirsin.

Komutla açmak istersen:

```powershell
New-Item -ItemType Directory -Force "C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop"

Expand-Archive "C:\HermesDeploy\bundles\HermesAirgapBundle_<tag>_with_desktop.zip" `
  -DestinationPath "C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop" `
  -Force
```

Açılan klasörde şunlar görünmeli:

```text
hermes-agent\
wheelhouse\
tools\
InstallOrUpdateHermesAirgapped.bat
InstallOrUpdateHermesAirgapped.ps1
VERSION.txt
requirements-hermes-win.txt
cert\
```

### 4.3 Kurulum veya Update Başlat

CMD aç:

```cmd
cd /d C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop
InstallOrUpdateHermesAirgapped.bat
```

Varsayılan mod `Auto` olur:

```text
Hermes yoksa  → Install
Hermes varsa → Update
```

Zorla update:

```cmd
InstallOrUpdateHermesAirgapped.bat Update
```

Zorla sıfırdan kurulum:

```cmd
InstallOrUpdateHermesAirgapped.bat Install
```

Temiz venv ile kurulum/update:

```cmd
InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
```

### 4.4 Script Ne Yapar?

Intranet tarafındaki script şunları yapar:

```text
1. Hermes kurulu mu kontrol eder.
2. Kuruluysa güvenli backup alır.
3. Python 3.11.9 izole kurulumunu bulur veya bundle içinden kurar.
4. Hermes source kodunu %LOCALAPPDATA%\hermes\hermes-agent altına yerleştirir.
5. Eski venv'i mümkünse korur.
6. CleanVenv seçildiyse temiz venv oluşturur.
7. wheelhouse'tan offline pip install yapar.
8. python3.exe alias oluşturur.
9. PATH ayarını yapar.
10. Git Bash path'ini ayarlar.
11. Desktop artifact varsa StartHermesDesktop.bat oluşturur.
12. config check / migrate / doctor dener.
```

### 4.5 Kurulum Sonrası Kontrol

Yeni bir PowerShell aç:

```powershell
hermes --version
```

Sonra:

```powershell
hermes doctor
```

Model ayarı:

```powershell
hermes model
```

Burada kritik seçim:

```text
Custom endpoint seçilecek.
Custom API seçilmeyecek.
```

Örnek ayarlar:

```text
Base URL: https://.../v1
Model: Qwen3.5-397B-A17B-FP8
API key: şirket API key'i
```

Test:

```powershell
hermes chat
```

Prompt:

```text
Merhaba, sadece tek cümleyle cevap ver.
```

---

## 5. Desktop Kullanımı

Eğer bundle içinde Desktop artifact başarılı geldiyse, kurulum sonrası şu dosya oluşur:

```text
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat
```

Mümkünse Desktop'a da kopyalanır:

```text
Desktop\StartHermesDesktop.bat
```

Desktop'ı başlatmak için:

```cmd
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat
```

veya:

```powershell
hermes desktop --skip-build
```

`--skip-build` önemlidir. Çünkü intranet makinede tekrar npm/electron build veya internet download yapılmasını istemiyoruz.

### CLI Kullanımı Devam Eder Mi?

Evet.

Desktop eklemek CLI kullanımını bozmaz. Şunlar aynı şekilde çalışmaya devam eder:

```powershell
hermes chat
hermes model
hermes doctor
hermes dashboard
hermes --version
```

Desktop, Hermes runtime'ı kullanan bir arayüz gibi düşünülmelidir.

---

## 6. Sertifika Gerekiyorsa

Bazı makinelerde şirket API endpoint'i için sertifika hatası çıkabilir:

```text
CERTIFICATE_VERIFY_FAILED
unable to get local issuer certificate
```

Bu durumda şirketin verdiği sertifika dosyasını şu isimle kullan:

```text
my_company.crt
```

Sertifika dosyası PEM/Base64 formatında olmalı ve şu şekilde başlamalı:

```text
-----BEGIN CERTIFICATE-----
```

### 6.1 Sertifika Dosyalarını Hazırla

Intranet bundle içinde `cert` klasörü bulunur:

```text
cert\
├── install_hermes_company_cert.py
└── run_install_cert.bat
```

`my_company.crt` dosyasını aynı klasöre koy:

```text
cert\my_company.crt
```

### 6.2 Sertifikayı Tanıt

CMD:

```cmd
cd /d C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop\cert
run_install_cert.bat
```

Bu script şunları ayarlar:

```text
SSL_CERT_FILE
REQUESTS_CA_BUNDLE
CURL_CA_BUNDLE
NODE_EXTRA_CA_CERTS
```

Sonra PowerShell/CMD'yi kapatıp yeniden aç.

### 6.3 Tekrar Test Et

```powershell
hermes chat
```

---

## 7. Backup ve Rollback

Installer/update script'i backup alır.

Backup klasörleri genelde şurada oluşur:

```text
%LOCALAPPDATA%\hermes_backup_before_airgap_<timestamp>
```

Örnek:

```text
C:\Users\<kullanıcı>\AppData\Local\hermes_backup_before_airgap_20260616_142530
```

Başarılı update sonrası birkaç gün test et. Sorun yoksa eski backup'lar temizlenebilir.

Backup'ları listelemek için:

```powershell
Get-ChildItem "$env:LOCALAPPDATA" -Directory |
  Where-Object { $_.Name -like "hermes_backup*" }
```

---

## 8. Sık Hatalar

### 8.1 `Custom API` Seçildiği İçin Model Çalışmıyor

Çözüm:

```powershell
hermes model
```

`Custom endpoint` seç.

### 8.2 Python `python3` Bulunamıyor

Script otomatik olarak:

```text
%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\python3.exe
```

alias'ını oluşturur.

Kontrol:

```powershell
python3 --version
```

Git Bash içinde kontrol:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -lc "which python3; python3 --version"
```

### 8.3 Sertifika Hatası

`cert\run_install_cert.bat` çalıştır.

### 8.4 Desktop Açılmıyor Ama CLI Çalışıyor

CLI çalışıyorsa Hermes kurulumu başarılıdır.

Desktop için kontrol:

```powershell
Test-Path "$env:LOCALAPPDATA\hermes\hermes-agent\apps\desktop\release"
```

Sonra:

```powershell
hermes desktop --skip-build
```

Desktop artifact build edilmemiş veya eksikse CLI yine kullanılabilir.

### 8.5 Git Bash Yok

Script `C:\Program Files\Git\bin\bash.exe` arar. Yoksa bundle içindeki PortableGit'i kullanmaya çalışır.

Kontrol:

```powershell
echo $env:HERMES_GIT_BASH_PATH
Test-Path $env:HERMES_GIT_BASH_PATH
```

---

## 9. Önerilen Güncelleme Politikası

Air-gapped ortamda her patch'i anında geçirmek şart değildir.

Öneri:

```text
Ayda 1 GitHub release kontrolü
Kritik Windows/native/custom endpoint/security fix varsa update
Büyük release çıktıysa önce tek test makinesinde dene
Sonra diğer intranet makinelerine dağıt
```

---

## 10. Kısa Akış Özeti

### Internet

```cmd
cd /d C:\HermesUnifiedAirgapFactoryWin10
BuildCompleteHermesAirgapBundle.bat
```

Çıktı:

```text
C:\HermesUnifiedAirgapFactory\output\HermesAirgapBundle_<tag>_with_desktop.zip
```

### Intranet

ZIP'i aç:

```text
C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop
```

Kur/update:

```cmd
cd /d C:\HermesDeploy\extracted\HermesAirgapBundle_<tag>_with_desktop
InstallOrUpdateHermesAirgapped.bat
```

Model ayarı:

```powershell
hermes model
```

Chat:

```powershell
hermes chat
```

Desktop:

```powershell
hermes desktop --skip-build
```

veya:

```cmd
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat
```
