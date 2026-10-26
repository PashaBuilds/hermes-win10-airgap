# 3. Kurulum rehberi

## A. İnternetli PC: paketi üret (factory)

**Gerekenler:**
- Windows 10/11 x64, PowerShell 5.1, Git, internet erişimi.
- Bootstrap için Python ≥3.11 (`py` ya da `python`).
- Factory kökü `C:\H4` olmalı; 24 karakterden kısa bir yol şart.
- Taşınabilir Node pin'i: `C:\H4\tools\node-selected.txt`. Factory ilk kez v4.6 ile çalıştırıldıysa bu dosya zaten vardır. Yoksa v4.6'nın `BuildHermesAirgapBundle.ps1` script'ini bir kez çalıştır; `GetNode` bu dosyayı oluşturur.
- Disk: yaklaşık 15 GB boş alan. Kaynak, önbellek, `win-unpacked`, MSIX yan ürünü ve ZIP için.

**Adımlar:**
1. Bu repodaki `factory\HermesAirgapFactoryAuto_v4` klasörünü `C:\HermesAirgapFactoryAuto_v4` olarak kopyala.
2. Script'leri kontrol et:
   ```bat
   cd /d C:\HermesAirgapFactoryAuto_v4
   ValidateFactoryScripts.bat
   ```
3. Paketi üret:
   ```bat
   BuildHermesDesktopWin10.bat
   ```
   Bu komut şunları yapar:
   - GitHub'daki son kararlı sürümü bulur (`releases/latest`) ve `C:\H4\jobs\<sürüm>_Slim\src` altına klonlar.
   - Resmî stable masaüstü derlemesi için gereken claim etiketini (`rc.N-<sürüm>`) bulur.
   - Eski derleme çıktılarını temizler (salt okunur dosyalar dahil).
   - Masaüstü önbelleğini yeniden kullanır: `C:\H4\desktop-cache` ya da en yeni `jobs\*\desktop-cache`.
   - Resmî hazırlığı minimal worker ile çalıştırır, ardından resmî paketlemeyi yapar.
   - Sonucu doğrular: yasaklı araç olmamalı, bundled CLI `--version` doğru sürümü vermeli.
   - Tüm dosyaların SHA256'sını hesaplar ve ZIP'i oluşturur.

   **Seçenekler:**
   - `-VersionRef v0.22.4`: belirli bir sürüm.
   - `-PackageOnly`: derleme yapmadan, mevcut minimal `win-unpacked` klasöründen yeniden paketler.
   - `-CaFile <pem>`: kurumsal TLS denetimi varsa CA dosyası.
   - `-HostPython <python.exe>`: bootstrap Python'u elle seçmek için.
4. **Çıktılar:**
   - `C:\H4\output\HermesAirgapBundle_<sürüm>_Win10_Desktop.zip` (+ `.sha256`)
   - Rapor: `C:\H4\jobs\<sürüm>_Slim\result-desktop-win10.json`
   - Log: `C:\H4\logs\desktop_win10_*.log`

   Beklenen son satırlar:
   ```
   [OK] win-unpacked is minimal and its bundled CLI runs
   [H4.8]   tool agent-browser-…  /  chromium-…  /  ffmpeg-…  /  git-…  /  node-…  /  npm-…  /  python-…  /  ripgrep-…  /  uv-…
   [OK] Minimal Windows 10 Desktop bundle ready
     ZIP / Size / SHA256
   ```

## B. Intranet PC: kur

1. **Aktar ve doğrula.** ZIP'i ve `.sha256` dosyasını `C:\H4Transfer\` içine koy:
   ```powershell
   Get-FileHash C:\H4Transfer\HermesAirgapBundle_v0.22.4_Win10_Desktop.zip -Algorithm SHA256
   ```
   Çıkan değer `.sha256` dosyasındakiyle aynı olmalı.
2. **Çıkar.** `tar` hem hızlıdır hem uzun yollarda daha güvenlidir:
   ```bat
   cd /d C:\H4Transfer
   tar -xf HermesAirgapBundle_v0.22.4_Win10_Desktop.zip
   ```
   Sonuç `C:\H4Transfer\HermesAirgapBundle_v0.22.4_Win10_Desktop\` olmalı; içinde aynı adlı ikinci bir klasör olmamalı. Klasörde `app\`, `app-manifest.tsv`, `BUNDLE.json`, `InstallOrUpdateHermesAirgapped.bat/.ps1`, `RollbackHermesAirgapped.bat` ve `README_KURULUM.txt` bulunur.
3. **Hermes'i kapat.** Masaüstü penceresini, `hermes` çalışan terminalleri ve pilotlardan açık kalan "Hermes Agent" pencerelerini kapat. `%LOCALAPPDATA%\hermes` altından çalışan bir süreç varsa installer durur.
4. **(İsteğe bağlı) Pilot.** Hiçbir şeyi değiştirmez:
   ```bat
   InstallOrUpdateHermesAirgapped.bat Pilot
   ```
   - Uygulamayı `%LOCALAPPDATA%\hpilot\P<MMddHHmmss>` klasörüne kurar ve tüm dosyaları doğrular.
   - Config'inin **kopyasını** oluşturup migrate eder.
   - `P…_StartDesktop.bat` dosyasıyla açılır.
   - Pilotu ve kurulu yeni sürümü aynı anda açma; aynı Electron veri klasörünü paylaşabilirler.
5. **Kur / güncelle:**
   ```bat
   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
   ```
   Sonunda `[OK] Hermes v0.22.4 Desktop installed.` görmelisin.
6. **Kullan:**
   - Masaüstündeki `StartHermesDesktop.bat` ya da Başlat menüsündeki "Hermes Agent" ile aç.
   - İlk açılış uzun sürebilir. Pencere bir kez kapanırsa tekrar aç; pilotta bir kez `0xE0000008` ile kapandığı görüldü, sonraki açılışlar sorunsuzdu.
   - **Yeni** bir terminalde `hermes --version` → `Hermes Agent v0.22.4 · stable`.
7. **Kısa kontrol:**
   - Modelle bir mesaj gönder.
   - Hermes'ten `dir` gibi bir terminal komutu çalıştırmasını iste.
   - MCP araçlarının listelendiğini gör.
   - İstersen `hermes dashboard`.

## C. Geri alma

```bat
RollbackHermesAirgapped.bat
```
Şunları geri koyar:
- Eski `hermes-agent` (v0.21.5) ve varsa önceki `app`
- Migrate öncesi `config.yaml` ve `.env`
- Kullanıcı PATH, `HERMES_HOME`, `HERMES_GIT_BASH_PATH`
- İki `StartHermesDesktop.bat`, `hermes.cmd` ve Başlat menüsü kaydı

Yeni uygulama `app_rolledback_<zaman>` adıyla kenarda kalır. İkinci bir rollback reddedilir.

## D. Temizlik (birkaç gün sorunsuz kullandıktan sonra)

- `%LOCALAPPDATA%\hpilot\` klasörünün tamamı (eski pilotlar ~9 GB tutabilir).
- `%LOCALAPPDATA%\hermes\hermes-agent_source_backup_*`, `app_backup_*`, `app_failed_*`, `app_rolledback_*`
- `%LOCALAPPDATA%\hermes_backup_before_airgap_*`
- `%APPDATA%\Hermes Agent` klasörüne **dokunma**; kurulu uygulamanın Electron verisi orada.

Yedekleri sildikten sonra rollback çalışmaz. Rollback eksik yedek görürse hiçbir şeye dokunmadan durur.

## E. Sonraki sürümler

Factory'yi tekrar çalıştırman yeterli. `latest` yeni sürümü kendiliğinden seçer. Intranette de aynı `Auto CleanVenv` komutunu kullan; installer bu sefer önceki `app` klasörünü yedekleyip yenisine geçer. Yeni sürümden önce bakılacaklar: [07-yeni-surum.md](07-yeni-surum.md)
