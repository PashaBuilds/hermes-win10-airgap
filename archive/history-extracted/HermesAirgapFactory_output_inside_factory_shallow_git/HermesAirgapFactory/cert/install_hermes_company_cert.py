#!/usr/bin/env python3
"""
install_hermes_company_cert.py

Run this script in the same folder as `my_company.crt`.

It creates %LOCALAPPDATA%\hermes\company-ca-bundle.pem by combining Hermes'
Python certifi CA bundle with your company certificate, then sets these User
environment variables:

  SSL_CERT_FILE
  REQUESTS_CA_BUNDLE
  CURL_CA_BUNDLE
  NODE_EXTRA_CA_CERTS

After running, close and reopen PowerShell/CMD.
"""

from __future__ import annotations

import ctypes
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

try:
    import winreg
except ImportError:  # non-Windows safety
    winreg = None

CERT_FILENAME = "my_company.crt"


def info(msg: str) -> None:
    print(f"[INFO] {msg}")


def warn(msg: str) -> None:
    print(f"[WARN] {msg}")


def fail(msg: str, code: int = 1) -> None:
    print(f"[ERROR] {msg}")
    sys.exit(code)


def find_certificate() -> Path:
    script_dir = Path(__file__).resolve().parent
    cwd = Path.cwd().resolve()
    for candidate in (script_dir / CERT_FILENAME, cwd / CERT_FILENAME):
        if candidate.exists():
            return candidate
    fail(
        f"Could not find {CERT_FILENAME} next to the script or in the current directory.\n"
        f"Script directory: {script_dir}\nCurrent directory: {cwd}"
    )


def validate_pem_certificate(cert_path: Path) -> str:
    text = cert_path.read_text(encoding="ascii", errors="ignore").strip()
    if "-----BEGIN CERTIFICATE-----" not in text or "-----END CERTIFICATE-----" not in text:
        fail(
            f"{cert_path} does not look like a PEM/Base64 certificate.\n"
            "Expected BEGIN CERTIFICATE and END CERTIFICATE."
        )
    return text + "\n"


def find_hermes_python() -> Path:
    localappdata = os.environ.get("LOCALAPPDATA")
    if not localappdata:
        fail("LOCALAPPDATA environment variable is not set.")

    candidates = [
        Path(localappdata) / "hermes" / "hermes-agent" / "venv" / "Scripts" / "python.exe",
        Path(localappdata) / "hermes" / "python311" / "python.exe",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate

    exe = Path(sys.executable).resolve()
    if exe.exists() and "hermes" in str(exe).lower():
        return exe

    fail(
        "Could not find Hermes Python. Expected one of:\n"
        + "\n".join(f"  - {c}" for c in candidates)
        + "\n\nMake sure Hermes is installed first."
    )


def run_python(hermes_py: Path, code: str) -> str:
    result = subprocess.run(
        [str(hermes_py), "-c", code],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        fail(
            "Failed to run Hermes Python.\n"
            f"Python: {hermes_py}\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return result.stdout.strip()


def get_certifi_bundle(hermes_py: Path) -> Path:
    output = run_python(hermes_py, "import certifi; print(certifi.where())")
    bundle = Path(output)
    if not bundle.exists():
        fail(f"certifi bundle path does not exist: {bundle}")
    return bundle


def make_combined_bundle(certifi_bundle: Path, company_cert_text: str) -> Path:
    localappdata = os.environ.get("LOCALAPPDATA")
    if not localappdata:
        fail("LOCALAPPDATA environment variable is not set.")

    hermes_home = Path(localappdata) / "hermes"
    hermes_home.mkdir(parents=True, exist_ok=True)
    combined = hermes_home / "company-ca-bundle.pem"

    certifi_text = certifi_bundle.read_text(encoding="ascii", errors="ignore")
    if combined.exists():
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        backup = combined.with_name(f"{combined.stem}_backup_{timestamp}{combined.suffix}")
        shutil.copy2(combined, backup)
        info(f"Existing combined bundle backed up to: {backup}")

    if company_cert_text.strip() in certifi_text:
        final_text = certifi_text.rstrip() + "\n"
        warn("Company certificate already appears to be inside certifi bundle.")
    else:
        final_text = certifi_text.rstrip() + "\n\n" + company_cert_text.strip() + "\n"

    combined.write_text(final_text, encoding="ascii")
    return combined


def set_user_env(name: str, value: str) -> None:
    if os.name != "nt":
        warn(f"Not Windows; setting {name} only for this process.")
        os.environ[name] = value
        return
    if winreg is None:
        fail("winreg is not available; cannot set Windows User environment variables.")
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment", 0, winreg.KEY_SET_VALUE) as key:
        winreg.SetValueEx(key, name, 0, winreg.REG_EXPAND_SZ, value)
    os.environ[name] = value
    info(f"Set User env: {name}={value}")


def broadcast_environment_change() -> None:
    if os.name != "nt":
        return
    HWND_BROADCAST = 0xFFFF
    WM_SETTINGCHANGE = 0x001A
    SMTO_ABORTIFHUNG = 0x0002
    try:
        ctypes.windll.user32.SendMessageTimeoutW(
            HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", SMTO_ABORTIFHUNG, 5000, None
        )
        info("Broadcasted Windows environment change notification.")
    except Exception as exc:
        warn(f"Could not broadcast environment change notification: {exc}")


def test_hermes_python_ssl(hermes_py: Path, combined_bundle: Path) -> None:
    code = """
import os, ssl, certifi, sys
print('Python:', sys.executable)
print('SSL_CERT_FILE:', os.environ.get('SSL_CERT_FILE'))
print('REQUESTS_CA_BUNDLE:', os.environ.get('REQUESTS_CA_BUNDLE'))
print('certifi:', certifi.where())
print('OpenSSL:', ssl.OPENSSL_VERSION)
"""
    env = os.environ.copy()
    env["SSL_CERT_FILE"] = str(combined_bundle)
    env["REQUESTS_CA_BUNDLE"] = str(combined_bundle)
    env["CURL_CA_BUNDLE"] = str(combined_bundle)
    result = subprocess.run([str(hermes_py), "-c", code], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    print("\n[Hermes Python SSL environment test]")
    print(result.stdout)
    if result.stderr.strip():
        print(result.stderr)


def main() -> None:
    print("=" * 72)
    print("Hermes company certificate installer")
    print("=" * 72)

    cert_path = find_certificate()
    info(f"Certificate found: {cert_path}")
    company_cert_text = validate_pem_certificate(cert_path)
    info("Certificate format looks valid: PEM/Base64")

    hermes_py = find_hermes_python()
    info(f"Hermes Python: {hermes_py}")
    py_version = run_python(hermes_py, "import sys; print(sys.version)")
    info(f"Hermes Python version: {py_version.splitlines()[0]}")

    certifi_bundle = get_certifi_bundle(hermes_py)
    info(f"Hermes certifi bundle: {certifi_bundle}")

    combined_bundle = make_combined_bundle(certifi_bundle, company_cert_text)
    info(f"Combined CA bundle written to: {combined_bundle}")

    set_user_env("SSL_CERT_FILE", str(combined_bundle))
    set_user_env("REQUESTS_CA_BUNDLE", str(combined_bundle))
    set_user_env("CURL_CA_BUNDLE", str(combined_bundle))
    set_user_env("NODE_EXTRA_CA_CERTS", str(cert_path))

    broadcast_environment_change()
    test_hermes_python_ssl(hermes_py, combined_bundle)

    print("=" * 72)
    print("Done. Close and reopen PowerShell/CMD, then test Hermes again.")
    print("PowerShell checks:")
    print("  echo $env:SSL_CERT_FILE")
    print("  Test-Path $env:SSL_CERT_FILE")
    print("  hermes chat")
    print("=" * 72)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        fail("Cancelled by user.", code=130)
