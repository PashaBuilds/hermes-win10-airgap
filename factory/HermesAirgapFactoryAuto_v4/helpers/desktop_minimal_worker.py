"""Minimal Windows 10 Desktop payload for an air-gapped intranet (factory v4.7+).

Runs inside the official isolated PM preparation dispatcher (same entry as the
v4.4 Slim worker, through helpers/desktop_prepare_driver.py). It changes only
two SELECTIONS, never source files, hashes or verification:

1. Python extras of the bundled agent venv: core + web + mcp (not all extras).
2. Managed tools staged into the payload: an allowlist instead of every
   non-internal package in pm/lock.json. Upstream prunes the staged store to
   this selection (prune_staged_store -> facts.retain) and records facts for
   exactly these tools, so manifest/facts stay consistent.

Excluded on purpose (models are served by company servers; no Internet):
llamacpp-* (local model serving), cua-driver (computer use), gh (GitHub CLI),
bws (Bitwarden secrets), whispercpp/iron-proxy/termux/dmgbuild if present.
optional=True packages are "installed on demand" upstream and their absence
"never blocks PATH activation" (pm/package.py).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Keep in sync with BuildHermesDesktopWin10.ps1 ($ToolAllowlist).
ALLOWLIST = ("python", "uv", "node", "npm", "ffmpeg", "ripgrep", "git", "chromium", "agent-browser")
# Never allowed to be dropped: required (optional=False) runtime roots on win32.
REQUIRED = ("python", "uv", "node", "npm", "ffmpeg", "ripgrep")


def install_overrides(expected_venv: Path) -> tuple[list, list]:
    """Patch the two selections in-process. Returns (extras_used, tools_used) trackers."""
    import pm
    from scripts.bundles import native as native_module

    # ---- 1. Python extras: core + web + mcp
    original_build_environment = pm.build_environment
    extras_used = []

    def scoped_build_environment(*a, **kwargs):
        out = Path(kwargs["out"]).resolve() if "out" in kwargs else None
        if out == expected_venv and kwargs.get("all_extras") is True:
            if extras_used:
                raise RuntimeError("Desktop payload venv was built twice unexpectedly")
            print("[H4.8] Bundled Desktop venv: core + web + mcp (not all extras)", flush=True)
            kwargs = {**kwargs, "extras": ("web", "mcp"), "all_extras": False}
            extras_used.append(True)
        return original_build_environment(*a, **kwargs)

    pm.build_environment = scoped_build_environment

    # ---- 2. Managed tools: allowlist
    original_names = native_module._bundle_package_names
    tools_used = []

    def minimal_bundle_package_names() -> list[str]:
        full = list(original_names())
        missing = [n for n in ALLOWLIST if n not in full]
        if missing:
            raise RuntimeError(f"Upstream bundle set no longer offers {missing}; review the factory allowlist")
        chosen = [n for n in full if n in ALLOWLIST]
        for name in REQUIRED:
            if name not in chosen:
                raise RuntimeError(f"Required runtime tool {name} would be dropped")
        dropped = [n for n in full if n not in ALLOWLIST]
        print(f"[H4.8] Desktop payload tools : {', '.join(chosen)}", flush=True)
        print(f"[H4.8] Excluded (not needed) : {', '.join(dropped) or '-'}", flush=True)
        tools_used.append(chosen)
        return chosen

    native_module._bundle_package_names = minimal_bundle_package_names

    return extras_used, tools_used


def main() -> None:
    args = sys.argv[1:]
    if "--request" not in args or "--worker" not in args:
        raise ValueError("Worker may only be invoked through official desktop preparation")
    idx = args.index("--request")
    if idx + 1 >= len(args):
        raise ValueError("Missing official desktop request.json")
    request_path = Path(args[idx + 1]).resolve(strict=True)
    request = json.loads(request_path.read_text(encoding="utf-8-sig"))
    source = Path(request["source"]).resolve(strict=True)
    if request.get("variant") != "bundled":
        raise ValueError("Minimal worker only supports the bundled variant")
    expected_venv = (source / "apps/desktop/build/agent-payload/venv").resolve()
    sys.path.insert(0, str(source))

    extras_used, tools_used = install_overrides(expected_venv)
    from scripts.bundles.desktop_prepare import main as official_main
    official_main()
    if not extras_used:
        raise RuntimeError("web+mcp selection was not used; refusing to claim a minimal Desktop prepare")
    if not tools_used:
        raise RuntimeError("Tool allowlist was not used; refusing to claim a minimal Desktop prepare")


if __name__ == "__main__":
    main()
