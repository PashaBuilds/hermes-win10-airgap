"""Scope Hermes PM's bundled Desktop native payload to web+mcp for Slim.

This is executed by the official isolated PM preparation dispatcher using
its pinned Python (3.14 on v0.22.2). No tracked source file is modified, no
installation-policy or prepared-input checksum is bypassed, and official
prepare_native, publish_prepared and finish_native still run in full.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


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
        raise ValueError("Slim worker only supports bundled variant")
    expected_venv = (source / "apps/desktop/build/agent-payload/venv").resolve()
    sys.path.insert(0, str(source))

    import pm

    original_build_environment = pm.build_environment
    selected = []

    def scoped_build_environment(*args, **kwargs):
        out = Path(kwargs["out"]).resolve() if "out" in kwargs else None
        if out == expected_venv and kwargs.get("all_extras") is True:
            if selected:
                raise RuntimeError("Slim Desktop native payload was built twice unexpectedly")
            print("[H4.4] Bundled Desktop payload: core + web + mcp (not all extras)", flush=True)
            kwargs = {**kwargs, "extras": ("web", "mcp"), "all_extras": False}
            selected.append(True)
        return original_build_environment(*args, **kwargs)

    pm.build_environment = scoped_build_environment
    from scripts.bundles.desktop_prepare import main as official_main
    official_main()
    if not selected:
        raise RuntimeError("Slim bundle selection was not used; refusing to claim a Slim Desktop prepare")


if __name__ == "__main__":
    main()
