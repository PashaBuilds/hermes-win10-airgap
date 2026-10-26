HERMES v0.22.2 - WINDOWS 10 MASAÜSTÜ (MSIX'SİZ) PİLOT KİTİ v1.0
================================================================

FİKİR
Resmî MSIX, sadece manifest şeması yüzünden Windows 11 22H2 istiyor. Factory'de
MSIX'ten önce üretilen release\win-unpacked klasörü ("Hermes Agent.exe" + kendi
runtime'ı resources\agent-payload) MSIX olmadan da çalışabilir. Bu kit onu
Windows 10'da izole olarak dener.

Büyük runtime (4,1 GB) zaten intranette: HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\payload.
Bu yüzden 4,5 GB'lık win-unpacked'i taşımak yerine sadece Electron kabuğu ve
farklı olan dosyalar taşınır. Intranette her dosya SHA256 ile doğrulanır.

A) FACTORY (internetli PC)
1) Bu ZIP'i C:\HermesDesktopKit klasörüne çıkar (factory\ ve intranet\ birlikte kalsın).
2) factory\PrepareHermesDesktopDelta.bat dosyasına çift tıkla.
   Okur : C:\H4\jobs\v0.22.2_Slim\src\apps\desktop\release\win-unpacked
          C:\H4\jobs\v0.22.2_Slim\package\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv
   Yazar: C:\H4\dd\ ve C:\H4\output\HermesDesktopWin10_v0.22.2_delta.zip (+ .sha256)
   Hiçbir şeyi derlemez, mevcut dosyaları değiştirmez.
3) Sonunda [DELTA_OK] ve "Files / Differ" satırları çıkar. Bu ekranı bana gönder;
   delta beklenmedik büyükse taşımadan önce konuşalım.

B) INTRANET (Windows 10 üretim PC)
1) HermesDesktopWin10_v0.22.2_delta.zip'i C:\H4Transfer\ içine koy, SHA256'yı karşılaştır,
   aynı yere çıkar. Sonuç:
     C:\H4Transfer\HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv\   (zaten var)
     C:\H4Transfer\HermesDesktopWin10_v0.22.2_delta\                 (yeni)
2) Eski Hermes masaüstü uygulaması açıksa kapat.
3) HermesDesktopWin10_v0.22.2_delta\TestHermesDesktopWin10Pilot.bat dosyasına çift tıkla.
   - payload + delta'dan %LOCALAPPDATA%\hpilot\D<numara> klasörünü kurar
   - her dosyayı SHA256 ile doğrular
   - daha önce test ettiğin pilot profilini (hpilot\..._cfg, config KOPYASI) kullanır
   - "Hermes Agent.exe"yi başlatır, 60 sn izler
4) Pencere açılınca DeepSeek ile bir mesaj dene. summary.txt'i ve ne gördüğünü gönder.
   Sonradan tekrar açmak için: %LOCALAPPDATA%\hpilot\D<numara>_StartDesktop.bat

DOKUNDUKLARI
%LOCALAPPDATA%\hpilot\ ve Electron'un kendi veri klasörü %APPDATA%\Hermes Agent.
%LOCALAPPDATA%\hermes, kullanıcı PATH'i, registry ve eski kısayol değişmez
(önce/sonra parmak iziyle kontrol edilir). Masaüstü uygulaması Windows'ta
CLI link'i/PATH oluşturmaz (upstream main.ts: provisionCliLinks yalnız Windows dışı).

Disk: yaklaşık 4,8 GB gerekir. Yer azsa önce eski CLI pilot runtime'ını sil:
%LOCALAPPDATA%\hpilot\1022073259  (1022073259_cfg klasörünü SİLME, profil orada).

SINIRLAR
Script'ler PowerShell 7 ile Linux'ta sahte dosyalarla test edildi. Windows 10'da
paketlenmemiş "Hermes Agent.exe"nin çalışması bu pilotla ilk kez sınanacak.
