# Sürüm notları (Türkçe özet)

Her airgap release'inin açıklaması, o Hermes sürümünde bir önceki sürüme göre nelerin değiştiğini anlatan Türkçe bir özetle başlar. Aynı metin release'e `SURUM-NOTLARI-<sürüm>.md` dosyası olarak da eklenir; e-postaya doğrudan yapıştırılabilir.

Özeti `.github/scripts/release_notes.py` hazırlar. Kaynak sırası:

1. **Bu klasördeki `<sürüm>.md` dosyası** (ör. `v0.22.5.md`). Varsa olduğu gibi kullanılır. Elle ya da bir asistanla yazılmış, kontrol edilmiş metin buraya konur.
2. **Yapay zekâ ile otomatik özet (isteğe bağlı).** Repo secret'ı `NOTES_LLM_API_KEY` tanımlıysa, OpenAI uyumlu bir `/chat/completions` uç noktasına upstream sürüm notları ve commit başlıkları gönderilir. Uç nokta ve model repo değişkenleriyle seçilir: `NOTES_LLM_BASE_URL` (varsayılan `https://api.openai.com/v1`) ve `NOTES_LLM_MODEL` (varsayılan `gpt-4.1`).
3. **Yedek.** İkisi de yoksa ya da başarısız olursa release yine yayımlanır; özetin üretilemediği yazılır ve upstream'in İngilizce notları açılır bir bölümde eklenir.

Özet hiçbir durumda zip yayınını durdurmaz. "Önceki sürüm", bu repodaki bir önceki airgap paketidir; yoksa bir önceki stabil upstream sürümdür.

Var olan bir release'in yalnızca özetini yenilemek için **Actions → Release notes (Turkish summary only) → Run workflow** çalıştırılır ve sürüm girilir (ör. `v0.22.5`). Bu iş zip'e dokunmaz; yalnızca açıklamanın özet bölümünü ve `SURUM-NOTLARI` dosyasını günceller. `dry_run` seçilirse sadece özeti gösterir.

> Not: GitHub Models 30 Temmuz 2026'da kapatıldığı için `GITHUB_TOKEN` ile ücretsiz model çağrısı artık mümkün değil; otomatik özet için ayrı bir API anahtarı gerekir.
