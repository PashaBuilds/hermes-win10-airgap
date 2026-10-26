# HermesAirgapFactoryAuto v4.0 — Windows 10/11 x64 air-gap

**Target first tested by script authorship:** Hermes `v0.22.1` (published 2026-10-14 UTC).  `latest` queries the stable GitHub release at build time.

**Status:** Static/source compatibility checks only; neither this script nor the final Hermes artifacts have been end-to-end run in Windows by the author.  The factory reports pass/fail for each gate and must not be assumed successful until run and checked on your machines.

## Start — Internet-connected Windows machine

1. Extract `HermesAirgapFactoryAuto_v4.zip` to `C:\HermesAirgapFactoryAuto_v4` (the scripts themselves may be anywhere; **working files must have a short root**).
2. Prerequisites: Git for Windows, Python >=3.11 bootstrap (`py -3.11` is sufficient), Windows x64. The factory downloads portable Node 24. Hermes PM downloads and uses its **own locked Python 3.14 runtime**. It does **not** modify globally installed Python.
3. Open PowerShell, run:

```powershell
cd C:\HermesAirgapFactoryAuto_v4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.1
```

Or double-click `BuildHermesAirgapBundle.bat` to use latest. PowerShell allows optional `-NoDesktop`, `-Profile Slim` (default) or `-Profile Full`, `-DesktopVariant light`, `-FactoryRoot C:\H4`, `-Fresh`, `-CaFile C:\path\company-root.pem`.

### Build outputs

`C:\H4\jobs\v0.22.1_Slim\native`: built native payload (`manifest.json`, pinned `tools`, Python3.14 `venv`, `uv-cache`, runnable `bin\hermes.exe`).

`C:\H4\output\HermesAirgap_v0.22.1_Slim_native.zip`: verified native-only ZIP if Desktop was not built, disabled, or failed.

`C:\H4\output\HermesAirgap_v0.22.1_Slim_desktop.zip`: ZIP when official Desktop build produces a package. May contain MSIX artifacts that Windows requires to be **trusted/signed** by policy before installation.

`C:\H4\jobs\v0.22.1_Slim\result.json`: machine-readable status; `C:\H4\logs\factory_*.log`: full logs. A desktop failure is NOT reported as a desktop success; native ZIP is still available.

### Native-only quick test (faster)

```powershell
.\BuildHermesAirgapBundle.ps1 -VersionRef v0.22.1 -NoDesktop
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
| Wasted repeated downloads after final assembly error | If `native.prepared.json` exists, attempts finish-only first, then full native stage if necessary. PM uv cache reused. |
| TGitCache.exe locks existing source on update | v4 uses **side-by-side versioned install**. Legacy source directories never renamed or killed automatically. |

## About Desktop

Hermes 0.22.x has replaced the old `hermes desktop --build-only` pipeline with its official `scripts/bundles/desktop.py` **two-phase** build (`--prepare-only` and `--prepared`). Stable builds also require an upstream **annotated `rc.N-vX.Y.Z` claim tag**. v4 locates the claim tag automatically, fetches it and sets `RELEASE_CLAIM_TAG` / `RELEASE_CLAIM_OBJECT`. No custom signing certificate is invented. The build may require Windows SDK, Visual Studio Build Tools, Rust and Electron packaging dependencies; the official **bundled** variant may separately fail on optional `[silk]`/`pilk`. The `-DesktopVariant light` option runs the official light Desktop build, which does **not** embed an agent runtime. Since v4 includes a separate native payload, this may help test the UI, but it is **not equivalent to a fully integrated Desktop installer**. Factory never quietly relabels such an artifact.

During official Desktop preparation, only the source repository's checked-out files are used. Source is clean before this phase; v4's native build patches do not persist.

A built MSIX may require certificate trust and sideload permission; `VerifyOfflineBundle.ps1` validates file hashes but does **not** attest signing or guarantee MSIX launch on intranet Windows 10.

## Air-gapped target machine

1. Copy the resulting `HermesAirgap_v....zip` using approved company transfer procedure.
2. Check SHA256 against neighboring `.zip.sha256` from the online machine, using `Get-FileHash -Algorithm SHA256`. The hash file must travel through a trusted channel.
3. Extract to a reasonably short **writable** folder on the target, for example `C:\H4Transfer\HermesAirgap_v0.22.1` (do not try to execute installer inside ZIP).
4. Run `VerifyOfflineBundle.ps1` inside extracted bundle.
5. Run `InstallOrUpdateHermesAirgapped.bat` (or PowerShell script). Default install root is `%LOCALAPPDATA%\HAgent`, and a versioned copy is placed under `releases\v0.22.1`.
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

`PowerShell parse error`: Copy full terminal output; the author did not execute PowerShell on Windows and source checks cannot replace a real runtime test.

## Version

v4.0 | 2026-10-15 | Target v0.22.1 | `README.md` and scripts contain no private certs or credentials.
