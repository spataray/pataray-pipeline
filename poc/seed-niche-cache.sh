#!/bin/bash
# Seeds the niche research cache.
# Cached results are reused by the pipeline instead of running an expensive
# live web search on every job — saves ~$0.50-0.80 per full channel build.
#
# Usage:
#   ./pipeline cache                           # seed all 6 niches
#   ./pipeline cache "Legal / True Crime"      # refresh one niche

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/submissions/niche-cache"

HTML_STYLE="Write the output as a complete, self-contained HTML file with professional dark theme styling. Use a <style> tag with these CSS rules: body { background:#0f1117; color:#e0e0e0; font-family:Segoe UI,Tahoma,sans-serif; padding:40px; line-height:1.7; margin:0; } h1 { color:#fff; border-bottom:2px solid #6366f1; padding-bottom:12px; } h2 { color:#22d3ee; margin-top:32px; } h3 { color:#67e8f9; } p,li { color:#b0b0c0; } .card { background:#1a1b26; border:1px solid #2a2b3d; border-radius:12px; padding:20px; margin:16px 0; } table { width:100%; border-collapse:collapse; margin:16px 0; } th { background:#1a1b26; color:#fff; padding:12px; text-align:left; border-bottom:2px solid #6366f1; } td { padding:10px 12px; border-bottom:1px solid #2a2b3d; color:#b0b0c0; } a { color:#22d3ee; } .highlight { color:#10b981; font-weight:bold; } Wrap all content in a centered div (max-width:800px; margin:0 auto). End with a footer div: Faceless AI Channel Builder. Make it polished and modern."

ALL_NICHES=(
    "Business / Motivation"
    "Horror / Supernatural"
    "Legal / True Crime"
    "Self-Improvement"
    "Language Learning"
    "Storytelling / Drama"
)

seed_niche() {
    local niche="$1"
    local slug
    slug=$(echo "$niche" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
    local dir="$CACHE_DIR/$slug"

    mkdir -p "$dir"
    echo "  Researching: $niche..."

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

Write the report to: $dir/01-niche-research.html
" --allowedTools "WebSearch,WebFetch,Read,Write" > /dev/null 2>&1

    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $niche" > "$dir/cached-at.txt"
    echo "  Cached: $niche → niche-cache/$slug/"
}

if [ "${1:-}" != "" ]; then
    seed_niche "$1"
else
    echo "═══ FCB Niche Cache Seeder ═══"
    echo "Seeding ${#ALL_NICHES[@]} niches — one Claude web search per niche."
    echo ""
    for niche in "${ALL_NICHES[@]}"; do
        seed_niche "$niche"
    done
    echo ""
    echo "Done. Future pipeline runs will skip Step 1 for all known niches."
fi
