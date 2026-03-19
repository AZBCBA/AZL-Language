#!/usr/bin/env python3
"""
Minimal AZL package registry HTTP server.
Serves .azlpack tarballs from a local directory.
GET /<name>/<version> returns tarball; GET /<name>/latest uses latest.
"""
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

DIR = os.environ.get("AZL_REGISTRY_DIR", ".azl/packages")
PORT = int(os.environ.get("AZL_REGISTRY_PORT", "8765"))
HOST = os.environ.get("AZL_REGISTRY_HOST", "127.0.0.1")


class RegistryHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.strip("/")
        parts = path.split("/")
        if not parts or not parts[0]:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"AZL Registry. GET /<name>/<version> or /<name>/latest\n")
            return
        name = parts[0]
        ver = parts[1] if len(parts) > 1 else "latest"
        pkg_dir = os.path.join(DIR, name)
        if not os.path.isdir(pkg_dir):
            self.send_error(404, f"Package {name} not found")
            return
        if ver == "latest":
            vers = sorted(os.listdir(pkg_dir))
            ver = vers[-1] if vers else ""
        tarball = os.path.join(pkg_dir, ver, "pkg.tar.gz")
        if not os.path.isfile(tarball):
            tarball = os.path.join(pkg_dir, ver + ".tar.gz")
        if not os.path.isfile(tarball):
            self.send_error(404, f"Version {ver} not found")
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/gzip")
        self.send_header("Content-Disposition", f"attachment; filename={name}-{ver}.azlpack")
        self.end_headers()
        with open(tarball, "rb") as f:
            self.wfile.write(f.read())

    def log_message(self, fmt, *args):
        sys.stderr.write(f"{self.log_date_time_string()} {fmt % args}\n")


def main():
    os.makedirs(DIR, exist_ok=True)
    print(f"AZL Registry: http://{HOST}:{PORT} -> {os.path.abspath(DIR)}")
    print("GET /<name>/<version> or /<name>/latest")
    server = HTTPServer((HOST, PORT), RegistryHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
