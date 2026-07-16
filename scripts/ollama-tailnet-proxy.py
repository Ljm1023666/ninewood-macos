#!/usr/bin/env python3
"""Rewrite Host to 127.0.0.1 for Tailscale Serve -> Ollama."""
import http.client
import logging
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 11434
LISTEN = ("127.0.0.1", 11435)

logging.basicConfig(
    filename="/tmp/ollama-tailnet-proxy.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 600

    def log_message(self, fmt, *args):
        logging.info("%s - %s", self.address_string(), fmt % args)

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def _proxy(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length) if length else None
        headers = {
            k: v
            for k, v in self.headers.items()
            if k.lower() not in ("host", "content-length", "connection", "transfer-encoding")
        }
        try:
            conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=600)
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            self.send_response(resp.status)
            for key, value in resp.getheaders():
                if key.lower() in ("transfer-encoding", "connection"):
                    continue
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if data:
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError, socket.timeout) as err:
            logging.warning("client disconnect: %s", err)
        except Exception as err:
            logging.exception("proxy error: %s", err)
            try:
                self.send_error(502, str(err))
            except Exception:
                pass
        finally:
            try:
                conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(LISTEN, Handler)
    logging.info("listening on %s:%s -> %s:%s", *LISTEN, UPSTREAM_HOST, UPSTREAM_PORT)
    server.serve_forever()
