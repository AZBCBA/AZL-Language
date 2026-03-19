#!/usr/bin/env python3
"""Minimal HTTP server for AZL vs Python benchmark comparison.
Uses only stdlib. Serves /healthz, /status, /api/exec_state.
"""
import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("BENCH_PYTHON_PORT", "31999"))
TOKEN = os.environ.get("BENCH_PYTHON_TOKEN", "azl_bench_token_2026")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, status, body):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/healthz":
            self.send_json(200, {"ok": True, "service": "python-bench-server"})
        elif path == "/status":
            self.send_json(200, {
                "status": "ok",
                "engine": "python",
                "uptime_sec": 0,
                "requests_total": 0,
            })
        elif path == "/api/exec_state":
            auth = self.headers.get("Authorization", "")
            if auth != f"Bearer {TOKEN}":
                self.send_response(401)
                self.end_headers()
                return
            self.send_json(200, {"ok": True, "running": True, "pid": os.getpid()})
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        self.do_GET()


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    sys.exit(0)
