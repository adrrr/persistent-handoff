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
#                            path comes from the working directory, turned into
#                            a slug (see below).
#
# jq is used when available, both to read the payload and to escape the output.
# Without it the script falls back to $PWD and to plain stdout, which Claude
# Code also adds to the context of a SessionStart hook.
#
# To run it by hand, feed it a payload: it reads stdin unconditionally and will
# otherwise sit there waiting.
#   echo "{\"cwd\":\"$PWD\"}" | ./session-start-handoff.sh

set -uo pipefail

payload=$(cat)
home=${HOME:-$PWD}

handoff_file="${PERSISTENT_HANDOFF_FILE:-}"
if [ -z "$handoff_file" ]; then
  cwd=""
  if command -v jq >/dev/null 2>&1; then
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  fi
  [ -n "$cwd" ] || cwd="$PWD"

  # The whole path becomes the name, not just its last segment: ~/work/acme/api
  # and ~/work/beta/api are two different agents and must not share a handoff.
  # ~/work/acme/api gives work-acme-api.md
  slug=$(printf '%s' "${cwd#"$home"/}" | tr -cs 'A-Za-z0-9._-' '-')
  slug=${slug#-}
  slug=${slug%-}
  [ -n "$slug" ] || slug="agent"
  handoff_file="$home/.claude/handoffs/$slug.md"
fi

# Nothing in flight: print nothing and exit clean. Silence is the normal case,
# and it is what makes the file's presence meaningful.
[ -e "$handoff_file" ] || exit 0

emit() {
  # jq failing is treated like jq missing. Testing only for its presence would
  # drop the handoff in silence the day it exits non-zero.
  if command -v jq >/dev/null 2>&1 && jq -n --arg ctx "$1" \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'; then
    return 0
  fi
  # The preamble comes first on purpose. A handoff whose own first line looks
  # like JSON would otherwise be read as this hook's structured output.
  printf '%s\n' "$1"
}

# A handoff that exists but cannot be read is a misconfiguration, not an absence,
# and it has to be reported through additionalContext: stderr from a hook that
# exits 0 reaches the debug log only, so Claude would never learn the file
# was there at all.
if [ ! -f "$handoff_file" ] || [ ! -r "$handoff_file" ]; then
  emit "A handoff exists at $handoff_file but could not be read: it is not a regular file, or it is not readable. Say so before relying on anything about the previous session."
  exit 0
fi

body=$(cat "$handoff_file" 2>/dev/null) || body=""
[ -n "$body" ] || exit 0

emit "Persistent handoff, read from $handoff_file. This is the state the previous session left behind, not a conversation summary. Start from \"Next action\". Update the file at the next milestone, remove from it whatever you resolve, and delete it when nothing is left in flight.

$body"

exit 0
