import hashlib
import json
import os
import random
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


VERSION = os.getenv("APP_VERSION", "dev")
ENV_NAME = os.getenv("APP_ENV", "local")
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
SECRET_FILE = os.getenv("SECRET_FILE", "/etc/demo-api/secrets/DEMO_API_KEY")

_lock = threading.Lock()
_counts = {}


def count(code):
    with _lock:
        _counts[code] = _counts.get(code, 0) + 1


def secret_fingerprint():
    try:
        with open(SECRET_FILE, "rb") as secret:
            return hashlib.sha256(secret.read().strip()).hexdigest()[:8]
    except OSError:
        return "unset"


class Handler(BaseHTTPRequestHandler):
    def respond(self, code, body, content_type="application/json"):
        payload = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/healthz":
            return self.respond(200, "ok", "text/plain")
        if self.path == "/metrics":
            with _lock:
                lines = ["# TYPE demo_api_http_requests_total counter"]
                lines.extend(
                    f'demo_api_http_requests_total{{code="{code}"}} {total}'
                    for code, total in _counts.items()
                )
            lines.append(
                f'demo_api_info{{version="{VERSION}",env="{ENV_NAME}"}} 1'
            )
            return self.respond(200, "\n".join(lines) + "\n", "text/plain")
        if self.path != "/":
            return self.respond(404, json.dumps({"error": "not found"}))
        if random.random() < ERROR_RATE:
            count(500)
            return self.respond(
                500, json.dumps({"error": "injected failure", "version": VERSION})
            )
        count(200)
        return self.respond(
            200,
            json.dumps(
                {
                    "version": VERSION,
                    "environment": ENV_NAME,
                    "secret_fingerprint": secret_fingerprint(),
                    "pod": os.getenv("HOSTNAME", "unknown"),
                }
            ),
        )

    def log_message(self, *_args):
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
