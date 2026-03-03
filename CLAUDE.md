# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Faceless AI Channel Builder (FCB) — an automated pipeline that creates complete YouTube channel packages (niche research, blueprints, video scripts, thumbnails, engagement content) using multi-agent Claude CLI calls. Orders come in via a landing page, flow through Google Sheets, and get processed by a bash-orchestrated pipeline that delivers HTML/TXT files by email.

## Running the Pipeline

```bash
# CLI management (recommended)
./pipeline start              # start watchdog + poller in background
./pipeline start -f           # foreground mode
./pipeline stop
./pipeline restart
./pipeline status
./pipeline logs               # tail watchdog.log

# Alternative: direct boot script
./poc/start-pipeline.sh       # start both services
./poc/start-pipeline.sh stop  # stop both

# Test submission (bypasses Google Sheets)
./poc/submit-test.sh "user@example.com" "Horror / Supernatural" full_channel_build
```

## Configuration

1. Copy `poc/config.env.example` → `poc/config.env` and set Gmail SMTP credentials (requires 2FA app password)
2. Set `SHEET_CSV_URL` in both `poc/poll-sheets.py` and `poc/watchdog.sh`
3. Set `APPS_SCRIPT_URL` in `index.html` for the frontend to poll status

## Architecture

**Order Flow:**
```
index.html (GitHub Pages) → Google Apps Script → Google Sheet
    → poll-sheets.py (every 30s) → submissions/pending/*.json
    → watchdog.sh (every 30s) → Claude CLI agents → send-email.py → customer
```

**Pipeline Stages (watchdog.sh):**
1. Niche Research (sonnet)
2. Channel Blueprint (sonnet)
3. 3 Video Scripts — **parallel** (sonnet, 3 concurrent calls)
4. Thumbnail Guide — **parallel with step 5** (sonnet)
5. Pinned Comments — **parallel with step 4** (haiku)
6. Getting Started Guide (haiku)

Each stage invokes `claude --model sonnet|haiku` with specific system prompts and `--allowedTools` for read/write/web search. Output goes to `submissions/completed/{order_id}_output/`.

**Three request types:** `full_channel_build`, `niche_research`, `reorder_scripts`. The reorder system lets returning customers get new scripts matching their original channel voice using 6-char codes stored in `submissions/reorder-codes.json`.

**Real-time status tracking:** watchdog.sh posts step updates to Google Apps Script, which the frontend polls every 5 seconds to animate a 6-station pipeline UI.

## Key Files

| File | Role |
|------|------|
| `poc/watchdog.sh` | Main pipeline orchestrator (~645 lines), all Claude agent prompts and parallelization logic |
| `index.html` | Landing page + animated pipeline status overlay (~1250 lines, vanilla JS) |
| `pipeline` | Bash CLI wrapper for start/stop/status/logs/restart |
| `poc/send-email.py` | HTML email assembly with attachments |
| `poc/poll-sheets.py` | Google Sheets CSV poller, creates JSON in pending/ |
| `poc/google-apps-script.js` | Google Sheets webhook (doPost/doGet for submit/status) |
| `poc/receiver.py` | Local HTTP server alternative to Google Sheets |

## Submission State Machine

JSON files move through directories: `submissions/pending/` → `submissions/processing/` → `submissions/completed/` or `submissions/failed/`

## Tech Stack

- **Frontend:** Vanilla HTML/CSS/JS (dark theme, no frameworks), deployed to GitHub Pages
- **Backend:** Bash (orchestration), Python 3 (polling, email, HTTP receiver)
- **AI:** Claude CLI (`claude --model sonnet` for heavy work, `--model haiku` for lighter tasks)
- **Infra:** Google Sheets + Apps Script (order tracking), Gmail SMTP (delivery)

## Style Conventions

- All HTML deliverables use self-contained dark theme with inline styles (no external CSS)
- Claude agent prompts are embedded directly in watchdog.sh heredocs
- Pipeline status messages use format: "Step N/6: Description"
