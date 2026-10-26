# 4. Kronoloji ve karşılaşılan hatalar

Bu belge iki dönemi kapsıyor. **Önceki oturum** 21.10.2026'ya kadar sürdü; tam devir notu `archive/handoff-2026-10-21/extracted/HERMES_DEVIR_NOTLARI_YENI_OTURUM_2026-10-21.md` içinde. **Bu çalışma** 22–26.10.2026 tarihlerini kapsıyor.

## Önceki oturum (factory v3 → v4.6, pilot v1 / v1.1)

| Aşama | Hata ya da gözlem | Çözüm |
|---|---|---|
| v0.21.5 ve eski factory'ler | ~800 MB'lık "wheelhouse" paketi: Python 3.11 + `pip --no-index`, `hermes desktop --skip-build` | Çalışan referans kurulum (`archive/.../eskiden_kullanilan_kurulum/`) |
| Auto v3 / v3.1 | Hermes PM'e ve Python 3.14'e geçmişti; `pip download` ve eksik bağımlılık sorunları | Resmî PM lock dosyalarını kullanan factory'ye geçildi |
| v4.0 → v4.1 | PowerShell parse hatası (`${pyVer}:`); `PYTHONPATH` sızıntısından `SRE module mismatch`; pyc etiketi 311/314 karışması; `WinError 145`; MAX_PATH; isteğe bağlı `pilk` wheel'i | Parser testleri, kaynak yama/geri alma, kısa `C:\H4` kökü, Slim profili (core + web + mcp), launcher izolasyonu |
| v0.22.1 Web/Vite | `Cannot find package 'babel-plugin-react-compiler'` | Orijinal checkout'ta `node-deps.mjs --workspace ui-tui --workspace web --reuse` (v4.2 otomatikleştirdi) |
| v0.22.1 → v0.22.2 | v0.22.1 yanlış commit'ten yayımlanmıştı | `-VersionRef v0.22.2` |
| v4.2 → v4.3 | ZIP'ten sonra `Get-FileHash -Path ''`: robocopy'nin stdout'u fonksiyonun dönüş değerine karışmış | stdout bastırıldı, `-LiteralPath` |
| İlk masaüstü derlemesi | `Prepared Electron PTY admission failed … ETIMEDOUT (15 s)` | Elle yapılan PTY testi ve ardından resmî `probe-prepared-native.mjs` exit 0 (4,43 s) |
| Masaüstü hazırlığı | `alibabacloud-gateway-dingtalk==1.0.2` wheel'i derlenemedi (`all_extras=True` yüzünden) | v4.4: harici worker, `extras=('web','mcp')` |
| v4.4 / v4.5 | Resmî `HermesBundled-0.22.2-win-x64.msix` oluştu; transfer ZIP'i 4 GB | — |
| MSIX analizi | `MinVersion=10.0.22621.0`, imzasız | **Windows 10'da kurulamaz** |
| v4.6 | `-PackageOnly -Win10Compat`: MSIX'siz, eski BAT sözleşmeli, CLI/Web/MCP içeren 1,7 GB ZIP (SHA `EA3183…D9E`) | Üretildi |
| Pilot v1 | `Exception calling GetFullPath … path is not of a legal form` | v1.1 (aşağıda) |

## Bu çalışma (22–26 Ekim 2026)

| # | Ne oldu | Neden | Çözüm |
|---|---|---|---|
| 1 | **Pilot v1.1 çalışmadan analiz edildi.** BAT, klasörü `-BundleRoot "%~dp0"` ile gönderiyordu. | `%~dp0` sonu `\` ile biter; powershell.exe için `\"` kaçışlı tırnaktır. Script'e `…\Bundle"` (sonunda tırnakla) gidiyordu. | **Pilot v1.2:** klasör bir ortam değişkeniyle aktarılıyor; script 5 aday yolu deneyip içinde `BUNDLE.json` olanı seçiyor. |
| 2 | v1.1'de ikinci gizli hata | PS 5.1'de `& exe 2>&1` + `ErrorActionPreference=Stop`: exe stderr'e tek satır yazsa bile test düşüyor. | v1.2: `Process` API ile stdout ve stderr ayrı yakalanıyor, zaman aşımı var. |
| 3 | Ek önlemler | Türkçe kod sayfası, MAX_PATH, eksik çıkarma riski | `PYTHONUTF8`; pilot yolu üretim yolundan kısa; ZIP'e karşı tam çıkarma kontrolü; disk kontrolü; mevcut kurulumun önce/sonra parmak izi |
| 4 | **Pilot v1.2 üretim PC'de: `PILOT_OK`** | — | 41.865 dosya, 4.136 MB; ZIP SHA eşleşti; `--version` 1,4 s |
| 5 | `vunknown (2026.9.24)` | Upstream `hermes_cli/__init__.py`: `__release_date__ = "2026.9.24"`; native payload'da `install-stamp.json` yok | Sorun değil; eski kod yüklenmiyor |
| 6 | Config kopyası v46 → v50 migrate edildi; DeepSeek cevap verdi, dashboard açıldı | — | — |
| 7 | "Masaüstü uygulaması gelecek mi?" sorusunun analizi | MSIX'in Windows 11 sınırı manifest şemasından geliyor; `hermes desktop --skip-build` yöntemi v0.22.2'de hâlâ var | MSIX'siz `win-unpacked` yolu seçildi |
| 8 | `Hermes.exe` arandı, bulunamadı | Bundled varyantta exe'nin adı `Hermes Agent.exe` | `win-unpacked` factory'de mevcuttu (4.523 MB) |
| 9 | **Masaüstü delta kiti v1.0** | 4,5 GB'ı tekrar taşımamak için | Factory'de dosya dosya hash karşılaştırması: 28.586 dosya payload'dan, 14.419 dosya kitte (265 MB ZIP) |
| 10 | Kit factory'de çalıştı, intranette 43.005/43.005 dosya doğrulandı; ama `Hermes Agent.exe` **ilk açılışta** `-536870904` (`0xE0000008`) ile kapandı | Chromium'un OOM istisna kodu. Gerçek bellek sıkıntısı yoktu (32 GB RAM, 20 GB boş). `desktop.log` `Starting Hermes backend` satırında kesildi, olay günlüğü boş. | Uygulama **ikinci açılışta çalıştı**; v0.22.2 açıldı ve modelle konuşuldu. İlk açılışa özgü olduğu değerlendirildi. |
| 11 | "Neden 4 GB?" analizi | `_bundle_package_names()` bütün araçları alıyor | Minimal izin listesi; kullanıcı tarayıcı aracı ve git'in kalmasını istedi |
| 12 | **Factory v4.7** | — | Minimal worker, `--dir`, tek runtime, Pilot/Auto/Rollback installer'ı |
| 13 | v4.7 simülasyonunda iki kez aynı hata sınıfı | Strict mode'da boş dizi `$null` oluyor, `.Count` patlıyor | `@(...)` ile sarmalandı |
| 14 | Bağımsız PS 5.1 incelemesi: engelleyici yok, **4 major** sorun | Rollback `switching`/`failed-partial` durumlarını kabul etmiyordu; rollback önce taşıyıp sonra kontrol ediyordu; geçiş bayrağı geç set ediliyordu; durum dosyası PS 5.1'de ANSI okunuyordu | Hepsi düzeltildi, ayrıca küçük bulgular ([05](05-test-ve-dogrulama.md)) |
| 15 | **v4.7 gerçek factory koşusu:** `PermissionError: [WinError 5] Access is denied: …agent-payload\hermes-agent\acp_adapter\__pycache__\auth.cpython-314.pyc` | v4.4'ten kalan eski `apps\desktop\build\agent-payload` klasöründeki `.pyc` dosyaları PM tarafından salt okunur işaretli; `shutil.rmtree` Windows'ta salt okunur dosyayı silemiyor | **v4.8:** hazırlıktan önce `attrib -R` + `Remove-Item -Force` (robocopy yedeğiyle) |
| 16 | Kullanıcı en güncel sürümü istedi | GitHub latest = **v0.22.4** (21.10.2026, claim `rc.2-v0.22.4`) | v4.8: `-VersionRef latest`, otomatik klonlama, paylaşılan önbellek; v0.22.2 → v0.22.4 upstream farkları kontrol edildi |
| 17 | **v4.8 gerçek koşu:** derleme başarılı (`Hermes Agent v0.22.4 · stable`), ama paketleme `Non-ASCII file name … LICENSE.electron.txt` hatasıyla durdu | **Türkçe İ:** PS 5.1 (.NET Framework regex) büyük/küçük harf duyarsız `-notmatch` ile tr-TR'de `I` harfini `ı` (U+0131) yapıyor, bu da ASCII aralığının dışında. Linux'taki PS 7 simülasyonu bunu yakalayamadı. | **v4.8.1:** `-cnotmatch` |
| 18 | Log'da MSIX yine üretildi | desktop.py her zaman `--win msix` veriyor; `--dir` bunu bastırmıyor | Zararsız yan ürün, pakete girmiyor |
| 19 | **v4.8.1 `-PackageOnly` → `HermesAirgapBundle_v0.22.4_Win10_Desktop.zip`** | — | — |
| 20 | **Intranette pilot atlanarak `Auto CleanVenv` ile kuruldu: SORUNSUZ** (23–26.10.2026) | — | — |

## Teslim edilen ZIP'ler

`archive/delivered-zips/SHA256SUMS.txt`:

| Dosya | SHA256 |
|---|---|
| `HermesWin10_UretimPilot_v1_2.zip` | `533f6fe4554933f690b379090385753ccddfce837aad7fe7a21e1f403e466112` |
| `HermesDesktopWin10_PilotKit_v1_0.zip` | `cac652e5528b514121818bb03693dcbadb592378ad40b36f07a8f8476c0fd0aa` |
| `HermesAirgapFactoryAuto_v4_7.zip` | `e7e7ff4300b00a770b141c5494eec5faac3ed43a20758910d02d64d718ed3360` |
| `HermesAirgapFactoryAuto_v4_8.zip` | `4abebf05cb43bcbc2885c53ccb559e8e831e28f67659cfda13ff45f947498275` |
| `HermesAirgapFactoryAuto_v4_8_1.zip` | `b3217a65d75794bab1d8db08b0394c925845cb9b5eb9627a4649c7459be154e0` |

Bu repoda bulunmayan, kullanıcının makinelerinde üretilmiş büyük dosyalar:

| Dosya | SHA256 |
|---|---|
| `HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip` (v4.6, 1,7 GB) | `EA3183E37E1344A6F25249A83F6FC78B17875D00252CF14C95D51AB8CA9D7D9E` |
| `HermesDesktopWin10_v0.22.2_delta.zip` (265 MB) | `66843E179DF648A0B97F0F0A01D56AACC702AE8C6DCA54C9093EE5427EC479DD` |
| `HermesAirgap_v0.22.2_Slim_desktop.zip` (v4.5, MSIX'li, ~4 GB) | `B21D11FDFF127DA6CF635F22C679F17DC749E7A0DAF9028806E649D15A049F20` |
