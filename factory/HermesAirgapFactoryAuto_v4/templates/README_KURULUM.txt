HERMES - WINDOWS 10 INTRANET MASAÜSTÜ PAKETİ (minimal, factory v4.8)
Sürüm: BUNDLE.json -> "release"
=============================================================================

İÇERİK
- app\                 Hermes Agent masaüstü uygulaması (MSIX'siz Electron) + TEK runtime
                       (app\resources\agent-payload). CLI de aynı runtime'ı kullanır.
- app-manifest.tsv     Her dosyanın SHA256'sı. Installer kopyaladığı HER dosyayı doğrular.
- Araçlar              python, uv, node, npm, ffmpeg, ripgrep, git (Git Bash),
                       chromium + agent-browser (tarayıcı aracı).
- Yok                  llama.cpp (yerel model sunucusu), cua-driver (bilgisayar kontrolü),
                       gh (GitHub CLI), bws (Bitwarden), MSIX. Modeller şirket sunucusunda.

KURULUM
1) ZIP'i kısa bir yola çıkar, örn. C:\H4Transfer\ (ZIP içindeki klasör bir kez oluşmalı).
2) Hermes masaüstü penceresini ve hermes çalışan terminalleri kapat.
3) İstersen önce dene (hiçbir şeyi değiştirmez):
      InstallOrUpdateHermesAirgapped.bat Pilot
   -> %LOCALAPPDATA%\hpilot\P<numara>_StartDesktop.bat ile aç, config KOPYAN kullanılır.
   Pilot ile kurulu yeni sürümü aynı anda açma (aynı Electron veri klasörünü paylaşabilirler).
4) Kur / güncelle (eski komutun aynısı):
      InstallOrUpdateHermesAirgapped.bat Auto CleanVenv

KURULUMDA NE OLUR
- Yedek: %LOCALAPPDATA%\hermes_backup_before_airgap_<zaman> (config.yaml, .env, sessions,
  skills, memories, cron + kullanıcı PATH/env değerleri + eski başlatıcı dosyaları).
- Uygulama önce geçici klasöre kopyalanır, tüm dosyalar doğrulanır, CLI test edilir.
  Ancak bundan sonra eski sürüm kenara alınır:
     %LOCALAPPDATA%\hermes\hermes-agent  -> hermes-agent_source_backup_<zaman>
- Yeni uygulama: %LOCALAPPDATA%\hermes\app\Hermes Agent.exe
- Başlatıcı: %LOCALAPPDATA%\hermes\StartHermesDesktop.bat + Masaüstü kopyası + Başlat menüsü
  "Hermes Agent". (HERMES_STREAM_READ_TIMEOUT=1800 korunur.)
- CLI: yeni terminalde "hermes" (PATH: app\resources\agent-payload\bin, eski venv kaydı çıkar).
- config: önce yedeklenir, sonra "hermes config migrate".
- Herhangi bir adım hata verirse önceki kurulum otomatik geri konur.
- %LOCALAPPDATA%\hermes altındaki config/sessions/skills/memories/cron SİLİNMEZ.

GERİ ALMA
   RollbackHermesAirgapped.bat
   Yeni app'i kenara alır, eski hermes-agent'i, config.yaml/.env'i (migrate öncesi),
   PATH/env değerlerini ve başlatıcıları geri koyar.

NOTLAR
- İlk açılış uzun sürebilir; pencere bir kez kapanırsa tekrar aç (pilotta görüldü).
- Yedek klasörlerini silersen RollbackHermesAirgapped.bat geri dönemez (değişiklik yapmadan durur).
- Kurulum sonrası eski yedek klasörleri elle silinebilir (hermes-agent_source_backup_*,
  hermes_backup_before_airgap_*), önce birkaç gün kullanıp emin ol.
