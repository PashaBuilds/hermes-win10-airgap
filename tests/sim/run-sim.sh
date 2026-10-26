#!/usr/bin/env bash
# Linux simulation of the Windows scripts with PowerShell 7 (pwsh) and stub executables.
#
#   PWSH=/path/to/pwsh tests/sim/run-sim.sh          (default: pwsh on PATH)
#
# What it proves: script logic, ordering, failure handling, rollback, file verification.
# What it can NOT prove: Windows PowerShell 5.1 / .NET Framework specifics (see docs/05-test-ve-dogrulama.md:
# the tr-TR 'I' regex bug only appeared on the real Windows factory), registry User env vars,
# WScript.Shell shortcuts, real robocopy/tar/Electron.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PWSH="${PWSH:-pwsh}"
command -v "$PWSH" >/dev/null || { echo "pwsh not found (set PWSH=...)"; exit 2; }
command -v zip >/dev/null && command -v unzip >/dev/null && command -v git >/dev/null || { echo "need zip, unzip, git"; exit 2; }
W="$(mktemp -d "${TMPDIR:-/tmp}/hermes-sim.XXXXXX")"
BIN="$W/bin"; mkdir -p "$BIN"; cp "$HERE/stubs/robocopy.exe" "$HERE/stubs/tar.exe" "$BIN/"
export PATH="$BIN:$PATH" PROCESSOR_ARCHITECTURE=AMD64
PASS=0; FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ps()   { "$PWSH" -NoProfile -File "$@"; }
sha()  { sha256sum "$1" | cut -d' ' -f1; }

echo "== 0. Parse all shipped PowerShell scripts (5.1 syntax guard)"
mapfile -t PS1 < <(find "$REPO/factory" "$REPO/pilots" -name '*.ps1')
if ps "$REPO/tests/parse.ps1" "${PS1[@]}" >/dev/null; then ok "parse ${#PS1[@]} scripts"; else bad "parse"; ps "$REPO/tests/parse.ps1" "${PS1[@]}"; fi

# ------------------------------------------------------------------ factory -PackageOnly
echo "== 1. Factory v4.8.1 BuildHermesDesktopWin10.ps1 -PackageOnly"
F="$REPO/factory/HermesAirgapFactoryAuto_v4"
TF="$W/factory"; cp -a "$F" "$TF"
# Linux paths are neither <=24 chars nor drive-letter paths: relax only ShortRoot's two checks.
sed -i "s/Require (\$full -match '^\[A-Za-z\]:\\\\\\\\') /Require (\$true) /; s/Require (\$full.Length -le 24)/Require (\$true)/" "$TF/BuildHermesDesktopWin10.ps1"
H4="$W/H4"; SRC="$H4/jobs/v0.22.4_Slim/src"; mkdir -p "$SRC"
( cd "$SRC" && git init -q && git config user.email s@s && git config user.name s && echo x > README && git add . && git commit -qm init && git tag v0.22.4 )
U="$SRC/apps/desktop/release/win-unpacked"; A="$U/resources/agent-payload"
mkdir -p "$U/locales" "$A/bin" "$A/venv" "$A/pm-runtime" "$A/hermes-agent"
for t in python-3.14.7+20260901-win32-x64 uv-0.12.3-win32-x64 node-26.7.0-win32-x64 npm-12.0.2-win32-x64 ffmpeg-9.0.1-win32-x64 \
         ripgrep-15.2.0-win32-x64 git-2.53.0+3-win32-x64 chromium-1208 agent-browser-0.26.0-win32-x64 .fetch-cache; do
  mkdir -p "$A/tools/$t"; head -c 20000 /dev/urandom > "$A/tools/$t/blob.bin"; done
echo '{}' > "$A/manifest.json"; echo '{}' > "$A/tools/facts.json"; echo '{}' > "$A/pm-runtime/pm-runtime.json"; echo '[]' > "$A/enabled-features.json"
echo '{"commit":"4d04303818b61bf3aa09278af48356315515965b","baseVersion":"0.22.4","updateMechanism":"app-installer"}' > "$A/hermes-agent/install-stamp.json"
echo x > "$U/locales/tr.pak"; echo license > "$U/LICENSE.electron.txt"
cp "$HERE/stubs/hermes.exe" "$A/bin/hermes.exe"; cp "$HERE/stubs/Hermes Agent.exe" "$U/Hermes Agent.exe"
ps "$TF/BuildHermesDesktopWin10.ps1" -VersionRef v0.22.4 -FactoryRoot "$H4" -PackageOnly > "$W/factory.log" 2>&1; rc=$?
ZIP="$H4/output/HermesAirgapBundle_v0.22.4_Win10_Desktop.zip"
check "factory exit 0" "[ $rc -eq 0 ]"
check "bundle ZIP + .sha256 written" "[ -f '$ZIP' ] && [ -f '$ZIP.sha256' ]"
check "BUNDLE.json schema 5 / contract" "unzip -p '$ZIP' '*/BUNDLE.json' | grep -q 'legacy-auto-cleanvenv-win10-desktop'"
mkdir -p "$A/tools/llamacpp-cuda-11671-win32-x64"
ps "$TF/BuildHermesDesktopWin10.ps1" -VersionRef v0.22.4 -FactoryRoot "$H4" -PackageOnly > "$W/factory_forbidden.log" 2>&1; rc=$?
check "factory refuses an excluded tool (llamacpp)" "[ $rc -ne 0 ] && grep -q 'Excluded tool still present' '$W/factory_forbidden.log'"
rmdir "$A/tools/llamacpp-cuda-11671-win32-x64"

# ------------------------------------------------------------------ installer scenarios
echo "== 2. Installer (InstallOrUpdateHermesAirgapped.ps1) scenarios"
T="$W/H4Transfer"; mkdir -p "$T"; ( cd "$T" && unzip -q "$ZIP" ); BR="$T/HermesAirgapBundle_v0.22.4_Win10_Desktop"
I="$BR/InstallOrUpdateHermesAirgapped.ps1"; LA="$W/LA"; HOMEX="$W/home"
reset() { rm -rf "$LA" "$HOMEX"; mkdir -p "$LA/hermes/hermes-agent/venv/Scripts" "$LA/hermes/sessions" "$HOMEX/Desktop"
          echo "model: deepseek  # v46" > "$LA/hermes/config.yaml"; echo "KEY=x" > "$LA/hermes/.env"; echo s > "$LA/hermes/sessions/a.json"
          echo "@echo old launcher" > "$LA/hermes/StartHermesDesktop.bat"; echo "@echo old desktop copy" > "$HOMEX/Desktop/StartHermesDesktop.bat"; sleep 1; }
inst() { ( cd "$BR" && HOME="$HOMEX" LOCALAPPDATA="$LA" APPDATA="$W/AD" "$@" ) > "$W/last.log" 2>&1; }
H="$LA/hermes"

reset; inst "$PWSH" -NoProfile -File "$I" -Mode Pilot; rc=$?
check "A  Pilot: exit 0" "[ $rc -eq 0 ]"
check "A  Pilot: real install untouched" "[ -d '$H/hermes-agent' ] && [ ! -e '$H/app' ] && grep -q '# v46' '$H/config.yaml' && ! grep -q migrated '$H/config.yaml'"
check "A  Pilot: copy of config migrated" "grep -q migrated $LA/hpilot/P*_cfg/config.yaml"

reset; inst "$PWSH" -NoProfile -File "$I" -Mode Auto -CleanVenv; rc=$?
check "B  Update: exit 0" "[ $rc -eq 0 ]"
check "B  Update: app active, old kept" "[ -f '$H/app/Hermes Agent.exe' ] && ls -d $H/hermes-agent_source_backup_* >/dev/null 2>&1 && [ ! -e '$H/hermes-agent' ]"
check "B  Update: launchers rewritten (+timeout kept)" "grep -q 'HERMES_STREAM_READ_TIMEOUT=1800' '$H/StartHermesDesktop.bat' && grep -q 'Hermes Agent.exe' '$HOMEX/Desktop/StartHermesDesktop.bat'"
check "B  Update: CLI shim + config migrated" "grep -q 'agent-payload' '$H/hermes.cmd' && grep -q migrated '$H/config.yaml'"
check "B  Update: state installed" "grep -q '\"status\": \"installed\"' $LA/hermes_backup_before_airgap_*/install-state.json"

inst "$PWSH" -NoProfile -File "$I" -Mode Rollback; rc=$?
check "C  Rollback: exit 0" "[ $rc -eq 0 ]"
check "C  Rollback: old install, config, launchers back; shim removed" "[ -d '$H/hermes-agent' ] && [ ! -e '$H/app' ] && ! grep -q migrated '$H/config.yaml' && grep -q 'old launcher' '$H/StartHermesDesktop.bat' && grep -q 'old desktop copy' '$HOMEX/Desktop/StartHermesDesktop.bat' && [ ! -e '$H/hermes.cmd' ]"
inst "$PWSH" -NoProfile -File "$I" -Mode Rollback; rc=$?
check "C2 second rollback refused" "[ $rc -ne 0 ] && grep -q 'No install to roll back' '$W/last.log'"

reset; inst env SIM_FAIL_ACTIVE=1 "$PWSH" -NoProfile -File "$I" -Mode Auto -CleanVenv; rc=$?
check "D  failure after switch -> exit 1 + auto-restore" "[ $rc -ne 0 ] && grep -q 'Previous installation restored' '$W/last.log' && [ -d '$H/hermes-agent' ] && [ ! -e '$H/app' ] && grep -q 'old launcher' '$H/StartHermesDesktop.bat'"
inst "$PWSH" -NoProfile -File "$I" -Mode Rollback; rc=$?
check "D2 rollback after auto-restore refused" "[ $rc -ne 0 ]"

reset; inst "$PWSH" -NoProfile -File "$I" -Mode Auto; rm -rf $H/hermes-agent_source_backup_*
inst "$PWSH" -NoProfile -File "$I" -Mode Rollback; rc=$?
check "F  rollback with deleted backup refused, nothing changed" "[ $rc -ne 0 ] && grep -q 'Nothing was changed' '$W/last.log' && [ -d '$H/app' ]"

reset; inst "$PWSH" -NoProfile -File "$I" -Mode Auto; sed -i 's/"status": "installed"/"status": "switching"/' $LA/hermes_backup_before_airgap_*/install-state.json
inst "$PWSH" -NoProfile -File "$I" -Mode Rollback; rc=$?
check "G  rollback from interrupted 'switching' state" "[ $rc -eq 0 ] && [ -d '$H/hermes-agent' ]"

reset; mkdir -p "$H/app/old"; echo oldapp > "$H/app/old/marker"; inst "$PWSH" -NoProfile -File "$I" -Mode Auto; rc1=$?
inst "$PWSH" -NoProfile -File "$I" -Mode Rollback; rc2=$?
check "H  update+rollback with hermes-agent AND app present" "[ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && grep -q oldapp '$H/app/old/marker' && [ -d '$H/hermes-agent' ]"

reset; echo tamper >> "$BR/app/locales/tr.pak"; inst "$PWSH" -NoProfile -File "$I" -Mode Auto; rc=$?
check "E  tampered file: refused, nothing changed, temp removed" "[ $rc -ne 0 ] && grep -q 'missing or damaged' '$W/last.log' && [ -d '$H/hermes-agent' ] && ! ls -d $H/.st* >/dev/null 2>&1"
sed -i '$ d' "$BR/app/locales/tr.pak"
reset; echo stray > "$BR/app/stray.txt"; inst "$PWSH" -NoProfile -File "$I" -Mode Auto; rc=$?
check "E2 stray extra file: refused" "[ $rc -ne 0 ] && grep -q 'manifest lists' '$W/last.log'"
rm -f "$BR/app/stray.txt"

# ------------------------------------------------------------------ CLI pilot v1.2 (v4.6 bundle layout)
echo "== 3. CLI pilot v1.2 (TestHermesWin10Pilot.ps1)"
B6="$W/pilotsim/H4Transfer/HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv"; P6="$B6/payload"
mkdir -p "$P6/bin" "$P6/pm-runtime" "$P6/venv" "$P6/uv-cache/x" "$P6/tools"
echo '{"target":"win32-x64"}' > "$P6/manifest.json"; echo '{}' > "$P6/pm-runtime/pm-runtime.json"; echo '{}' > "$P6/tools/facts.json"; echo '[]' > "$P6/enabled-features.json"
printf 'home = C:\\H4\\jobs\\x\nrelocatable = true\n' > "$P6/venv/pyvenv.cfg"
cp "$HERE/stubs/hermes.exe" "$P6/bin/hermes.exe"
cp "$REPO/pilots/cli-pilot-v1.2/TestHermesWin10Pilot.ps1" "$F/templates/VerifyOfflineBundle.ps1" "$B6/"
cat > "$B6/BUNDLE.json" <<EOF
{"schema":4,"release":"v0.22.2","commit":"d923a5eb487a17c0a68801bba9ef0f56c81040a8","profile":"Slim","desktopIncluded":false,"installContract":"legacy-auto-cleanvenv-win10","arch":"win32-x64","createdUtc":"x",
"hashes":{"payload/manifest.json":"$(sha "$P6/manifest.json")","payload/bin/hermes.exe":"$(sha "$P6/bin/hermes.exe")","payload/pm-runtime/pm-runtime.json":"$(sha "$P6/pm-runtime/pm-runtime.json")","payload/tools/facts.json":"$(sha "$P6/tools/facts.json")"}}
EOF
( cd "$(dirname "$B6")" && zip -qr "$(basename "$B6").zip" "$(basename "$B6")" -x '*.ps1' )
LA6="$W/LA6"; mkdir -p "$LA6/hermes"
( cd "$W" && LOCALAPPDATA="$LA6" HERMES_PILOT_BUNDLE="$B6/\"" SIM_VERSION_TEXT="Hermes Agent vunknown (2026.9.24)" "$PWSH" -NoProfile -File "$B6/TestHermesWin10Pilot.ps1" ) > "$W/pilot.log" 2>&1; rc=$?
check "CLI pilot: trailing \\\" bundle variable tolerated, PILOT_OK, stderr not fatal" "[ $rc -eq 0 ] && grep -q PILOT_OK '$W/pilot.log' && grep -q 'existingInstallUnchanged=yes' '$W/pilot.log'"
rm "$P6/venv/pyvenv.cfg"
( cd "$W" && LOCALAPPDATA="$LA6" "$PWSH" -NoProfile -File "$B6/TestHermesWin10Pilot.ps1" ) > "$W/pilot2.log" 2>&1; rc=$?
check "CLI pilot: incomplete extraction detected" "[ $rc -ne 0 ] && grep -q 'Extraction is INCOMPLETE' '$W/pilot2.log'"

# ------------------------------------------------------------------ Desktop delta kit v1.0
echo "== 4. Desktop delta kit v1.0 (factory delta + intranet pilot)"
K="$REPO/pilots/desktop-delta-kit-v1.0"
printf 'home = C:\\H4\\jobs\\x\n' > "$P6/venv/pyvenv.cfg"
FJ="$W/dsim/jobs/v0.22.2_Slim"; PK="$FJ/package/HermesAirgapBundle_v0.22.2_Win10_AutoCleanVenv"; mkdir -p "$FJ/package"; cp -a "$B6" "$PK"
echo native-only > "$PK/payload/uv-cache/x/native_only.txt"
WU="$FJ/src/apps/desktop/release/win-unpacked"; mkdir -p "$WU/resources"; cp -a "$PK/payload" "$WU/resources/agent-payload"; rm "$WU/resources/agent-payload/uv-cache/x/native_only.txt"
mkdir -p "$WU/resources/agent-payload/hermes-agent"; echo '{"commit":"d923a5e"}' > "$WU/resources/agent-payload/hermes-agent/install-stamp.json"
echo '{"different":true}' > "$WU/resources/agent-payload/enabled-features.json"; head -c 100000 /dev/urandom > "$WU/resources/app.asar"
cp "$HERE/stubs/Hermes Agent.exe" "$WU/Hermes Agent.exe"
ps "$K/factory/PrepareHermesDesktopDelta.ps1" -Unpacked "$WU" -OutDir "$W/dsim/output" -WorkDir "$W/dsim/dd" > "$W/delta.log" 2>&1; rc=$?
check "delta factory: DELTA_OK, differing+new files in kit" "[ $rc -eq 0 ] && grep -q DELTA_OK '$W/delta.log' && grep -q 'Differ  : 1 agent-payload files differ, 1 only in agent-payload, 1 payload files unused' '$W/delta.log'"
( cd "$(dirname "$B6")" && unzip -q -o "$W/dsim/output/HermesDesktopWin10_v0.22.2_delta.zip" )
KD="$(dirname "$B6")/HermesDesktopWin10_v0.22.2_delta"; mkdir -p "$LA6/hpilot/1022073259_cfg"; echo "model: x" > "$LA6/hpilot/1022073259_cfg/config.yaml"
( cd "$W" && LOCALAPPDATA="$LA6" APPDATA="$W/AD6" SIM_APP_SECONDS=20 "$PWSH" -NoProfile -File "$KD/TestHermesDesktopWin10Pilot.ps1" -ObserveSeconds 5 ) > "$W/dpilot.log" 2>&1; rc=$?
check "delta intranet pilot: every file verified, app started" "[ $rc -eq 0 ] && grep -q DPILOT_OK '$W/dpilot.log' && grep -q 'verifyErrors=0' '$W/dpilot.log'"

echo
echo "RESULT: $PASS passed, $FAIL failed   (work dir: $W)"
[ $FAIL -eq 0 ]
