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
