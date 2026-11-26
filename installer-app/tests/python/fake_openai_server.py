"""Tiny OpenAI-compatible /v1/models server for helper tests. Requires Bearer test-key-123456."""
import json
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


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
