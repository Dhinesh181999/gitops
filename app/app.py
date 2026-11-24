"""Storefront sample service (standard library only).

Endpoints
  /          JSON: version, environment, fingerprint of the mounted secret
  /healthz   liveness/readiness
  /metrics   Prometheus text format
Behaviour toggles (env vars, set from Git via the overlays)
  ERROR_RATE  0.0-1.0  fraction of "/" requests answered with HTTP 500
"""
import hashlib
import json
import os
import random
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.getenv("APP_VERSION", "dev")
ENV_NAME = os.getenv("APP_ENV", "local")
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
SECRET_FILE = os.getenv("SECRET_FILE", "/etc/storefront/secrets/PAYMENT_API_KEY")

_lock = threading.Lock()
_counts = {}


def count(code):
    with _lock:
        _counts[code] = _counts.get(code, 0) + 1


def secret_fingerprint():
    """Return a short hash, never the secret itself, so a rotation is visible.
    The file is re-read on every request: kubelet refreshes mounted Secrets,
    so rotation needs no pod restart."""
    try:
        with open(SECRET_FILE, "rb") as f:
            return hashlib.sha256(f.read().strip()).hexdigest()[:8]
    except OSError:
        return "unset"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            return self._send(200, "ok", "text/plain")
        if self.path == "/metrics":
            with _lock:
                lines = ["# TYPE storefront_http_requests_total counter"]
                lines += [f'storefront_http_requests_total{{code="{c}"}} {n}' for c, n in _counts.items()]
            lines.append(f'storefront_app_info{{version="{VERSION}",env="{ENV_NAME}"}} 1')
            return self._send(200, "\n".join(lines) + "\n", "text/plain")
        if random.random() < ERROR_RATE:
            count(500)
            return self._send(500, json.dumps({"error": "injected failure", "version": VERSION}))
        count(200)
        self._send(200, json.dumps({
            "version": VERSION,
            "env": ENV_NAME,
            "secret_fingerprint": secret_fingerprint(),
            "pod": os.getenv("HOSTNAME", "?"),
        }))

    def log_message(self, *args):  # keep logs quiet
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
