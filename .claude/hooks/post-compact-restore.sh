#!/bin/bash
# post-compact-restore.sh — runs after a conversation compaction. Re-injects
# HANDOFF.md (and any other critical state you choose to add) into the
# freshly compacted context as additionalContext, so Claude doesn't lose
# load-bearing facts to the compaction summary.
#
# This is a starter stub. Extend it to re-inject anything project-specific
# that shouldn't survive only as a one-line summary — common picks:
#   - HANDOFF.md (default below)
#   - reference_*.md memory files (e.g. "where every secret lives")
#   - a CHANGELOG tail or recent-commits list
#   - a PR/issue snapshot
#
# Stdin: PostCompact event JSON (we don't read it).
# Stdout: JSON with hookSpecificOutput.additionalContext = restored snapshot.
set -uo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-/workspace}"
HANDOFF="$PROJ/HANDOFF.md"

snapshot=""
[ -f "$HANDOFF" ] && snapshot+=$'## HANDOFF.md (post-compact restore)\n\n'"$(cat "$HANDOFF")"$'\n\n'

# Add more here as needed. Example:
# MEM_DIR="$HOME/.claude/projects/$(echo "$PROJ" | tr / -)/memory"
# [ -f "$MEM_DIR/reference_secrets_locations.md" ] && \
#     snapshot+=$'## Secrets locations\n\n'"$(cat "$MEM_DIR/reference_secrets_locations.md")"$'\n'

# jq -Rs reads all stdin as one raw string and JSON-encodes it; safer than
# hand-escaping (handles quotes, newlines, etc.).
printf '%s' "$snapshot" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "PostCompact",
    additionalContext: .
  },
  systemMessage: "Post-compact: restored HANDOFF.md into context."
}'
