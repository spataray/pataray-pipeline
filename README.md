# Pataray Pipeline — Faceless AI Channel Builder

AI-powered YouTube channel builder. Pick a niche, get a complete channel package delivered to your inbox.

## Live Demo

Visit the GitHub Pages URL to try it out.

## How It Works

1. You pick a niche and submit the form
2. The animated pipeline shows your request being processed
3. Behind the scenes, AI agents research your niche, build a channel blueprint, and write A+ scripts
4. Everything gets emailed to you

## Architecture

```
Browser (GitHub Pages)
    → Google Apps Script → Google Sheet
    → Desktop poller picks up new rows
    → Watchdog triggers AI pipeline (claude CLI)
    → Results emailed to customer
```

Built by a creator, for creators.
