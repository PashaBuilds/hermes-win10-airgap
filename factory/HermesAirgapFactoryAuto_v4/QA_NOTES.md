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

## v4.7 minimal Windows 10 Desktop (2026-10-22)
- Upstream facts (v0.22.2, d923a5e): MSIX Win11 floor comes from the MSIX manifest schema
  (electron-builder.config.cjs comment), not Electron. Unpacked `win-unpacked\Hermes Agent.exe`
  ran on the user's Windows 10 LTSC 19044 (delta pilot): opened, showed v0.22.2, chatted with
  the company model. First start once exited with 0xE0000008; second start fine.
- Size cause: scripts/bundles/native.py `_bundle_package_names()` stages EVERY non-internal
  PM package. New helpers/desktop_minimal_worker.py overrides only that selection (and the
  v4.4 web+mcp venv selection) inside the official preparation worker. Upstream prunes the
  staged store to the selection (prune_staged_store/facts.retain) and records facts for it.
- Allowlist: python uv node npm ffmpeg ripgrep git chromium agent-browser. ffmpeg is
  optional=False upstream (pm/install.py health check), so it stays. git: pm.shell bash.
- Tested here: worker against the real v0.22.2 tree (win32-x64 selection + dependency closure
  = exactly the allowlist); BuildHermesDesktopWin10.ps1 -PackageOnly and the installer
  (Pilot, Update, Rollback, refuse 2nd rollback, failure-after-switch auto-restore, tampered
  file) in a PowerShell 7 Linux simulation with stub executables.
- NOT tested here: the real Windows build (prepare + electron-builder --dir), Windows-only
  parts (User env registry, Start menu .lnk via WScript.Shell), real Electron start.
- Independent review (Windows PowerShell 5.1 focus) found no blockers; fixed: rollback accepts
  'switching'/'failed-partial' and records moved folders BEFORE moving; rollback pre-checks all
  backups and changes nothing if one is missing; auto-restore only moves the app aside when the
  new one was activated; state files read as UTF-8 ([IO.File], not Get-Content) and written
  atomically; rollback keeps PATH entries added after install; launchers use %LOCALAPPDATA%;
  stray-file check; Zone.Identifier unblock; Sysnative PowerShell in BATs; Move retries;
  factory Exec ignores stderr lines, PYTHONDONTWRITEBYTECODE during smoke test, ASCII file names.
- Regression (PowerShell 7 simulation): Pilot, Update, Rollback, 2nd rollback refused,
  failure-after-switch auto-restore, rollback after auto-restore refused, deleted-backup
  rollback refused unchanged, rollback from 'switching', update+rollback with both
  hermes-agent and app present, tampered file, stray file.

## v4.8 (2026-10-23)
- Real Windows run of v4.7 failed in upstream snapshot(): shutil.rmtree WinError 5 on a read-only
  .pyc inside the stale v4.4 apps\desktop\build\agent-payload. Fix: Remove-Tree (attrib -R, then
  Remove-Item -Force, robocopy /MIR fallback) for apps\desktop\build\agent-payload and
  apps\desktop\release before preparing (both are .gitignored build outputs, no tracked files).
- -VersionRef latest (default) via GitHub releases/latest; clones jobs\<tag>_Slim\src when missing.
- Desktop cache shared across versions (C:\H4\desktop-cache or newest jobs\*\desktop-cache).
- v0.22.4 (4d04303, 2026-10-21, claim rc.2-v0.22.4) checked against v0.22.2: desktop.py,
  desktop_prepare.py, payload.py, run-electron-builder.mjs, product-identity.cjs, pm/packages.py,
  electron-builder config unchanged; native.py only adds phase timing; pm/lock.json same names
  (llamacpp version bump only). Worker selection on v0.22.4 = the same 9 tools.

## v4.8.1 (2026-10-23)
- Real v0.22.4 build succeeded (bundled CLI "Hermes Agent v0.22.4 stable"; tools uncompressed MB:
  agent-browser 10, chromium 393, ffmpeg 427, git 384, node 111, npm 12, python 148, ripgrep 4, uv 46).
- Packaging aborted on a FALSE non-ASCII check for LICENSE.electron.txt: Windows PowerShell 5.1
  (.NET Framework regex) with tr-TR culture case-folds 'I' to U+0131 under -notmatch. Fixed with
  -cnotmatch. Not reproducible in PowerShell 7 (.NET 8) on Linux, which is why the simulation passed.
- Observed: electron-builder still builds the MSIX (desktop.py always passes "--win msix"); harmless.
