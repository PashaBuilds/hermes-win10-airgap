# 2. Mimari ve kararlar

## 2.1 Resmî paket neden ~4 GB?

Factory v4.4–v4.5'in ürettiği resmî paket (masaüstü MSIX + native payload), ZIP içinde sıkıştırılmış olarak şu boyutlara sahipti:

| Bileşen | MB | Ne işe yarıyor |
|---|---:|---|
| `desktop/MSIX` | **2.304,9** | Windows 11 masaüstü kurulumu |
| `tools/llamacpp-cuda` | **551,0** | Modeli **bu PC'de** NVIDIA GPU ile çalıştırma |
| `tools/llamacpp-hip` | **248,8** | AMD GPU ile aynı iş |
| `tools/chromium-1208` | 172,7 | Tarayıcı aracı |
| `tools/ffmpeg` | 161,8 | Ses, TTS, ekran kaydı |
| `tools/git` | 151,9 | Git Bash (Windows'ta terminal aracı) |
| `venv` | 70,6 | Python bağımlılıkları |
| `uv-cache` | 54,2 | Çevrimdışı yeniden kurulum için wheel'ler |
| `hermes-agent` | 52,7 | Kaynak anlık görüntüsü |
| `python-3.14.7` | 47,2 | Gömülü Python |
| `node-26.7.0` | 40,6 | Dashboard, TUI, `npx` ile çalışan MCP sunucuları |
| `llamacpp-vulkan` / `llamacpp-cpu` | 32,5 / 18,9 | Yerel model çalıştırma |
| `cua-driver` | 25,1 | Bilgisayar kontrolü (computer use) |
| `uv` | 18,7 | Paket yöneticisi |
| `gh` | 14,0 | GitHub CLI |
| `bws` | 5,5 | Bitwarden secrets |
| `agent-browser` | 4,5 | Tarayıcı aracının sürücüsü |
| `npm` | 3,7 | — |
| `ripgrep` | 1,8 | Dosya içi arama |

**Kök neden:** Upstream'in `scripts/bundles/native.py` dosyasındaki `_bundle_package_names()` fonksiyonu, `pm/lock.json`'daki dahili olmayan **bütün** paketleri pakete koyuyor. Bunların çoğu PM'de `optional = True` tanımlı; upstream'in kendi tanımıyla "installed on demand" ve "its absence never blocks PATH activation". Ayrıntılar: [06-upstream-analizi.md](06-upstream-analizi.md).

## 2.2 Seçim: izin listesi

| Karar | Paketler | Gerekçe |
|---|---|---|
| ✅ Kalıyor | `python`, `uv` | Runtime'ın kendisi |
| ✅ Kalıyor | `node`, `npm` | Dashboard, TUI, `npx` tabanlı MCP sunucuları. Upstream'de `optional=False`. |
| ✅ Kalıyor | `ffmpeg` | Upstream'de **`optional=False`**: `pm/install.py`'deki sağlık kontrolü eksik olduğunu "not installed or outdated" diye raporluyor. Çevrimdışı makinede bu, onarma denemesine yol açabilir. |
| ✅ Kalıyor | `ripgrep` | Arama aracı (2 MB). Upstream'de `optional=False`. |
| ✅ Kalıyor | `git` | Windows'ta terminal aracı `pm.shell.bash()` üzerinden Git Bash istiyor. Kullanıcının isteğiyle kesin kalsın. |
| ✅ Kalıyor | `chromium`, `agent-browser` | Tarayıcı aracı; kullanıcı istedi (intranet sayfaları için). |
| ❌ Çıktı | `llamacpp-cpu`, `-cuda`, `-hip`, `-vulkan`, `-metal` | Modeller şirket sunucusunda; bu PC'de model çalıştırılmayacak. |
| ❌ Çıktı | `cua-driver` | Computer use. Upstream'de `default=True`, ama sadece `hermes pm install` ve `hermes update` sırasında kuruluyor; masaüstü uygulaması açılışta kurmaya çalışmıyor. |
| ❌ Çıktı | `gh` | Intranette GitHub yok. |
| ❌ Çıktı | `bws` | Bitwarden kullanılmıyor. |
| ❌ Çıktı | `iron-proxy`, `whispercpp-cpu`, `termux-docker`, `dmgbuild` | Windows'ta zaten yok ya da gereksiz. |
| ❌ Çıktı | MSIX | Windows 10'da kurulamıyor. |

**Python extras:** `web` + `mcp`. Upstream varsayılanı `all_extras=True`; bu, DingTalk gibi alakasız SDK'ları da çekiyor ve v4.3'te derlemeyi kırmıştı.

**Sonuç:** ZIP **~0,9 GB**. Açılmış uygulama ~2 GB; eski 804 MB'lık v0.21.5 paketiyle aynı seviye.

v0.22.4'ün factory'de ölçülen açılmış araç boyutları (MB): agent-browser 10,4 · chromium 393,4 · ffmpeg 427,3 · git 383,9 · node 110,6 · npm 11,8 · python 147,8 · ripgrep 4,4 · uv 46,4.

### Seçim nasıl uygulanıyor (dosya silinmeden)

`factory/.../helpers/desktop_minimal_worker.py`, upstream'in resmî masaüstü hazırlık dispatcher'ı (`desktop_toolchain.run_preparation(..., worker=...)`) içinde çalışır. İki şeyi bellekte değiştirir:

1. `scripts.bundles.native._bundle_package_names` → izin listesi. İzin listesindeki bir paket upstream'de yoksa ya da zorunlu bir paket düşecek olursa hata verir.
2. `pm.build_environment` → yalnızca masaüstü `agent-payload/venv` için `extras=("web","mcp"), all_extras=False`.

Upstream daha sonra kendi kodunu çalıştırır:
- `prune_staged_store(store_dir, names)` → `facts.retain(...)`: seçilmeyen araç klasörlerini siler ve `facts.json`'u günceller.
- `record_tools(...)`: yalnızca seçilenleri kaydeder.

Böylece manifest, `facts.json` ve hash zinciri PM tarafından **tutarlı** üretilir. Elle dosya silmek bu zinciri bozardı; bu yüzden hiç yapılmadı.

Factory paketlemeden önce `tools\` klasörünü kontrol eder: `llamacpp-`, `cua-driver`, `gh-`, `bws-`, `whispercpp` ya da `iron-proxy` ile başlayan bir klasör kalmışsa **paketlemeyi reddeder**.

## 2.3 Masaüstü uygulaması Windows 10'da: MSIX yerine `win-unpacked`

- `apps/desktop/electron-builder.config.cjs` içindeki yorum, Windows 11 sınırının sebebini açıklıyor. 18307'den eski build'lerde manifest şeması AppExtension adını 39 karakterle sınırlıyor; Microsoft'un `com.microsoft.windows.copilotkeyprovider` uzantısının adı ise 40 karakter. Bu yüzden `minVersion: '10.0.22621.0'`. Yani sınır **manifest şemasından** geliyor, Electron'dan değil.
- Electron 40.10.2, factory PC'de (Windows 10) çalıştı ve upstream'in kendi PTY testi (`probe-prepared-native.mjs`) exit 0 ile geçti.
- electron-builder, MSIX'i oluşturmadan önce `release\win-unpacked\` klasörünü üretir. "Bundled" varyantta bu klasör kendi runtime'ını `resources\agent-payload` içinde taşır, `resources\install-stamp.json` dosyasını içerir, ve uygulamanın adı **`Hermes Agent.exe`**'dir (`product-identity.cjs` → bundled: `display: 'Hermes Agent'`).
- 22.10.2026'da yapılan masaüstü pilotunda bu klasör üretim PC'de (Windows 10 LTSC 19044) MSIX'siz çalıştı: v0.22.2 açıldı ve modelle konuşuldu.
- Masaüstü uygulaması `HERMES_HOME` değişkenine uyuyor (`electron/backend-env.ts`, `fs-ipc.ts`). Windows'ta CLI link'i ya da PATH değişikliği yapmıyor (`main.ts`: `if (!IS_WINDOWS) provisionCliLinks(...)`).
- Paketleme: `desktop.py --prepared … -- --dir`. Ancak desktop.py electron-builder'a her zaman `--win msix` veriyor, bu yüzden MSIX yine **yan ürün** olarak çıkıyor. Pakete girmiyor ve bir sonraki derlemede temizleniyor.

## 2.4 Tek runtime

Masaüstü uygulamasının runtime'ı (`app\resources\agent-payload`) CLI için de kullanılıyor:

- **PATH:** Kullanıcı PATH'ine `…\app\resources\agent-payload\bin` ekleniyor.
- **Shim:** `%LOCALAPPDATA%\hermes\hermes.cmd` → `app\resources\agent-payload\bin\hermes.exe`.
- **Stamp:** Bundled payload'da `install-stamp.json` olduğu için `hermes --version` doğru sürümü gösteriyor (`Hermes Agent v0.22.4 · stable`). v4.6'nın native payload'ında stamp yoktu, sürüm `vunknown (2026.9.24)` görünüyordu.

## 2.5 Kurulum yerleşimi

```
%LOCALAPPDATA%\hermes\                         HERMES_HOME — config/sessions/skills/memories/cron DOKUNULMAZ
%LOCALAPPDATA%\hermes\app\Hermes Agent.exe      masaüstü uygulaması
%LOCALAPPDATA%\hermes\app\resources\agent-payload\bin\hermes.exe   CLI
%LOCALAPPDATA%\hermes\StartHermesDesktop.bat    (+ masaüstü kopyası, + Başlat menüsü "Hermes Agent")
%LOCALAPPDATA%\hermes\hermes.cmd                CLI shim
%LOCALAPPDATA%\hermes\hermes-agent_source_backup_<zaman>   eski v0.21.5 (rollback için)
%LOCALAPPDATA%\hermes_backup_before_airgap_<zaman>\        yedek + install-state.json
```

`StartHermesDesktop.bat` şu değişkenleri ayarlar: `HERMES_HOME`, `PYTHONUTF8=1`, `PYTHONIOENCODING=utf-8` ve `HERMES_STREAM_READ_TIMEOUT=1800` (eski başlatıcıdan korundu). Yollar ASCII kalsın diye `%LOCALAPPDATA%` değişkeni üzerinden yazılır.

## 2.6 Installer akışı ve güvenlik ağı

`InstallOrUpdateHermesAirgapped.ps1` (modlar: `Auto`, `Install`, `Update`, `Pilot`, `Rollback`):

1. **Paket kontrolü:** `BUNDLE.json` şema 5 ve `installContract=legacy-auto-cleanvenv-win10-desktop` olmalı. `app-manifest.tsv`'nin SHA256'sı `BUNDLE.json`'dakiyle eşleşmeli.
2. **Ön koşullar:** Disk alanı yeterli olmalı. `%LOCALAPPDATA%\hermes` altından çalışan bir süreç varsa **hiçbir şey yapmadan** durur.
3. **Yedek:** `config.yaml`, `.env`, `company-ca-bundle.pem`, `sessions`, `skills`, `memories`, `cron`. Ayrıca kullanıcı ortam değişkenleri ve başlatıcı dosyaları `install-state.json` içine kaydedilir.
4. **Geçici kopya ve doğrulama:** `app\` klasörü `.stMMddHHmm` geçici klasörüne kopyalanır. **Her dosya** SHA256 ile doğrulanır, fazladan dosya olup olmadığına bakılır, internet bölgesi işareti (MOTW) varsa kaldırılır.
5. **CLI testi:** Geçici kopyadaki CLI, izole bir profille ve proxy kara deliğe yönlendirilmiş hâlde çalıştırılır (`--version`).
6. **Geçiş:** Eski `hermes-agent` → `hermes-agent_source_backup_<zaman>`, eski `app` → `app_backup_<zaman>`. Taşınacak yollar durum dosyasına taşımadan **önce** yazılır. Ardından geçici kopya → `app` ve aktif kopyada CLI testi tekrarlanır.
7. **Ortam ve başlatıcılar:** PATH'teki eski venv kaydı yeni `bin` ile değiştirilir. `HERMES_HOME` boşsa doldurulur. `HERMES_GIT_BASH_PATH` artık var olmayan bir yolu gösteriyorsa silinir; paketteki Git Bash kullanılır. Shim, başlatıcılar ve Başlat menüsü kısayolu yazılır.
8. **Config:** `hermes config migrate` çalıştırılır (v46 → v50).
9. **Hata olursa:** Geçişten önceki bir adımda hata çıkarsa geçici kopya silinir ve "hiçbir şey değişmedi" denir. Geçişten sonraysa yeni uygulama `app_failed_<zaman>` adıyla kenara alınır, eskisi geri konur, ortam değişkenleri, başlatıcılar ve config yedekten geri yüklenir.
10. **Rollback:**
    - Durumu `installed`, `switching` ya da `failed-partial` olan en yeni kaydı alır.
    - Önce bütün yedeklerin yerinde olup olmadığını kontrol eder; eksik varsa **hiçbir şeye dokunmaz**.
    - PATH'i seçici geri yükler: kurulumdan sonra eklenen kayıtlar korunur.
    - Durum dosyaları UTF-8 olarak okunur ve atomik yazılır.

## 2.7 Bilinçli olarak yapılmayanlar

- Payload'dan elle dosya silmek (manifest ve facts zincirini bozar).
- MSIX manifestinde `MinVersion` değerini düşürmek (desteklenmiyor; şema da izin vermiyor).
- TLS doğrulamasını kapatmak (`UV_INSECURE_HOST`, `PIP_TRUSTED_HOST` görülürse factory durur).
- Upstream kaynağını kalıcı olarak değiştirmek. v4.6 native yolu kaynağı geçici olarak yamayıp geri alıyordu; masaüstü yolu hiç yamamıyor.
