# 5. Test ve doğrulama

## 5.1 Gerçek makine sonuçları

### Intranet (Windows 10 Enterprise LTSC 19044, PS 5.1.19041.7725)

| Tarih | Ne | Sonuç |
|---|---|---|
| 22.10 | CLI pilot v1.2 (v0.22.2) | **PILOT_OK**. ZIP SHA eşleşti; 41.870 ZIP kaydı, eksik 0; payload 41.865 dosya / 4.136 MB; en uzun yol üretimde 194, geçici klasörde 213, pilotta 192; `--version` 1,4 s, `--help` 1,8 s; mevcut kurulum değişmedi |
| 22.10 | Config kopyası ile | v46 → v50 migrate; DeepSeek cevap verdi; `hermes dashboard` açıldı |
| 22.10 | Masaüstü delta kiti (v0.22.2) | 43.005/43.005 dosya doğrulandı; bundled CLI `v0.22.2 · stable`; ilk açılışta `0xE0000008`, ikincide açıldı ve modelle konuşuldu |
| 23–26.10 | **v0.22.4 minimal paket, `Auto CleanVenv` (pilot atlanarak)** | **Sorunsuz kurulum ve kullanım** |

### Factory (Windows 10, PS 5.1, tr-TR)

| Tarih | Ne | Sonuç |
|---|---|---|
| 23.10 | v4.7 | `WinError 5` (eski, salt okunur `agent-payload`) → v4.8 |
| 23.10 | v4.8, v0.22.4 | Hazırlık ve paketleme OK, bundled CLI `v0.22.4 · stable`; araç listesi doğru; paketleme Türkçe İ hatasıyla durdu → v4.8.1 |
| 23.10 | v4.8.1 `-PackageOnly` | ZIP üretildi |

## 5.2 Simülasyon (Linux, PowerShell 7.4.6, stub exe'ler)

```bash
PWSH=/path/to/pwsh tests/sim/run-sim.sh
```

26.10.2026 çalıştırması: **27/27 PASS**.

| Grup | Senaryo |
|---|---|
| 0 | Repodaki bütün `.ps1` dosyaları parse ediliyor ve PS 7'ye özgü sözdizimi (`??`, `?.`, `&&`, `\|\|`, ternary) içermiyor |
| 1 | Factory `-PackageOnly`: ZIP ve `.sha256` oluşuyor, `BUNDLE.json` sözleşmesi doğru, `LICENSE.electron.txt` geçiyor; `tools\llamacpp-*` varsa **reddediyor** |
| 2-A | Pilot: gerçek kuruluma dokunmuyor, config kopyası migrate ediliyor |
| 2-B | Update: `app` aktif, eski klasör yedekte, başlatıcılar (+`HERMES_STREAM_READ_TIMEOUT`), shim, migrate, durum `installed` |
| 2-C / C2 | Rollback her şeyi geri koyuyor (shim siliniyor, başlatıcılar ve config eski hâline dönüyor); ikinci rollback reddediliyor |
| 2-D / D2 | Geçişten sonra hata (`SIM_FAIL_ACTIVE`) → otomatik geri yükleme; sonrasında rollback reddediliyor |
| 2-F | Yedek silinmişken rollback → **hiçbir şey değişmiyor** |
| 2-G | Yarıda kesilmiş `switching` durumundan rollback |
| 2-H | Hem `hermes-agent` hem `app` varken update ve rollback |
| 2-E / E2 | Bozuk dosya ya da fazladan dosya → reddediliyor, geçici kopya temizleniyor, kurulum değişmiyor |
| 3 | CLI pilot v1.2: sonunda `\"` kalıntısı olan BAT değişkeni, stderr gürültüsü, eksik çıkarma |
| 4 | Masaüstü delta kiti: factory tarafı fark ve yeni dosyaları paketliyor; intranet tarafı her dosyayı doğruluyor ve uygulamayı başlatıyor |

**Simülasyonun kanıtlayamadıkları:**
- Windows PowerShell 5.1 ve .NET Framework'e özgü davranışlar. Örneğin [Türkçe İ](08-sorun-giderme.md#türkçe-i-regex-hatası) hatası sadece gerçek factory'de görüldü.
- Registry'deki kullanıcı ortam değişkenleri, `WScript.Shell` ile kısayol oluşturma, gerçek robocopy, tar ve Electron.

## 5.3 Bağımsız inceleme (Windows PowerShell 5.1 odaklı)

Engelleyici sorun çıkmadı. Düzeltilen **major** bulgular:

1. **Rollback durumları:** Rollback yalnızca `installed` kabul ediyordu. Pencere kapanırsa (`switching`) ya da otomatik geri yükleme yarıda kalırsa (`failed-partial`) geri dönüş yapılamıyor veya yanlış yedeğe dönülüyordu. Taşınan klasörlerin yolları da taşımadan **sonra** yazılıyordu.
2. **Geçiş bayrağı geç set ediliyordu:** `hermes-agent` taşındıktan sonra `app` taşınamazsa installer "hiçbir şey değişmedi" diyordu. Yeni uygulama yalnızca gerçekten etkinleştirildiyse kenara alınmalıydı.
3. **Rollback önce taşıyıp sonra kontrol ediyordu:** Yedek silinmişse kullanıcı ne eski ne yeni kurulumla kalabiliyordu.
4. **Durum dosyası kodlaması:** Dosya PS 5.1'de `Get-Content -Raw` ile ANSI (cp1254) olarak okunuyordu; Türkçe yollar bozulabilirdi. Ayrıca atomik yazılmıyordu.

Küçük bulgular ve düzeltmeleri:
- Rollback'te PATH artık seçici geri yükleniyor; kurulumdan sonra eklenen kayıtlar korunuyor.
- Başlatıcılar yolları `%LOCALAPPDATA%` değişkeniyle yazıyor.
- Fazladan dosya kontrolü eklendi; internet bölgesi işareti (Zone.Identifier) kaldırılıyor.
- 32 bit kabuktan çağrılırsa Sysnative PowerShell kullanılıyor; taşıma işlemleri tekrar deneniyor.
- Şema kontrolü, sürüm alanları okunmadan önce yapılıyor.
- Factory: `Exec` stderr satırlarını sonuçtan ayırıyor; duman testi sırasında `PYTHONDONTWRITEBYTECODE` set ediliyor; ASCII dışı dosya adları reddediliyor; stamp'te `commit` alanı yoksa korunuyor.

## 5.4 Kontroller (her teslimden önce)

- `tests/parse.ps1`: bütün script'ler parse ediliyor ve 5.1 sözdizimine uygun.
- Teslim edilen dosyalarda satır sonları CRLF; `.ps1` ve Türkçe `.txt` dosyalarında UTF-8 BOM var. `.ps1` dosyalarının içeriği ASCII.
- Yeni bir upstream sürümünde worker'ı gerçek kaynağa karşı çalıştır: [07-yeni-surum.md](07-yeni-surum.md)
