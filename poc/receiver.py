#!/usr/bin/env python3
"""
Local HTTP server for the Faceless AI Channel Builder POC.

- Serves landing-page.html on GET /
- Receives form submissions on POST /submit
- Writes each submission as a JSON file to submissions/pending/
- CORS enabled so the landing page can POST from file:// or GitHub Pages

Usage:
    python3 poc/receiver.py          # starts on port 8080
    python3 poc/receiver.py 9090     # custom port
"""

import json
import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PENDING = os.path.join(ROOT, "submissions", "pending")


class Handler(BaseHTTPRequestHandler):

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Accept")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            filepath = os.path.join(ROOT, "landing-page.html")
            if os.path.exists(filepath):
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                with open(filepath, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"landing-page.html not found")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path != "/submit":
            self.send_response(404)
            self.end_headers()
            return

        content_len = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_len).decode("utf-8")

        # Parse JSON or form-encoded
        content_type = self.headers.get("Content-Type", "")
        if "application/json" in content_type:
            data = json.loads(body)
        else:
            parsed = parse_qs(body)
            data = {k: v[0] if len(v) == 1 else v for k, v in parsed.items()}

        # Add metadata
        data["submitted_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
        data["status"] = "pending"

        # Determine request type based on form data
        niche = data.get("niche", "unknown")
        request_type = data.get("request_type", "full_channel_build")
        data["request_type"] = request_type

        # Write to pending folder
        timestamp = time.strftime("%Y%m%d-%H%M%S")
        safe_niche = niche.replace("/", "-").replace(" ", "_").lower()
        filename = f"{timestamp}_{safe_niche}.json"
        filepath = os.path.join(PENDING, filename)

        os.makedirs(PENDING, exist_ok=True)
        with open(filepath, "w") as f:
            json.dump(data, f, indent=2)

        print(f"[{data['submitted_at']}] New submission: {filename}")
        print(f"  Email: {data.get('email', '?')}")
        print(f"  Niche: {niche}")
        print(f"  Type:  {request_type}")

        # Respond
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.end_headers()
        self.wfile.write(json.dumps({
            "ok": True,
            "message": "Submission received",
            "id": filename
        }).encode())

    def log_message(self, format, *args):
        # Quieter logging
        pass


if __name__ == "__main__":
    os.makedirs(PENDING, exist_ok=True)
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"=== Faceless AI POC Receiver ===")
    print(f"Serving on http://localhost:{PORT}")
    print(f"Landing page: http://localhost:{PORT}/")
    print(f"Submissions go to: {PENDING}")
    print(f"Press Ctrl+C to stop\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()
