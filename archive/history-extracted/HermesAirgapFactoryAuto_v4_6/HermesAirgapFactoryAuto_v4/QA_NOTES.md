# v4 pre-release quality checks

Validated on 2026-10-15:
- GitHub `releases/latest` is `v0.22.1` (published 2026-10-14T23:59:24Z).
- The `v0.22.1` tag still contains all exact source fragments used by the temporary `native.py`, `bytecode.py`, `launchers.py` patches; each was observed once (via connected GitHub fetch_file).
- `package.json` still declares Node `^22.22.0 || ^24.11.0 || >=26.0.0` and npm `<11.10.0 || >=11.17.0`.
- The upstream annotated `rc.5-v0.22.1` Git tag exists as a real Git tag; the factory locates the newest matching claim dynamically rather than assuming `rc.5`.
- Native and Desktop statuses are not conflated. A request for Desktop that cannot build produces a native-only ZIP and then raises an error (nonzero exit).
- Factory does not write to the pre-v4 legacy Hermes installation or user model config; the offline installer is side-by-side.
- v4 intentionally skips `[silk]` in the default Slim native staging profile; full-profile Desktop still requires upstream's full native toolchain when built locally.

**NOT checked**: Real Windows PowerShell parsing and runtime execution; Windows 10/11 source checkout, C++/Rust native components, Electron/MSIX signing and installation, final ZIP cold-install/relocation on an air-gapped PC. These checks must happen in the user's actual environment. The script does not claim success before those gates run. No TLS-insecure fallback used.

### v4.1 regression review

- Confirmed the original v4.0 parser bug `$pyVer:` and fixed the interpolated identifier.
- Fixed missing `tools` parent directory in `WriteUtf8` for finish-prepared.py.
- Avoids possible `$PROFILE` PowerShell automatic-variable collision.
- Added Windows PowerShell parser preflight, **not run in this non-Windows container**.
- Updated ZIP output directory to match README.

### v4.2

- User-provided v0.22.1 log confirms Vite 8.2.0 cannot resolve `babel-plugin-react-compiler` from the original checkout `src/babel-virtual-resolve-base.js`.
- `web/package.json` at v0.22.1 declares `babel-plugin-react-compiler` as devDependency; upstream `scripts/build/node-deps.mjs` installs pinned `npm ci` workspace union and supports `--reuse`.
- Added preflight on the original checkout, an explicit `require.resolve` check and immediate failure before potentially expensive stage if the plugin remains absent.
- No changes made to shipped Hermes source; all previous temporary native patches are still restored.
- NOT run on Windows here; validate with the bundled PowerShell parser preflight and an actual build.

### v4.3: Windows-confirmed native output / result-report regression

User supplied v0.22.2 runtime transcript proving 7/7 payload verification,
`manifest.json`, Python 3.14.7 launcher exit 0, ZIP ready, SHA256 output.
Final `$bundleZip=Bundle ...` captured robocopy stdout blank strings in the
PowerShell output pipeline, so the report's `Get-FileHash -Path $bundleZip`
rejected an empty array element. Suppressed robocopy output inside `Bundle`;
asserted exactly one scalar ZIP and used `-LiteralPath`. Code reviewed via
static textual assertions; real Windows v4.3 run not yet independently tested.


## v4.4 / 2026-10-16

- Hermes v0.22.2 Windows native ZIP / SHA256 and runtime launcher succeeded on user's Windows machine.
- Official Electron PTY probe succeeded (exitCode=0) in 4.43 seconds on user's machine.
- Desktop bundled preparation failed in second `prepare_native` using `all_extras=True` due to old DingTalk SDK wheel build (`dependency_links.txt` not created).
- Added outside-checkout `desktop_prepare_driver.py` and `desktop_slim_worker.py`, with a narrow PM in-memory override only for the Desktop agent-payload venv.
- Added `-DesktopOnly` option to keep existing native ZIP/manifest/cache and skip native ZIP recreation on Desktop failure.
- Local Python 3.13 `-I -S -B` mock contract smoke checks passed for driver and worker. Real Windows native Desktop rebuild not yet tested.
- Official upstream code (v0.22.2) read to verify dispatcher `run_preparation(...worker=...)`, `prepare_in_worker`, and `pm.build_environment` path. Strong upstream input and manifest verification is not suppressed.


## v4.5

- Fix native subprocess stdout escaping from `Run()` and polluting `DesktopBuild()` return.
- `DesktopBuild()` must return exactly one valid release-directory path.
- Passing a requested Desktop path that is absent/empty fails rather than generating `_native.zip`.
- `-PackageOnly` reuses already-built Desktop MSIX and native payload; no recomputation of Electron/Python dependencies. Requires matching prior `result.json` (`desktop=passed`) and actual `.msix`.
- Windows end-to-end, MSIX signing and offline installation remain unverified.

## v4.6 Windows 10 legacy-command mode
- Opt-in `-PackageOnly -Win10Compat` uses existing validated native payload; excludes Win11-only MSIX.
- Does NOT delete native GPU, Node, Chromium or PM-managed files, preserving tool facts.
- Exact `InstallOrUpdateHermesAirgapped.bat Auto CleanVenv` UX and `%LOCALAPPDATA%\hermes` directory.
- Rollback preserves the old `hermes-agent_source_backup_*` on success and restores it on failure after rename.
- CleanVenv provisions new sealed PM environment; NOT the same implementation as old Python3.11 pip wheelhouse.
- No Windows execution testing has been performed in this environment. On target machine run ValidateFactoryScripts.ps1 first, build using cached native payload, and test-install only on a nonproduction Windows 10 PC.
- Windows 10 Desktop GUI remains UNSUPPORTED by the official v0.22.2 MSIX. Future work may investigate using unpackaged Desktop built artifacts.
