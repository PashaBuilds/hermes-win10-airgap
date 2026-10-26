# 1. Hedef ve ortam

## Hedef

- Hermes Agent'ı **internetsiz** bir Windows 10 intranet bilgisayarında **masaüstü uygulamasından** kullanmak. Model olarak şirketin yerel sunucuları kullanılır (DeepSeek vb., OpenAI uyumlu uç noktalar).
- Paket **minimal** olmalı: kullanılmayan özellikler (yerel model sunucusu, computer use, GitHub CLI, Bitwarden, MSIX vb.) pakete girmemeli.
- **En güncel kararlı Hermes sürümü** kullanılmalı. Factory varsayılan olarak `latest` sürümü seçer.
- Kullanıcı deneyimi değişmemeli. Tek ZIP gelir, çıkarılır ve tek komutla kurulur:
  ```bat
  InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
  ```
- Çalışan kurulum asla riske atılmamalı. Bunun için yedek alınır, tüm dosyalar doğrulanır, hata olursa otomatik geri alınır ve ayrıca bir rollback komutu vardır.

### Değişmez şartlar (ilk günden beri)

1. Hedef sistem **Windows 10 x64** olarak kalacak; Windows 11'e yükseltme yok.
2. Intranet makinesinin **internet erişimi yok**. Dosyalar onaylı kurumsal yöntemle aktarılır.
3. Eski komut sözleşmesi korunacak: `Auto` (kurulum varsa güncelle, yoksa kur), `Install`, `Update`, `CleanVenv`.
4. Ana konum `%LOCALAPPDATA%\hermes` olacak. Config, sessions, skills, memories, cron ve logs korunacak.
5. Var olan `StartHermesDesktop.bat` kullanım alışkanlığı kaybolmayacak; aynı ada sahip dosya yeni uygulamayı açacak.

## Ortam

| | İnternetli PC (factory) | Intranet PC (üretim) |
|---|---|---|
| İşletim sistemi | Windows 10 (PowerShell 5.1.19041.7725) | Windows 10 Enterprise **LTSC**, build **19044**, x64 |
| Yerel ayar | **tr-TR** (bkz. [Türkçe İ hatası](08-sorun-giderme.md#türkçe-i-regex-hatası)) | tr-TR |
| Konumlar | Factory `C:\HermesAirgapFactoryAuto_v4`, iş kökü `C:\H4` (≤24 karakter şartı), job `C:\H4\jobs\<sürüm>_Slim\src`, çıktı `C:\H4\output` | Transfer `C:\H4Transfer` |
| Araçlar | Taşınabilir Node 24.22.0 (`C:\H4\tools`), bootstrap Python 3.11 (`%LOCALAPPDATA%\Programs\Python\Python311`), Git | `robocopy`, `tar.exe` (Windows 10 dahili); ExecutionPolicy Bypass ile script çalıştırılabiliyor |
| Donanım ve disk | — | 32 GB RAM, pagefile 2 GB (D:), `LongPathsEnabled=1`, C: diskinde ~18–23 GB boş |
| Önceki Hermes | — | v0.21.5 (eski "wheelhouse" yöntemi): `%LOCALAPPDATA%\hermes\hermes-agent` (kaynak + Python 3.11 venv), config şema **v46**, `StartHermesDesktop.bat` hem `%LOCALAPPDATA%\hermes` hem masaüstünde |
| Modeller | — | Şirket içi sunucular (DeepSeek; ayrıca vLLM üzerinde GLM / Qwen) |

### Eski (v0.21.5) kurulumun yaptıkları

Eski kurulum `archive/handoff-2026-10-21/extracted/kaynaklar/eskiden_kullanilan_kurulum/` altında duruyor:

- **Kurulum:** Python 3.11 kurucusu `%LOCALAPPDATA%\hermes\python311` içine kurulur. Ardından venv oluşturulur ve `pip install --no-index --find-links wheelhouse -e ".[web,mcp,cron,cli]"` çalıştırılır.
- **Ortam:** Kullanıcı PATH'ine `hermes-agent\venv\Scripts` ve paketteki Node eklenir. `HERMES_HOME`, `PYTHONUTF8`, `PYTHONIOENCODING` ve `HERMES_GIT_BASH_PATH` kullanıcı ortam değişkeni olarak yazılır.
- **Başlatıcı:** `StartHermesDesktop.bat` → `venv\Scripts\hermes.exe desktop --skip-build`. Bu dosya `HERMES_STREAM_READ_TIMEOUT=1800` ayarını da içerir.

v0.22.x bu yöntemi artık desteklemiyor: Python 3.14 ve PM'in mühürlü runtime'ını kullanıyor, venv doğrudan çalıştırılmıyor. Yeni yöntem bu davranışları **taklit eder**, ama içeride tamamen farklı çalışır.

## Kapsam dışı

- Windows 11 ve MSIX ile kurulum.
- Hermes'in kendi `hermes update` güncelleme kanalı. Ortam çevrimdışı olduğu için güncellemeler factory üzerinden yapılır.
- Kurumsal kod imzalama. Payload exe'leri upstream imzası olmadan gelir.
