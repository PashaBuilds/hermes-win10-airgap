from __future__ import annotations
import os, sys, shutil, subprocess, time
from pathlib import Path

CERT_FILENAME = "my_company.crt"

def fail(msg):
    print("[ERROR]", msg)
    sys.exit(1)

def find_cert():
    for p in [Path(__file__).resolve().parent / CERT_FILENAME, Path.cwd() / CERT_FILENAME]:
        if p.exists():
            return p
    fail(f"Could not find {CERT_FILENAME} next to this script or in current directory.")

def find_hermes_py():
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        fail("LOCALAPPDATA is not set.")
    candidates = [
        Path(local) / "hermes" / "hermes-agent" / "venv" / "Scripts" / "python.exe",
        Path(local) / "hermes" / "python311" / "python.exe",
    ]
    for c in candidates:
        if c.exists():
            return c
    fail("Could not find Hermes Python. Install Hermes first.")

def run(py, code):
    r = subprocess.run([str(py), "-c", code], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        fail(r.stderr or r.stdout)
    return r.stdout.strip()

cert = find_cert()
text = cert.read_text(encoding="ascii", errors="ignore").strip()
if "-----BEGIN CERTIFICATE-----" not in text:
    fail(f"{cert} does not look like PEM/Base64 certificate.")

py = find_hermes_py()
certifi_path = Path(run(py, "import certifi; print(certifi.where())"))
local = Path(os.environ["LOCALAPPDATA"])
hermes_home = local / "hermes"
hermes_home.mkdir(parents=True, exist_ok=True)
combined = hermes_home / "company-ca-bundle.pem"

if combined.exists():
    backup = combined.with_name(f"company-ca-bundle_backup_{time.strftime('%Y%m%d_%H%M%S')}.pem")
    shutil.copy2(combined, backup)
    print("[INFO] Backup:", backup)

combined.write_text(certifi_path.read_text(encoding="ascii", errors="ignore").rstrip() + "\n\n" + text + "\n", encoding="ascii")

# Set user env vars using setx, good enough for next shells.
for k, v in {
    "SSL_CERT_FILE": str(combined),
    "REQUESTS_CA_BUNDLE": str(combined),
    "CURL_CA_BUNDLE": str(combined),
    "NODE_EXTRA_CA_CERTS": str(cert),
}.items():
    subprocess.run(["setx", k, v], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.environ[k] = v
    print("[INFO]", k, "=", v)

print("[INFO] Done. Close and reopen PowerShell/CMD, then test Hermes.")
