#!/usr/bin/env python3
"""Tiny Strata stand-in for screenshots.

Usage: tools/mock-server.py [loaded] [fixture] [port]
  loaded   true | false      what /health reports (default false)
  fixture  metrics_idle      which /metrics fixture to serve (default metrics_idle)
  port     8099              what port to listen on (default 8099)
"""
import json, pathlib, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

root = pathlib.Path("Packages/StrataCore/Tests/StrataCoreTests/Fixtures")
loaded = (sys.argv[1] if len(sys.argv) > 1 else "false") == "true"
fixture = sys.argv[2] if len(sys.argv) > 2 else "metrics_idle"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            body = json.dumps({
                "status": "ok", "max_context": 262144,
                "model": "qwen3.8-flash-next-iq3_xxs", "images": True,
                "api_key": True, "loaded": loaded, "service": "strata",
            }).encode()
        elif path == "/metrics":
            body = (root / f"{fixture}.json").read_bytes()
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


port = int(sys.argv[3]) if len(sys.argv) > 3 else 8099
print(f"mock strata on 127.0.0.1:{port} ({fixture}.json, loaded={loaded})")
HTTPServer(("127.0.0.1", port), Handler).serve_forever()
