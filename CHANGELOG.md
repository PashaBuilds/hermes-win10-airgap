# CHANGELOG

## Factory v4.8.1 — 2026-10-23 (güncel)
- **Düzeltme:** ASCII dışı dosya adı kontrolünde `-notmatch` yerine `-cnotmatch` kullanılıyor. Windows PowerShell 5.1, tr-TR yerel ayarda `I` harfini `ı` yaptığı için `LICENSE.electron.txt` yanlışlıkla reddediliyordu.
- **Gözlem:** desktop.py `--win msix` verdiği için MSIX yan ürün olarak oluşuyor. Pakete girmiyor; yorumlar buna göre düzeltildi.
- **Sonuç:** v0.22.4 paketi üretildi ve intranette `Auto CleanVenv` ile **sorunsuz kuruldu** (23–26.10).

## Factory v4.8 — 2026-10-23
- **Sürüm seçimi:** `-VersionRef latest` varsayılan oldu (GitHub `releases/latest`). Checkout yoksa factory `jobs\<sürüm>_Slim\src` altına klonluyor.
- **WinError 5 düzeltmesi:** Hazırlıktan önce eski `apps\desktop\build\agent-payload` ve `apps\desktop\release` klasörleri salt okunur bayrağı temizlenerek siliniyor (`attrib -R`, `Remove-Item -Force`, robocopy yedeği).
- **Önbellek:** Masaüstü indirme önbelleği sürümler arasında paylaşılıyor (`C:\H4\desktop-cache` ya da en yeni `jobs\*\desktop-cache`).
- **Upstream:** v0.22.4 farkları kontrol edildi, worker v0.22.4 kaynağına karşı test edildi.

## Factory v4.7 — 2026-10-22
- **Yeni script:** `BuildHermesDesktopWin10.ps1/.bat` minimal Windows 10 masaüstü paketini üretiyor.
  - `helpers/desktop_minimal_worker.py`, upstream'in araç seçimini (`_bundle_package_names`) ve venv extras'ını (`web+mcp`) değiştiriyor.
  - Araç izin listesi: python, uv, node, npm, ffmpeg, ripgrep, git, chromium, agent-browser.
  - Paketleme `desktop.py --prepared … -- --dir` ile yapılıyor; tek runtime `app\resources\agent-payload`.
  - Pakette tüm dosyaların SHA256'sını içeren `app-manifest.tsv` ve `BUNDLE.json` (şema 5, `legacy-auto-cleanvenv-win10-desktop`) var.
  - Yasaklı bir araç pakette kalırsa paketleme reddediliyor.
- **Yeni installer** (`templates/DesktopInstallOrUpdateHermesAirgapped.ps1`):
  - Modlar: `Auto|Install|Update|Pilot|Rollback`; `CleanVenv` kabul ediliyor.
  - Akış: yedek, geçici kopya, her dosyanın doğrulanması, CLI testi, geçiş; ardından PATH, shim, `StartHermesDesktop.bat` (`hermes` klasörü + masaüstü), Başlat menüsü kısayolu ve `config migrate`.
  - Hata olursa otomatik geri yükleme yapılıyor.
- **Bağımsız PS 5.1 incelemesinden sonra düzeltilenler:**
  - Rollback artık `switching` ve `failed-partial` durumlarını da kabul ediyor; taşınacak yollar durum dosyasına taşımadan önce yazılıyor.
  - Rollback önce bütün yedekleri kontrol ediyor; eksik varsa hiçbir şeye dokunmuyor.
  - Otomatik geri yükleme, yeni uygulamayı yalnızca gerçekten etkinleştirildiyse kenara alıyor.
  - Durum dosyası UTF-8 okunuyor ve atomik yazılıyor.
  - Rollback'te PATH seçici geri yükleniyor; başlatıcılar `%LOCALAPPDATA%` ile yazılıyor.
  - Fazladan dosya kontrolü ve MOTW temizliği eklendi; Sysnative PowerShell kullanılıyor; taşıma işlemleri tekrar deneniyor.
- **Ne zaman çalışır:** Tek başına çalışmaz; v4.6 checkout'u gerekir (v4.8'de kaldırıldı).

## Masaüstü delta kiti v1.0 — 2026-10-22
- **Amaç:** Factory'deki `win-unpacked` klasörünü, intranete zaten taşınmış native payload ile dosya dosya karşılaştırıp yalnızca farkı taşımak (265 MB).
- **Intranet tarafı:** Uygulamayı yeniden kuruyor, 43.005 dosyayı doğruluyor ve izole bir profille başlatıyor. MSIX'siz masaüstü uygulamasının Windows 10'da çalıştığını kanıtladı.
- **Düzeltme:** Simülasyonda strict mode'daki `.Count` hatası bulundu ve düzeltildi.

## CLI Pilot v1.2 — 2026-10-22
- **Düzeltme:** v1.1'deki `-BundleRoot "%~dp0"` hatası; sondaki `\"` yola tırnak ekliyordu. Klasör artık ortam değişkeniyle aktarılıyor ve 5 aday yol deneniyor.
- **Düzeltme:** PS 5.1'deki `2>&1` + `Stop` hatası. stdout ve stderr Process API ile ayrı yakalanıyor, zaman aşımı var.
- **Eklenenler:**
  - `PYTHONUTF8`; pilot yolu artık üretim yolundan kısa.
  - ZIP SHA256 ve tam çıkarma kontrolü; yol uzunluğu, disk ve LongPaths raporu.
  - `doctor` (bilgi amaçlı) ve mevcut kurulumun önce/sonra parmak izi.
- **Sonuç:** Üretim PC'de `PILOT_OK`.

## Önceki sürümler (devralınan, 21.10.2026'ya kadar)
- Factory v3 → v4.6 ve Pilot v1 / v1.1: ayrıntılar `docs/04-kronoloji.md` ve `archive/handoff-2026-10-21/` içinde.
