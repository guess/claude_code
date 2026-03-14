#!/usr/bin/env bash
# Fetches official Claude Agent SDK docs as markdown and saves them
# to docs/guides/.official/ for tracking upstream changes.
#
# Usage:
#   ./scripts/fetch-official-docs.sh              # fetch all
#   ./scripts/fetch-official-docs.sh permissions   # fetch one
#   ./scripts/fetch-official-docs.sh permissions sessions hooks  # fetch several
#   ./scripts/fetch-official-docs.sh --list        # list cached docs with fetch dates
#   ./scripts/fetch-official-docs.sh --diff-all    # show which docs have changed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../docs/guides/.official"
GUIDES_DIR="${SCRIPT_DIR}/../docs/guides"
BASE_URL="https://platform.claude.com/docs/en/agent-sdk"

# All guide slugs matching the inventory in SKILL.md
ALL_SLUGS=(
  cost-tracking
  custom-tools
  file-checkpointing
  hooks
  hosting
  mcp
  modifying-system-prompts
  permissions
  plugins
  secure-deployment
  sessions
  skills
  slash-commands
  stop-reasons
  streaming-output
  streaming-vs-single-mode
  structured-outputs
  subagents
  user-input
)

mkdir -p "$OUT_DIR"

cmd_list() {
  if ls "$OUT_DIR"/*.md &>/dev/null; then
    for f in "$OUT_DIR"/*.md; do
      local slug date
      slug=$(basename "$f" .md)
      date=$(head -2 "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
      echo "  ${slug}  (fetched: ${date:-unknown})"
    done
  else
    echo "No cached official docs yet. Run without flags to fetch all."
  fi
}

cmd_diff_all() {
  local any_diff=0
  for f in "$OUT_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    local slug guide
    slug=$(basename "$f" .md)
    guide="${GUIDES_DIR}/${slug}.md"
    if [[ ! -f "$guide" ]]; then
      echo "  ${slug}: no local guide"
    else
      local lines
      lines=$(diff "$f" "$guide" 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$lines" -gt 0 ]]; then
        echo "  ${slug}: ${lines} diff lines"
        any_diff=1
      fi
    fi
  done
  [[ $any_diff -eq 0 ]] && echo "  All cached docs match local guides (structurally)."
}

fetch_one() {
  local slug="$1"
  local url="${BASE_URL}/${slug}.md"
  local out_file="${OUT_DIR}/${slug}.md"

  printf "  %-30s" "${slug}..."

  local tmp
  tmp=$(mktemp)

  if ! curl -sL --fail --max-time 30 "$url" -o "$tmp" 2>/dev/null; then
    echo "FAILED"
    rm -f "$tmp"
    return 1
  fi

  # Prepend metadata header
  {
    echo "<!-- Fetched from: ${url} -->"
    echo "<!-- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ) -->"
    echo ""
    cat "$tmp"
  } > "$out_file"

  rm -f "$tmp"
  echo "OK"
}

# Handle flags
case "${1:-}" in
  --list)
    echo "Cached official docs:"
    cmd_list
    exit 0
    ;;
  --diff-all)
    echo "Comparing cached official docs vs local guides:"
    cmd_diff_all
    exit 0
    ;;
  --help|-h)
    cat <<'USAGE'
Usage:
  ./scripts/fetch-official-docs.sh                  Fetch all official docs
  ./scripts/fetch-official-docs.sh <slug> [slug...]  Fetch specific docs
  ./scripts/fetch-official-docs.sh --list            List cached docs
  ./scripts/fetch-official-docs.sh --diff-all        Compare cached vs local
USAGE
    exit 0
    ;;
esac

# Determine which slugs to fetch
if [[ $# -gt 0 ]]; then
  SLUGS=("$@")
else
  SLUGS=("${ALL_SLUGS[@]}")
fi

echo "Fetching ${#SLUGS[@]} official doc(s) to docs/guides/.official/"
echo ""

failed=0
for slug in "${SLUGS[@]}"; do
  fetch_one "$slug" || ((failed++))
done

echo ""
echo "Done: $((${#SLUGS[@]} - failed))/${#SLUGS[@]} fetched successfully."
[[ $failed -gt 0 ]] && echo "${failed} failed — check output above." && exit 1
exit 0
