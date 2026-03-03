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

# ── Reorder code helpers ──
REORDER_CODES_FILE="$PROJECT_ROOT/submissions/reorder-codes.json"

generate_reorder_code() {
    python3 -c "
import random, string
charset = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'
print(''.join(random.choices(charset, k=6)))
"
}

save_reorder_code() {
    local code="$1" folder="$2" niche="$3" email_addr="$4"
    python3 -c "
import json, os
from datetime import datetime, timezone

path = '$REORDER_CODES_FILE'
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
else:
    data = {}

data['$code'] = {
    'folder': '$folder',
    'niche': '$niche',
    'email': '$email_addr',
    'created_at': datetime.now(timezone.utc).isoformat(),
    'uses': 0
}

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
}

lookup_reorder_code() {
    local code="$1"
    python3 -c "
import json, os, sys

path = '$REORDER_CODES_FILE'
if not os.path.exists(path):
    print('INVALID')
    sys.exit(0)

with open(path) as f:
    data = json.load(f)

entry = data.get('$code')
if not entry:
    print('INVALID')
else:
    print(entry['folder'])
"
}

increment_reorder_uses() {
    local code="$1"
    python3 -c "
import json

path = '$REORDER_CODES_FILE'
with open(path) as f:
    data = json.load(f)

if '$code' in data:
    data['$code']['uses'] = data['$code'].get('uses', 0) + 1

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
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
        reorder_code=$(python3 -c "import json; d=json.load(open('$submission')); print(d.get('reorder_code',''))")
        # Normalize reorder code to uppercase
        reorder_code=$(echo "$reorder_code" | tr '[:lower:]' '[:upper:]')

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

                    # Step 3/6: Generate 3 sample scripts (PARALLEL)
                    log "  Step 3/6: Generating 3 sample scripts (parallel)..."
                    update_status "$order_id" 3 "Writing video scripts..."

                    SCRIPT_PROMPT_BASE="You are the Script Writer Agent. Read the channel blueprint at $output_dir/02-channel-blueprint.html.

Write ONE complete video script for a faceless YouTube channel based on this blueprint.

Rules:
- 107-120 narration lines (HARD LIMIT: 133 lines)
- 800-1000 words
- Target runtime: 8-9 minutes
- Format: plain text, one narration line per line
- Include [HOOK], [INTRO], [BODY], [CTA], [OUTRO] section markers
- A+ quality: strong hook, clear value, emotional engagement
- Pick a DIFFERENT topic from the blueprint's content calendar"

                    s1_ok=true; s2_ok=true; s3_ok=true

                    claude --model sonnet -p "$SCRIPT_PROMPT_BASE

Pick the 1st topic from the content calendar. Write the script to: $output_dir/03-script-v01.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || s1_ok=false &
                    pid_s1=$!

                    claude --model sonnet -p "$SCRIPT_PROMPT_BASE

Pick the 4th topic from the content calendar (skip the first 3). Write the script to: $output_dir/03-script-v02.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || s2_ok=false &
                    pid_s2=$!

                    claude --model sonnet -p "$SCRIPT_PROMPT_BASE

Pick the 7th topic from the content calendar (skip the first 6). Write the script to: $output_dir/03-script-v03.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || s3_ok=false &
                    pid_s3=$!

                    wait $pid_s1 || s1_ok=false
                    wait $pid_s2 || s2_ok=false
                    wait $pid_s3 || s3_ok=false

                    if [ "$s1_ok" = false ] || [ "$s2_ok" = false ] || [ "$s3_ok" = false ]; then
                        log "  WARNING: Some scripts failed (s1=$s1_ok s2=$s2_ok s3=$s3_ok)"
                        # Continue if at least 1 succeeded
                        if [ "$s1_ok" = false ] && [ "$s2_ok" = false ] && [ "$s3_ok" = false ]; then
                            pipeline_ok=false
                        fi
                    fi
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 3 DONE"
                    update_status "$order_id" 3 "Scripts complete"

                    # Steps 4+5 run in PARALLEL (both read scripts, write different files)
                    log "  Steps 4+5: Thumbnails + Pinned comments (parallel)..."
                    update_status "$order_id" 4 "Designing thumbnails + crafting comments..."

                    step4_ok=true; step5_ok=true

                    claude --model haiku -p "
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
" --allowedTools "Read,Write" > /dev/null 2>&1 || step4_ok=false &
                    pid_s4=$!

                    claude --model haiku -p "
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
" --allowedTools "Read,Write" > /dev/null 2>&1 || step5_ok=false &
                    pid_s5=$!

                    wait $pid_s4 || step4_ok=false
                    wait $pid_s5 || step5_ok=false

                    if [ "$step4_ok" = false ] || [ "$step5_ok" = false ]; then
                        log "  WARNING: step4=$step4_ok step5=$step5_ok"
                        [ "$step4_ok" = false ] && [ "$step5_ok" = false ] && pipeline_ok=false
                    fi
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Steps 4+5 DONE"
                    update_status "$order_id" 5 "Thumbnails + comments complete"

                    # Generate reorder code for this build (before Step 6 so it can be included in the guide)
                    reorder_code=$(generate_reorder_code)
                    log "  Reorder code generated: $reorder_code"

                    # Step 6/6: Getting Started Guide
                    log "  Step 6/6: Generating getting started guide..."
                    update_status "$order_id" 6 "Building your getting started guide..."
                    claude --model haiku -p "
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

6. Getting More Scripts
   - Your personal reorder code is: $reorder_code
   - When you want more scripts, go to the order form and click 'I Have a Reorder Code'
   - Enter your code and we'll generate new scripts that match your channel's voice and style
   - Each batch includes 3 new scripts, thumbnail designs, and pinned comments

$HTML_STYLE

Write the guide to: $output_dir/00-getting-started.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 6 DONE"
                    update_status "$order_id" 6 "Getting Started guide complete"
                fi
                ;;

            reorder_scripts)
                log "  Pipeline: Reorder Scripts (3 new scripts for existing channel)"
                log "  Reorder code: $reorder_code"

                # Look up the original folder from the reorder code
                original_folder=$(lookup_reorder_code "$reorder_code")

                if [ "$original_folder" = "INVALID" ] || [ -z "$original_folder" ]; then
                    log "  ERROR: Invalid reorder code: $reorder_code"
                    pipeline_ok=false
                elif [ ! -d "$original_folder" ]; then
                    log "  ERROR: Original folder not found: $original_folder"
                    pipeline_ok=false
                else
                    log "  Original folder: $original_folder"

                    # Count existing scripts to determine next numbers
                    existing_count=$(ls "$original_folder"/03-script-v*.txt 2>/dev/null | wc -l)
                    next_start=$((existing_count + 1))
                    next_v1=$(printf "%02d" $next_start)
                    next_v2=$(printf "%02d" $((next_start + 1)))
                    next_v3=$(printf "%02d" $((next_start + 2)))
                    log "  Existing scripts: $existing_count, next: v$next_v1-v$next_v3"

                    # Shared HTML styling
                    HTML_STYLE="Write the output as a complete, self-contained HTML file with professional dark theme styling. Use a <style> tag with these CSS rules: body { background:#0f1117; color:#e0e0e0; font-family:Segoe UI,Tahoma,sans-serif; padding:40px; line-height:1.7; margin:0; } h1 { color:#fff; border-bottom:2px solid #6366f1; padding-bottom:12px; } h2 { color:#22d3ee; margin-top:32px; } h3 { color:#67e8f9; } p,li { color:#b0b0c0; } .card { background:#1a1b26; border:1px solid #2a2b3d; border-radius:12px; padding:20px; margin:16px 0; } table { width:100%; border-collapse:collapse; margin:16px 0; } th { background:#1a1b26; color:#fff; padding:12px; text-align:left; border-bottom:2px solid #6366f1; } td { padding:10px 12px; border-bottom:1px solid #2a2b3d; color:#b0b0c0; } a { color:#22d3ee; } .highlight { color:#10b981; font-weight:bold; } Wrap all content in a centered div (max-width:800px; margin:0 auto). End with a footer div: Faceless AI Channel Builder. Make it polished and modern."

                    # Step 1/3: Generate 3 new scripts (PARALLEL)
                    log "  Step 1/3: Generating 3 new scripts (parallel)..."
                    update_status "$order_id" 3 "Writing new video scripts..."

                    REORDER_PROMPT_BASE="You are the Script Writer Agent writing NEW scripts for a RETURNING customer.

Read the channel blueprint at: $original_folder/02-channel-blueprint.html
Also read ALL existing scripts in $original_folder (files matching 03-script-v*.txt) to understand the channel's established voice, tone, and style.

Write ONE NEW script that:
- Matches the exact voice, tone, and style of the existing scripts
- Covers a NEW topic (do not repeat topics from existing scripts)
- Uses the same content pillars from the blueprint
- Follows the same structural patterns (hooks, transitions, CTAs)

Rules:
- 107-120 narration lines (HARD LIMIT: 133 lines)
- 800-1000 words
- Target runtime: 8-9 minutes
- Format: plain text, one narration line per line
- Include [HOOK], [INTRO], [BODY], [CTA], [OUTRO] section markers"

                    rs1_ok=true; rs2_ok=true; rs3_ok=true

                    claude --model sonnet -p "$REORDER_PROMPT_BASE

Pick a topic from the blueprint's content calendar that has NOT been written yet. Write the script to: $output_dir/03-script-v${next_v1}.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || rs1_ok=false &
                    pid_rs1=$!

                    claude --model sonnet -p "$REORDER_PROMPT_BASE

Pick a DIFFERENT topic from the blueprint's content calendar that has NOT been written yet (skip the first few calendar items). Write the script to: $output_dir/03-script-v${next_v2}.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || rs2_ok=false &
                    pid_rs2=$!

                    claude --model sonnet -p "$REORDER_PROMPT_BASE

Pick yet ANOTHER topic from the blueprint's content calendar that has NOT been written yet (skip the first several calendar items). Write the script to: $output_dir/03-script-v${next_v3}.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || rs3_ok=false &
                    pid_rs3=$!

                    wait $pid_rs1 || rs1_ok=false
                    wait $pid_rs2 || rs2_ok=false
                    wait $pid_rs3 || rs3_ok=false

                    if [ "$rs1_ok" = false ] || [ "$rs2_ok" = false ] || [ "$rs3_ok" = false ]; then
                        log "  WARNING: Some scripts failed (s1=$rs1_ok s2=$rs2_ok s3=$rs3_ok)"
                        if [ "$rs1_ok" = false ] && [ "$rs2_ok" = false ] && [ "$rs3_ok" = false ]; then
                            pipeline_ok=false
                        fi
                    fi

                    if [ "$pipeline_ok" = true ]; then
                        log "  Step 1 DONE"
                        update_status "$order_id" 4 "Designing thumbnails + crafting comments..."

                        # Steps 2+3 run in PARALLEL
                        log "  Steps 2+3: Thumbnails + Pinned comments (parallel)..."
                        r_step2_ok=true; r_step3_ok=true

                        claude --model haiku -p "
You are the Thumbnail Designer Agent. Read the 3 NEW scripts in $output_dir (03-script-v${next_v1}.txt, 03-script-v${next_v2}.txt, 03-script-v${next_v3}.txt) and the channel blueprint in $original_folder/02-channel-blueprint.html.

For EACH of the 3 scripts, create a detailed thumbnail design section with:
1. Thumbnail Concept — What the thumbnail should show
2. Text Overlay — Bold text for the thumbnail (max 5 words)
3. Color Scheme — 2-3 dominant colors that pop
4. Background Style — Gradient, photo, dark/moody, bright, split-screen, etc.
5. AI Image Prompt — A ready-to-paste prompt for Ideogram, Canva AI, or Leonardo AI

After the 3 thumbnail briefs, include a brief HOW-TO reminder covering:
- Free platforms: Canva (canva.com) with YouTube Thumbnail 1280x720 template
- AI image generation: Ideogram (ideogram.ai), Leonardo AI (leonardo.ai), Canva AI

$HTML_STYLE

Write the complete guide to: $output_dir/04-thumbnail-guide.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || r_step2_ok=false &
                        pid_rt=$!

                        claude --model haiku -p "
You are the Engagement Agent. Read the 3 NEW scripts in $output_dir (03-script-v${next_v1}.txt, 03-script-v${next_v2}.txt, 03-script-v${next_v3}.txt).

For EACH script, create a pinned comment section with:
- The video title from the script
- A ready-to-paste pinned comment (3-5 lines, conversational, 1-2 emoji, includes a question to encourage replies and a soft CTA for likes/subscribes)

Make each comment feel natural and engaging, not salesy.

$HTML_STYLE

Write the complete file to: $output_dir/05-pinned-comments.html
" --allowedTools "Read,Write" > /dev/null 2>&1 || r_step3_ok=false &
                        pid_rc=$!

                        wait $pid_rt || r_step2_ok=false
                        wait $pid_rc || r_step3_ok=false

                        if [ "$r_step2_ok" = false ] || [ "$r_step3_ok" = false ]; then
                            log "  WARNING: step2=$r_step2_ok step3=$r_step3_ok"
                            [ "$r_step2_ok" = false ] && [ "$r_step3_ok" = false ] && pipeline_ok=false
                        fi
                    fi

                    if [ "$pipeline_ok" = true ]; then
                        log "  Steps 2+3 DONE"
                        update_status "$order_id" 5 "Reorder complete"

                        # Copy new scripts back to the original folder
                        log "  Copying new scripts to original folder..."
                        for script_file in "$output_dir"/03-script-v*.txt; do
                            if [ -f "$script_file" ]; then
                                cp "$script_file" "$original_folder/"
                                log "  Copied $(basename "$script_file") to original folder"
                            fi
                        done

                        # Increment uses counter
                        increment_reorder_uses "$reorder_code"
                    fi
                fi
                ;;

            *)
                log "  ERROR: Unknown request type: $request_type"
                pipeline_ok=false
                ;;
        esac

        # ── Handle result ──
        if [ "$pipeline_ok" = true ]; then
            log "  Pipeline COMPLETE"

            # For reorder_scripts, generate a new reorder code for next time
            if [ "$request_type" = "reorder_scripts" ]; then
                reorder_code=$(generate_reorder_code)
                log "  New reorder code for next time: $reorder_code"
            fi

            # Send email with results
            log "  Sending results to $email..."
            update_status "$order_id" 7 "Packaging and sending email..."
            python3 "$SCRIPT_DIR/send-email.py" \
                --to "$email" \
                --niche "$niche" \
                --output-dir "$output_dir" \
                --reorder-code "$reorder_code" \
                --request-type "$request_type" \
                >> "$LOGFILE" 2>&1 && email_ok=true || email_ok=false

            if [ "$email_ok" = true ]; then
                log "  Email SENT to $email"
                update_status "$order_id" 7 "Email sent!" "complete"
                # Move everything to completed
                mv "$PROCESSING/$filename" "$COMPLETED/$filename"
                mv "$output_dir" "$COMPLETED/${order_id}_output"
                completed_folder="$COMPLETED/${order_id}_output"
                log "  Status: COMPLETED"

                # Save reorder code mapping (points to the completed folder)
                if [ -n "$reorder_code" ]; then
                    save_reorder_code "$reorder_code" "$completed_folder" "$niche" "$email"
                    log "  Reorder code $reorder_code saved → $completed_folder"
                fi
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
