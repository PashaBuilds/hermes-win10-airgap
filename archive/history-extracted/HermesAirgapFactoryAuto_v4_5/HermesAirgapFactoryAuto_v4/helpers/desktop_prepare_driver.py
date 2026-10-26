"""Invoke the official Desktop CLI with a scoped, external preparation worker.

Used only with -Profile Slim -DesktopVariant bundled.  The Hermes checkout
remains byte-for-byte unmodified so upstream commit/cleanliness verification
runs normally. Other preparation/build paths use upstream code unchanged.
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 5:
        raise SystemExit("Usage: desktop_prepare_driver.py SOURCE WORKER --tag ... --prepare-only")
    source = Path(sys.argv[1]).resolve(strict=True)
    worker = Path(sys.argv[2]).resolve(strict=True)
    expected = source / "scripts" / "bundles" / "desktop.py"
    if not expected.is_file():
        raise FileNotFoundError(f"Hermes desktop.py missing: {expected}")
    if not worker.is_file():
        raise FileNotFoundError(f"Slim Desktop preparation worker missing: {worker}")
    if "--prepare-only" not in sys.argv[3:]:
        raise ValueError("Slim preparation driver is for --prepare-only, never packaging")
    sys.path.insert(0, str(source))
    from scripts.bundles import desktop_toolchain

    original_run_preparation = desktop_toolchain.run_preparation

    def scoped_run_preparation(repo, work, cache, request_file, *, worker=None):
        if worker is not None:
            raise ValueError("Conflicting desktop preparation worker")
        print("[H4.4] Selecting a clean-source Slim Desktop preparation worker", flush=True)
        return original_run_preparation(repo, work, cache, request_file, worker=worker_path)

    worker_path = worker
    desktop_toolchain.run_preparation = scoped_run_preparation
    sys.argv = [str(expected), *sys.argv[3:]]
    from scripts.bundles.desktop import main as official_main
    official_main()


if __name__ == "__main__":
    main()
