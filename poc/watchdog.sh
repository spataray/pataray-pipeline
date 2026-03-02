#!/bin/bash
# ═══════════════════════════════════════════════════════
# Faceless AI Channel Builder Watchdog
# Monitors submissions/pending/ for new orders and
# triggers the pipeline for each one.
#
# Usage:
#   ./poc/watchdog.sh              # run in foreground
#   ./poc/watchdog.sh &            # run in background
#   nohup ./poc/watchdog.sh &      # survive terminal close
#
# Checks every 30 seconds for new .json files in pending/
# ═══════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PENDING="$PROJECT_ROOT/submissions/pending"
PROCESSING="$PROJECT_ROOT/submissions/processing"
COMPLETED="$PROJECT_ROOT/submissions/completed"
FAILED="$PROJECT_ROOT/submissions/failed"
LOGFILE="$PROJECT_ROOT/poc/watchdog.log"

POLL_INTERVAL=30  # seconds

# ── Apps Script URL for status updates ──
APPS_SCRIPT_URL="https://script.google.com/macros/s/AKfycbyKNhQTz7lHSAMai0ID2zaW_PKcIVh0RkK6U3reDuUKs8hkwfrf8zLjpJBtoVqkWdzB/exec"

# ── Load Gmail creds from crontab env (same vars) ──
export GMAIL_USER="${GMAIL_USER:-spataray@gmail.com}"
export GMAIL_APP_PASSWORD="${GMAIL_APP_PASSWORD:-$(crontab -l 2>/dev/null | grep GMAIL_APP_PASSWORD | head -1 | cut -d= -f2)}"

# ── Ensure directories exist ──
mkdir -p "$PENDING" "$PROCESSING" "$COMPLETED" "$FAILED"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOGFILE"
}

update_status() {
    local oid="$1" step="$2" msg="$3" status="${4:-processing}"
    [ -z "$oid" ] && return 0
    curl -s -L -X POST "$APPS_SCRIPT_URL" \
        -H "Content-Type: application/json" \
        -d "{\"action\":\"update_status\",\"order_id\":\"$oid\",\"pipeline_step\":$step,\"pipeline_message\":\"$msg\",\"status\":\"$status\"}" \
        > /dev/null 2>&1 &
}

log "═══ Faceless AI Watchdog started ═══"
log "Monitoring: $PENDING"
log "Poll interval: ${POLL_INTERVAL}s"
log ""

while true; do
    # Find all .json files in pending (oldest first)
    shopt -s nullglob
    pending_files=("$PENDING"/*.json)
    shopt -u nullglob

    if [ ${#pending_files[@]} -eq 0 ]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    for submission in "${pending_files[@]}"; do
        filename="$(basename "$submission")"
        log "──────────────────────────────────────"
        log "NEW SUBMISSION: $filename"

        # Parse the JSON
        email=$(python3 -c "import json; d=json.load(open('$submission')); print(d.get('email',''))")
        niche=$(python3 -c "import json; d=json.load(open('$submission')); print(d.get('niche',''))")
        request_type=$(python3 -c "import json; d=json.load(open('$submission')); print(d.get('request_type','full_channel_build'))")
        order_id=$(python3 -c "import json; d=json.load(open('$submission')); print(d.get('order_id',''))")

        log "  Email: $email"
        log "  Niche: $niche"
        log "  Type:  $request_type"
        log "  Order: $order_id"

        # Move to processing
        mv "$submission" "$PROCESSING/$filename"
        log "  Status: PROCESSING"

        # Create output directory for this order
        order_id="${filename%.json}"
        output_dir="$PROCESSING/${order_id}_output"
        mkdir -p "$output_dir"

        # ── Run the pipeline based on request type ──
        pipeline_ok=true

        case "$request_type" in
            niche_research)
                log "  Pipeline: Niche Research only"
                update_status "$order_id" 1 "Researching your niche..."
                claude --model sonnet -p "
You are the Niche Research Agent for the Faceless AI Channel Builder.

Research the following niche for a faceless YouTube channel: \"$niche\"

Provide a comprehensive niche analysis report including:
1. Niche viability score (1-10)
2. Estimated CPM range
3. Competition level (Low/Medium/High)
4. Monthly search volume estimate
5. Top 5 sub-niches within this space
6. Content format recommendations (list, story, tutorial, etc.)
7. Monetization potential beyond ads
8. 10 video title ideas to start with
9. Recommended posting frequency
10. Growth timeline estimate (months to 1K subs)

Format as a clean, readable report.
" --allowedTools "WebSearch,WebFetch,Read,Write" > "$output_dir/niche-research.txt" 2>&1 || pipeline_ok=false
                ;;

            full_channel_build)
                log "  Pipeline: Full Channel Build (6 steps)"

                # Shared HTML styling instructions for all HTML deliverables
                HTML_STYLE="Write the output as a complete, self-contained HTML file with professional dark theme styling. Use a <style> tag with these CSS rules: body { background:#0f1117; color:#e0e0e0; font-family:Segoe UI,Tahoma,sans-serif; padding:40px; line-height:1.7; margin:0; } h1 { color:#fff; border-bottom:2px solid #6366f1; padding-bottom:12px; } h2 { color:#22d3ee; margin-top:32px; } h3 { color:#67e8f9; } p,li { color:#b0b0c0; } .card { background:#1a1b26; border:1px solid #2a2b3d; border-radius:12px; padding:20px; margin:16px 0; } table { width:100%; border-collapse:collapse; margin:16px 0; } th { background:#1a1b26; color:#fff; padding:12px; text-align:left; border-bottom:2px solid #6366f1; } td { padding:10px 12px; border-bottom:1px solid #2a2b3d; color:#b0b0c0; } a { color:#22d3ee; } .highlight { color:#10b981; font-weight:bold; } Wrap all content in a centered div (max-width:800px; margin:0 auto). End with a footer div: Faceless AI Channel Builder. Make it polished and modern."

                # Step 1/6: Niche Research
                log "  Step 1/6: Niche Research..."
                update_status "$order_id" 1 "Researching your niche..."
                claude --model sonnet -p "
You are the Niche Research Agent. Research the niche \"$niche\" for a faceless YouTube channel.

Provide a comprehensive analysis including:
1. Niche viability score (1-10) with reasoning
2. Estimated CPM range with data sources
3. Competition level (Low/Medium/High) and top competitor channels
4. Monthly search volume estimate
5. Top 5 sub-niches within this space
6. Content format recommendations (list, story, tutorial, etc.)
7. Monetization potential beyond ads
8. 10 video title ideas to start with
9. Recommended posting frequency
10. Growth timeline estimate (months to 1K subs)

$HTML_STYLE

Write the report to: $output_dir/01-niche-research.html
" --allowedTools "WebSearch,WebFetch,Read,Write" > /dev/null 2>&1 || pipeline_ok=false

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 1 DONE"
                    update_status "$order_id" 1 "Niche Research complete"

                    # Step 2/6: Channel Blueprint
                    log "  Step 2/6: Channel Blueprint..."
                    update_status "$order_id" 2 "Building channel blueprint..."
                    claude --model sonnet -p "
You are the Blueprint Architect Agent. Based on the niche research in $output_dir/01-niche-research.html, create a full channel blueprint.

Include:
1. Three channel name options (with reasoning)
2. Channel brand voice and tone
3. Target audience persona (age, interests, problems)
4. Content pillars (3-4 main topic categories)
5. 30-day content calendar (title + brief description for each video)
6. Thumbnail style recommendations
7. Channel description and about section copy
8. Initial tags and keywords

$HTML_STYLE

Write the blueprint to: $output_dir/02-channel-blueprint.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 2 DONE"
                    update_status "$order_id" 2 "Channel Blueprint complete"

                    # Step 3/6: Generate 3 sample scripts
                    log "  Step 3/6: Generating 3 sample scripts..."
                    update_status "$order_id" 3 "Writing video scripts..."
                    claude --model sonnet -p "
You are the Script Writer Agent. Based on the channel blueprint in $output_dir/02-channel-blueprint.html, write 3 complete video scripts.

Rules:
- Each script must be 107-120 narration lines (HARD LIMIT: 133 lines)
- Each script 800-1000 words
- Target runtime: 8-9 minutes
- Format: plain text, one narration line per line
- Include [HOOK], [INTRO], [BODY], [CTA], [OUTRO] section markers
- Make them A+ quality: strong hooks, clear value, emotional engagement

Write each script to a separate file:
- $output_dir/03-script-v01.txt
- $output_dir/03-script-v02.txt
- $output_dir/03-script-v03.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 3 DONE"
                    update_status "$order_id" 3 "Scripts complete"

                    # Step 4/6: Thumbnail Guide
                    log "  Step 4/6: Generating thumbnail guide..."
                    update_status "$order_id" 4 "Designing thumbnails..."
                    claude --model sonnet -p "
You are the Thumbnail Designer Agent. Read all 3 scripts in $output_dir (03-script-v01.txt, 03-script-v02.txt, 03-script-v03.txt) and the channel blueprint in $output_dir/02-channel-blueprint.html.

For EACH of the 3 scripts, create a detailed thumbnail design section with:
1. Thumbnail Concept — What the thumbnail should show
2. Text Overlay — Bold text for the thumbnail (max 5 words)
3. Color Scheme — 2-3 dominant colors that pop
4. Background Style — Gradient, photo, dark/moody, bright, split-screen, etc.
5. AI Image Prompt — A ready-to-paste prompt for Ideogram, Canva AI, or Leonardo AI

After the 3 thumbnail briefs, include a HOW-TO section covering:
- Free platforms: Canva (canva.com) with YouTube Thumbnail 1280x720 template, Adobe Express, Snappa
- AI image generation: Ideogram (ideogram.ai), Leonardo AI (leonardo.ai), Canva AI
- Step-by-step: generate background image, open Canva, upload, add text overlay (bold contrasting font), add elements, download as PNG, upload as thumbnail
- Thumbnail rules for high CTR: faces with emotion get 30% more clicks, max 5 words, contrasting colors, one focal point, test at small size

$HTML_STYLE

Write the complete guide to: $output_dir/04-thumbnail-guide.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 4 DONE"
                    update_status "$order_id" 4 "Thumbnails complete"

                    # Step 5/6: Pinned Comments
                    log "  Step 5/6: Generating pinned comments..."
                    update_status "$order_id" 5 "Crafting engagement comments..."
                    claude --model sonnet -p "
You are the Engagement Agent. Read all 3 scripts in $output_dir (03-script-v01.txt, 03-script-v02.txt, 03-script-v03.txt).

For EACH script, create a pinned comment section with:
- The video title from the script
- A ready-to-paste pinned comment (3-5 lines, conversational, 1-2 emoji, includes a question to encourage replies and a soft CTA for likes/subscribes)

Make each comment feel natural and engaging, not salesy. The viewer should want to reply.

After the 3 pinned comments, include:
- How to Pin a Comment on YouTube (step-by-step: publish video, post comment, click three dots, select Pin)
- Why Pinned Comments Matter (boosts engagement as algorithm signal, directs conversation, increases watch time, builds community)

$HTML_STYLE

Write the complete file to: $output_dir/05-pinned-comments.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 5 DONE"
                    update_status "$order_id" 5 "Comments complete"

                    # Step 6/6: Getting Started Guide
                    log "  Step 6/6: Generating getting started guide..."
                    update_status "$order_id" 6 "Building your getting started guide..."
                    claude --model sonnet -p "
You are the Onboarding Guide Agent. Read all the files in $output_dir to understand what was delivered to this customer.

Create a comprehensive Getting Started guide for a complete beginner. Structure it as:

1. Welcome and What You Received
   - List every file in the package with a one-line description
   - Recommended order to read and use them

2. Your First Video in 30 Minutes
   - Step 1: Review your Channel Blueprint (02-channel-blueprint.html) for your channel name, brand, and audience
   - Step 2: Pick one of your 3 scripts (03-script-v01.txt, v02, v03) — read it, make sure you like it
   - Step 3: Turn the script into a video using ONE of these free/cheap tools:
     * Pictory AI (pictory.ai) — paste your script, AI auto-generates video with stock footage and voiceover. Easiest option.
     * InVideo (invideo.io) — similar to Pictory, great templates for faceless videos
     * CapCut (capcut.com) — completely free, more hands-on but no cost
   - Step 4: Create your thumbnail using the guide in 04-thumbnail-guide.html
   - Step 5: Upload to YouTube with the optimized title from your script and tags from your Blueprint
   - Step 6: Pin your first comment using 05-pinned-comments.html

3. Setting Up Your YouTube Channel (if you do not have one yet)
   - How to create a channel on YouTube
   - Profile picture and banner tips
   - Channel description (copy from your Blueprint)
   - Important settings: monetization preferences, default upload settings, playlists

4. Uploading Tips
   - Title optimization (use the titles from your scripts)
   - Description template with keywords from the Blueprint
   - Tags from the Blueprint
   - Best times to publish (weekday mornings or weekend evenings)
   - Always add your pinned comment right after publishing

5. Growing Your Channel
   - Consistency beats frequency (2-3 videos per week is ideal)
   - First 30 days: focus on publishing, not views
   - YouTube Partner Program requirements: 1,000 subscribers + 4,000 watch hours
   - When you are ready for more scripts, just submit another request

$HTML_STYLE

Write the guide to: $output_dir/00-getting-started.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 6 DONE"
                    update_status "$order_id" 6 "Getting Started guide complete"
                fi
                ;;

            scripts_only)
                log "  Pipeline: Scripts Only (3 scripts for existing niche)"
                claude --model sonnet -p "
You are the Script Writer Agent. Write 3 complete faceless YouTube video scripts for the niche: \"$niche\"

Rules:
- Each script 107-120 narration lines (HARD LIMIT: 133)
- Each script 800-1000 words
- Strong hooks, clear value, emotional engagement
- Format: plain text for Pictory AI compatibility
- Include [HOOK], [INTRO], [BODY], [CTA], [OUTRO] markers

Write each to:
- $output_dir/script-v01.txt
- $output_dir/script-v02.txt
- $output_dir/script-v03.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                ;;

            *)
                log "  ERROR: Unknown request type: $request_type"
                pipeline_ok=false
                ;;
        esac

        # ── Handle result ──
        if [ "$pipeline_ok" = true ]; then
            log "  Pipeline COMPLETE"

            # Send email with results
            log "  Sending results to $email..."
            update_status "$order_id" 7 "Packaging and sending email..."
            python3 "$SCRIPT_DIR/send-email.py" \
                --to "$email" \
                --niche "$niche" \
                --output-dir "$output_dir" \
                >> "$LOGFILE" 2>&1 && email_ok=true || email_ok=false

            if [ "$email_ok" = true ]; then
                log "  Email SENT to $email"
                update_status "$order_id" 7 "Email sent!" "complete"
                # Move everything to completed
                mv "$PROCESSING/$filename" "$COMPLETED/$filename"
                mv "$output_dir" "$COMPLETED/${order_id}_output"
                log "  Status: COMPLETED"
            else
                log "  WARNING: Email failed, output saved in processing/"
                log "  Manual action needed: send files from $output_dir to $email"
                update_status "$order_id" 7 "Email delivery issue — we will retry" "complete"
            fi
        else
            log "  Pipeline FAILED"
            update_status "$order_id" 0 "Error encountered" "failed"
            mv "$PROCESSING/$filename" "$FAILED/$filename"
            [ -d "$output_dir" ] && mv "$output_dir" "$FAILED/${order_id}_output"
            log "  Status: FAILED (moved to failed/)"
        fi

        log ""
    done

    sleep "$POLL_INTERVAL"
done
