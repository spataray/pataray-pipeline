#!/bin/bash
# ═══════════════════════════════════════════════════════
# Pataray Pipeline Watchdog
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

log "═══ Pataray Watchdog started ═══"
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

        log "  Email: $email"
        log "  Niche: $niche"
        log "  Type:  $request_type"

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
                claude --model sonnet -p "
You are the Niche Research Agent for the Pataray Pipeline.

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
                log "  Pipeline: Full Channel Build (niche + blueprint + 3 scripts)"

                # Step 1: Niche Research
                log "  Step 1/3: Niche Research..."
                claude --model sonnet -p "
You are the Niche Research Agent. Research the niche \"$niche\" for a faceless YouTube channel.
Provide: viability score, CPM range, competition level, top 5 sub-niches, 10 video title ideas.
Write the report to: $output_dir/01-niche-research.txt
" --allowedTools "WebSearch,WebFetch,Read,Write" > /dev/null 2>&1 || pipeline_ok=false

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 1 DONE"

                    # Step 2: Channel Blueprint
                    log "  Step 2/3: Channel Blueprint..."
                    claude --model sonnet -p "
You are the Blueprint Architect Agent. Based on the niche research in $output_dir/01-niche-research.txt, create a full channel blueprint.

Include:
1. Three channel name options (with reasoning)
2. Channel brand voice and tone
3. Target audience persona (age, interests, problems)
4. Content pillars (3-4 main topic categories)
5. 30-day content calendar (title + brief description for each video)
6. Thumbnail style recommendations
7. Channel description and about section copy
8. Initial tags and keywords

Write the blueprint to: $output_dir/02-channel-blueprint.txt
" --allowedTools "Read,Write" > /dev/null 2>&1 || pipeline_ok=false
                fi

                if [ "$pipeline_ok" = true ]; then
                    log "  Step 2 DONE"

                    # Step 3: Generate 3 sample scripts
                    log "  Step 3/3: Generating 3 sample scripts..."
                    claude --model sonnet -p "
You are the Script Writer Agent. Based on the channel blueprint in $output_dir/02-channel-blueprint.txt, write 3 complete video scripts.

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
            python3 "$SCRIPT_DIR/send-email.py" \
                --to "$email" \
                --niche "$niche" \
                --output-dir "$output_dir" \
                >> "$LOGFILE" 2>&1 && email_ok=true || email_ok=false

            if [ "$email_ok" = true ]; then
                log "  Email SENT to $email"
                # Move everything to completed
                mv "$PROCESSING/$filename" "$COMPLETED/$filename"
                mv "$output_dir" "$COMPLETED/${order_id}_output"
                log "  Status: COMPLETED"
            else
                log "  WARNING: Email failed, output saved in processing/"
                log "  Manual action needed: send files from $output_dir to $email"
            fi
        else
            log "  Pipeline FAILED"
            mv "$PROCESSING/$filename" "$FAILED/$filename"
            [ -d "$output_dir" ] && mv "$output_dir" "$FAILED/${order_id}_output"
            log "  Status: FAILED (moved to failed/)"
        fi

        log ""
    done

    sleep "$POLL_INTERVAL"
done
