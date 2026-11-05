#!/usr/bin/env bash
#
# UserPromptSubmit hook, opt-in: when the context grows past a threshold, tell
# the session its handoff is at risk and to bring it current before a
# compaction drops what lives only in the context. Issue #7.
#
# Contract: https://code.claude.com/docs/en/hooks#userpromptsubmit
#
# Why not PreCompact: its output cannot reach the session or the compaction. It
# can only block it. So the reminder goes out on the prompts before, while the
# session still has a turn to write in.
#
# Configuration:
#   PERSISTENT_HANDOFF_WARN_TOKENS  the context size, in tokens, past which the
#                                   reminder fires. Unset, empty or not a whole
#                                   number: the hook does nothing.
#   PERSISTENT_HANDOFF_FILE and XDG_STATE_HOME move the handoff path exactly as
#   they do for session-start-handoff.sh, which this hook asks for the path. A
#   value set inline in the SessionStart command has to be set the same way
#   here, or the two hooks name different files.
#
# The size is the last main-chain assistant entry of the transcript: input
# tokens plus both cache fields, which is what that request sent. API errors
# are written as assistant entries from the model "<synthetic>" with a usage of
# zero, and are skipped: they say nothing about the context. A compaction
# boundary after it means the size is unknown until the next reply, and unknown
# counts as under.
#
# Once per crossing: the first prompt past the threshold creates a marker
# directory for the session under $TMPDIR, and the reminder stays quiet while it
# exists. A prompt under the threshold removes it, so after a compaction the next
# crossing warns again.
#
# Exit 0 on every path. A reminder that fails must never hold a prompt back.

set -uo pipefail

threshold=${PERSISTENT_HANDOFF_WARN_TOKENS:-}
case $threshold in ''|*[!0-9]*) exit 0 ;; esac
# Past 18 digits the shell's test cannot compare it, and a failed comparison
# would read as "over".
[ "${#threshold}" -le 18 ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
fields=$(printf '%s' "$payload" | jq -r '(.session_id // ""), (.transcript_path // ""), (.cwd // "")' 2>/dev/null) || exit 0
{ IFS= read -r session_id; IFS= read -r transcript; IFS= read -r cwd; } <<EOF
$fields
EOF
[ -f "$transcript" ] && [ -r "$transcript" ] || exit 0

# The tail only: a long session's transcript runs to tens of megabytes, and the
# entry wanted is near the end. Lines that are not JSON are skipped, not fatal.
tokens=$(tail -n 400 "$transcript" 2>/dev/null | jq -R '
  fromjson? |
  if .type == "system" and .subtype == "compact_boundary" then 0
  elif .type == "assistant" and .isSidechain != true and .message.model != "<synthetic>"
    and .message.usage != null then
    .message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
  else empty end' 2>/dev/null | tail -n 1)
case $tokens in ''|*[!0-9]*) exit 0 ;; esac

session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')
marker="${TMPDIR:-/tmp}/persistent-handoff-warned-${session_id:-unknown}"

if [ "$tokens" -le "$threshold" ]; then
  rmdir "$marker" 2>/dev/null
  exit 0
fi
# mkdir rather than a file: it fails on an existing name instead of following a
# symlink, and two prompts racing get one reminder between them.
mkdir "$marker" 2>/dev/null || exit 0

# The path comes from session-start-handoff.sh --path, so the rule that derives
# it lives in one place. Run from CLAUDE_PROJECT_DIR, the directory the session
# started in, which is where the session start read the handoff from. The
# payload's cwd moves when the session runs cd, and naming the handoff of a
# subdirectory would get a second file written that nothing reads. No path, no
# reminder, and the marker goes so the next prompt tries again.
here=$(cd "${0%/*}" 2>/dev/null && pwd)
handoff=$(cd "${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}" 2>/dev/null && "$here/session-start-handoff.sh" --path 2>/dev/null)
[ -n "$handoff" ] || { rmdir "$marker" 2>/dev/null; exit 0; }

printf '%s' "Your context is about $tokens tokens, past the $threshold set in PERSISTENT_HANDOFF_WARN_TOKENS. A compaction is coming, and what lives only in this context will not survive it. If work is in flight, bring the handoff at $handoff current now: where you are, the next action, open questions, traps. Write it if it does not exist yet. If nothing is in flight, ignore this. This reminder comes once, and again only after the context drops back under the threshold." |
  jq -Rs '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: .}}' 2>/dev/null
exit 0
