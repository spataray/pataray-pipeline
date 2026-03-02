# Faceless AI Channel Builder

AI-powered YouTube channel builder. Pick a niche, get a complete channel package delivered to your inbox.

## Live Demo

Visit the GitHub Pages URL to try it out.

## How It Works

1. You pick a niche and submit the form
2. The animated pipeline shows your request being processed
3. Behind the scenes, AI agents research your niche, build a channel blueprint, and write A+ scripts
4. Everything gets emailed to you as a professional HTML package

## What You Get

| File | Format | Description |
|------|--------|-------------|
| Getting Started Guide | HTML | Step-by-step instructions for your first video |
| Niche Research Report | HTML | CPM data, competition analysis, video ideas |
| Channel Blueprint | HTML | Name, brand, audience, 30-day calendar |
| 3 Video Scripts | TXT | Ready for Pictory AI, InVideo, or CapCut |
| Thumbnail Guide | HTML | AI prompts + Canva walkthrough |
| Pinned Comments | HTML | Copy-paste engagement comments |

## Architecture

```
Browser (GitHub Pages)
    -> Google Apps Script -> Google Sheet
    -> Local poller picks up new rows
    -> Watchdog triggers AI pipeline (claude CLI)
    -> Results emailed to customer via Gmail
```

## Running Locally

```bash
# Start both poller + watchdog
./poc/start-pipeline.sh

# Monitor
tail -f poc/watchdog.log

# Stop
./poc/start-pipeline.sh stop
```

Built by a creator, for creators.
