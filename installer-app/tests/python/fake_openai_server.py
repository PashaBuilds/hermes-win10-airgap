"""Tiny OpenAI-compatible /v1/models server for helper tests. Requires Bearer test-key-123456.

usage: fake_openai_server.py <port> [model,model,...]
HTTPS when FAKE_TLS_CERT and FAKE_TLS_KEY (PEM files) are set; used by the Windows e2e test to check
that Hermes trusts a "company" CA installed by the assistant."""
import json
import os
import ssl
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

KEY = "test-key-123456"
MODELS = sys.argv[2].split(",") if len(sys.argv) > 2 else ["model-a", "model-b"]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.rstrip("/") not in ("/v1/models", "/models"):
            self.send_response(404); self.end_headers(); return
        if self.headers.get("Authorization") != f"Bearer {KEY}":
            self.send_response(401); self.end_headers(); self.wfile.write(b'{"error":"unauthorized"}'); return
        body = json.dumps({"object": "list", "data": [{"id": m, "object": "model"} for m in MODELS]}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)


srv = HTTPServer(("127.0.0.1", int(sys.argv[1])), H)
if os.environ.get("FAKE_TLS_CERT") and os.environ.get("FAKE_TLS_KEY"):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.environ["FAKE_TLS_CERT"], os.environ["FAKE_TLS_KEY"])
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
