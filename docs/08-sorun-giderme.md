# 8. Sorun giderme

## Factory (internetli PC)

### `PermissionError: [WinError 5] Access is denied: …agent-payload\…\__pycache__\*.pyc`
- **Neden:** Önceki bir derlemeden kalan `apps\desktop\build\agent-payload` klasörü var. PM bu klasördeki dosyaları salt okunur işaretliyor, upstream'in `snapshot()` fonksiyonundaki `shutil.rmtree` da Windows'ta salt okunur dosyaları silemiyor.
- **Çözüm:** v4.8 ve sonrası bu klasörü (ve `apps\desktop\release`) derlemeden önce kendisi temizliyor. Elle yapmak istersen:
  ```bat
  attrib -R "C:\H4\jobs\<sürüm>_Slim\src\apps\desktop\build\agent-payload\*" /S /D
  rmdir /S /Q "C:\H4\jobs\<sürüm>_Slim\src\apps\desktop\build\agent-payload"
  ```
- `Could not remove …` görürsen o klasörden başlatılmış bir `Hermes Agent.exe` ya da açık bir Explorer penceresi vardır; kapatıp tekrar dene.

### Türkçe İ regex hatası
- **Belirti:** `Non-ASCII file name would not survive tar/Explorer: LICENSE.electron.txt`
- **Neden:** Windows PowerShell 5.1'in (.NET Framework) büyük/küçük harf duyarsız regex'i (`-match`/`-notmatch`), tr-TR yerel ayarda `I` harfini noktasız `ı` (U+0131) yapıyor. `[^\x20-\x7E]` gibi **negatif** bir karakter sınıfı bu yüzden yanlış eşleşiyor.
- **Çözüm:** v4.8.1 `-cnotmatch` kullanıyor.
- **Genel kural:** Bu tür makinelerde aralık ya da negatif sınıf içeren regex'lerde büyük/küçük harf duyarlı operatörleri (`-cmatch`, `-cnotmatch`) kullan. PowerShell 7 (.NET 8) bu hatayı yapmıyor; Linux simülasyonu bu yüzden yakalayamadı.

### `Official Desktop stable builder requires an rc.N-vX.Y.Z claim tag`
Sürüm için claim etiketi henüz yayınlanmamış. Bir önceki sürümü seç (`-VersionRef`) ya da etiketin yayınlanmasını bekle.

### `Excluded tool still present: llamacpp-…`
İzin listesi uygulanmamış. Muhtemelen eski bir `prepared.json` ya da `-PackageOnly` ile eski bir `win-unpacked` kullanıldı. `-PackageOnly` olmadan tekrar çalıştır.

### `Portable Node pin not found (C:\H4\tools\node-selected.txt)`
v4.6'nın `BuildHermesAirgapBundle.ps1` script'ini bir kez çalıştır; bu dosyayı oluşturur. İstersen `C:\H4\tools\node-selected.txt` dosyasını `v24.x.y` içeriğiyle elle de yazabilirsin.

### Log'da `building target=MSIX`
Normal. desktop.py electron-builder'a her zaman `--win msix` veriyor. MSIX yan ürün olarak oluşuyor, pakete girmiyor ve bir sonraki derlemede temizleniyor.

### `[batch-sign] AZURE_SIGN_* not set — payload binaries will be UNSIGNED`
Normal. Upstream'in imza anahtarları yalnızca kendi CI'ında var.

## Intranet

### Installer: `Close Hermes first … Still running: …`
`%LOCALAPPDATA%\hermes` altından çalışan bir süreç var: masaüstü uygulaması, `hermes` çalışan bir terminal ya da gateway. Kapat ve tekrar çalıştır. Bu noktaya kadar hiçbir şey değişmemiştir.

### `N files are missing or damaged` / `Copied folder has X files, manifest lists Y`
ZIP eksik ya da hatalı çıkarılmış veya klasöre fazladan bir dosya girmiş. ZIP'i `tar -xf` ile temiz bir klasöre yeniden çıkar ve SHA256'yı kontrol et. Kurulum değişmemiştir.

### Masaüstü uygulaması ilk açılışta hemen kapanıyor (`-536870904` / `0xE0000008`)
- **Ne olduğu:** Bu Chromium'un OOM istisna kodu. Delta pilotunda bir kez görüldü; sonraki açılışlarda uygulama sorunsuz çalıştı. Gerçek bellek sıkıntısı yoktu (32 GB RAM).
- **Tekrar açınca çalışmazsa** şunları topla:
  - `%LOCALAPPDATA%\hermes\logs\desktop.log` dosyasının son 60 satırı
  - Olay günlüğü:
    ```powershell
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-3)} | Where-Object { $_.Message -match 'Hermes Agent' }
    ```
  - Uygulamayı log modunda başlat:
    ```powershell
    $env:ELECTRON_ENABLE_LOGGING='1'
    & "$env:LOCALAPPDATA\hermes\app\Hermes Agent.exe" --enable-logging=stderr 2>&1 | Out-File "$env:TEMP\electron_stderr.txt"
    ```
  - Crash dump'ları:
    ```powershell
    Get-ChildItem "$env:APPDATA\Hermes Agent" -Recurse -Filter *.dmp
    ```

### `hermes` komutu bulunamıyor
Yeni bir terminal aç; PATH değişikliği yalnızca yeni açılan terminallerde geçerli olur. Yine bulunamıyorsa doğrudan `%LOCALAPPDATA%\hermes\hermes.cmd --version` ile dene.

### Sürüm `vunknown (2026.9.24)` görünüyor
Bu çıktı v4.6'nın native payload'ından geliyor; içinde install stamp yok. Masaüstü paketinde (v4.7+) sürüm doğru görünür. Zararsız; `2026.9.24` upstream kaynağındaki release-date sabiti.

### Terminal aracı çalışmıyor (bash bulunamadı)
Installer, var olmayan bir yolu gösteren `HERMES_GIT_BASH_PATH` değerini siler; böylece paketteki Git Bash kullanılır. Değişken bilerek başka bir yolu gösteriyorsa o yolun var olduğundan emin ol.

### Geri dönmek istiyorum
`RollbackHermesAirgapped.bat`. Yedekler silindiyse rollback hiçbir şeye dokunmadan durur. Bu durumda `%LOCALAPPDATA%\hermes_backup_before_airgap_*` klasöründen elle geri yükle.

## Pilotlar (tarihsel)

### Pilot v1/v1.1: `Exception calling "GetFullPath" … path is not of a legal form` / `Illegal characters in path`
- **v1:** `param` varsayılanındaki `$PSScriptRoot` boş geldi.
- **v1.1:** `-BundleRoot "%~dp0"` kullanıldı; sondaki `\"` kaçış dizisi yola bir tırnak ekledi.
- **v1.2:** Klasörü ortam değişkeniyle aktarıyor ve birden fazla aday yolu deniyor. BAT dosyalarında `"%~dp0"`'ı hiçbir zaman bir argümanın sonuna koyma; gerekiyorsa `"%~dp0."` kullan.

### PS 5.1'de `& exe 2>&1` + `ErrorActionPreference=Stop`
Exe stderr'e tek satır yazsa bile script sonlanır. `System.Diagnostics.Process` ile stdout ve stderr'i ayrı yakala ya da o blokta EAP'yi geçici olarak `Continue` yap.

### Strict mode'da `The property 'Count' cannot be found`
Bir fonksiyondan dönen boş dizi `$null` olur. Çağrıyı `@(Get-Something).Count` şeklinde sarmala.
