# HermesAirgapFactoryAuto v4.3 — Windows 10/11 x64 air-gap

**Current field-tested native build:** Hermes `v0.22.2` (2026-10-15 release, Windows x64 native payload created; air-gapped installation and Desktop still pending).  `latest` queries the stable GitHub release at build time.

**Status:** Static/source compatibility checks only; neither this script nor the final Hermes artifacts have been end-to-end run in Windows by the author.  The factory reports pass/fail for each gate and must not be assumed successful until run and checked on your machines.

## Start — Internet-connected Windows machine

1. Extract `HermesAirgapFactoryAuto_v4_5.zip` to `C:\HermesAirgapFactoryAuto_v4` (the scripts themselves may be anywhere; **working files must have a short root**).
2. Prerequisites: Git for Windows, Python >=3.11 bootstrap (`py -3.11` is sufficient), Windows x64. The factory downloads portable Node 24. Hermes PM downloads and uses its **own locked Python 3.14 runtime**. It does **not** modify globally installed Python.
3. **Before a long build, validate every PowerShell file using the machine’s own parser:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ValidateFactoryScripts.ps1
```

4. Open PowerShell, run:

```powershell
cd C:\HermesAirgapFactoryAuto_v4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2
```

Or double-click `BuildHermesAirgapBundle.bat` to use latest. PowerShell allows optional `-NoDesktop`, `-Profile Slim` (default) or `-Profile Full`, `-DesktopVariant light`, `-FactoryRoot C:\H4`, `-Fresh`, `-CaFile C:\path\company-root.pem`.

### Build outputs

`C:\H4\jobs\v0.22.2_Slim\native`: built native payload (`manifest.json`, pinned `tools`, Python3.14 `venv`, `uv-cache`, runnable `bin\hermes.exe`).

`C:\H4\output\HermesAirgap_v0.22.2_Slim_native.zip`: verified native-only ZIP if Desktop was not built, disabled, or failed.

`C:\H4\output\HermesAirgap_v0.22.2_Slim_desktop.zip`: ZIP when official Desktop build produces a package. May contain MSIX artifacts that Windows requires to be **trusted/signed** by policy before installation.

`C:\H4\jobs\v0.22.2_Slim\result.json`: machine-readable status; `C:\H4\logs\factory_*.log`: full logs. A desktop failure is NOT reported as a desktop success; native ZIP is still available.

### Native-only quick test (faster)

```powershell
.\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2 -NoDesktop
```

Once native succeeds, rerun without `-NoDesktop` to try the full **official** Desktop packaging phase. It reuses the same native result.

## What v4 handles from previous factory failures

| Observed failure | v4 approach |
|---|---|
| `pip download` empty arguments | No legacy pip download resolver. Hermes PM lockfiles are the dependency authority. |
| Missing `ruamel.yaml` from Python3.11 environment | Pinned Hermes runtime Python3.14, independent of host bootstrap. |
| `UnknownIssuer` from uv | `UV_NATIVE_TLS=true`, `UV_SYSTEM_CERTS=true`, Windows trust store; no auto-insecure-host mode. Use a trusted corporate root CA when necessary. |
| `pilk==0.2.4` has no cp314 wheel | **Slim** profile excludes the `[silk]` extra and keeps core+web+mcp. **Full** will attempt official all-extras and may require Visual Studio C++ build tools. |
| Windows 260-character long paths | Default short root `C:\H4`, nested staging below it; reject long root. |
| `WinError 145` during TemporaryDirectory cleanup | Temporarily tolerates cleanup error, but build failure still propagates; all patches are restored. |
| 2,227 missing `.pyc` | Check bytecode for **pinned staged interpreter's** cache tag (3.14), not bootstrap host (3.11). |
| `AssertionError: SRE module mismatch` | Launcher mint subprocess strips inherited `PYTHONPATH` / `PYTHONHOME`; launcher validation performed. |
| Vite 8 / Babel `Cannot find package babel-plugin-react-compiler` | Preflight locked `npm ci` workspaces on the original checkout before staging; the Rolldown virtual resolver anchors to that checkout, not to stage.py temporary source; validate `require.resolve()` there. |
| Wasted repeated downloads after final assembly error | If `native.prepared.json` exists, attempts finish-only first, then full native stage if necessary. PM uv cache reused. |
| TGitCache.exe locks existing source on update | v4 uses **side-by-side versioned install**. Legacy source directories never renamed or killed automatically. |

## About Desktop

Hermes 0.22.x has replaced the old `hermes desktop --build-only` pipeline with its official `scripts/bundles/desktop.py` **two-phase** build (`--prepare-only` and `--prepared`). Stable builds also require an upstream **annotated `rc.N-vX.Y.Z` claim tag**. v4 locates the claim tag automatically, fetches it and sets `RELEASE_CLAIM_TAG` / `RELEASE_CLAIM_OBJECT`. No custom signing certificate is invented. The build may require Windows SDK, Visual Studio Build Tools, Rust and Electron packaging dependencies; the official **bundled** variant may separately fail on optional `[silk]`/`pilk`. The `-DesktopVariant light` option runs the official light Desktop build, which does **not** embed an agent runtime. Since v4 includes a separate native payload, this may help test the UI, but it is **not equivalent to a fully integrated Desktop installer**. Factory never quietly relabels such an artifact.

During official Desktop preparation, only the source repository's checked-out files are used. Source is clean before this phase; v4's native build patches do not persist.

A built MSIX may require certificate trust and sideload permission; `VerifyOfflineBundle.ps1` validates file hashes but does **not** attest signing or guarantee MSIX launch on intranet Windows 10.

## Air-gapped target machine

1. Copy the resulting `HermesAirgap_v....zip` using approved company transfer procedure.
2. Check SHA256 against neighboring `.zip.sha256` from the online machine, using `Get-FileHash -Algorithm SHA256`. The hash file must travel through a trusted channel.
3. Extract to a reasonably short **writable** folder on the target, for example `C:\H4Transfer\HermesAirgap_v0.22.2` (do not try to execute installer inside ZIP).
4. Run `VerifyOfflineBundle.ps1` inside extracted bundle.
5. Run `InstallOrUpdateHermesAirgapped.bat` (or PowerShell script). Default install root is `%LOCALAPPDATA%\HAgent`, and a versioned copy is placed under `releases\v0.22.2`.
6. Launch with `%LOCALAPPDATA%\HAgent\hermes.cmd --version`, then use this command for Hermes. The installer will not overwrite `%LOCALAPPDATA%\hermes\hermes-agent` from the old v3 system.

PowerShell direct installation with same-version replacement:

```powershell
.\InstallOrUpdateHermesAirgapped.ps1 -Force
```

If needed select `-InstallRoot C:\HAgent` (must be writable by your user; no admin required). The default `HAgent` path is deliberately separate from the old install, preserving configuration and enabling rollback. The stable `hermes.cmd` launcher changes only after the relocated binary passes an **offline** `--version` smoke test.

User settings like `~/.hermes/config.yaml`, `~/.hermes/.env` and custom certificates are not included in ZIP nor rewritten by installer. Configure the internal OpenAI-compatible model endpoint independently. **Do not run `hermes update` or lazy plugin installation on the air-gapped target** unless it uses a company-approved internal mirror/offline provisioner; unbundled extras need more wheels.

## Limitations and warnings

- v4 targets **Windows x64 only**, recent 0.22.x layout. Future upstream changes stop at exact code-signature checks instead of making guesses.
- `Slim` does not ship **all** extras (specifically `[silk]`; it installs core + `web` + `mcp` and any transitive dependencies, with feature inventory generated by Hermes PM). For specialized plugins like voice/silk and new providers, offline dependencies may be absent. An offline rebuild of only the installed feature set can be supported by the included uv-cache; a new feature is not automatically supported.
- No automatic TLS verification bypass, no global Python install, no unconditional process termination, no in-place replacement of previous Hermes installs.
- Short directories do not guarantee Windows filesystem long-path support for *every* future Hermes file; if the upstream package creates still-longer paths, Windows long path policy / short paths may need work.
- The final installer is a native **side-by-side rollout tool**, not a vendor-signed/MSIX deployment manager.
- Resource requirements can be high: multiple GB of storage, network fetches, Electron/Node modules, many minutes or hours depending on network and compiler availability.
- Avoid exposing sensitive `.env`, cached authorization, internal URLs in shared logs/ZIP. The factory isolates HOME during staging, but inspect before transfer according to corporate policies.

## Quick troubleshooting

`ERROR UnknownIssuer`: Confirm corporate root certificate in Windows Trusted Root; set `-CaFile` to trusted PEM if needed. Never use `UV_INSECURE_HOST` / `PIP_TRUSTED_HOST`.

`pilk / MSVC`: Use `-Profile Slim`; for Desktop bundled variant, Visual Studio C++ / SDK may still be required by upstream. Try `-DesktopVariant light` for UI-only packaging test.

`Release claim missing`: Stable upstream claim may be absent or permission-restricted; run `-NoDesktop` and inspect available upstream annotated tags.

`Desktop prepare changed`: Delete nothing; inspect logs. `desktop-work/prepared.json` is a native checkpoint, but if source revision/selected variant changed, use a new factory job/root or `-Fresh` (archives old job).

`Failed at end`: Rerun identical command to attempt resume from prepared native inputs. The script does not silently roll forward a different tag.

`PowerShell parse error`: Run `ValidateFactoryScripts.ps1` first; it reports the exact file and line number using the native Windows PowerShell parser. This validation is not a substitute for an end-to-end Windows build.

## Version

v4.1 | 2026-10-15 | Target v0.22.1 | `README.md` and scripts contain no private certs or credentials.

### v4.1 changes after first live Windows invocation

- Fixed PowerShell `$pyVer:` interpolation parse error by delimiting `${pyVer}`.
- `WriteUtf8` now creates its destination directory first, including the native assembly runner at `jobs\...\tools\finish-prepared.py`.
- Renamed internal `$Profile` variable to `$HermesProfile` while retaining CLI `-Profile` for users.
- Unified output location to `C:\H4\output` to match documentation.
- Added `ValidateFactoryScripts.ps1` and `.bat` preflight to parse every bundled PowerShell file **before** attempting downloads.
- These edits have been inspected statically in Linux; actual PowerShell parsing and build must be tested on Windows by the user.

### v4.2: Web/Vite dependency-resolution fix

Observed on Hermes v0.22.1 Windows: the `stage.py` transient Git snapshot gets its own
`node_modules`, but `@rolldown/plugin-babel` resolves `babel-plugin-react-compiler`
from the **original checkout** (`src/babel-virtual-resolve-base.js`). This is not
a Python dependency issue. v4.2 calls the upstream `node-deps.mjs` for the original
checkout (`--workspace ui-tui --workspace web --reuse`) before the stage. The
install is locked to `package-lock.json`, does not modify global npm, and reuses
its completed `node_modules` on retries. It then verifies that Node can resolve
the plugin in the original checkout. `stage.py`'s transient copy still does its
own build; the preflight does not change upstream source.

If rerunning v4.1 immediately, manually run the same upstream node-deps command
from `C:\H4\jobs\v0.22.1_Slim\src` as explained in the conversation, then
rerun with the same tag and **without** `-Fresh`.

Other toolchain/native/Desktop limitations in the main README still apply;
this patch addresses the **observed Web Babel module-resolution failure**, not
a Windows end-to-end certification.

### v4.3: final ZIP reporting fix (observed on v0.22.2)

Windows confirmed native bundle staging, manifest, Python 3.14.7 launcher smoke,
ZIP packaging and SHA256; factory then failed with `Get-FileHash -Path ''` at
`result.json` report construction. Root cause: `Bundle()` captured raw `robocopy`
stdout in addition to its `return $zip` string; PowerShell functions emit all
uncaptured pipeline output, including empty lines. `-Path` treated one of those
as an empty path. Now robocopy stdout is suppressed, exactly one returned
ZIP path is required, and `Get-FileHash -LiteralPath` receives a validated scalar.

**No native rebuild required:** the already created v0.22.2 ZIP may be validated
in place using its adjacent `.zip.sha256` and `Get-FileHash`. Re-running this
script with the same tag/profile reuses `native/manifest.json`, but may
recreate a transfer ZIP in the output folder. Never use `-Fresh` for this fix.

The `Hermes Agent vunknown (2026.9.24)` display from `hermes --version` is a
separate upstream/runtime metadata discrepancy; its exit status was 0 and the
checkout is pinned, but version-label accuracy and the complete offline
Windows deployment have NOT yet been certified.


### v4.4 (2026-10-16): Desktop bundled Slim Python dependencies

Observed on v0.22.2 Windows 10 x64: **native Slim transfer ZIP builds
successfully**, but the *official bundled Desktop preparation* runs a second
`prepare_native(...)` with `all_extras=True`. That unnecessarily attempts
`hermes-agent[dingtalk] -> alibabacloud-dingtalk -> alibabacloud-gateway-dingtalk`
where the old source distribution fails to create `dependency_links.txt` under
Python 3.14/Windows. Earlier Windows PTY `ETIMEDOUT` was re-tested using the
**exact upstream** `probe-prepared-native.mjs` and succeeded in 4.43 s. It is
not the current blocker.

**Default Slim+bundled fix:** The factory now supplies an **external worker** to
Hermes' official `desktop_toolchain.run_preparation(...)` via a small *in-memory*
scoped driver. It selects `extras=('web','mcp')` rather than `all_extras=True`
**only when** PM builds the Desktop's own
`apps/desktop/build/agent-payload/venv`. This avoids both the DingTalk build
and unrelated `silk/pilk`. All other PM builds, original source checks,
`prepare_native`/`finish_native`, bytecode checks, hashes, Electron/PTY
admission, and official MSIX builder remain active and unchanged. No tracked
Hermes source files are modified, and no Git clean check is suppressed.

**Recommended continuation from an already built v0.22.2 Slim native ZIP:**

```powershell
cd C:\HermesAirgapFactoryAuto_v4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ValidateFactoryScripts.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2 -DesktopOnly
```

`-DesktopOnly` verifies the existing native payload but **skips native staging**.
If Desktop preparation fails, it leaves the existing native ZIP byte-for-byte
unchanged instead of re-copying several GB. It cannot be combined with
`-NoDesktop` or `-Fresh`. Successful Desktop builds produce a new `_desktop.zip`
containing both the verified native payload and packaged MSIX artifact.

**Important limitation:** The bundled Desktop agent is also a **Slim** payload:
it does not promise optional DingTalk/Silk/etc. features offline. Select
`-Profile Full` only if you have established buildable wheels/toolchains for
all upstream extras. This implementation has passed code compilation and
local *mocked worker contract tests*; actual Windows PM/desktop end-to-end
and MSIX signing have NOT been completed here. A future Hermes version may
change the upstream entry points; if so, investigate before using this shim.


### v4.5 (2026-10-19): Desktop succeeded, final ZIP mislabeled native-only

**Observed on v0.22.2:** Official bundled Desktop finishes, and `result.json`
reports `desktop: passed`, but output remains `_native.zip`. Root cause:
`Run()` streamed a subprocess's stdout into the PowerShell function return
pipeline. `DesktopBuild()` emitted build log lines *and* its release directory;
when `Bundle()` received that array as a string, the path was invalid. As a
result, no Desktop MSIX was copied to the transfer bundle.

v4.5 pipes native subprocess stdout to `Out-Host` rather than its caller's
success pipeline, requires `DesktopBuild()` to return exactly one verified
release directory, and **fails closed** if a requested Desktop folder is
missing/contains no transferable files.

If v4.4 reports `desktop: passed` but `_native.zip`, **do not rebuild**:

```powershell
cd C:\HermesAirgapFactoryAuto_v4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ValidateFactoryScripts.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.2 -PackageOnly
```

`-PackageOnly` explicitly requires a previous matching successful
`result.json` and an actual `.msix` file under
`src\apps\desktop\release`. It skips **both** native and Desktop
compilation; it recopies existing bytes into
`C:\H4\output\HermesAirgap_v0.22.2_Slim_desktop.zip`, computes its SHA256,
re-runs the transfer-bundle hash checks, and writes a corrected `result.json`.
It cannot be combined with `-Fresh`, `-NoDesktop`, or `-DesktopOnly`. Existing
`_native.zip` is retained. `-PackageOnly` still verifies local toolchain, Git
revision, the staged Hermes launcher, and the exact native manifest.

**Transfer note:** The Desktop ZIP includes the MSIX bytes but Windows
installation may require publisher signature trust / sideload policy.
`VerifyOfflineBundle.ps1` verifies hashes, not Authenticode signing or the
end-to-end offline launch. Do not deploy to production until tested on a
representative offline Windows 10 machine.
