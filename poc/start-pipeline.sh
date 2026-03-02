#!/bin/bash
# ═══════════════════════════════════════════
# Faceless AI Channel Builder — Start All Services
#
# Starts the Google Sheets poller + watchdog as background processes.
# Run once after boot (or add to crontab with @reboot).
#
# Usage:
#   ./poc/start-pipeline.sh          # start services
#   ./poc/start-pipeline.sh stop     # stop services
# ═══════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PIDFILE_POLLER="$SCRIPT_DIR/poller.pid"
PIDFILE_WATCHDOG="$SCRIPT_DIR/watchdog.pid"

# Gmail creds from crontab
export GMAIL_USER="${GMAIL_USER:-spataray@gmail.com}"
export GMAIL_APP_PASSWORD="${GMAIL_APP_PASSWORD:-$(crontab -l 2>/dev/null | grep GMAIL_APP_PASSWORD | head -1 | cut -d= -f2)}"

cd "$PROJECT_ROOT"

stop_services() {
    echo "Stopping services..."
    for pidfile in "$PIDFILE_POLLER" "$PIDFILE_WATCHDOG"; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo "  Stopped PID $pid"
            fi
            rm -f "$pidfile"
        fi
    done
    echo "Done."
}

if [ "${1:-}" = "stop" ]; then
    stop_services
    exit 0
fi

# Stop any existing instances first
stop_services 2>/dev/null || true

echo "═══ Starting Faceless AI Channel Builder Services ═══"
echo ""

# Start poller (checks Google Sheet every 30s)
nohup python3 poc/poll-sheets.py --loop 30 >> poc/poller.log 2>&1 &
echo $! > "$PIDFILE_POLLER"
echo "Poller started (PID: $(cat "$PIDFILE_POLLER"))"
echo "  Log: poc/poller.log"

# Start watchdog (processes submissions)
nohup ./poc/watchdog.sh >> poc/watchdog.log 2>&1 &
echo $! > "$PIDFILE_WATCHDOG"
echo "Watchdog started (PID: $(cat "$PIDFILE_WATCHDOG"))"
echo "  Log: poc/watchdog.log"

echo ""
echo "Both services running. Submissions from GitHub Pages will be"
echo "processed automatically and emailed to the customer."
echo ""
echo "To stop: ./poc/start-pipeline.sh stop"
echo "To monitor: tail -f poc/watchdog.log"
