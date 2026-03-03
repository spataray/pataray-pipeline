#!/usr/bin/env python3
"""
Faceless AI Channel Builder — Google Sheets Poller

Polls a published Google Sheet CSV for new submissions and drops
JSON files into submissions/pending/ for the watchdog to process.

Usage:
    python3 poc/poll-sheets.py              # run once
    python3 poc/poll-sheets.py --loop       # poll every 60s
    python3 poc/poll-sheets.py --loop 30    # poll every 30s

Setup:
    1. Publish your Google Sheet to web as CSV (File > Share > Publish to web)
    2. Set the SHEET_CSV_URL below to your published CSV URL
    3. Run this script — it tracks processed rows in poc/processed-rows.txt
"""

import csv
import io
import json
import os
import sys
import time
import urllib.request

# ═══════════════════════════════════════════
# CONFIGURE THIS — your published sheet CSV URL
# ═══════════════════════════════════════════
SHEET_CSV_URL = os.environ.get(
    "SHEET_CSV_URL",
    "https://docs.google.com/spreadsheets/d/e/2PACX-1vRYU9VtD1QwCdGQ-e1HpkuF1PRLhFjY3oUMZUw-NYiM-lSnba_KStUnj7gkDEf8IgSeHS-1V4ehwTYJ/pub?gid=0&single=true&output=csv"
)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
PENDING_DIR = os.path.join(PROJECT_ROOT, "submissions", "pending")
PROCESSED_FILE = os.path.join(SCRIPT_DIR, "processed-rows.txt")


def load_processed():
    """Load set of already-processed row keys."""
    if not os.path.exists(PROCESSED_FILE):
        return set()
    with open(PROCESSED_FILE) as f:
        return set(line.strip() for line in f if line.strip())


def save_processed(keys):
    """Save processed row keys."""
    with open(PROCESSED_FILE, "w") as f:
        for k in sorted(keys):
            f.write(k + "\n")


def row_key(row):
    """Unique key for a row: timestamp + email."""
    return f"{row.get('timestamp', '')}|{row.get('email', '')}"


def fetch_sheet():
    """Fetch and parse the published CSV."""
    if "PASTE_YOUR" in SHEET_CSV_URL:
        print("ERROR: Set SHEET_CSV_URL in poll-sheets.py or as env var.")
        print("Publish your Google Sheet as CSV and paste the URL.")
        sys.exit(1)

    req = urllib.request.Request(SHEET_CSV_URL, headers={"User-Agent": "Faceless AIPoller/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        text = resp.read().decode("utf-8")

    reader = csv.DictReader(io.StringIO(text))
    rows = []
    for r in reader:
        # Normalize header names (strip whitespace, lowercase)
        cleaned = {}
        for k, v in r.items():
            if k:
                cleaned[k.strip().lower()] = (v or "").strip()
        rows.append(cleaned)
    return rows


def create_submission(row):
    """Write a JSON file to submissions/pending/."""
    os.makedirs(PENDING_DIR, exist_ok=True)

    ts = row.get("timestamp", "")
    email = row.get("email", "")
    niche = row.get("niche", "")
    channel_status = row.get("channel_status", "")
    request_type = row.get("request_type", "full_channel_build")
    status = row.get("status", "pending")
    order_id = row.get("order_id", "")
    reorder_code = row.get("reorder_code", "")

    # Only process pending rows
    if status.lower() != "pending":
        return None

    # Build filename
    file_ts = time.strftime("%Y%m%d-%H%M%S")
    safe_niche = niche.replace("/", "-").replace(" ", "_").lower()
    filename = f"{file_ts}_{safe_niche}.json"
    filepath = os.path.join(PENDING_DIR, filename)

    data = {
        "email": email,
        "niche": niche,
        "channel_status": channel_status,
        "request_type": request_type,
        "submitted_at": ts,
        "status": "pending",
        "source": "google_sheets",
        "order_id": order_id,
    }
    if reorder_code:
        data["reorder_code"] = reorder_code

    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)

    return filename


def poll_once():
    """Check sheet for new submissions."""
    processed = load_processed()
    rows = fetch_sheet()
    new_count = 0

    for row in rows:
        key = row_key(row)
        if key in processed:
            continue
        if not row.get("email"):
            continue

        filename = create_submission(row)
        if filename:
            print(f"  New: {row.get('email')} — {row.get('niche')} → {filename}")
            new_count += 1

        processed.add(key)

    save_processed(processed)
    return new_count


def main():
    loop = "--loop" in sys.argv
    interval = 60
    for i, arg in enumerate(sys.argv):
        if arg == "--loop" and i + 1 < len(sys.argv):
            try:
                interval = int(sys.argv[i + 1])
            except ValueError:
                pass

    print("═══ Faceless AI Sheets Poller ═══")
    print(f"Sheet: {SHEET_CSV_URL[:60]}...")
    print(f"Pending dir: {PENDING_DIR}")
    if loop:
        print(f"Polling every {interval}s (Ctrl+C to stop)\n")
    else:
        print("Single poll\n")

    while True:
        ts = time.strftime("%H:%M:%S")
        try:
            new = poll_once()
            if new:
                print(f"[{ts}] Found {new} new submission(s)")
            else:
                print(f"[{ts}] No new submissions")
        except Exception as e:
            print(f"[{ts}] Error: {e}")

        if not loop:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
