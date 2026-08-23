#!/usr/bin/env bash
#
# SessionStart hook: put the agent's handoff back into the context of a fresh
# session. Reads the SessionStart payload on stdin and returns the handoff as
# additionalContext.
#
# Contract: https://code.claude.com/docs/en/hooks#sessionstart
#
# Install:
#   install -m 755 session-start-handoff.sh ~/.claude/hooks/
#   then register it under hooks.SessionStart in settings.json (see README).
#
# Configuration:
#   PERSISTENT_HANDOFF_FILE  explicit path to the handoff. Set this for an agent
#                            that is not tied to one directory. Without it, the
#                            path is derived from the session's working
#                            directory: ~/.claude/handoffs/<dirname>.md
#
# jq is used when present, for correct JSON escaping. Without it the script
# falls back to plain stdout, which Claude Code also adds to the context of a
# SessionStart hook.

set -uo pipefail

payload=$(cat)

handoff_file="${PERSISTENT_HANDOFF_FILE:-}"
if [ -z "$handoff_file" ]; then
  cwd=""
  if command -v jq >/dev/null 2>&1; then
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  fi
  [ -n "$cwd" ] || cwd="$PWD"
  handoff_file="${HOME:-$PWD}/.claude/handoffs/$(basename "$cwd").md"
fi

# A handoff that exists but cannot be read is a misconfiguration, not an absence.
# Say so on stderr, where the user sees it, and still let the session start.
if [ -e "$handoff_file" ] && [ ! -r "$handoff_file" ]; then
  printf 'session-start-handoff: %s exists but is not readable\n' "$handoff_file" >&2
  exit 0
fi

# No handoff, or an empty one: print nothing and exit clean. Silence is the
# normal case. It is also what makes the file's presence meaningful.
[ -s "$handoff_file" ] || exit 0

header="Persistent handoff, read from $handoff_file. This is the state the previous session left behind, not a conversation summary. Start from \"Next action\". Update the file at the next milestone, remove from it whatever you resolve, and delete it when nothing is left in flight."

context="$header"$'\n\n'"$(cat "$handoff_file")"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$context" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  printf '%s\n' "$context"
fi

exit 0
