# 7. Yeni Hermes sürümüne geçiş

Factory varsayılan olarak `-VersionRef latest` kullanır; yeni bir sürüm çıktığında çoğu zaman tek yapman gereken onu çalıştırmak. Factory upstream'in iç fonksiyonlarına dayandığı için, sürüm değişince aşağıdaki kontrolleri yap.

## 1. Sürümü ve claim etiketini kontrol et

```bash
git ls-remote --tags https://github.com/NousResearch/hermes-agent | grep -E 'refs/tags/(v0\.|rc\.[0-9]+-v0\.)' | sort -V | tail
```

Resmî stable masaüstü derlemesi, yeni sürüm için bir `rc.N-vX.Y.Z` annotated etiketi ister. Etiket yoksa factory `Official Desktop stable builder requires an rc.N-vX.Y.Z claim tag` hatası verir.

## 2. Worker'ı yeni kaynağa karşı çalıştır (internet olan herhangi bir makinede, ~1 dk)

```bash
git clone --depth 1 --branch vX.Y.Z https://github.com/NousResearch/hermes-agent hermes-src
python3 -I tests/check_worker.py hermes-src
```

Çıktıda şunları bekle:
- **Seçim:** `selection (win32-x64)` ve `dependency closure` yalnızca izin listesindeki 9 aracı içermeli.
- **Sonuç:** son satır `OK` olmalı.
- **Hata durumu:** `PROBLEM:` satırı görürsen upstream hook'larından biri değişmiş demektir; derlemeden önce worker'ı güncelle.
- **Yeni paket:** `pm/lock.json`'a yeni bir paket eklendiyse "Excluded" listesinde görünür. Gerekli olup olmadığını değerlendir. Gerekliyse ALLOWLIST'e ekle; bunu iki yerde birden yapman gerekir:
  - `helpers/desktop_minimal_worker.py`
  - `BuildHermesDesktopWin10.ps1` içindeki `$ToolAllowlist`

## 3. Factory'nin dayandığı dosyalarda değişiklik var mı?

Önceki sürümle karşılaştır ([06-upstream-analizi.md](06-upstream-analizi.md)):

```bash
git diff vOLD vNEW -- scripts/bundles/native.py scripts/bundles/desktop.py scripts/bundles/desktop_prepare.py \
  scripts/bundles/desktop_toolchain.py scripts/bundles/payload.py apps/desktop/scripts/run-electron-builder.mjs \
  apps/desktop/product-identity.cjs apps/desktop/electron-builder.config.cjs pm/lock.json pm/packages.py pm/package.py
```

Shallow clone ile çalışıyorsan iki sürümü ayrı klasörlere klonlayıp `diff -u` kullan.

Özellikle şunlara bak:
- **`_bundle_package_names` / `_prepare_native` / `prune_staged_store`:** Araç seçimi buradan geçiyor.
- **`build_environment(... all_extras=True ...)`:** Venv seçimi buradan geçiyor.
- **`product-identity.cjs`:** Exe adı değişirse factory ve installer'daki `Hermes Agent.exe` adı da güncellenmeli.
- **`desktop.py` hedefleri:** `--win msix` yerine başka bir hedef gelirse paketleme değişebilir.
- **Masaüstü uygulamasının Windows'ta CLI link'i ya da PATH değişikliği yapıp yapmadığı:** `electron/main.ts` → `provisionCliLinks` çağrısı.
- **Windows 10 desteği:** Electron sürüm notlarında Windows 10'un desteklenmeye devam ettiğinden emin ol.

## 4. Derle ve kur

```bat
BuildHermesDesktopWin10.bat            &:: ya da -VersionRef vX.Y.Z
```

Sonra intranette, gerekirse önce `Pilot`, ardından `Auto CleanVenv` çalıştır. Installer önceki `app` klasörünü `app_backup_<zaman>` adıyla yedekleyip yeni sürüme geçer. Rollback yalnızca **son** kurulumu geri alır.

## 5. Bu repoyu güncelle

- **`CHANGELOG.md`:** Yeni sürümü ve gerçek makine sonuçlarını ekle.
- **`docs/06-upstream-analizi.md`:** Satır numaralarını ve sürüm farkı tablosunu güncelle.
- **Testler:** `tests/sim/run-sim.sh` dosyasını çalıştır. Factory'yi değiştirdiysen yeni senaryo ekle.
