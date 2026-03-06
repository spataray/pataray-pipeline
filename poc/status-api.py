#!/usr/bin/env python3
"""
FCB Status API — tiny local HTTP server for the pipeline dashboard.

Endpoints:
  GET  /status              pipeline state + all submissions
  POST /pipeline/start      start the watchdog
  POST /pipeline/stop       stop the watchdog
  POST /release/<filename>  move processing/ -> pending/ (un-stick)
  POST /retry/<filename>    move failed/     -> pending/ (retry)
"""

import json
import os
import shutil
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from pathlib import Path

PORT     = 7373
FCB_ROOT = Path(__file__).resolve().parent.parent
SUBS     = FCB_ROOT / "submissions"
PIDFILE  = FCB_ROOT / "poc" / "watchdog.pid"
PIPELINE = FCB_ROOT / "pipeline"

STATES        = ["processing", "pending", "failed", "completed"]
STATUS_FILE   = SUBS / "pipeline-status.json"


# ── helpers ────────────────────────────────────────────────────────────────

def load_pipeline_status():
    """Read the latest pipeline step/message written by watchdog."""
    try:
        return json.loads(STATUS_FILE.read_text())
    except Exception:
        return {}

def pipeline_state():
    """Return (running: bool, pid: int|None, start_epoch: int|None)."""
    if not PIDFILE.exists():
        return False, None, None
    try:
        pid = int(PIDFILE.read_text().strip())
        os.kill(pid, 0)          # raises if dead
        start_epoch = _proc_start(pid)
        return True, pid, start_epoch
    except (ValueError, ProcessLookupError, PermissionError):
        return False, None, None


def _proc_start(pid):
    try:
        stat    = Path(f"/proc/{pid}/stat").read_text().split()
        hz      = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        with open("/proc/stat") as f:
            btime = next(int(l.split()[1]) for l in f if l.startswith("btime"))
        return int(btime + int(stat[21]) / hz)
    except Exception:
        return None


def load_submissions():
    items = []
    for state in STATES:
        d = SUBS / state
        if not d.exists():
            continue
        for p in sorted(d.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True):
            if p.name == "reorder-codes.json":
                continue
            try:
                data  = json.loads(p.read_text())
                mtime = p.stat().st_mtime
                items.append({
                    "filename":     p.name,
                    "state":        state,
                    "email":        data.get("email", ""),
                    "niche":        data.get("niche", ""),
                    "request_type": data.get("request_type", ""),
                    "order_id":     data.get("order_id", ""),
                    "submitted_at": data.get("submitted_at", ""),
                    "mtime":        mtime,
                })
            except Exception:
                pass

    state_order = {s: i for i, s in enumerate(STATES)}
    items.sort(key=lambda x: (state_order.get(x["state"], 99), -x["mtime"]))
    return items


def move_submission(filename, src_state, dst_state):
    src = SUBS / src_state / filename
    if not src.exists():
        return False, f"not found in {src_state}/"
    dst_dir = SUBS / dst_state
    dst_dir.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dst_dir / filename))
    return True, "ok"


# ── HTTP handler ────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):

    def log_message(self, *_):
        pass  # suppress access logs

    def _json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type",                  "application/json")
        self.send_header("Content-Length",                str(len(body)))
        self.send_header("Access-Control-Allow-Origin",          "*")
        self.send_header("Access-Control-Allow-Methods",         "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers",         "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._json(200, {})

    def do_GET(self):
        if self.path != "/status":
            self._json(404, {"error": "not found"})
            return
        running, pid, start_time = pipeline_state()
        ps      = load_pipeline_status()
        subs    = load_submissions()
        # Attach live step/message to the matching submission
        if ps.get("order_id"):
            for s in subs:
                if s["order_id"] == ps["order_id"]:
                    s["pipeline_step"]    = ps.get("pipeline_step", 0)
                    s["pipeline_message"] = ps.get("pipeline_message", "")
                    break
        self._json(200, {
            "pipeline_running": running,
            "pid":              pid,
            "start_time":       start_time,
            "now":              int(time.time()),
            "submissions":      subs,
        })

    def do_POST(self):
        p = self.path

        if p == "/pipeline/start":
            running, _, _ = pipeline_state()
            if running:
                self._json(200, {"ok": False, "msg": "already running"})
            else:
                subprocess.Popen([str(PIPELINE), "start"])
                time.sleep(1.2)
                self._json(200, {"ok": True})

        elif p == "/pipeline/stop":
            running, _, _ = pipeline_state()
            if not running:
                self._json(200, {"ok": False, "msg": "not running"})
            else:
                subprocess.run([str(PIPELINE), "stop"], capture_output=True)
                self._json(200, {"ok": True})

        elif p.startswith("/release/"):
            filename = p[len("/release/"):]
            ok, msg  = move_submission(filename, "processing", "pending")
            self._json(200 if ok else 404, {"ok": ok, "msg": msg})

        elif p.startswith("/retry/"):
            filename = p[len("/retry/"):]
            ok, msg  = move_submission(filename, "failed", "pending")
            self._json(200 if ok else 404, {"ok": ok, "msg": msg})

        else:
            self._json(404, {"error": "not found"})


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True

if __name__ == "__main__":
    server = ThreadedHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"FCB Status API  http://127.0.0.1:{PORT}/status")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
