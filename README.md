# Hermes Agent — İnternetsiz Windows 10 Intranet Kurulumu (minimal masaüstü, MSIX'siz)

[Hermes Agent](https://github.com/NousResearch/hermes-agent)'ı **internete hiç çıkmayan bir Windows 10 kurumsal PC'de** masaüstü uygulamasıyla kullanmak için hazırlanmış yöntem, script ve notların hepsi bu repoda. Modeller şirket içindeki sunuculardan geliyor (örneğin yerel DeepSeek, vLLM üzerinde GLM/Qwen).

> **Durum (26 Ekim 2026):** Hermes **v0.22.4**, bu yöntemle intranetteki Windows 10 Enterprise LTSC (build 19044) makinesine **sorunsuz kuruldu**. Kurulumda eski komut kullanıldı: `InstallOrUpdateHermesAirgapped.bat Auto CleanVenv`. Masaüstü uygulaması, CLI, yerel model bağlantısı, MCP ve dashboard çalışıyor.

## Neden gerekli?

- **Resmî masaüstü paketi Windows 10'a kurulamıyor.** Hermes'in resmî masaüstü paketi bir MSIX ve manifestinde `MinVersion=10.0.22621.0` yazıyor; yani Windows 11 22H2 veya üstü istiyor. Bu sınırın kaynağı Electron değil, MSIX manifest şeması. Aynı uygulama, paketlenmemiş hâliyle (`win-unpacked\Hermes Agent.exe`) Windows 10'da çalışıyor.
- **Resmî tam paket çok büyük.** Paket ~4 GB tutuyor çünkü upstream, PM'deki **bütün** araçları pakete koyuyor: dört llama.cpp varyantı, computer-use sürücüsü, GitHub CLI, Bitwarden ve diğerleri. Modeller şirket sunucusundaysa bunların hiçbiri gerekmiyor.
- **Bu repodaki factory'nin ürettiği paket:**
  - **~0,9 GB** büyüklüğünde tek bir ZIP.
  - Masaüstü uygulaması ve tek bir runtime içeriyor; CLI da aynı runtime'ı kullanıyor.
  - Pakete giren araçlar: python, uv, node, npm, ffmpeg, ripgrep, git (Git Bash), chromium ve agent-browser (tarayıcı aracı). Python tarafında `web` ve `mcp` eklentileri var.
  - Kurulum eski alışılmış komutla yapılıyor. Yedek alma, tam SHA256 doğrulaması, otomatik geri alma ve rollback dahil.

## Hızlı başlangıç

**1. İnternetli Windows PC (factory)**
```bat
:: factory\HermesAirgapFactoryAuto_v4 klasörünü C:\HermesAirgapFactoryAuto_v4 olarak kopyala
cd /d C:\HermesAirgapFactoryAuto_v4
ValidateFactoryScripts.bat
BuildHermesDesktopWin10.bat                      &:: en güncel kararlı sürüm
:: belirli bir sürüm:  BuildHermesDesktopWin10.bat -VersionRef v0.22.4
:: sadece yeniden paketle:  BuildHermesDesktopWin10.bat -PackageOnly
```
Çıktı: `C:\H4\output\HermesAirgapBundle_<sürüm>_Win10_Desktop.zip` ve `.sha256` dosyası.

**2. Intranet PC**
```bat
:: ZIP'i C:\H4Transfer'e aktar, SHA256'yı karşılaştır, çıkar:
cd /d C:\H4Transfer && tar -xf HermesAirgapBundle_v0.22.4_Win10_Desktop.zip
cd HermesAirgapBundle_v0.22.4_Win10_Desktop
InstallOrUpdateHermesAirgapped.bat Pilot              &:: isteğe bağlı, hiçbir şeyi değiştirmez
InstallOrUpdateHermesAirgapped.bat Auto CleanVenv     &:: kur / güncelle
RollbackHermesAirgapped.bat                           &:: geri al
```
Ayrıntılı adımlar: [docs/03-kurulum-rehberi.md](docs/03-kurulum-rehberi.md)

## Repo içeriği

| Yol | İçerik |
|---|---|
| [`factory/HermesAirgapFactoryAuto_v4/`](factory/HermesAirgapFactoryAuto_v4) | **Güncel factory v4.8.1.** `BuildHermesDesktopWin10.ps1` minimal masaüstü paketini üretir. `helpers/desktop_minimal_worker.py` upstream'in araç ve extras seçimini değiştirir. `templates/` altında intranet installer'ı, rollback ve README var. Eski v4.6 CLI-only yolu (`BuildHermesAirgapBundle.ps1`) da duruyor. |
| [`pilots/cli-pilot-v1.2/`](pilots/cli-pilot-v1.2) | Üretim makinesinde mevcut kuruluma dokunmadan v0.22.2 CLI'yi test eden izole pilot. |
| [`pilots/desktop-delta-kit-v1.0/`](pilots/desktop-delta-kit-v1.0) | MSIX'siz masaüstü uygulamasının Windows 10'da çalıştığını kanıtlayan kit. Factory tarafı payload ile karşılaştırıp yalnızca farkı (265 MB) paketler; intranet tarafı uygulamayı yeniden kurar ve doğrular. |
| [`tests/`](tests) | PowerShell parser ve 5.1 sözdizimi kontrolü (`parse.ps1`). Linux üzerinde PowerShell 7 ve stub'larla çalışan simülasyon paketi (`sim/run-sim.sh`). |
| [`docs/`](docs) | Bütün bilgi; aşağıdaki listeye bak. |
| [`archive/handoff-2026-10-21/`](archive/handoff-2026-10-21) | Önceki oturumdan devralınan tam paket (orijinal ZIP ve açılmış hâli): devir notu, factory v3–v4.6, pilot v1/v1.1, eski installer ve runbook'lar. |
| [`archive/history-extracted/`](archive/history-extracted) | Arşivdeki bütün eski ZIP'lerin açılmış hâli, kolay okumak için. |
| [`archive/delivered-zips/`](archive/delivered-zips) | Bu çalışmada teslim edilen ZIP'ler (pilot v1.2, masaüstü kiti, factory v4.7 / v4.8 / v4.8.1) ve `SHA256SUMS.txt`. |
| [`CHANGELOG.md`](CHANGELOG.md) | Sürüm sürüm değişiklikler. |

## Dokümanlar

1. [Hedef ve ortam](docs/01-hedef-ve-ortam.md)
2. [Mimari ve kararlar](docs/02-mimari-ve-kararlar.md): neden 4 GB, neyi neden çıkardık, tek runtime, MSIX analizi
3. [Kurulum rehberi](docs/03-kurulum-rehberi.md): factory, intranet, pilot, rollback, temizlik
4. [Kronoloji ve karşılaşılan hatalar](docs/04-kronoloji.md): v3'ten v4.8.1'e kadar her hata ve çözümü
5. [Test ve doğrulama](docs/05-test-ve-dogrulama.md): gerçek makine sonuçları, simülasyon senaryoları, bağımsız inceleme, hash'ler
6. [Upstream kod analizi](docs/06-upstream-analizi.md): Hermes kaynağındaki hangi dosya ve satıra dayandığımız
7. [Yeni Hermes sürümüne geçiş](docs/07-yeni-surum.md): her yeni sürümde ne kontrol edilmeli
8. [Sorun giderme](docs/08-sorun-giderme.md): bilinen hatalar, belirtileri ve çözümleri

## Güvenlik notları

- Upstream kaynak koduna dokunulmuyor. Seçimler, PM'in resmî hazırlık akışı içinde harici bir worker'la yapılıyor. TLS doğrulamasını devre dışı bırakan hiçbir şey yok.
- Pakette sertifika, `.env`, token veya şirket içi adres yok. Installer `.env` ve `company-ca-bundle.pem` dosyalarını sadece kullanıcının **kendi** makinesinde yedekler.
- ZIP'in SHA256'sı aktarımın bozulmadığını kanıtlar; imza ya da menşe doğrulamasının yerini tutmaz. Payload içindeki exe'ler upstream imzası olmadan gelir (`AZURE_SIGN_*` tanımlı değil).
