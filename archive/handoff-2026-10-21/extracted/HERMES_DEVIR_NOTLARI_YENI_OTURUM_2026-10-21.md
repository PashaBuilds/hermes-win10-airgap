# HERMES AIR-GAP — YENİ OTURUMA DEVİR DOSYASI

**Durum tarihi:** 21 Ekim 2026  
**Çalışma dili:** Türkçe  
**Kapsam:** Windows 10 x64, tamamen internetsiz/intranet şirket bilgisayarında Hermes Agent v0.22.2'nin kurulumu; önceki v0.21.5 kullanım biçimini koruma; yerel DeepSeek + CLI/Web/MCP; Windows 10 Desktop GUI ve paket küçültme.  
**Bu belge, uzun ChatGPT oturumunu yeni oturumda devam ettirmek amacıyla hazırlanmıştır.** Kodlar, önceki üretilmiş ZIP'ler ve checksum'lar ayrıca `HERMES_OTURUM_DEVIR_TAM_PAKET_2026-10-21.zip` içindedir.

> **EN ÖNEMLİ GÜNCEL DURUM:** Native ve resmî Desktop derlemeleri internetli Windows makinesinde başarılı oldu. Fakat resmî Desktop MSIX'i Windows 11 22H2+ gerektirdiğinden hedef **Windows 10'da kurulamıyor**. Windows 10 için MSIX'siz, eski `Auto CleanVenv` komutunu kabul eden **v4.6 transfer ZIP'i başarıyla üretildi**. Üretim bilgisayarındaki mevcut Hermes'i etkilememek için ayrı bir **Pilot v1** oluşturuldu; çalıştırılınca `Exception calling GetFullPath ... path is not of a legal form` hatası çıktı. Bunu düzeltmek amacıyla **Pilot v1.1** hazırlandı ve paylaşıldı; **henüz kullanıcıdan v1.1 sonucu alınmadı**. Yeni oturumun ilk görevi **v1.1 pilotunu çalıştırmak ve çıkan gerçek hatayı/başarıyı yorumlamak**. Üretimde mevcut kurulumun üzerine güncelleme henüz yapılmadı.

---

## 1. KULLANICININ DEĞİŞTİRİLEMEZ ŞARTLARI

1. **Hedef sistem kesinlikle Windows 10 x64 kalacak.** Windows 11'e yükseltme yapılmayacak. Ortam **internetsiz**; aktarım onaylı kurumsal yöntemle yapılacak.
2. **Tek ZIP, çıkar, tek BAT ile kur/güncelle** deneyimi korunacak. Kullanıcının önceden kullandığı ve aynen kabul edilmesini istediği komut:

   ```bat
   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
   ```

3. Eski davranış: `Auto` mevcut kurulum varsa güncelleme, yoksa kurulum; ayrıca `Install`, `Update`, `CleanVenv` seçenekleri. Ana konum **`%LOCALAPPDATA%\hermes`**, kurulu kaynak **`%LOCALAPPDATA%\hermes\hermes-agent`**. Eski kurulum/kullanıcı ayarları/sessions/skills/memories/cron/logs korunmalı; güvenilir yedek ve geri dönüş olmalı.
4. Kullanıcı için gerekenler: **yerel DeepSeek sunucusuyla çalışma, CLI, Web, MCP**; **Desktop GUI** mümkünse Windows 10'da çalışmalı. İnternete bağımlı veya faydası olmayan entegrasyonlar gereksiz; mevcut başarılı paket silinmeden, ayrı deneylerle inceltilmeli.
5. Önceki v0.21.5 civarı paket kullanıcıya göre **`HermesAirgapBundle_v2026.9.24_with_desktop.zip`**, yaklaşık **800 MB** idi. Yeni 4 GB'lık paketi kullanıcı gereksiz büyük buluyor. 800 MB rakamı kullanıcı beyanı, eski ZIP'in byte düzeyinde doğrulaması burada yok.
6. **Üretimdeki intranet Windows 10 makinesinde deneme yapmak istiyor**, fakat çalışan eski Hermes'in bozulmasını istemiyor. Bunun için güncel yaklaşım: **yan yana izole pilot** önce; gerçek `Auto CleanVenv` güncellemesi sonra, kullanıcı onayı ve bakım/rollback planıyla.
7. Mevcut önceki **`StartHermesDesktop.bat` kısayolu** eskiden `venv\Scripts\hermes.exe` çağırıyor; yeni payload'da `bin\hermes.exe` var. Kısayol uyumsuzluğu önemli ve çözülmedi. Kullanıcı görünür biçimde bu yöntemin kaybolmasını kabul etmiyor.

---

## 2. TEKNİK ORTAM VE SABİT SÜRÜM BİLGİLERİ

| Öğeler | Doğrulanmış durum |
|---|---|
| Hedef Hermes | `v0.22.2` (15.10.2026 resmî sürüm, v0.22.1 yanlış commit'ten yayımlanmış) |
| Git commit | `d923a5eb487a17c0a68801bba9ef0f56c81040a8` |
| Repo | `https://github.com/NousResearch/hermes-agent` |
| Etiket sayfası | `https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.2` |
| Factory ana dizini | `C:\HermesAirgapFactoryAuto_v4` (dizin adı eski kalsa da içeriği v4.6) |
| Factory çalışma dizini | `C:\H4` |
| Checkout | `C:\H4\jobs\v0.22.2_Slim\src` |
| Native stage | `C:\H4\jobs\v0.22.2_Slim\native` |
| Çıktılar | `C:\H4\output` |
| Loglar | `C:\H4\logs\factory_*.log` |
| Profil | `Slim` = temel + `web` + `mcp` (opsiyonel tüm entegrasyonlar değil) |
| Bootstrap Python | `3.11.9`, yalnızca factory başlatıcısı |
| Hermes PM runtime | `Python 3.14.7` |
| Factory Node | `24.22.0` (portable) |
| Desktop hazırlama Node | `26.7.0` (PM lock) |
| Electron | `40.10.2`; Electron içindeki Node `24.15.0` |
| Host PowerShell | `5.1.19041.7725` (kullanıcı Windows makinesindeki çıktı) |
| Eski gerçek kurulum | `%LOCALAPPDATA%\hermes\hermes-agent` |
| Yan yana pilot | `%LOCALAPPDATA%\HermesWin10Pilot\v0.22.2_*\runtime` |

**`hermes --version` tuhaflığı:** Başarılı native launcher testi sırasında `Hermes Agent vunknown (2026.9.24)` yazdı. Bu, pinli checkout v0.22.2 olsa bile sürüm etiketinin düzgün gömülmediğini gösteriyor. `--version` exit code 0 ile çalıştı; ancak doğru görünen sürüm etiketi veya tam offline çalışma **henüz kanıtlanmadı**.

**Not:** Tarih 21.10.2026; en son denenen hedef sürüm v0.22.2. Bundan sonra yeni bir sürüm çıkmış olabilir, fakat **mevcut işi çalışan v0.22.2 üzerinde bitirmeden otomatik sürüm değiştirme**.

---

## 3. ESKİ KURULUM YÖNTEMİ — KULLANICININ PAYLAŞTIĞI GERÇEK DAVRANIŞ

Kullanıcı eski v0.21.5 installer script'lerini konuşmada paylaştı. BAT'ın tamamı şöyleydi:

```bat
@echo off
setlocal
cd /d "%~dp0"

echo Hermes unified air-gapped installer/updater for Windows 10/11
echo.
echo This installs or updates Hermes from this extracted bundle.
echo.
echo Optional:
echo   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
echo   InstallOrUpdateHermesAirgapped.bat Update
echo   InstallOrUpdateHermesAirgapped.bat Install
echo.

set MODE=%~1
if "%MODE%"=="" set MODE=Auto

set CLEAN=
if /I "%~2"=="CleanVenv" set CLEAN=-CleanVenv

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0InstallOrUpdateHermesAirgapped.ps1" -Mode "%MODE%" %CLEAN%

if errorlevel 1 (
  echo.
  echo [ERROR] Install/update failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
```

Eski `.ps1` önemli mantığı (tam içerik bu oturumun kullanıcısı tarafından mesaj olarak verilmiştir; yeni factory'nin `templates/LegacyInstallOrUpdateHermesAirgapped.ps1` dosyası **aynı kaynak kod değildir**):

- Parametreler `-Mode Auto|Install|Update`, `-CleanVenv`, `-LaunchDesktop`.
- `%LOCALAPPDATA%\hermes`, kaynak `hermes-agent`, `wheelhouse`, `tools`.
- `config.yaml`, `.env`, `company-ca-bundle.pem` ve `sessions`, `skills`, `memories`, `cron`, `logs` için seçici yedek.
- Yerel **Python 3.11** kurucusu, `venv` oluşturma, `pip --no-index --find-links wheelhouse`, editable paket `.[web,mcp,cron,cli]`.
- Eski kaynak klasörünü `hermes-agent_source_backup_<timestamp>` olarak yeniden adlandırma; temiz venv seçeneğinde venv'i sıfırdan oluşturma.
- `python3.exe` alias, kullanıcı PATH, Git Bash ve Node PATH, `HERMES_HOME` kullanıcı ayarları.
- Desktop release dosyaları varsa `StartHermesDesktop.bat` oluşturma. Eski GUI komutu `"%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe" desktop --skip-build`.
- `config check`, `config migrate`, `doctor`, `--version` denemeleri.

**Kritik fark:** Hermes v0.22.2 Python **3.14 + resmî PM sealed runtime** kullanıyor. Eski Python 3.11 + wheelhouse/pip adımlarını birebir kopyalamak mümkün olmayabilir. v4.6 kullanıcıya aynı BAT parametre sözleşmesini sunar, fakat **içerideki uygulama eski yöntemle birebir aynı değildir**. `CleanVenv` yeni hazırlanmış runtime jenerasyonunu kullanır; önceki venv'i yeniden kullanmaz.

---

## 4. KRONOLOJİ — SÜRÜMLER, GÖRÜLEN HATALAR, ÇÖZÜMLER

| Factory / aşama | Kanıt, hata ya da karar | Çözüm / gerçek durum |
|---|---|---|
| Eski v0.21.5 ve erken factory denemeleri | Yaklaşık 800 MB, `Auto CleanVenv`, Python 3.11, wheelhouse, `hermes desktop --skip-build` | Eski çalışan kurulum korunmalı; yeni kod aynı yaklaşımı kendiliğinden sağlamıyor. |
| Auto v3 / v3.1 | Güncel Hermes PM Python 3.14'e taşınmıştı; eski pip download / eksik bağımlılık sorunları | Resmî PM lock'larını kullanan factory tasarımına geçildi. Kendi arşivleri `arsiv/factory_gecmisi` içindedir. |
| v4.0 -> v4.1 | PowerShell parse hatası `${pyVer}:`; başka Python ortamının `PYTHONPATH` sızıntısından `SRE module mismatch`; pyc tag `cpython-311`/`314`; temizleme `WinError 145`; Windows MAX_PATH; optional `pilk` wheel | v4.1 parser testleri, kaynak patch/restore, kısa `C:\H4`, Slim core + web+mcp, PM Python3.14, launcher izolasyonu. |
| v0.22.1 Web/Vite | `[plugin @rolldown/plugin-babel] ... Cannot find package 'babel-plugin-react-compiler' imported from ...\src\babel-virtual-resolve-base.js` | Kaynağın *orijinal checkout*'ında `node-deps.mjs --workspace ui-tui --workspace web --reuse` çağrısı; kullanıcı elle 563 paket kurdu ve `require.resolve('babel-plugin-react-compiler')` başarılı oldu; v4.2 otomatikleştirdi. |
| Resmî v0.22.2'ye geçiş | v0.22.1 yanlış commit ile yayımlanmış; v0.22.2 kaynak patch anchor'ları korunmuş | `-VersionRef v0.22.2` ile devam edildi. |
| Native stage | 7/7 payload hashing ve manifest, Python3.14.7, 3 launcher başarılı; ZIP oluşturuldu | **Native derleme başarılı.** |
| v4.2 -> v4.3 | ZIP üretildikten sonra `Get-FileHash -Path ''` raporlama hatası, PowerShell `robocopy` stdout fonksiyonun dönüşüne karışmıştı | v4.3 stdout suppression, scalar path doğrulaması, hash `-LiteralPath`; native payload tekrar derlenmedi. |
| İlk Desktop derlemesi | `Prepared Electron PTY admission failed ... electron.exe ETIMEDOUT` (15 sn) | Electron `40.10.2` tek başına çalıştı, manuel node-pty/ConPTY testi başarı verdi, sonra **resmî** `probe-prepared-native.mjs` exit 0 ve 4.4349 sn; bu engel aşıldı. |
| Sonraki Desktop hazırlığı | Python wheel `alibabacloud-gateway-dingtalk==1.0.2`, `dependency_links.txt` yok; `hermes-agent[dingtalk]` Desktop all-extras yüzünden geliyor | v4.4 harici Desktop worker, Desktop `agent-payload/venv` için yalnız `extras=('web','mcp')`; kaynak temiz Git kontrolü korunuyor. |
| v4.4 Desktop | Kullanıcı raporunda `desktop: passed`, resmî MSIX `HermesBundled-0.22.2-win-x64.msix` oluştu | **Resmî Desktop derlemesi başarılı** ama Windows 10 uyumlu değil. |
| v4.4 -> v4.5 | Desktop başarılıyken son transfer ZIP hâlâ `_native.zip` ve `desktopIncluded` yok; stdout dönüş problemi | v4.5 `-PackageOnly` ile hazır MSIX'i native payload yanında transfer ZIP'ine ekledi. |
| v4.5 MSIX kontrolü | `AppxSignature.p7x` bulunmadı. `AppxManifest.xml` içinde `MinVersion=10.0.22621.0`, `Windows.Desktop`, `x64`; publisher `CN=Nous Research Inc., O=Nous Research Inc., L=Austin, S=Texas, C=US` | Windows 10 22H2 build 19045 üzerinde **kurulamaz**. Yalnızca imzalamak yeterli değil. Bu, upstream `apps/desktop/BUILDING.md` ile uyumlu. |
| Kullanıcı şartları | Windows 10 kesin, eski BAT Auto CleanVenv korunmalı; 4 GB çok büyük | v4.6 `-Win10Compat -PackageOnly`, MSIX hariç, `%LOCALAPPDATA%\hermes`, legacy komut sözleşmesi, ayrı çıktı. |
| v4.6 gerçek çalıştırma | Parser 5/5 OK, pinned commit, no recompilation; `Win10 compatibility transfer ...`, native smoke passed, ZIP ready | **v4.6 Win10 transfer ZIP'i başarılı üretildi; intranet kurulum henüz yapılmadı.** |
| Üretimdeki ilk pilot v1 | `Exception calling GetFullPath with 1 arguments the path is not of a legal form` | İlk teşhis boş/geçersiz `$BundleRoot`; v1.1 BAT'tan explicit `-BundleRoot` ve PS1 script konumundan fallback sağlandı. |
| **ŞİMDİKİ EN SON** | `HermesWin10_UretimPilot_v1_1.zip` gönderildi; kullanıcıya klasör yapısı anlatıldı | **v1.1 gerçek Windows 10 test sonucu bekleniyor.** |

### Native başarı logundan önemli örnek

```text
payload verification complete
assembling verified payload
C:\H4\jobs\v0.22.2_Slim\native\bin\hermes.exe
C:\H4\jobs\v0.22.2_Slim\native\bin\hermes-agent.exe
C:\H4\jobs\v0.22.2_Slim\native\bin\hermes-acp.exe
✓ manifest (...\native\manifest.json)
[OK] Native payload passes launcher test
```

### v4.6 başarı raporundan temel alanlar

```json
{
  "release": "v0.22.2",
  "commit": "d923a5eb487a17c0a68801bba9ef0f56c81040a8",
  "native": "passed",
  "desktop": "excluded-win10",
  "profile": "Slim",
  "desktopIncluded": false,
  "win10LegacyBat": true,
  "outputZip": "C:\\H4\\output\\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip",
  "sha256": "EA3183E37E1344A6F25249A83F6FC78B17875D00252CF14C95D51AB8CA9D7D9E"
}
```

---

## 5. İNTERNETLİ FACTORY PC'DE GERÇEKTEN OLUŞAN BÜYÜK PAKETLER

**Bunlar bu devir ZIP'inin içinde DEĞİLDİR.** Bu dosyalar kullanıcının kendi `C:\H4\output` klasöründe üretilmiş, çoğu GB boyutundadır. Bu konuşma dosyalarından onların byte'larına erişemiyoruz. **Yeni oturumda varmış gibi davranma, yeniden üretildiğini iddia etme.**

| Dosya / örnek | En son kullanıcıdan gelen hash | Durum |
|---|---|---|
| `HermesAirgap_v0.22.2_Slim_native.zip` | `F7557AAC156A37BA91C07A5AADDCD15D508CB4A943613F2855EB9BC38819A538` (v4.4 çalışma sonu) | Başarılı native; sürüm bazlı ZIP her çalıştırmada yeniden üretildiği için hash değişebiliyor. |
| `HermesAirgap_v0.22.2_Slim_desktop.zip` | `B21D11FDFF127DA6CF635F22C679F17DC749E7A0DAF9028806E649D15A049F20` | SHA256 kullanıcı tarafından `[OK] ZIP dogrulandi` ile onaylandı; MSIX içeriyor, Windows 10'a uygun değil. |
| `HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip` | **`EA3183E37E1344A6F25249A83F6FC78B17875D00252CF14C95D51AB8CA9D7D9E`** | **Güncel pilot için esas dosya**. v4.6 sonucu; Windows 10 için MSIX içermez, legacy BAT barındırır. |
| Eski `HermesAirgapBundle_v2026.9.24_with_desktop.zip` | Bilinmiyor | Kullanıcı eski sürümünün ~800 MB olduğunu belirtti; burada arşiv mevcut değil. |

Eski ara native hash örnekleri: `3949476759F881D96B395ABB40BC72CA7EB20FC8C398F1C99100D1C7F4B60A49`, `C456D82768AEADA641E4ADEAFE6C6208F8413EEE1EE7C14A1A78A1073B85EBEE`, `A68D757BD8A73F81C4BD2A50D8855C1D102C70E9E632C42DF818F8D3B2E5AD00`. Bunlar **güncel hash yerine kullanılmamalı**.

Factory raporları/loglar kullanıcı PC'sinde:

- `C:\H4\jobs\v0.22.2_Slim\result.json`: resmî Desktop başarılı raporu.
- `C:\H4\jobs\v0.22.2_Slim\result-win10-compat.json`: Win10 legacy raporu; önceki result korunur.
- `C:\H4\logs\factory_20261019_105229.log`: v4.6 Win10 ZIP oluşturma.
- `C:\H4\logs\factory_20261019_093630.log`: v4.5 Desktop ZIP.
- `C:\H4\logs\factory_20261019_084415.log`: v4.4 Desktop başarı/önceki native ZIP.
- `C:\H4\vite-v0.22.1-error.log`: eski Babel hatasının ilk tanısı.

---

## 6. PAKETİN 4 GB OLMASININ GERÇEK NEDENİ

Kullanıcı `HermesAirgap_v0.22.2_Slim_desktop.zip` dosyasının *içindeki sıkıştırılmış* dosya boyutlarını .NET `System.IO.Compression.ZipArchive` ile ölçtü:

| ZIP içi bileşen | Sıkıştırılmış MB |
|---|---:|
| `desktop/MSIX` | **2304,9** |
| `payload/tools/llamacpp-cuda-11370-win32-x64` | **551,0** |
| `payload/tools/llamacpp-hip-11370-win32-x64` | **248,8** |
| `payload/tools/chromium-1208` | 172,7 |
| `payload/tools/ffmpeg-9.0.1-win32-x64` | 161,8 |
| `payload/tools/git-2.53.0+3-win32-x64` | 151,9 |
| `payload/venv` | 70,6 |
| `payload/uv-cache` | 54,2 |
| `payload/hermes-agent` | 52,7 |
| `payload/tools/python-3.14.7+20260901-win32-x64` | 47,2 |
| `payload/tools/node-26.7.0-win32-x64` | 40,6 |
| `payload/tools/llamacpp-vulkan-11370-win32-x64` | 32,5 |
| `payload/tools/cua-driver-0.21.0-win32-x64` | 25,1 |
| `payload/tools/llamacpp-cpu-11370-win32-x64` | 18,9 |
| `payload/tools/uv-0.12.3-win32-x64` | 18,7 |
| `payload/tools/gh-2.97.0-win32-x64` | 14,0 |
| `payload/tools/bws-2.0.0-win32-x64` | 5,5 |
| `payload/tools/agent-browser-0.26.0-win32-x64` | 4,5 |
| `payload/tools/npm-12.0.2-win32-x64` | 3,7 |
| `payload/tools/ripgrep-15.2.0-win32-x64` | 1,8 |

**Yorum:** Windows 10'da çalışmayacak Desktop MSIX **tek başına ~2,3 GB**. CUDA/HIP **~800 MB**. Bu nedenle yeni MSIX'siz ZIP'in yaklaşık **1,7 GB** olacağı düşünüldü; gerçek ZIP boyutu henüz kullanıcı tarafından gönderilmedi. Native payload içinden dosya **manuel silinmemeli**: PM manifest/hash/tool-facts zincirini bozabilir. Gelecek optimizasyonda önce gerçek hedef kullanım ve bağımlılık grafiği ölçülmeli; sonra seçimli tool paketleme/yeniden manifest üretimi yapılmalı. DeepSeek başka yerel sunucuda çalışıyorsa CUDA/HIP llama.cpp çalıştırıcıları gereksiz **olabilir**, henüz kanıtlanmadı. **800 MB hedef değil, araştırılacak eski referans boyutudur.**

---

## 7. RESMÎ DESKTOP MSIX NEDEN WINDOWS 10'DA KURULMAZ?

Kullanıcının PowerShell'de MSIX içindeki `AppxManifest.xml` okumasından:

```text
Name                  : NousResearch.HermesBundled
Publisher             : CN=Nous Research Inc., O=Nous Research Inc., L=Austin, S=Texas, C=US
Version               : 2026.6894.803.0
ProcessorArchitecture : x64
TargetDeviceFamily    : Windows.Desktop
MinVersion            : 10.0.22621.0
MaxVersionTested      : 10.0.26100.0
```

Windows 10 22H2 build `19045`, istenen `22621`'in altındadır. `tar -tf ... | Select-String '^AppxSignature\.p7x$'` boş döndü; MSIX **imzasız**. İmza eklemek bile OS sürüm şartını çözmez. Hermes upstream `apps/desktop/BUILDING.md` resmî minimumun Windows 11 22H2 olduğunu belirtir. Aynı kaynak Web/CLI script'leri için Windows 10 desteği ayrı olabilir. **Yalnızca manifest MinVersion değerini düşürerek uyumlu olduğunu varsayma.**

Önceki eski Desktop yönteminde `hermes desktop --skip-build` çağrılıyordu; o kullanım biçiminin **yeni 0.22.2'de Windows 10 GUI üretebildiği veya mevcut release dosyalarından başlatılabildiği kanıtlanmadı**. Desktop en önemli sonraki geliştirme başlıklarından biri.

---

## 8. GÜNCEL TRANSFER / ÇIKARMA / ÜRETİMDE YAN YANA PİLOT PROSEDÜRÜ

### 8.1 Taşınacak iki dosya (kullanıcı kendi PC'sinden)

1. **Büyük, kullanıcı PC'sinde üretilmiş ZIP:** `C:\H4\output\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip` (SHA256 `EA3183...D9E`).
2. **Küçük pilot düzeltme ZIP'i:** `HermesWin10_UretimPilot_v1_1.zip`, bu devir paketinde `guncel/` altındadır. Pilot v1 yerine **v1.1** kullanılmalı.

Büyük Hermes ZIP'i bu devir arşivinde yoktur; intranete aktarılırken doğrulanmış mevcut kopyası kullanılmalıdır.

### 8.2 Windows Gezgini ile çıkarma: klasör yapısı

`C:\H4Transfer` klasörünü oluştur. Her iki ZIP'i buraya kopyalayabilirsin. Büyük ZIP'in **içindeki ana klasörü** çıkar; aynı adlı çift iç içe dizin oluşmamalı. Sonra küçük pilot v1.1 ZIP içindeki **3 dosyayı** bu büyük paketin `payload` ile **aynı seviyedeki köküne** kopyala/eskilerin üzerine yaz:

```text
C:\H4Transfer\
  HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip       [büyük ZIP, isteğe bağlı burada tutulur]
  HermesWin10_UretimPilot_v1_1.zip                         [küçük ZIP, isteğe bağlı burada tutulur]
  HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\
    BUNDLE.json
    VerifyOfflineBundle.ps1
    InstallOrUpdateHermesAirgapped.bat
    InstallOrUpdateHermesAirgapped.ps1
    payload\
       bin\hermes.exe
       manifest.json
       pm-runtime\
       venv\
       tools\
       hermes-agent\
       uv-cache\
    TestHermesWin10Pilot.bat           <-- pilot v1.1 ZIP
    TestHermesWin10Pilot.ps1           <-- pilot v1.1 ZIP
    README_PRODUCTION_PILOT.txt        <-- pilot v1.1 ZIP
```

**Hatalı klasör yapısı:** `...\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\payload` (çift kök). Pilot BAT da `.ps1` de `BUNDLE.json`, `payload`, `VerifyOfflineBundle.ps1` ile **aynı düzeyde** olmalıdır.

### 8.3 Çalıştırılacak DOSYA

Sadece **`TestHermesWin10Pilot.bat`** dosyasına çift tıkla. Gerçek güncellemeyi yapan `InstallOrUpdateHermesAirgapped.bat Auto CleanVenv` komutunu **henüz üretimde çalıştırma**. Pilot mevcut kurulumun üzerine yazmıyor.

Beklenen başlama satırı:

```text
[PILOT] Bundle folder: C:\H4Transfer\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv
```

Başarılı olursa:

```text
[PILOT_OK] Isolated Hermes CLI started without changing the current installation.
```

Pilot; paket meta/bütünlük kontrolü, yeni `%LOCALAPPDATA%\HermesWin10Pilot\v0.22.2_*\runtime` klasörüne runtime kopyalama, yalıtılmış `HERMES_HOME`, `hermes --version`, `hermes --help` testleri yapar. Güncel `Pilot v1.1` BAT, bulunduğu dizini `-BundleRoot` ile açıkça gönderir; PS1 ise gerekirse kendi konumundan çıkarır.

Pilot log: `%LOCALAPPDATA%\HermesWin10Pilot\v0.22.2_*\pilot.log` ve aynı pilot klasöründe `version.txt`, `help.txt`. Hata varsa **son 20–40 satırı ve `[PILOT_ERROR]` mesajını** yeni oturuma getir; *şirket içi URL, token, .env vb. gizli bilgileri temizle*.

**Pilot olumlu olsa bile:** Yalnızca CLI startup doğrulanmış olur. Windows 10 Desktop GUI, model bağlantısı, MCP, gerçek tam çalışma ve üretim güncellemesi **henüz doğrulanmaz**.

### 8.4 Kullanıcı açısından eski KOMUTU koruyan gerçek güncelleme (ŞİMDİLİK ÇALIŞTIRMA)

```bat
InstallOrUpdateHermesAirgapped.bat Auto CleanVenv
```

v4.6 bu sözleşmeyi ve `%LOCALAPPDATA%\hermes` konumunu destekler; eski `hermes-agent` klasörünü zaman damgalı yedeğe alır, kullanıcı config/sessions vb. verilerine dokunmamaya çalışır, yeni `bin\hermes.exe` PATH'i yazar. Ancak **eski Desktop kısayolu bozulabilir**; eski `venv\Scripts\hermes.exe` yolunu yeni runtime taşımaz. Gerçek güncellemeden önce bakım penceresi, servislerin kapatılması, kapsamlı doğrulanabilir yedek ve açık rollback adımları gerekir. Pilot başarıya ulaşmadan gerçek kurulum önermeyin.

---

## 9. FACTORY'DE YENİDEN ÜRETME KOMUTLARI (SADECE GEREKİRSE)

**Mevcut v4.6, `C:\HermesAirgapFactoryAuto_v4` klasöründe.** ZIP içindeki üst klasör adı da aynı. Factory ZIP'lerini kendi başlarına intranette çalıştırmayın; üretim kaynaklarının hazırlanması internetli build PC'de yapılır.

```powershell
cd C:\HermesAirgapFactoryAuto_v4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ValidateFactoryScripts.ps1

# Başarılı native stage'i yeniden derlemeden Win10 ZIP oluşturma
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\BuildHermesAirgapBundle.ps1 `
  -VersionRef v0.22.2 -PackageOnly -Win10Compat
```

Çıktı `C:\H4\output\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv.zip` olur. `-Fresh` **kullanma**; derlenmiş native stage korunmalı. Factory canlı çalıştırma geçmişi: kullanıcı v4.6 PowerShell parser testinde `[PARSE OK]` beş script, paketlemede `[OK] Package ready` ve `desktop: "excluded-win10"`, `win10LegacyBat: true` aldı.

İleride gerekirse:

```powershell
# Sadece native build (sıfırdan değilse mevcutları yeniden kullanır)
.\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2 -NoDesktop

# Desktop hazırlama denemesi; resmî MSIX Win10'a uygun değil
.\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2 -DesktopOnly

# Var olan Desktop MSIX + native paket için aktarma ZIP'i (Windows 11 hedefli)
.\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2 -PackageOnly
```

### Eski Babel özel düzeltmesi (artık v4.2+ içinde otomatik)

```powershell
$Repo = 'C:\H4\jobs\v0.22.1_Slim\src'
$Node = 'C:\H4\tools\node-v24.22.0-win-x64\node.exe'
$env:Path = "$(Split-Path $Node -Parent);$env:Path"
Push-Location $Repo
try {
  & $Node scripts/build/node-deps.mjs --source $Repo --workspace ui-tui --workspace web --reuse
  & $Node -p "require.resolve('babel-plugin-react-compiler')"
} finally { Pop-Location }
```

Bunlar yalnızca geçmiş sorun giderme referansıdır; **v1.1 üretim pilotu için gerekli değildir.**

---

## 10. RESMÎ KAYNAK KODU AÇIKLAMASI / SINIRLAR

- Repo: `https://github.com/NousResearch/hermes-agent`.
- v0.22.2 tag: `https://github.com/NousResearch/hermes-agent/releases/tag/v0.22.2`.
- `apps/desktop/BUILDING.md`: resmî Desktop sideload MSIX, Windows 11 22H2+ alt sınırı; Desktop bundled vs light; native kaynak scriptleri ayrı.
- `apps/desktop/scripts/probe-prepared-native.mjs`: Electron 40.10.2, node-pty/ConPTY; child test 10 sn, parent child spawnSync 15 sn; 4,43 sn manuel resmî test başarılı.
- `scripts/bundles/native.py`: orijinal `all_extras=True`; v4.4 yalnız Desktop bundled Slim Python ortamı için, kaynak değişmeden, scoped worker ile `web+mcp` kullanır.
- `scripts/build/node-deps.mjs`: npm lock ile `ci` ve workspace hazırlığı; Babel original-checkout çözümü.
- `apps/desktop/electron-builder.config.cjs`, `scripts/msix-shared.mjs`, `apps/desktop/scripts/before-build.mjs`: resmî MSIX packaging config/identity/Win 11 manifest.

**Güvenlik/uyumluluk notları:**

- Factory/Pilot script'leri yerel statik kontrol ile incelendi ve kullanıcı tarafında Windows'da yalnız belirtilen aşamalar koştu. **Üretimde v1.1 veya Auto CleanVenv uçtan uca çalıştırıldığı kanıtlanmadı.**
- PowerShell parse OK yalnız sözdizimini garanti eder; MSI/MSIX, runtime ve offline fonksiyon testinin yerini tutmaz.
- `VerifyOfflineBundle.ps1` yalnız belli kritik dosya hash'lerini karşılaştırır; **tüm dosyaları tek tek doğruladığını varsayma**.
- ZIP SHA256 dosyası transferin beklenmedik bozulmasını ortaya çıkarır; **imza veya menşe doğrulamasının yerine geçmez**. Hash güvenilir bir kanaldan karşılaştırılmalı.
- `HERMES_HOME` gerçekten `%LOCALAPPDATA%\hermes` ile eşleşiyor mu ve mevcut kullanıcı profili nerede, gerçek yüklemede kontrol edilmeli.
- Scriptlerin `PYTHONPATH`, kurumsal sertifikalar, kullanıcı PATH'i vb. ile etkileşimi üretimde dikkatle test edilmeli. İçe aktarılacak kurumsal model endpointini kullanıcıdan öğrenmeden varsayma.
- Windows 10'da eski Desktop GUI açıkken gerçek güncelleme yapılmamalı; servis/süreç yönetimi ve uygulama rollback planı lazım.
- Gereksiz CUDA/HIP/Chromium/FFmpeg vb. dosyaları **manifest bütünlük zincirini güncellemeden elle çıkarma**.
- Kurumsal sertifikaları, gerçek kimlik bilgilerini, `.env`, model API tokenlarını ZIP'e veya paylaşılan loglara koyma.

---

## 11. YENİ OTURUMDA YAPILACAK İŞLER — ÖNCELİK SIRASI

1. **Kullanıcıdan Pilot v1.1 sonucunu al.** Beklenen `PILOT_OK`; hata çıkarsa son log, gerçek `TestHermesWin10Pilot.ps1` satırı, dosya konumu. Kullanıcı GUI ile çıkarıp BAT'a çift tıklamak istiyor; mümkünse yine tek BAT çözümü ver.
2. Pilot `PILOT_OK` ise bunun yalnız CLI startup olduğunu açıkla. Pilot profil içinde, çalışan Hermes'i etkilemeden `hermes --help`, `hermes model`, yerel DeepSeek endpointi / küçük test promptu / MCP smoke testleri için ayrı kontrollü adımlar tasarla. Özel URL/anahtarları isteme, paylaşılacak logları sansürle.
3. **Windows 10 GUI** için dürüst mühendislik değerlendirmesi yap: v0.22.2 resmi MSIX Win 11 only. Eskiden kullanıcı `hermes desktop --skip-build` ile GUI açtığını söyledi; bunun mevcut kaynak/build'de Windows 10 x64 üzerinde offline çalışması gerçekten test edilmeli. Kaynak bazlı/taşınabilir Electron yürütme alternatifi mümkündür ama **henüz kanıtlanmadı**.
4. **Eski kurulum sözleşmesi** (`Auto CleanVenv`, `%LOCALAPPDATA%\hermes`, config ve desktop kısayolları) korunmalı. Üretimde gerçek güncelleme ancak test + yedek/geri dönüş + duruş onayı sonrasında.
5. **Paket küçültme**: Önce fiilen gereken araçlar; özellikle CUDA/HIP 800 MB ve Windows 10'da işe yaramayan MSIX 2,3 GB; daha sonra PM-managed seçmeli toolchain ile manifest/facts/launchers yeniden üretme. Boyutu küçültmek için güvenlik/bütünlük devre dışı bırakılmamalı.
6. İş bittiğinde, kullanıcı dostu **tek ZIP / tek BAT** Windows 10 intranet kurulum seti oluştur, gerçek kullanıcı bilgisayarındaki test sonuçlarıyla belgeyi güncelle.

### Yeni oturum için kopyala-yapıştır başlangıç mesajı

> Ekteki `HERMES_DEVIR_NOTLARI_YENI_OTURUM_2026-10-21.md` belgesini ve `HERMES_OTURUM_DEVIR_TAM_PAKET_2026-10-21.zip` arşivini incele. Hermes Agent v0.22.2 Windows 10 air-gap projesine kaldığımız yerden devam edeceğiz. Kesin şartlar: Windows 10 x64, internetsiz, eski `InstallOrUpdateHermesAirgapped.bat Auto CleanVenv` davranışı, `%LOCALAPPDATA%\hermes`, mevcut çalışan Hermes'i koruma, yerel DeepSeek + CLI/Web/MCP ve mümkünse Win10 Desktop GUI. Son durum: v4.6 Win10 ZIP build başarılı, üretimde Pilot v1 `GetFullPath` hatası; v1.1 düzeltme ZIP'i hazır, sonucu bekleniyor. Mevcut üretim Hermes'i izinsiz güncelleme; önce v1.1 pilot sonucunu değerlendir. Büyük 1,7 GB transfer ZIP'i yalnız benim `C:\H4\output` klasörümde; eklere dahil değil. Doğrudan en son adımdan ilerle.

---

## 12. BU DEVİR ARŞİVİNİN İÇERİĞİ

- `HERMES_DEVIR_NOTLARI_YENI_OTURUM_2026-10-21.md`: bu belge.
- `guncel/HermesAirgapFactoryAuto_v4_6.zip`: çalışan Win10 `-PackageOnly -Win10Compat` factory kaynak kodları.
- `guncel/HermesWin10_UretimPilot_v1_1.zip`: **en son pilot düzeltmesi**.
- `arsiv/factory_gecmisi/`: daha önce bu konuşma ve öncesinde verilen v3 → v4.5 ZIP'leri, tarihsel hata ayıklama için.
- `arsiv/diger_onceki_araclar/`: daha eski factory/runner/Desktop/media yardımcı ZIP'leri; **güncel talimat yerine kullanılmamalı**.
- `kaynaklar/`: doğrulanmış kaynak runbook'lar, eski tekil PS1 düzeltmeleri, QA notları, ayrı pilot README.
- `SHA256_MANIFEST.txt`: devir arşivine konmuş dosyaların gerçek SHA256 kontrolleri.
- `START_HERE.txt`: yeni oturumda kullanım talimatı.

**Arşive DAHİL OLMAYANLAR:** 800 MB eski v0.21.5 Hermes ZIP, yeni ~4 GB Desktop Hermes ZIP, yeni ~1,7 GB Win10 Hermes transfer ZIP, şirket içi veri/model ağırlıkları, credentiallar ve kullanıcının `C:\H4\...` çalışma dosyaları. Bunlar kullanıcı makinesindedir; model bu dosyalara erişemez.

---

*Belge güvenilir olarak bu konuşmadaki kullanıcı loglarına, kullanıcı tarafından paylaşılan eski installer metnine ve oluşturulmuş yerel ZIP'lerin kaynak kodlarına dayanır. Çalıştırılmamış adımlar ayrı işaretlenmiştir. Bu belge bir kurulum sertifikası değildir.*
