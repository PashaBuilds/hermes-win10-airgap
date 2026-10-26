"""Check the factory's minimal worker against a Hermes source checkout (any OS, Python >= 3.11).

    git clone --depth 1 --branch vX.Y.Z https://github.com/NousResearch/hermes-agent hermes-src
    python3 -I tests/check_worker.py hermes-src

Prints the tool selection for win32-x64 and its dependency closure, and fails if the
upstream hooks the worker relies on have moved. Run this before building a new release.
"""
from __future__ import annotations

import importlib.util
import inspect
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKER = REPO / "factory/HermesAirgapFactoryAuto_v4/helpers/desktop_minimal_worker.py"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = Path(sys.argv[1]).resolve(strict=True)
    sys.path.insert(0, str(src))
    spec = importlib.util.spec_from_file_location("desktop_minimal_worker", WORKER)
    worker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(worker)

    from scripts.bundles import native  # noqa: E402  (upstream module)
    problems = []
    if "all_extras=True" not in inspect.getsource(native):
        problems.append("native.py no longer builds the venv with all_extras=True (extras hook may be dead)")
    if "_bundle_package_names()" not in inspect.getsource(native._prepare_native):
        problems.append("_prepare_native no longer calls _bundle_package_names() (tool hook may be dead)")
    from scripts.bundles import desktop_prepare
    if "prepare_native(" not in inspect.getsource(desktop_prepare.prepare_in_worker):
        problems.append("desktop_prepare.prepare_in_worker no longer calls prepare_native")

    worker.install_overrides(src / "apps/desktop/build/agent-payload/venv")
    from pm.registry import get_package, walk
    names = [n for n in native._bundle_package_names() if get_package(n).missing_reason("win32-x64") is None]
    closure = sorted(p.name for p in walk(names))
    print("selection (win32-x64):", names)
    print("dependency closure   :", closure)
    extra = sorted(set(closure) - set(worker.ALLOWLIST))
    if extra:
        problems.append(f"dependency closure pulls excluded packages: {extra}")
    for p in problems:
        print("PROBLEM:", p)
    print("OK" if not problems else "REVIEW NEEDED")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
