# 6. Upstream kod analizi

Yöntem, [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) kaynağındaki şu noktalara dayanıyor. Satır numaraları **v0.22.4** (`4d04303818b61bf3aa09278af48356315515965b`) içindir. v0.22.2 (`d923a5eb487a17c0a68801bba9ef0f56c81040a8`) ile farklar en altta.

## Paket içeriği ve araç seçimi

| Konu | Yer | Ne söylüyor / ne yapıyor |
|---|---|---|
| Hangi araçlar pakete giriyor | `scripts/bundles/native.py:20` `_bundle_package_names()` | `pm/lock.json`'daki dahili olmayan **her** paket (`uv` dahil, `python` eklenir) |
| Seçimin kullanıldığı yer | `native.py` `_prepare_native` | `names = [n for n in _bundle_package_names() if missing_reason(target) is None]` → `prepare_tools`, `stage_tools` |
| Seçilmeyenlerin temizliği | `native.py:143` `prune_staged_store(store_dir, names)` | `facts.retain(walk(names))` sonrasında kullanılmayan araç klasörlerini siliyor |
| Kayıt | `scripts/bundles/payload.py:70` `record_tools` | Yalnızca seçilen araçların facts kaydını yazıyor; bütün kilit paketlerini zorunlu kılan bir kontrol yok |
| Venv extras | `native.py:242` `build_environment(..., all_extras=True, ...)` | Worker bunu masaüstü `agent-payload/venv` için `extras=("web","mcp")` yapıyor |
| `optional` anlamı | `pm/package.py:58-62` | "optional: not part of the root closure; installed on demand … its absence never blocks PATH activation" |
| ffmpeg zorunlu | `pm/packages.py:808-810` | `name = "ffmpeg"`, `optional = False` ("required runtime tool where supported") |
| Zorunlu araç sağlık kontrolü | `pm/install.py:881` | Opsiyonel ya da dahili olmayan her paket kurulu değilse `"not installed or outdated"` döner. Bu yüzden ffmpeg, node, npm ve ripgrep pakette kalmalı. |
| Varsayılan opsiyoneller | `pm/defaults.py:61` | `cua-driver` ve `agent-browser` için `default=True`. Yalnızca `hermes pm install` (`pm/cli.py`) ve `hermes update` (`hermes_cli/update_cmd_maint.py`) kuruyor; masaüstü uygulaması açılışta kurmuyor. |
| Windows bash | `pm/shell.py:106` `bash()`, `tools/environments/local.py` | Terminal aracı bash istiyor: `HERMES_GIT_BASH_PATH`, PM git ya da sistem Git'i |
| Kaynak anlık görüntüsü | `payload.py:33-45` `snapshot()` | Hedef klasörü `shutil.rmtree` ile siliyor; salt okunur dosyalarda **WinError 5** veriyor (v4.8 düzeltmesinin nedeni) |
| Taşınabilirlik | `payload.py:103`, `pm/environment.py` (`venv --relocatable`) | "Its paths remain valid after the payload moves" |
| Venv doğrudan çalıştırılmıyor | `apps/desktop/BUILDING.md:325` | "Hermes never runs a venv's own executables". Bu yüzden `venv\pyvenv.cfg`'deki `C:\H4\…` yolu zararsız, ama eski `venv\Scripts\hermes.exe` başlatıcısı yeni yapıda çalışmaz. |

## Masaüstü derleme akışı

| Konu | Yer | Not |
|---|---|---|
| Hazırlık dispatcher'ı | `scripts/bundles/desktop_toolchain.py:64` `run_preparation(..., worker=None)` | Factory'nin `helpers/desktop_prepare_driver.py` dosyası buraya harici worker veriyor (v4.4'ten beri) |
| Worker içinde payload | `scripts/bundles/desktop_prepare.py:368` | `prepare_native(out=…/apps/desktop/build/agent-payload, …)` |
| Paketleme hedefleri | `scripts/bundles/desktop.py:99` | Windows'ta her zaman `["--win", "msix"]`. Bu yüzden `--dir` MSIX'i durdurmuyor; MSIX yan ürün olarak çıkıyor. |
| Ek electron-builder argümanları | `desktop.py` `builder_args` (`nargs=REMAINDER`, `--` filtreleniyor) | `--prepared X -- --dir` |
| `--dir` kabulü | `apps/desktop/scripts/run-electron-builder.mjs:171` | `if (args.includes('--dir')) return ['dir']` (doğrulama tarafı) |
| Stable claim | `desktop_prepare` / CI | `rc.N-vX.Y.Z` annotated etiketi gerekiyor. v0.22.2 için `rc.2-v0.22.2`, v0.22.4 için `rc.2-v0.22.4`. |

## Windows 11 sınırı ve uygulama kimliği

| Konu | Yer | Not |
|---|---|---|
| MSIX minimum sürümü | `apps/desktop/electron-builder.config.cjs:264` | `minVersion: '10.0.22621.0'` |
| Sınırın nedeni | aynı dosya, `:260` civarındaki yorum | 18307'den eski şemalarda AppExtension adı 39 karakterle sınırlı; `com.microsoft.windows.copilotkeyprovider` 40 karakter |
| Resmî belge | `apps/desktop/BUILDING.md:15` | "The current MSIX manifest requires Windows 11 22H2" |
| Uygulama adı | `apps/desktop/product-identity.cjs:19, :74` | bundled: `display: 'Hermes Agent'` → `windowsExecutableName` = `Hermes Agent.exe` |
| Masaüstü uygulamasının HERMES_HOME kullanımı | `apps/desktop/electron/backend-env.ts`, `fs-ipc.ts`, `bootstrap-runner.ts` | Ortamdaki `HERMES_HOME` kullanılıyor |
| Windows'ta CLI link'i yok | `apps/desktop/electron/main.ts:5003-5007` | `if (!IS_WINDOWS) provisionCliLinks(...)` |
| `hermes desktop --skip-build` | `hermes_cli/subcommands/gui.py:36`, `hermes_cli/main_desktop.py:152-155` | `apps/desktop/release/win-unpacked/<exe>` dosyasını başlatıyor (eski yöntem). Native payload'da `apps/` yok (`INERT_SNAPSHOT_DIRS`). |
| `0xE0000008` | Chromium `base::win::kOomExceptionCode` | Hermes kaynağında böyle bir çıkış kodu yok; Electron'un kendi OOM istisnası |

## Sürüm etiketi

- `hermes_cli/__init__.py:5`: `__release_date__ = "2026.9.24"`. Bu, v0.22.2 ve v0.22.4 kaynağının kendisinde yazıyor.
- `hermes_cli/version_info.py` `get_version_info()`: önce install stamp'e, sonra git'e bakıyor; ikisi de yoksa `unknown`. Native payload'da stamp olmadığı için `vunknown (2026.9.24)`, bundled payload'da `v0.22.x · stable`.

## Factory worker'ın v0.22.4'e karşı testi (Linux, CPython 3.13)

```
[H4.8] Desktop payload tools : agent-browser, chromium, ffmpeg, git, node, npm, python, ripgrep, uv
[H4.8] Excluded (not needed) : bws, cua-driver, gh, iron-proxy, llamacpp-cpu, llamacpp-cuda, llamacpp-hip,
                               llamacpp-metal, llamacpp-vulkan, termux-docker, whispercpp-cpu
final (win32-x64): [agent-browser, chromium, ffmpeg, git, node, npm, python, ripgrep, uv]
closure          : [agent-browser, chromium, ffmpeg, git, node, npm, python, ripgrep, uv]
```

## v0.22.2 → v0.22.4 farkı (factory açısından)

| Dosya | Durum |
|---|---|
| `scripts/bundles/desktop.py`, `desktop_prepare.py`, `payload.py` | aynı |
| `apps/desktop/scripts/run-electron-builder.mjs`, `product-identity.cjs`, `electron-builder.config.cjs` | aynı |
| `pm/packages.py`, `pm/package.py`, `hermes_cli/__init__.py` | aynı |
| `scripts/bundles/native.py` | yalnızca aşama süresi çıktıları (`_phase`); `_bundle_package_names` aynı |
| `scripts/bundles/desktop_toolchain.py` | MSVC kimliği `vswhere` ile; `VCPKG_DEFAULT_BINARY_CACHE` |
| `pm/lock.json` | paket adları aynı; yalnızca llama.cpp `11370 → 11671` |
