#!/bin/bash
# ═══════════════════════════════════════════
# Create a test submission manually (no server needed)
#
# Usage:
#   ./poc/submit-test.sh                                    # interactive
#   ./poc/submit-test.sh "test@example.com" "Horror"        # quick test
#   ./poc/submit-test.sh "test@example.com" "Business" niche_research
# ═══════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PENDING="$PROJECT_ROOT/submissions/pending"

mkdir -p "$PENDING"

if [ -n "${1:-}" ]; then
    EMAIL="$1"
    NICHE="${2:-Horror / Supernatural}"
    REQUEST_TYPE="${3:-full_channel_build}"
else
    read -rp "Email: " EMAIL
    echo ""
    echo "Niches:"
    echo "  1) Business / Motivation"
    echo "  2) Horror / Supernatural"
    echo "  3) Legal / True Crime"
    echo "  4) Self-Improvement"
    echo "  5) Language Learning"
    echo "  6) Storytelling / Drama"
    echo ""
    read -rp "Pick niche (1-6): " NICHE_NUM
    case "$NICHE_NUM" in
        1) NICHE="Business / Motivation" ;;
        2) NICHE="Horror / Supernatural" ;;
        3) NICHE="Legal / True Crime" ;;
        4) NICHE="Self-Improvement" ;;
        5) NICHE="Language Learning" ;;
        6) NICHE="Storytelling / Drama" ;;
        *) NICHE="Horror / Supernatural" ;;
    esac

    echo ""
    echo "Request types:"
    echo "  1) full_channel_build  (niche + blueprint + 3 scripts)"
    echo "  2) niche_research      (research report only)"
    echo "  3) scripts_only        (3 scripts for existing channel)"
    echo ""
    read -rp "Pick type (1-3): " TYPE_NUM
    case "$TYPE_NUM" in
        1) REQUEST_TYPE="full_channel_build" ;;
        2) REQUEST_TYPE="niche_research" ;;
        3) REQUEST_TYPE="scripts_only" ;;
        *) REQUEST_TYPE="full_channel_build" ;;
    esac
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SAFE_NICHE=$(echo "$NICHE" | tr '/ ' '-_' | tr '[:upper:]' '[:lower:]')
FILENAME="${TIMESTAMP}_${SAFE_NICHE}.json"
FILEPATH="$PENDING/$FILENAME"

cat > "$FILEPATH" << ENDJSON
{
  "email": "$EMAIL",
  "niche": "$NICHE",
  "channel_status": "No",
  "request_type": "$REQUEST_TYPE",
  "submitted_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "status": "pending"
}
ENDJSON

echo ""
echo "Test submission created:"
echo "  File: $FILEPATH"
echo "  Email: $EMAIL"
echo "  Niche: $NICHE"
echo "  Type: $REQUEST_TYPE"
echo ""
echo "The watchdog will pick this up on its next poll cycle."
