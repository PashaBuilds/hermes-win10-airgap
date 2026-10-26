HERMES v0.22.2 - WINDOWS 10 ÜRETİM PİLOTU v1.2
===============================================

NE DÜZELDİ (v1.1 -> v1.2)
- v1.1 BAT'ı klasörü -BundleRoot "%~dp0" ile gönderiyordu. %~dp0 "\" ile biter;
  powershell.exe için \" kaçışlı tırnaktır. Script'e  C:\...\Bundle"  (sonunda
  tırnak) gidiyordu ve GetFullPath "Illegal characters in path" hatası verecekti.
  v1.2'de klasör bir ortam değişkeniyle aktarılıyor; script 5 kaynağı sırayla
  deniyor ve yalnızca içinde BUNDLE.json bulunan klasörü kabul ediyor.
- PowerShell 5.1'de "2>&1" + ErrorActionPreference=Stop, hermes.exe stderr'e
  tek satır uyarı yazsa bile testi düşürüyordu. Artık stdout/stderr ayrı yakalanıyor.
- Alt sürece PYTHONUTF8=1 / PYTHONIOENCODING=utf-8 veriliyor (Türkçe kod sayfası).
- Pilot runtime yolu (%LOCALAPPDATA%\hpilot\MMddHHmmss) üretim yolundan
  (%LOCALAPPDATA%\hermes\hermes-agent) uzun değil; MAX_PATH açısından temsilî.
- Yeni: ZIP SHA256 + tam çıkarma kontrolü, en uzun yol raporu, disk alanı kontrolü,
  hermes doctor (bilgi amaçlı), mevcut kurulumun değişmediğine dair parmak izi.

KURULUM (büyük paketi yeniden üretmeye gerek yok)
1) Bu ZIP'teki 3 dosyayı, çıkarılmış
   C:\H4Transfer\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\
   klasörüne (BUNDLE.json ve payload\ ile AYNI seviyeye) kopyala, eskilerin üzerine yaz.
2) Büyük ZIP'i C:\H4Transfer\ içinde bırakırsan (klasörle aynı adı taşıyan .zip),
   pilot SHA256'yı ve çıkarılan TÜM dosyaları ZIP'e karşı kontrol eder. Önerilir.
3) TestHermesWin10Pilot.bat dosyasına çift tıkla.
   InstallOrUpdateHermesAirgapped.bat Auto CleanVenv'i HENÜZ çalıştırma.

BEKLENEN
[PILOT] Bundle folder: C:\H4Transfer\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv   (source: ...)
...
[PILOT_OK] Isolated Hermes v0.22.2 CLI started from a relocated copy; current installation untouched.

"Hermes Agent vunknown (2026.9.24)" çıktısı BEKLENEN bir durum: payload'da
install-stamp.json yok, 2026.9.24 ise v0.22.2 kaynağındaki release-date sabiti.

SONUÇ GÖNDERİMİ
Ekranın sonunda summary.txt basılır. Dosya:
%LOCALAPPDATA%\hpilot\<MMddHHmmss>_diag\summary.txt
Hata varsa ayrıca aynı klasördeki version.txt / help.txt / robocopy.log.
Paylaşmadan önce şirket içi URL/token vb. temizle.

PİLOTUN DOKUNDUKLARI
Yalnızca %LOCALAPPDATA%\hpilot\ altına yazar. %LOCALAPPDATA%\hermes, kullanıcı
PATH'i, HERMES_HOME kullanıcı değişkeni, registry ve masaüstü kısayolu değişmez.
Silmek için: %LOCALAPPDATA%\hpilot klasörünü komple sil.

SINIRLAR
- Bu bir CLI başlangıç testidir. Desktop GUI, DeepSeek bağlantısı, MCP ve gerçek
  Auto CleanVenv güncellemesi bu testle doğrulanmaz.
- Script statik olarak ve PowerShell 7 ile sahte paket üzerinde test edildi;
  Windows PowerShell 5.1 üzerinde ilk gerçek koşu senin makinende olacak.
