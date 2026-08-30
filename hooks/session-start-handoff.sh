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
#
# jq is used when available, both to read the payload and to escape the output.
# Without it the script falls back to $PWD and to plain stdout, which Claude
# Code also adds to the context of a SessionStart hook.
#
# To run it by hand, feed it a payload: it reads stdin and will otherwise sit
# there waiting.
#   echo "{\"cwd\":\"$PWD\"}" | ./session-start-handoff.sh
#
# To ask where the handoff for the current directory lives, which is what an
# agent needs before it writes its first one:
#   ./session-start-handoff.sh --path

set -uo pipefail

# --path prints the handoff path for the current directory and exits, without
# reading stdin. The derived name ends in a digest of the full path, so an agent
# writing its first handoff cannot work the name out by hand. It asks here, and
# the rule stays in one place.
#
# Anything else is refused rather than ignored: the hook reads stdin
# unconditionally on its normal path, so a mistyped flag would hang on a
# terminal instead of saying anything.
want_path=""
usage() {
  printf 'usage: %s [--path]\n' "${0##*/}" >&2
  printf '  no arguments: read a SessionStart payload on stdin, emit the handoff\n' >&2
  printf '  --path:       print the handoff path for the current directory\n' >&2
  exit 2
}
[ "$#" -le 1 ] || usage
case ${1:-} in
  "") ;;
  --path) want_path=yes ;;
  *) usage ;;
esac

payload=""
[ -n "$want_path" ] || payload=$(cat)
home=${HOME:-$PWD}
home=${home%/}   # a trailing slash would silently change every derived name

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

handoff_file="${PERSISTENT_HANDOFF_FILE:-}"
if [ -z "$handoff_file" ]; then
  cwd=""
  if command -v jq >/dev/null 2>&1; then
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  fi
  [ -n "$cwd" ] || cwd="$PWD"
  # ~/proj and ~/proj/ are one directory and must be one handoff. The digest is
  # taken over the string, so the slash has to go before it is computed.
  [ "$cwd" = "/" ] || cwd=${cwd%/}

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
  if digest=$(path_digest "$cwd"); then
    slug="$slug-$digest"
  else
    printf '%s: no usable cksum, falling back to %s.md, which cannot tell two similar paths apart\n' \
      "${0##*/}" "$slug" >&2
  fi
  handoff_file="$home/.claude/handoffs/$slug.md"
fi

if [ -n "$want_path" ]; then
  # --path is asked immediately before a first write. The plugin install never
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
# Read below the --path exit, which has no payload to read and would spawn a jq
# for nothing. Same fallback as the cwd above when there is no jq at all: the
# source stays empty and the fresh-start preamble is used. It claims no
# precedence, so it is the safe one to be wrong with.
start_source=""
if command -v jq >/dev/null 2>&1; then
  start_source=$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null)
fi

# Nothing in flight: print nothing and exit clean. Silence is the normal case,
# and it is what makes the file's presence meaningful. -e is false for a dangling
# symlink, which is a broken handoff rather than an absent one, so -L catches it
# and the unreadable branch below reports it.
[ -e "$handoff_file" ] || [ -L "$handoff_file" ] || exit 0

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

# An unknown source takes the fresh-start preamble too. Asserting a precedence
# over a context whose shape this hook does not know is worse than asserting
# none, and a sixth source added upstream lands here first.
case $start_source in
  compact|resume|fork)
    emit "Persistent handoff, read back after a $start_source, from $handoff_file. Your context above is newer than this file for what you did in this session; the file is the reference for everything else. If they disagree, update the file. The file is state, not a conversation summary. Start from \"Next action\". Update the file at the next milestone, remove from it whatever you resolve, and delete it when nothing is left in flight.

$body"
    ;;
  *)
    emit "Persistent handoff, read from $handoff_file. This is the state the previous session left behind, not a conversation summary. Start from \"Next action\". Update the file at the next milestone, remove from it whatever you resolve, and delete it when nothing is left in flight.

$body"
    ;;
esac

exit 0
