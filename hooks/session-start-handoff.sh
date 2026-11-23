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
#   then register it under hooks.SessionStart in settings.json
#   (see docs/INSTALL.md).
#
# Configuration:
#   PERSISTENT_HANDOFF_FILE  explicit path to the handoff. Set this for an agent
#                            that is not tied to one directory. Without it, the
#                            path comes from the working directory, turned into
#                            a slug (see below).
#   XDG_STATE_HOME           where the derived path lives. Defaults to
#                            ~/.local/state, so the handoff is
#                            ~/.local/state/persistent-handoff/<slug>.md. A
#                            relative value is ignored, as the XDG spec says.
#
# jq is used when available, both to read the payload and to escape the output.
# Without it the script uses the project and process directories and emits
# plain stdout, which Claude Code also adds to the context of a SessionStart hook.
#
# To run it by hand, feed it a payload: it reads stdin and will otherwise sit
# there waiting.
#   echo "{\"cwd\":\"$PWD\"}" | ./session-start-handoff.sh
#
# To ask where the handoff for the current directory lives, which is what an
# agent needs before it writes its first one:
#   ./session-start-handoff.sh --path

set -uo pipefail

# Past this many bytes, the handoff is injected under one line naming its size
# and asking for a prune. The skill says a handoff is state and not a journal,
# and nothing made that true: a file that only grows is read at every session
# start until a session starts skipping it. Nothing is pruned here. Deciding
# what is resolved means reading the work, which is the session's job.
#
# Bytes, not characters, and the line says so. ${#body} counts characters in a
# UTF-8 locale and bytes in the C locale, so the same accented handoff crossed
# this threshold on one machine and not on the next, and reported a size that
# was off by a factor of two. Same reason the digest below uses cksum.
#
# 8000 is four times the size the skill asks a handoff to be, so the line fires
# at a size that is a journal by any reading rather than on a judgement call.
# It is also below Claude Code's 10,000 character cap on hook output, which
# means the first handoff to trip the line is still injected whole: the ask to
# prune arrives while there is a full handoff behind it, not a preview.
HANDOFF_WARN_BYTES=8000

# --path prints the handoff path for the current directory and exits, without
# reading stdin. The derived name ends in a digest of the full path, so an agent
# writing its first handoff cannot work the name out by hand. It asks here, and
# the rule stays in one place.
#
# Anything else is refused rather than ignored: the hook reads stdin
# unconditionally on its normal path, so a mistyped flag would hang on a
# terminal instead of saying anything.
mode=${1:-}
usage() {
  printf 'usage: %s [--path | --read-path]\n' "${0##*/}" >&2
  printf '  no arguments: read a SessionStart payload on stdin, emit the handoff\n' >&2
  printf '  --path:       print the handoff path for the current directory\n' >&2
  printf '  --read-path:  read the payload and print the selected handoff path\n' >&2
  exit 2
}
[ "$#" -le 1 ] || usage
case $mode in
  ""|--path|--read-path) ;;
  *) usage ;;
esac

payload=""
[ "$mode" = --path ] || payload=$(cat)
home=${HOME:-$PWD}
home=${home%/}   # a trailing slash would silently change every derived name

# Same treatment for the other directory a derived name is built from. The XDG
# spec says a relative value is invalid and must be ignored, and it matters more
# here than in most programs: a relative handoff path resolves against the
# process's own directory, which is not the cwd the payload names, so the hook
# would answer --path with one file and read another, then go silent. Going
# silent is what this hook does when nothing is in flight.
# Claude Code protects ~/.claude ahead of any allow rule, so handoffs live in
# the state directory where the agent can write them at milestones.
state_home=${XDG_STATE_HOME:-}
case $state_home in
  /*) state_home=${state_home%/} ;;
  *)  state_home="$home/.local/state" ;;
esac

# A short digest of the absolute path. The readable slug below is lossy, so it
# alone cannot tell two directories apart: ~/my project and ~/my-project squeeze
# to the same string. cksum is POSIX and reads bytes, so the digest does not move
# with the locale the way a character-wise hash would. Twenty-four bits does not
# make the name unique, it makes a clash a coincidence rather than a certainty.
path_digest() {
  local out crc
  # cksum prints "<crc> <bytes>". Only the crc is wanted, and it is validated
  # before it reaches the arithmetic: an unexpected first field used to abort on
  # set -u, or be read as octal, and leave the name silently back at its lossy
  # 0.1.0 form.
  out=$(printf '%s' "$1" | cksum 2>/dev/null) || return 1
  crc=${out%% *}
  case $crc in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%06x' "$(( 10#$crc & 0xFFFFFF ))"
}

# ~/proj and ~/proj/ have the same handoff. Keep the slash for the root itself.
normalize_cwd() { # <variable> <directory>
  local directory=$2
  [ "$directory" = / ] || directory=${directory%/}
  printf -v "$1" '%s' "$directory"
}

handoff_name() {
  local cwd=$1 rel slug suffix digest
  # The whole path becomes the name, not just its last segment: ~/work/acme/api
  # and ~/work/beta/api are two different agents and must not share a handoff.
  # A cwd outside $HOME keeps an "abs-" prefix, and $HOME itself is named "home"
  # rather than after its own absolute path, which would collide with the same
  # path spelled out under $HOME.
  rel=${cwd#"$home"/}
  if [ "$cwd" = "$home" ]; then
    rel="home"
  elif [ "$rel" = "$cwd" ]; then
    rel="abs-$cwd"
  fi
  slug=$(printf '%s' "$rel" | tr -cs 'A-Za-z0-9._-' '-')
  slug=${slug#-}
  slug=${slug%-}
  # Reachable: a directory whose name holds no character of the keep set at all,
  # ~/€ for one, slugs to the empty string.
  [ -n "$slug" ] || slug="agent"
  # ~/work/acme/api gives work-acme-api-<digest>.md. With no usable cksum the
  # name falls back to the slug alone: still readable, still stable for this
  # directory, but lossy again, so say so somewhere a human can find it. stderr
  # from a hook that exits 0 reaches the debug log only, which is the right
  # volume for something this rare.
  suffix=""
  if digest=$(path_digest "$cwd"); then
    suffix="-$digest"
  else
    printf '%s: no usable cksum, falling back to %s.md, which cannot tell two similar paths apart\n' \
      "${0##*/}" "$slug" >&2
  fi
  # A file name holds 255 bytes, and the slug is ASCII, so characters are
  # bytes. A deep enough directory used to give a longer name, and the agent's
  # first write died on "File name too long". Past the limit only, the slug
  # keeps its last 100 characters, the end of the path a human recognises, and
  # the digest of the full path still tells two such directories apart. A name
  # that fits is left exactly as it was, so no existing handoff moves.
  if [ "$(( ${#slug} + ${#suffix} + 3 ))" -gt 255 ]; then
    slug=${slug:${#slug}-100}
    slug=${slug#-}
  fi
  printf '%s%s.md' "$slug" "$suffix"
}

exists() { [ -e "$1" ] || [ -L "$1" ]; }   # A dangling symlink needs a diagnostic.

select_handoff() {
  local candidate previous name file first="" legacy_cwd
  local seen=("")
  normalize_cwd legacy_cwd "${1:-$PWD}"
  for candidate in "${CLAUDE_PROJECT_DIR:-}" "$1" "$PWD"; do
    normalize_cwd candidate "$candidate"
    for previous in "${seen[@]}"; do
      [ "$candidate" != "$previous" ] || continue 2
    done
    seen+=("$candidate")
    name=$(handoff_name "$candidate")
    file="$state_home/persistent-handoff/$name"
    [ -n "$first" ] || first=$file
    # Keep the old migration notice for the directory we used to read.
    if [ "$candidate" = "$legacy_cwd" ]; then
      legacy_file="$home/.claude/handoffs/$name"
    fi
    # A strict comparison leaves the earliest candidate in place on a tie.
    if exists "$file" && { [ -z "$handoff_file" ] || [ "$file" -nt "$handoff_file" ]; }; then
      handoff_file=$file
    fi
  done
  # The reminder needs a path for a first write when there is no handoff yet.
  if [ "$mode" = --read-path ]; then
    handoff_file=${handoff_file:-$first}
  fi
}

legacy_file=""
handoff_file="${PERSISTENT_HANDOFF_FILE:-}"
if [ -z "$handoff_file" ]; then
  if [ "$mode" = --path ]; then
    normalize_cwd cwd "$PWD"
    handoff_file="$state_home/persistent-handoff/$(handoff_name "$cwd")"
  else
    cwd=""
    if command -v jq >/dev/null 2>&1; then
      # Join output so native jq's line ending cannot become part of the path.
      cwd=$(printf '%s' "$payload" | jq -j '.cwd // empty' 2>/dev/null)
    fi
    select_handoff "$cwd"
  fi
fi

if [ -n "$mode" ]; then
  # Both path commands can be asked before a first write. The plugin install never
  # runs the hand install's mkdir, so without this the write fails and the agent
  # is left with nowhere to put its handoff. Only when there is a directory part
  # to create: "${handoff_file%/*}" is the whole string for a bare filename, so
  # an unguarded mkdir would create a directory where the file belongs.
  # A failed mkdir used to be swallowed, which printed a confident path inside a
  # directory that does not exist: the agent's first write then died on "No such
  # file or directory" with nothing naming the cause. Exit stays 0, a hook that
  # fails the session is worse than one that warns.
  case $handoff_file in
    */*) mkdir -p "${handoff_file%/*}" 2>/dev/null ||
      printf '%s: could not create %s, the first write to this handoff will fail\n' \
        "${0##*/}" "${handoff_file%/*}" >&2 ;;
  esac
  printf '%s\n' "$handoff_file"
  exit 0
fi

# Which preamble to use. Claude Code names the start in the payload: startup,
# clear, compact, resume and fork. The first two hand the session nothing but
# this file. The last three hand it a context of its own, newer than the file
# for whatever that session already did, and the preamble has to say so or the
# session holds two states with no rule for which wins.
#
# Read below the path-only exits. When there is no jq, the source stays empty
# and the fresh-start preamble is used. It claims no precedence.
start_source=""
if command -v jq >/dev/null 2>&1; then
  start_source=$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null)
fi

emit() {
  # jq failing is treated like jq missing. Testing only for its presence would
  # drop the handoff in silence the day it exits non-zero.
  # The text reaches jq on stdin rather than as an argument. Passing it with
  # --arg puts the whole handoff in the new process's argv, and Linux caps a
  # single argument at 128 KB, so a large handoff failed the exec itself.
  if command -v jq >/dev/null 2>&1 && printf '%s' "$1" | jq -Rs \
      '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'; then
    return 0
  fi
  # The preamble comes first on purpose. A handoff whose own first line looks
  # like JSON would otherwise be read as this hook's structured output.
  printf '%s\n' "$1"
}

# The default path used to be under ~/.claude, and a handoff written back then is
# still sitting there where nothing reads it. Say so. Handing the content over
# instead reads well exactly once: the old file has no expiry, so the session
# that finishes its work and deletes its handoff, which is how this plugin says
# nothing is in flight, would be given its pre-upgrade state back at the next
# start, and at every start after that. A filename cannot go stale that way, and
# moving the file ends the message for good.
if [ -z "$handoff_file" ] && [ -n "$legacy_file" ] && exists "$legacy_file"; then
  handoff_file="$state_home/persistent-handoff/${legacy_file##*/}"
  emit "A handoff for this directory sits at $legacy_file. That is where this plugin kept handoffs before the default moved out of ~/.claude, and nothing reads it any more, so its contents are not in this session. Read that file, write it to $handoff_file, and delete the old one. After that it loads by itself again, and this message stops."
  exit 0
fi

# Nothing in flight: print nothing and exit clean. Silence is the normal case,
# and it is what makes the file's presence meaningful.
exists "$handoff_file" || exit 0

# A handoff that exists but cannot be read is a misconfiguration, not an absence,
# and it has to be reported through additionalContext: stderr from a hook that
# exits 0 reaches the debug log only, so Claude would never learn the file
# was there at all.
if [ ! -f "$handoff_file" ] || [ ! -r "$handoff_file" ]; then
  emit "A handoff exists at $handoff_file but could not be read: it is not a regular file, or it is not readable. Say so before relying on anything about the previous session."
  exit 0
fi

body=$(cat "$handoff_file" 2>/dev/null) || body=""
# Whitespace is emptiness here. A file of blank lines would otherwise buy the
# preamble with nothing behind it, which is the hollow output this hook avoids
# everywhere else.
case $body in *[![:space:]]*) ;; *) exit 0 ;; esac

# The file is measured, not $body: the two differ by the trailing newline every
# editor leaves, and a line that states a size has to state the one a human gets
# from ls or wc. tr rather than a bare expansion because wc pads its count with
# leading blanks on the BSD side, which would land in the middle of the line.
size_note=""
size_bytes=$(wc -c < "$handoff_file" 2>/dev/null | tr -cd '0-9')
[ -n "$size_bytes" ] || size_bytes=0
if [ "$size_bytes" -gt "$HANDOFF_WARN_BYTES" ]; then
  size_note="

This file is $size_bytes bytes, over the $HANDOFF_WARN_BYTES a handoff stays under. Prune what is resolved before you go further."
fi

# An unknown source takes the fresh-start preamble too. Asserting a precedence
# over a context whose shape this hook does not know is worse than asserting
# none, and a sixth source added upstream lands here first.
case $start_source in
  compact|resume|fork)
    emit "Persistent handoff, read back after a $start_source, from $handoff_file. Your context above is newer than this file for what you did in this session; the file is the reference for everything else. If they disagree, update the file. The file is state, not a conversation summary. Start from \"Next action\". Update the file at the next milestone, remove from it whatever you resolve, and delete it when nothing is left in flight.$size_note

$body"
    ;;
  *)
    emit "Persistent handoff, read from $handoff_file. This is the state the previous session left behind, not a conversation summary. Start from \"Next action\". Update the file at the next milestone, remove from it whatever you resolve, and delete it when nothing is left in flight.$size_note

$body"
    ;;
esac

exit 0
