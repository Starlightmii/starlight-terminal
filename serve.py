#!/usr/bin/env python3
"""
Serve the Flutter web build and reverse-proxy /pi/* to the pi bridge.

Why a proxy instead of pointing the app straight at :5077:

* The public preview URL terminates TLS and forwards to exactly one port, so
  the app must reach the bridge through the same origin it was loaded from.
* A same-origin path avoids CORS entirely and keeps working when the preview
  hostname rotates.
* On Android the app talks to the bridge directly; this proxy is web-only.

Usage:  python3 serve.py [port] [build_dir]
"""

import http.server
import os
import socketserver
import sys
import urllib.error
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 5060
BUILD_DIR = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "build", "web"
)
BRIDGE = os.environ.get("PI_BRIDGE_ORIGIN", "http://127.0.0.1:5077")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def log_message(self, fmt, *args):
        # Keep the console readable: only report failures.
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "content-type,accept")
        self.send_header("X-Frame-Options", "ALLOWALL")
        self.send_header("Content-Security-Policy", "frame-ancestors *")

    def _proxy(self, method):
        path = self.path[len("/pi"):] or "/"
        url = BRIDGE + path
        body = None
        if method in ("POST", "DELETE"):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
        req = urllib.request.Request(url, data=body, method=method)
        if body is not None:
            req.add_header("Content-Type", "application/json")

        # Streaming responses (chat deltas) must reach the browser as they
        # arrive. Buffering with upstream.read() would hold every token until
        # the turn finished, which makes the PI terminal look dead. So: copy
        # the status line + headers through, then pump the body in chunks.
        upstream = None
        try:
            upstream = urllib.request.urlopen(req, timeout=300)
            self.send_response(upstream.status)
            self.send_header(
                "Content-Type",
                upstream.headers.get("Content-Type", "application/json"),
            )
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Accel-Buffering", "no")
            self._cors()
            if upstream.headers.get("Transfer-Encoding") is None:
                length = upstream.headers.get("Content-Length")
                if length is not None:
                    self.send_header("Content-Length", length)
            self.end_headers()
            while True:
                chunk = upstream.read(1024)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except urllib.error.HTTPError as e:
            payload = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self._cors()
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except Exception as e:  # bridge down / client went away
            msg = ('{"ok":false,"error":"pi bridge unreachable: %s"}'
                   % str(e).replace('"', "'"))
            data = msg.encode()
            try:
                self.send_response(503)
                self.send_header("Content-Type", "application/json")
                self._cors()
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            except Exception:
                pass  # the client already hung up mid-stream
        finally:
            if upstream is not None:
                try:
                    upstream.close()
                except Exception:
                    pass

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/pi/"):
            return self._proxy("GET")
        return super().do_GET()

    def do_POST(self):
        if self.path.startswith("/pi/"):
            return self._proxy("POST")
        self.send_error(404)

    def do_DELETE(self):
        if self.path.startswith("/pi/"):
            return self._proxy("DELETE")
        self.send_error(404)

    def end_headers(self):
        if not self.path.startswith("/pi/"):
            self._cors()
            # A rebuilt bundle must not be masked by a cached index.html.
            if self.path in ("/", "/index.html"):
                self.send_header("Cache-Control", "no-store")
        super().end_headers()


class Reuse(socketserver.ThreadingTCPServer):
    """Threaded, because the app polls /pi/*/events while a turn is in flight.

    A single-threaded TCPServer serialises every request: one long-poll would
    block asset loads, and a streaming prompt would block its own poll. Each
    connection now gets its own thread.
    """

    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    if not os.path.isdir(BUILD_DIR):
        sys.exit(f"build directory not found: {BUILD_DIR}")
    with Reuse(("0.0.0.0", PORT), Handler) as httpd:
        print(f"serving {BUILD_DIR} on :{PORT}  (proxy /pi -> {BRIDGE})", flush=True)
        httpd.serve_forever()
