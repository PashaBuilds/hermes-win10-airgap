# Hermes Kurulum Asistanı (`HermesKurulumAsistani.exe`)

İnternetsiz Windows 10/11 PC'de Hermes airgap paketini **pencereli bir sihirbazla** kurmak ya da güncellemek için küçük bir Windows uygulaması. Komut satırı bilmeyen bir kullanıcı da her adımı ekrandan takip edebilir.

Asistan kendi başına bir şey kurmaz. **Paketin kendi kurulum betiğini** (`InstallOrUpdateHermesAirgapped.ps1 -Mode Auto -CleanVenv`) çalıştırır. Yedek alma, dosyaların SHA256 doğrulaması, hata olursa otomatik geri yükleme ve rollback yine o betiğin işidir. Asistan bunların önüne paket kontrolünü ve ZIP'i açma işini, arkasına da şirket sertifikası ve model bağlantısı adımlarını ekler.

## Neler yapar?

| Adım | Ne olur |
|---|---|
| **1. Paket** | `HermesAirgapBundle_<sürüm>_Win10_Desktop.zip` (veya açılmış klasörü) seçilir. `BUNDLE.json` okunur, kurulu sürüm ile paket sürümü yan yana gösterilir (ör. `v0.23.0 → v0.23.4`). ZIP'in yanında `.sha256` varsa karşılaştırılır. Açılacak klasör (varsayılan `C:\Tools\HermesAirgapBundle`) için 260 karakter yol sınırı ve boş disk alanı kontrol edilir. |
| **2. Sertifika** | Şirketin iç sitesinden indirilen kök sertifika dosyası seçilir. Adı ne olursa olsun olur: `.crt`, `.cer`, `.pem`, DER ya da PEM, tek ya da birden fazla sertifika. Asistan geçerlilik tarihlerini, konu ve veren bilgisini, SHA-256 parmak izini gösterir. Özel anahtar içeren dosyaları (`.pfx` ya da `PRIVATE KEY`) ve süresi dolmuş sertifikaları reddeder. |
| **3. Kurulum** | Sırasıyla SHA256, ZIP'i açma, kurulum betiği, sertifika ve `hermes --version` adımları çalışır. Her adımın durumu ve süresi, genel ilerleme çubuğu ve canlı ayrıntılı kayıt ekranda görünür. Betiğin adımları (yedek, kopyalama, 50 bin dosyanın doğrulanması, geçiş, kısayollar, `config migrate`) Türkçe adlarıyla gösterilir. |
| **4. Model** (isteğe bağlı) | `hermes model` → *Custom endpoint* akışının aynısıdır: base URL, API anahtarı, API modu (*Otomatik algıla*), **Modelleri getir** (`/v1/models`), model seçimi, bağlam uzunluğu (boş bırakılırsa otomatik) ve görünen ad. Model zaten ayarlıysa mevcut ayar gösterilir ve varsayılan olarak değiştirilmez. |
| **5. Özet** | `hermes --version` çıktısı, kurulu sürüm, model ve sertifika durumu gösterilir. Buradan **hermes dashboard**, **hermes chat** ya da **masaüstü uygulaması** açılabilir. Gerekirse **Son güncellemeyi geri al** düğmesi kullanılır. |

Kayıt dosyası: `%LOCALAPPDATA%\HermesKurulumAsistani\logs\kurulum_<tarih>.log`. API anahtarı ne ekrana ne de bu dosyaya yazılır; anahtarın kendisi ve Hermes'in ekrana bastığı ilk 8 karakteri `****` ile maskelenir.

**Komut satırından ön seçim (isteğe bağlı):** `HermesKurulumAsistani.exe --paket <zip|klasör> --sertifika <.crt> --klasor <açılacak yer>`. Örneğin BT ekibi hazır bir kısayol dağıtabilir. Exe ile aynı klasörde (ya da İndirilenler'de) bir `HermesAirgapBundle_*_Win10_Desktop.zip` varsa zaten kendiliğinden seçilir.

**Atla kutusuna dikkat:** "Kurulum / güncellemeyi atla" işaretliyken Hermes güncellenmez. Paket daha yeniyse asistan önce onay sorar. Özet sayfasında turuncu "Güncelleme atlandı" yazısı ve **Geri dön ve güncellemeyi yap** düğmesi görünür. Kurulum adımı 0 ile bitip sürüm değişmediyse bu durum hata olarak gösterilir.

**Yalnızca sertifika ya da model:** 1. adımdaki *Kurulum / güncellemeyi atla* kutusu işaretlenirse paket seçmeye gerek kalmaz. Sertifikayı yenilemek veya modeli değiştirmek için asistan tek başına da çalıştırılabilir.

## Sertifika nasıl kuruluyor?

Hermes 0.23.x TLS doğrulamasında iki kaynağa bakar (`agent/ssl_verify.py`). Birincisi Windows sertifika deposudur (`truststore`). İkincisi ise `SSL_CERT_FILE` ile verilen PEM paketidir; bu paket deponun **üstüne** eklenir. Masaüstü uygulaması ve tarayıcı aracı Node/Electron tabanlıdır ve `NODE_EXTRA_CA_CERTS` değişkenine bakar. Asistan bu yüzden, eski `install_hermes_company_cert.py` ile aynı şekilde, şunları yapar. **Yönetici yetkisi gerekmez.**

1. `%LOCALAPPDATA%\hermes\company-ca.pem`: yalnızca şirket sertifikaları.
2. `%LOCALAPPDATA%\hermes\company-ca-bundle.pem`: Hermes runtime'ının `certifi` paketi ile şirket sertifikalarının birleşimi. Her çalıştırmada yeniden üretilir; eski dosyanın yedeği alınır.
3. **Kullanıcı** ortam değişkenleri: `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE` ve `CURL_CA_BUNDLE` bu pakete, `NODE_EXTRA_CA_CERTS` ise `company-ca.pem` dosyasına yönlendirilir. Açık pencerelere `WM_SETTINGCHANGE` gönderilir.
4. İsteğe bağlı olarak (varsayılan: açık) sertifika **CurrentUser** deposuna da eklenir: kök sertifika *Güvenilen Kök* deposuna, ara sertifika *Ara CA* deposuna. Windows bir onay penceresi açar; **Evet** denmelidir. Bu adım başarısız olursa yalnızca uyarı verilir, çünkü 1–3 tek başına yeterlidir.

### Sertifika bir kez kurulur

Asistan her açılışta sertifikanın daha önce kurulup kurulmadığını kontrol eder. Bu kontrol hiçbir şeyi değiştirmez ve bir onay penceresi açmaz. Kontrol edilenler:

- `company-ca.pem` dosyası okunuyor ve en az bir geçerli sertifika içeriyor mu?
- `company-ca-bundle.pem` dosyası bu sertifikaları içeriyor mu?
- Dört kullanıcı değişkeni doğru dosyaları gösteriyor mu?
- Sertifika Windows kullanıcı deposunda var mı? Bu yalnızca bilgi içindir.

Eski `install_hermes_company_cert.py` betiğiyle yapılmış kurulumlar da tanınır. Bu betik certifi listesinin sonuna şirket sertifikasını ekliyordu; asistan, değişkenlerin gösterdiği paketin sonundaki certifi'de olmayan sertifikaları şirket sertifikası olarak kabul eder.

- **Zaten kurulu:** Sertifika sayfasında yeşil "✓ Sertifika zaten kurulu" yazısı, sertifikanın adı ve son geçerlilik tarihi görünür. "Atla" önceden seçilidir ve dosya seçmek gerekmez. Adım "Zaten kurulu" olarak geçilir ve Windows onay penceresi açılmaz. Sertifikayı değiştirmek için **Yeni sertifika seç / yeniden kur** düğmesi kullanılır. Aynı sertifika yeniden seçilirse yine "zaten kurulu" sayılır.
- **Eksik var:** Bir değişken silinmiş, paket dosyası kaybolmuş ya da kurulum eski betikle yapılmış olabilir. Bu durumda eksikler listelenir ve mevcut sertifikadan **sessizce tamamlanır**. `.crt` dosyası tekrar istenmez, onay penceresi açılmaz.
- **Süre:** 30 gün içinde dolacak sertifika için uyarı gösterilir. Süresi dolmuşsa yeni dosya seçmek zorunludur.
- **Hermes güncellemesinden sonra:** Yeni sürümün `certifi` listesi değiştiyse `company-ca-bundle.pem` mevcut `company-ca.pem` dosyasından sessizce yeniden üretilir. Bunun nedeni şu: `REQUESTS_CA_BUNDLE` ayarlıyken `requests` yalnızca bu pakete güvenir. Paket eski kalırsa yeni sürümün genel kök sertifika güncellemeleri devre dışı kalır. İşlem dosya, onay ya da yönetici yetkisi gerektirmez ve önceki paketin yedeği alınır.
- **Windows deposu:** Sertifika depoda yoksa "Windows deposuna da ekle" kutusu boş gelir. Kullanıcı işaretlemedikçe onay penceresi açılmaz.

Dosyalar `HERMES_HOME` altında durduğu için güncellemelerde silinmez. Yeni bir sürümden sonra asistanı tekrar çalıştırmak, yeni runtime'ın `certifi` dosyasıyla paketi tazeler. Bu adım tekrar tekrar çalıştırılabilir.

## Güncelleme sırasında neler korunur?

Kurulum betiği `HERMES_HOME` klasörünü (`%LOCALAPPDATA%\hermes`) **yerinde bırakır**. Bu klasördeki `config.yaml`, `.env`, `sessions`, `skills`, `memories`, `cron` ve `company-ca-bundle.pem` dosyalarının önce `%LOCALAPPDATA%\hermes_backup_before_airgap_<tarih>` altına yedeğini alır. Eski uygulama klasörünü `app_backup_<tarih>` adıyla saklar ve en sonda `hermes config migrate` çalıştırır. Kurulum yarıda kalırsa önceki kurulum otomatik olarak geri yüklenir. Asistandaki **Son güncellemeyi geri al** düğmesi `RollbackHermesAirgapped.bat` ile aynı işi yapar.

## Model ayarı nasıl kaydediliyor?

Asistan küçük bir Python yardımcısını (`src/Resources/hermes_model_setup.py`) **kurulu Hermes'in kendi Python'u ile** çalıştırır. Yardımcı, Hermes'in `_model_flow_custom` fonksiyonunu çağırır ve sorulara asistanda girilen cevapları verir. Böylece sonuç `hermes model` komutunun yazacağıyla birebir aynı olur:

- Anahtar `%LOCALAPPDATA%\hermes\.env` dosyasına `HERMES_CUSTOM_<host>_..._API_KEY` olarak yazılır.
- `config.yaml` dosyasında `model.api_key: ${HERMES_CUSTOM_..._API_KEY}` referansı, `model.provider: custom`, `base_url` ve `custom_providers` girdisi yer alır.

Anahtar yardımcıya komut satırından değil, stdin üzerinden verilir.

Model listesi alınamazsa asistan nedenini Türkçe açıklar: yanlış anahtar (401/403), sertifikaya güvenilmiyor (sertifika adımı), zaman aşımı, adres yanlış (`/v1` eksik) ve benzeri.

## Gereksinimler

- Windows 10 1903+ (LTSC 2021 / 19044 dahil) ya da Windows 11. Bu sürümlerde .NET Framework 4.8 hazır gelir; ayrıca bir şey kurmak gerekmez.
- Windows PowerShell 5.1 (Windows ile gelir). Betik `-ExecutionPolicy Bypass` ile, yalnızca o işlem için çalıştırılır.
- Yönetici yetkisi **gerekmez** (`asInvoker`).
- Exe imzasızdır. Windows SmartScreen *"Windows bilgisayarınızı korudu"* derse **Ek bilgi → Yine de çalıştır** seçilir. Ya da dosyaya sağ tıklayıp **Özellikler → Engellemeyi kaldır** işaretlenir.

## Derleme

```bash
# Linux/macOS (.NET 8 SDK): installer-app/dist/HermesKurulumAsistani.exe + .sha256
installer-app/build.sh            # --test: birim testleri de çalıştırır
```
```powershell
# Windows (.NET 8 SDK)
installer-app\build.ps1 -Test
```

Uygulama C#/WPF ile yazıldı ve hedefi .NET Framework 4.8. Çıktı tek bir exe (~230 KB). `.github/workflows/installer-app.yml` her PR'da exe'yi gerçek bir Windows runner'da derler, testleri çalıştırır, exe'yi bir kez açıp ekran görüntüsü alır ve sonucu artifact olarak yükler. Elle çalıştırılıp `release_tag` verilirse exe'yi o release'e ekler.

## Testler

- `tests/CoreTests` (.NET 8 konsol uygulaması): JSON, sürüm karşılaştırma, maskeleme, betik çıktısının çözümlenmesi, sertifika okuma/reddetme, CA paketi ve ortam değişkenleri, ZIP açma (zip-slip ve uzun yol kontrolü dahil). İsteğe bağlı argümanlarla şunlar da test edilir:
  - `--bundle-zip <gerçek paket>`: gerçek bir paketin okunması.
  - `--sim-zip <sim paketi> --pwsh pwsh`: `tests/sim` paketi üzerinde uçtan uca kurulum ve rollback.
  - `--hermes-src <kaynak> --hermes-python <python>`: gerçek Hermes koduna karşı model ayarı.
- `tests/e2e/Invoke-UpgradeE2E.ps1` (CI'daki `e2e-upgrade` işi, gerçek Windows'ta, Windows PowerShell 5.1 ile çalışır):
  1. Eski paket (varsayılan v0.23.0) kendi betiğiyle kurulur.
  2. Asistan UI Automation ile bir kullanıcı gibi tıklanarak yeni pakete (v0.23.4) güncellenir.
  3. Garip adlı bir test `.crt` dosyası kurulur ve Windows'un onay penceresinde "Evet"e basılır.
  4. O sertifikayla imzalanmış HTTPS sahte model sunucusundan modeller getirilir ve kaydedilir.
  5. Sonuç doğrulanır: `hermes --version`, korunan oturum/hafıza/.env kayıtları, `config.yaml` içindeki anahtar referansı, ortam değişkenleri, sertifika deposu ve kayıt dosyasında anahtar bulunmaması kontrol edilir. Ekran görüntüleri artifact olarak yüklenir.
- `tests/python/test_model_helper.sh`: Model yardımcısı, sahte bir OpenAI uyumlu sunucuya karşı ve gerçek Hermes kaynağıyla test edilir (v0.23.0 ve v0.23.4). Kontrol edilenler: model listesi, yanlış anahtar teşhisi, kaydetme, yeniden kaydetme, tek model yolu ve anahtarın hiçbir çıktıda görünmemesi.
