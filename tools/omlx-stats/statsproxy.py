"""Tiny read-only stats proxy for oMLX.

Serves omlx-stats.html and forwards a whitelist of GET endpoints to the local
oMLX server, adding the API key server-side so the browser never needs it.
The /admin/api/stats response has its api_key field removed.

Also tails oMLX's server.log for `Chat completion:` lines and serves them as
/admin/api/recent: a small ring of finished requests (model, prompt/output
tokens, duration, speed, finish reason, TTFT, context used/window). The log is
read incrementally, so the cost is only the appended bytes; no extra requests
hit the engine. Model context windows come from /admin/api/models, refreshed
once a minute.
"""
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(HERE, "omlx-stats.html")
UPSTREAM = "http://127.0.0.1:8000"
ALLOWED = {"/admin/api/activity", "/admin/api/stats", "/health"}
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8001

HOME = os.path.expanduser("~")
SETTINGS = os.path.join(HOME, ".omlx", "settings.json")
LOG_DIR = os.path.join(HOME, ".omlx", "logs")
LOG_PATH = os.path.join(LOG_DIR, "server.log")

RECENT_LIMIT = 20
SEED_BYTES = 256 * 1024
MODELS_REFRESH_S = 60

# `Chat completion: model=X, N tokens in Ds (T tok/s), prompt: P,
#  finish_reason=R, max_tokens=M, request_max_tokens=RM, stream_model_ttft=Ss`
COMPLETION = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) .*?Chat completion: "
    r"model=(?P<model>[^,]+), (?P<out>\d+) tokens in (?P<dur>[\d.]+)s "
    r"\((?P<tps>[\d.]+) tok/s\), prompt: (?P<prompt>\d+), "
    r"finish_reason=(?P<finish>\w+), max_tokens=(?P<max>\d+), "
    r"request_max_tokens=(?P<rmax>\d+), stream_model_ttft=(?P<ttft>[\d.]+)s"
)


def api_key() -> str:
    with open(SETTINGS) as f:
        return json.load(f)["auth"]["api_key"]


def epoch(ts: str) -> float:
    # "YYYY-MM-DD HH:MM:SS,mmm" in local time.
    import datetime
    return datetime.datetime.strptime(ts, "%Y-%m-%d %H:%M:%S,%f").timestamp()


class Recorder:
    """A ring of finished requests, read from the tail of server.log."""

    def __init__(self):
        self._lock = threading.Lock()
        self._recent: list[dict] = []
        self._windows: dict[str, int] = {}
        self._models_at = 0.0
        self._slots = 0
        self._offset = 0
        self._carry = ""
        self._inode = None

    # MARK: models

    def _refresh_models(self):
        if time.time() - self._models_at < MODELS_REFRESH_S:
            return
        self._models_at = time.time()
        self._refresh_slots()
        req = urllib.request.Request(
            UPSTREAM + "/admin/api/models",
            headers={"Authorization": "Bearer " + api_key()},
        )
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                data = json.loads(r.read())
        except Exception:  # noqa: BLE001
            return
        windows = {}
        for model in data.get("models") or []:
            length = model.get("model_context_length")
            if isinstance(length, int) and length > 0:
                windows[model.get("id", "")] = length
        if windows:
            with self._lock:
                self._windows = windows

    def _refresh_slots(self):
        """How many requests the engine runs side by side (`scheduler.max_concurrent_requests`)."""
        try:
            with open(SETTINGS) as f:
                data = json.load(f)
            count = (data.get("scheduler") or {}).get("max_concurrent_requests")
        except Exception:  # noqa: BLE001
            return
        if isinstance(count, int) and count > 0:
            with self._lock:
                self._slots = count

    # MARK: log tail

    def _seed(self):
        try:
            with open(LOG_PATH, "rb") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                start = max(0, size - SEED_BYTES)
                f.seek(start)
                chunk = f.read(size - start)
        except OSError:
            return
        self._offset = size
        self._inode = self._stat_inode()
        lines = chunk.decode("utf-8", "replace").splitlines()
        # Only complete lines; a trailing partial is carried into the next read.
        if chunk and not chunk.endswith(b"\n"):
            self._carry = lines.pop() if lines else chunk.decode("utf-8", "replace")
        for line in lines:
            self._parse(line)
        self._trim()

    def _stat_inode(self):
        try:
            return os.stat(LOG_PATH).st_ino
        except OSError:
            return None

    def _parse(self, line: str):
        m = COMPLETION.search(line)
        if not m:
            return
        g = m.groupdict()
        prompt = int(g["prompt"])
        out = int(g["out"])
        with self._lock:
            window = self._windows.get(g["model"])
            self._recent.append({
                "finished_at": int(epoch(g["ts"])),
                "model": g["model"],
                "prompt_tokens": prompt,
                "output_tokens": out,
                "duration_s": float(g["dur"]),
                "tok_s": float(g["tps"]),
                "finish": g["finish"],
                "max_tokens": int(g["max"]),
                "request_max_tokens": int(g["rmax"]),
                "ttft_s": float(g["ttft"]),
                "context_used": prompt + out,
                "context_window": window,
            })

    def _trim(self):
        with self._lock:
            self._recent = self._recent[-RECENT_LIMIT:]

    def _follow(self):
        inode = self._stat_inode()
        if inode is not None and self._inode is not None and inode != self._inode:
            # Rotated: the old lines are gone, start the new file from the top.
            self._inode = inode
            self._offset = 0
            self._carry = ""
        try:
            size = os.path.getsize(LOG_PATH)
        except OSError:
            return
        if size < self._offset:
            self._offset = 0
            self._carry = ""
        if size <= self._offset:
            return
        try:
            with open(LOG_PATH, "rb") as f:
                f.seek(self._offset)
                chunk = f.read(size - self._offset)
        except OSError:
            return
        self._offset = size
        text = self._carry + chunk.decode("utf-8", "replace")
        lines = text.splitlines()
        if text and not text.endswith("\n"):
            self._carry = lines.pop() if lines else text
        else:
            self._carry = ""
        for line in lines:
            self._parse(line)
        self._trim()

    def run(self):
        self._refresh_models()
        self._seed()
        while True:
            time.sleep(1.0)
            try:
                self._refresh_models()
                self._follow()
            except Exception:  # noqa: BLE001
                # The recorder is best-effort: a bad read never takes the proxy down.
                time.sleep(2.0)

    def payload(self) -> dict:
        with self._lock:
            recent = list(reversed(self._recent))
            windows = dict(self._windows)
            slots = self._slots
        return {
            "requests": recent,
            "windows": windows,
            "slots": slots,
            "generated_at": int(time.time()),
        }


recorder = Recorder()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep quiet
        pass

    def _cors(self):
        # Read-only stats, no credentials: any origin may read them.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Max-Age", "600")

    def _send(self, code: int, body: bytes, ctype: str = "application/json"):
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            with open(PAGE, "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if path == "/admin/api/recent":
            return self._send(200, json.dumps(recorder.payload()).encode())
        if path not in ALLOWED:
            return self._send(404, b'{"error":"not found"}')
        req = urllib.request.Request(UPSTREAM + path, headers={"Authorization": "Bearer " + api_key()})
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                body = r.read()
                code = r.status
        except urllib.error.HTTPError as e:
            body, code = e.read(), e.code
        except Exception as e:  # noqa: BLE001
            return self._send(502, json.dumps({"error": f"oMLX unreachable: {e}"}).encode())
        if path == "/admin/api/stats":
            try:
                data = json.loads(body)
                data.pop("api_key", None)
                body = json.dumps(data).encode()
            except ValueError:
                pass
        return self._send(code, body)


if __name__ == "__main__":
    threading.Thread(target=recorder.run, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
