#!/usr/bin/env bash
# Test harness for hooks/session-start-handoff.sh. Run: bash tests/hook.sh
set -u
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=$SCRIPT_DIR/../hooks/session-start-handoff.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"
# The suite stages its own handoffs at derived paths, so a PERSISTENT_HANDOFF_FILE
# inherited from the caller wins over every one of them. The README tells fleet
# operators to export exactly that, and CONTRIBUTING tells them to run this file.
# XDG_STATE_HOME moves the derived path the same way, and a machine that exports
# it would send every staged handoff somewhere the assertions do not look.
unset PERSISTENT_HANDOFF_FILE
unset XDG_STATE_HOME
# Where the derived name lands, and where it used to land. The old
# directory is created empty and stays empty: cases 1 to 37 then also say that an
# upgraded machine with nothing left in it behaves like a machine that never had
# one. Case 40 stages a file in it, in a home of its own.
STATE=$HOME_DIR/.local/state/persistent-handoff
LEGACY=$HOME_DIR/.claude/handoffs
mkdir -p "$STATE" "$LEGACY" "$HOME_DIR/proj-alpha"
fail=0
skipped=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; fail=1; }
# A skipped case asserted nothing, so the summary has to say so. A run that
# reports ALL TESTS PASS while quietly skipping four cases is the failure this
# suite refuses to allow in tests/manifests.sh.
sk() { echo "SKIP $1"; skipped=$((skipped + 1)); }

# A PATH with no jq on it, to exercise the fallback branch. Neither way of
# building one works everywhere, so both are tried and the result is checked
# before use. Dropping every directory that holds a jq is the cheap way, and it
# fails wherever jq shares a directory with bash (/usr/bin on Ubuntu). Symlinking
# the commands into a fresh directory is the other way, and it fails under Git
# Bash, where a relocated binary no longer finds its DLLs.
usable_path() { # <path>: usable when the hook's commands resolve and jq does not
  local b
  PATH="$1" type -P jq >/dev/null 2>&1 && return 1
  for b in bash cat tr; do
    PATH="$1" type -P "$b" >/dev/null 2>&1 || return 1
  done
  return 0
}

path_dropping_jq_dirs() {
  local d out=""
  local IFS=:
  set -f   # a PATH element holding a glob would otherwise expand, which is the
           # bug class test 18 defends the hook against
  for d in $PATH; do
    { [ -x "$d/jq" ] || [ -x "$d/jq.exe" ]; } && continue
    out="${out:+$out:}$d"
  done
  set +f
  printf '%s' "$out"
}

NO_JQ=""
cand=$(path_dropping_jq_dirs)
if usable_path "$cand"; then
  NO_JQ=$cand
else
  mkdir -p "$TMP/bin"
  for b in bash cat tr; do
    p=$(type -P "$b") && ln -sf "$p" "$TMP/bin/" 2>/dev/null
  done
  usable_path "$TMP/bin" && NO_JQ=$TMP/bin
fi

payload_for() { printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"; }
PAYLOAD=$(payload_for "$HOME_DIR/proj-alpha")
run() { printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" "$HOOK"; }
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

# The digest the hook appends to the slug, computed here the same way so the
# assertions below can name the file they stage. One duplicated cksum call buys
# tests that assert a path rather than only the absence of a collision.
digest_of() { printf '%s' "$1" | cksum | { read -r crc _; printf '%06x' "$((crc & 0xFFFFFF))"; }; }
# Stage a handoff for the cwd the hook will be given, and echo that cwd.
handoff_for() { # <cwd> <slug> <content>
  printf '%s' "$3" > "$STATE/$2-$(digest_of "$1").md"
}
reads() { # <cwd> <marker> -> 0 if the hook read a handoff containing <marker>
  payload_for "$1" | HOME="$HOME_DIR" "$HOOK" | grep -q "$2"
}

# 1. No handoff at the derived path: silent, exit 0.
out=$(run); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "1 missing file: silent, exit 0" || ko "1 (rc=$rc out=<$out>)"

# 2. Empty handoff file: still silent. Emptiness is legitimate.
ALPHA=$STATE/proj-alpha-$(digest_of "$HOME_DIR/proj-alpha").md
: > "$ALPHA"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "2 empty file: silent, exit 0" || ko "2 (rc=$rc out=<$out>)"

# 3. Handoff at the path derived from cwd, with JSON-hostile characters.
cat > "$ALPHA" <<'EOF'
# Handoff - alpha

## Where I am
Migration "half done": 3 of 7 tables. Backslash \ and quote " on purpose.

## Next action
Run `make migrate-next`.
EOF
out=$(run); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null \
   && ctx_of "$out" | grep -q 'make migrate-next' \
   && ctx_of "$out" | grep -q 'Backslash \\ and quote "'; then
  ok "3 derived path: valid JSON, body verbatim"
else
  ko "3 (rc=$rc)"; printf '%s\n' "$out"
fi

# 4. REGRESSION: two projects sharing a directory name must not share a handoff.
mkdir -p "$HOME_DIR/acme/api" "$HOME_DIR/beta/api"
handoff_for "$HOME_DIR/acme/api" acme-api '# Handoff

acme state
'
handoff_for "$HOME_DIR/beta/api" beta-api '# Handoff

beta state
'
a=$(payload_for "$HOME_DIR/acme/api" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'acme state')
b=$(payload_for "$HOME_DIR/beta/api" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'beta state')
cross=$(payload_for "$HOME_DIR/beta/api" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'acme state')
[ "$a" -eq 1 ] && [ "$b" -eq 1 ] && [ "$cross" -eq 0 ] \
  && ok "4 same basename, different parents: no collision" || ko "4 (a=$a b=$b cross=$cross)"

# 5. PERSISTENT_HANDOFF_FILE wins over the derived path.
printf '# Handoff - fleet\n\n## Next action\nCheck the 04:12 backup run.\n' > "$TMP/pinned.md"
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK"); rc=$?
c=$(ctx_of "$out")
[ "$rc" -eq 0 ] && echo "$c" | grep -q '04:12 backup' && ! echo "$c" | grep -q 'migrate-next' \
  && ok "5 env override wins" || ko "5 (rc=$rc)"

# 6. No jq on PATH: plain stdout fallback, and it must not start with '{'.
if [ -z "$NO_JQ" ]; then
  sk "6 (could not build a PATH without jq on this machine)"
else
  out=$(printf '%s' "$PAYLOAD" | env PATH="$NO_JQ" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK"); rc=$?
  [ "$rc" -eq 0 ] && [ "${out:0:1}" != "{" ] && echo "$out" | grep -q '04:12 backup' \
    && ok "6 no-jq fallback: raw text, no leading brace" || ko "6 (rc=$rc out=<$out>)"
fi

# 7. REGRESSION: jq present but failing must fall back, not swallow the handoff.
# A shim placed first on PATH shadows the real jq without moving any binary.
mkdir -p "$TMP/badbin"
printf '#!/bin/sh\nexit 3\n' > "$TMP/badbin/jq"; chmod +x "$TMP/badbin/jq"
out=$(printf '%s' "$PAYLOAD" | env PATH="$TMP/badbin:$PATH" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '04:12 backup' \
  && ok "7 failing jq: falls back to plain text" || ko "7 (rc=$rc out=<$out>)"

# 8. REGRESSION: a directory must not produce a preamble with an empty body.
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$STATE" "$HOOK"); rc=$?
c=$(ctx_of "$out")
[ "$rc" -eq 0 ] && echo "$c" | grep -q 'could not be read' && ! echo "$c" | grep -q 'Start from' \
  && ok "8 directory: reports unreadable, no hollow preamble" || ko "8 (rc=$rc ctx=<$c>)"

# 9. Unreadable file: the warning reaches Claude via additionalContext, since
# stderr from a hook that exits 0 never leaves the debug log. Staging it needs a
# chmod that actually denies a read, which is not true under root and not true on
# a filesystem without POSIX modes, Git Bash on Windows included. Ask whether the
# scenario took, rather than guessing from the uid.
printf 'secret\n' > "$TMP/noread.md"; chmod 000 "$TMP/noread.md"
if [ -r "$TMP/noread.md" ]; then
  sk "9 (chmod 000 does not deny reads here: root, or no POSIX file modes)"
else
  out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/noread.md" "$HOOK"); rc=$?
  [ "$rc" -eq 0 ] && ctx_of "$out" | grep -q 'could not be read' \
    && ok "9 unreadable file: reported in additionalContext" || ko "9 (rc=$rc)"
fi
chmod 644 "$TMP/noread.md"

# 10. Nominal run must keep stderr silent.
err=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK" 2>&1 >/dev/null)
[ -z "$err" ] && ok "10 nominal run: stderr silent" || ko "10 (stderr=<$err>)"

# 11. Path containing spaces.
mkdir -p "$TMP/a dir with spaces"
printf '# Handoff\n\n## Next action\nship it\n' > "$TMP/a dir with spaces/h.md"
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/a dir with spaces/h.md" "$HOOK")
ctx_of "$out" | grep -q 'ship it' && ok "11 path with spaces" || ko "11"

# 12. HOME unset must not trip `set -u`, and must print nothing on stdout.
out=$(printf '%s' "$PAYLOAD" | env -u HOME "$HOOK" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "12 HOME unset tolerated, no stray stdout" || ko "12 (rc=$rc out=<$out>)"

# 13. Malformed stdin, and empty stdin, both fall back without crashing.
for p in 'not json at all' ''; do
  out=$(printf '%s' "$p" | HOME="$HOME_DIR" "$HOOK" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || ko "13 payload=<$p> rc=$rc"
done
ok "13 malformed and empty payloads tolerated"

# 14. JSON-looking handoff must stay behind the preamble in fallback mode.
printf '{"malicious": "looks like hook output"}\n' > "$TMP/jsonish.md"
if [ -z "$NO_JQ" ]; then
  sk "14 (could not build a PATH without jq on this machine)"
else
  out=$(printf '%s' "$PAYLOAD" | env PATH="$NO_JQ" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/jsonish.md" "$HOOK")
  [ "${out:0:1}" != "{" ] && echo "$out" | grep -q 'looks like hook output' \
    && ok "14 JSON-looking handoff stays behind the preamble" || ko "14"
fi

# 15. Exotic cwd values must not crash the derived-path branch.
for c in "/" "." "$HOME_DIR/proj-alpha/" "$HOME_DIR/w e i r d"; do
  payload_for "$c" | HOME="$HOME_DIR" "$HOOK" >/dev/null 2>&1 || ko "15 cwd=$c"
done
ok "15 exotic cwd values tolerated"

# 16. REGRESSION: a runaway handoff still emits valid JSON. Handing the text to
# jq with --arg put it in the child's argv, which Linux caps at 128 KB per
# argument and macOS at 1 MB in total, so the exec failed and the hook silently
# dropped to its plain-text branch. 2 MB clears both limits.
awk 'BEGIN { print "# Handoff"; line = sprintf("%100s", ""); gsub(/ /, "x", line); for (i = 0; i < 20000; i++) print line }' > "$TMP/big.md"
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/big.md" "$HOOK")
printf '%s' "$out" | jq -e . >/dev/null 2>&1 && ok "16 oversized handoff: valid JSON" || ko "16"

# 17. A cwd outside $HOME must not share a file with the same path under $HOME.
# The abs- prefix is what keeps the two names apart, and since the digest was
# added it is no longer the only thing doing so: removing the prefix now fails
# test 21 rather than this one. This case survives as the end-to-end statement
# of the invariant. Test 21 is the one that pins the prefix itself.
mkdir -p "$HOME_DIR/var/tmp/x"
handoff_for "$HOME_DIR/var/tmp/x" var-tmp-x 'inside home
'
out=$(payload_for "/var/tmp/x" | HOME="$HOME_DIR" "$HOOK")
if printf '%s' "$out" | grep -q 'inside home'; then
  ko "17 outside-\$HOME cwd read the in-home handoff (collision)"
else
  ok "17 outside-\$HOME cwd gets its own file"
fi

# 18. A $HOME containing glob metacharacters must still strip cleanly: an
# unquoted \$home in the prefix-strip turns [1] into a character class and the
# derived name silently changes.
GLOB_HOME="$TMP/h[1]"
mkdir -p "$GLOB_HOME/.local/state/persistent-handoff" "$GLOB_HOME/proj"
printf 'glob home works\n' > "$GLOB_HOME/.local/state/persistent-handoff/proj-$(digest_of "$GLOB_HOME/proj").md"
out=$(payload_for "$GLOB_HOME/proj" | HOME="$GLOB_HOME" "$HOOK")
printf '%s' "$out" | grep -q 'glob home works' \
  && ok "18 \$HOME with glob metacharacters" || ko "18"

# The cwd is never stat'ed by the hook, so tests 19 to 22 stage their scenarios
# with fictive paths. That keeps them off the filesystem's own opinions about
# non-ASCII names, which differ between macOS, Linux and Git Bash.

# 19. REGRESSION: the readable slug is lossy, so two directories that differ only
# outside its keep set must still get two files. tr replaces every byte outside
# 'A-Za-z0-9._-' and squeezes runs, so the two bytes of a u-umlaut collapse with
# the preceding slash into the single dash that ~/dev/ber already produces.
UMLAUT_DIR=$HOME_DIR/dev/$'\303\274'ber   # ~/dev/über, written as explicit bytes
handoff_for "$UMLAUT_DIR" dev-ber 'umlaut state
'
handoff_for "$HOME_DIR/dev/ber" dev-ber 'plain state
'
if reads "$UMLAUT_DIR" 'umlaut state' && reads "$HOME_DIR/dev/ber" 'plain state' \
   && ! reads "$UMLAUT_DIR" 'plain state' && ! reads "$HOME_DIR/dev/ber" 'umlaut state'; then
  ok "19 non-ASCII sibling: no collision"
else
  ko "19 (~/dev/ueber and ~/dev/ber share a handoff)"
fi

# 20. REGRESSION: a space and a dash both become a dash, so ~/my project and
# ~/my-project are one file without a digest.
handoff_for "$HOME_DIR/my project" my-project 'space state
'
handoff_for "$HOME_DIR/my-project" my-project 'dash state
'
if reads "$HOME_DIR/my project" 'space state' && reads "$HOME_DIR/my-project" 'dash state' \
   && ! reads "$HOME_DIR/my project" 'dash state' && ! reads "$HOME_DIR/my-project" 'space state'; then
  ok "20 space versus dash: no collision"
else
  ko "20 (~/my project and ~/my-project share a handoff)"
fi

# 21. REGRESSION: the abs- prefix alone does not separate an outside-$HOME cwd
# from an in-$HOME directory literally named abs, because tr squeezes "abs-" and
# the leading "/" of the absolute path into one dash. This is test 17 one level up.
handoff_for "$HOME_DIR/abs/var/tmp/x" abs-var-tmp-x 'in-home abs dir
'
handoff_for "/var/tmp/x" abs-var-tmp-x 'outside home
'
if reads "$HOME_DIR/abs/var/tmp/x" 'in-home abs dir' && reads "/var/tmp/x" 'outside home' \
   && ! reads "$HOME_DIR/abs/var/tmp/x" 'outside home' && ! reads "/var/tmp/x" 'in-home abs dir'; then
  ok "21 in-home abs/ versus outside \$HOME: no collision"
else
  ko "21 (~/abs/var/tmp/x and /var/tmp/x share a handoff)"
fi

# 22. cwd == $HOME must not be named after its own absolute path: the prefix strip
# carries a trailing slash and does not fire, and the abs- guard is skipped, so ~
# used to be read as <state>/Users-alice.md and collided with ~/Users/alice.
handoff_for "$HOME_DIR" home 'home itself
'
reads "$HOME_DIR" 'home itself' && ok "22 cwd == \$HOME is named home" \
  || ko "22 (cwd == \$HOME did not read home-<digest>.md)"

# 23. A dangling symlink exists as far as the user is concerned, and swallowing it
# contradicts the unreadable-file branch six lines below: report, do not go silent.
ln -s "$TMP/nowhere-at-all" "$TMP/dangling.md" 2>/dev/null || true
if [ -L "$TMP/dangling.md" ] && [ ! -e "$TMP/dangling.md" ]; then
  out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/dangling.md" "$HOOK"); rc=$?
  [ "$rc" -eq 0 ] && ctx_of "$out" | grep -q 'could not be read' \
    && ok "23 dangling symlink: reported, not swallowed" || ko "23 (rc=$rc out=<$out>)"
else
  sk "23 (this filesystem will not stage a dangling symlink)"
fi

# 24. A whitespace-only handoff is empty in every sense that matters, and emitting
# the preamble with nothing behind it is the hollow output test 8 already rejects.
printf '   \n\t\n' > "$TMP/blank.md"
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/blank.md" "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "24 whitespace-only handoff: silent" || ko "24 (rc=$rc out=<$out>)"

# 25. --path reports the handoff path for the current directory and exits. The
# derived name ends in a digest, so an agent writing its first handoff cannot
# work the name out by hand. It asks here instead, which keeps one source of
# truth. The payload names a different cwd on purpose: --path must answer for
# the process's own directory and must not wait on stdin.
p=$(cd "$HOME_DIR/proj-alpha" && payload_for "$HOME_DIR/acme/api" | HOME="$HOME_DIR" "$HOOK" --path)
[ "$p" = "$ALPHA" ] && ok "25 --path agrees with the path the hook reads" \
  || ko "25 (--path=<$p> expected=<$ALPHA>)"

# 26. --path is the moment before a first write, so the directory it names has to
# be writable. The plugin install never runs the hand install's mkdir, so without
# this the agent's first handoff fails with "No such file or directory" and the
# hook it was supposed to feed goes on reporting nothing in flight.
# A mkdir that worked stays silent, which is the half case 37 does not cover:
# warn on every call and 37 is still green, while the agent reads the warning on
# every first write.
FRESH=$TMP/fresh-home
mkdir -p "$FRESH"
p=$(cd "$TMP" && HOME="$FRESH" "$HOOK" --path 2>"$TMP/fresh.err")
err=$(cat "$TMP/fresh.err")
if printf 'first handoff\n' > "$p" 2>/dev/null && [ -f "$p" ] && [ -z "$err" ]; then
  ok "26 --path creates the handoff directory, so the first write lands"
else
  ko "26 (path=<$p> stderr=<$err>)"
fi

# 27. REGRESSION: a cksum that prints something unexpected must not crash the
# arithmetic. A non-numeric first field tripped `set -u`, and a leading zero was
# read as octal, both leaking to stderr and silently reverting the name to the
# lossy 0.1.0 slug.
# The verdict is a flag of its own, like cases 33 and 34. Reading the global
# `fail` here meant one failure anywhere above swallowed this case whole: no
# PASS, no FAIL, and a run that quietly printed 36 lines instead of 37.
mkdir -p "$TMP/oddbin"
t27=1
for bad in 'garbage 12' '0891 12' '' '-5 12'; do
  printf '#!/bin/sh\necho "%s"\n' "$bad" > "$TMP/oddbin/cksum"; chmod +x "$TMP/oddbin/cksum"
  err=$(cd "$TMP" && env PATH="$TMP/oddbin:$PATH" HOME="$HOME_DIR" "$HOOK" --path 2>&1 >/dev/null)
  case $err in
    *"unbound variable"*|*"value too great"*|*"syntax error"*)
      ko "27 cksum printing <$bad> leaks a shell error: $err"; t27=0; break ;;
  esac
done
[ "$t27" -eq 1 ] && ok "27 unexpected cksum output: no shell error on stderr"
rm -f "$TMP/oddbin/cksum"

# 28. An argument that is not --path must not hang waiting on a payload. The hook
# reads stdin unconditionally otherwise, so `--help` on a terminal just sits there.
out=$(printf '' | "$HOOK" --help 2>&1); rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'usage' \
  && ok "28 unknown argument: usage on stderr, non-zero exit" || ko "28 (rc=$rc out=<$out>)"

# 29. REGRESSION: a trailing slash on cwd names the same directory, so it must
# name the same handoff. The digest is taken over the raw string, so without
# normalising, ~/proj and ~/proj/ became two files for one directory.
handoff_for "$HOME_DIR/slashy" slashy 'slash state
'
if reads "$HOME_DIR/slashy" 'slash state' && reads "$HOME_DIR/slashy/" 'slash state'; then
  ok "29 trailing slash on cwd reads the same handoff"
else
  ko "29 (~/slashy and ~/slashy/ do not agree)"
fi

# 30. With no usable cksum the name degrades to the bare slug, which is the
# lossy 0.1.0 behaviour. That is the right call for a hook that must never break
# a session, but it silently changes which file is read, so it has to announce
# itself on stderr. A shim that exits non-zero stages it without touching PATH
# resolution for anything else.
mkdir -p "$TMP/nocksum"
printf '#!/bin/sh\nexit 127\n' > "$TMP/nocksum/cksum"; chmod +x "$TMP/nocksum/cksum"
printf 'degraded state\n' > "$STATE/proj-alpha.md"
out=$(printf '%s' "$PAYLOAD" | env PATH="$TMP/nocksum:$PATH" HOME="$HOME_DIR" "$HOOK" 2>"$TMP/degraded.err"); rc=$?
err=$(cat "$TMP/degraded.err")
if [ "$rc" -eq 0 ] && ctx_of "$out" | grep -q 'degraded state' && printf '%s' "$err" | grep -q 'no usable cksum'; then
  ok "30 no cksum: falls back to the bare slug and says so on stderr"
else
  ko "30 (rc=$rc err=<$err>)"
fi

# 31. REGRESSION: --path must not turn a slashless PERSISTENT_HANDOFF_FILE into a
# directory. "${handoff_file%/*}" is the whole string when there is no slash, so
# `handoff.md` used to be created as a directory, and every session start after
# that reported a handoff that could not be read.
mkdir -p "$TMP/slashless" && (
  cd "$TMP/slashless" && HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="handoff.md" "$HOOK" --path >/dev/null 2>&1
)
[ ! -d "$TMP/slashless/handoff.md" ] \
  && ok "31 slashless pinned path: no directory created in its place" \
  || ko "31 (handoff.md was created as a directory)"

# 32. An extra argument after --path is a typo, not a request. Accepting it would
# print a confident path for a command the caller did not mean.
out=$(printf '' | "$HOOK" --path --nonsense 2>&1); rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'usage' \
  && ok "32 --path with an extra argument is refused" || ko "32 (rc=$rc out=<$out>)"

# 33. The three sources that hand the session a context of its own get the
# precedence preamble instead of the fresh-start one. Without it the agent holds
# two states after a compact, its summary and this file, with no rule saying
# which wins for what.
src_ok=1
for src in compact resume fork; do
  p=$(printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$HOME_DIR/proj-alpha" "$src")
  c=$(printf '%s' "$p" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
  printf '%s' "$c" | grep -q "read back after a $src" || src_ok=0
  # The direction of the rule, spelled out. Without this assertion the preamble
  # can be inverted, "this file is newer than your context", and the suite stays
  # green while telling the agent to throw away the work it just did.
  printf '%s' "$c" | grep -q 'Your context above is newer than this file' || src_ok=0
  printf '%s' "$c" | grep -q 'the file is the reference for everything else' || src_ok=0
  printf '%s' "$c" | grep -q 'If they disagree, update the file' || src_ok=0
  # The instructions the other preamble carries. A compacted session is exactly
  # the one that no longer has them, so this branch has to repeat them.
  printf '%s' "$c" | grep -q 'not a conversation summary' || src_ok=0
  printf '%s' "$c" | grep -q 'Start from "Next action"' || src_ok=0
  printf '%s' "$c" | grep -q 'delete it when nothing is left in flight' || src_ok=0
  printf '%s' "$c" | grep -q 'state the previous session left behind' && src_ok=0
  printf '%s' "$c" | grep -q 'make migrate-next' || src_ok=0
  printf '%s' "$c" | grep -q "$ALPHA" || src_ok=0
done
[ "$src_ok" -eq 1 ] \
  && ok "33 compact, resume and fork get the precedence preamble" || ko "33 (one of compact/resume/fork)"

# 34. startup and clear are the starts with nothing behind them. They keep the
# original preamble, which claims no precedence because there is nothing to
# take precedence over.
fresh_ok=1
for src in startup clear; do
  p=$(printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$HOME_DIR/proj-alpha" "$src")
  c=$(printf '%s' "$p" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
  printf '%s' "$c" | grep -q 'state the previous session left behind' || fresh_ok=0
  printf '%s' "$c" | grep -q 'read back after a' && fresh_ok=0
done
[ "$fresh_ok" -eq 1 ] && ok "34 startup and clear keep the fresh-start preamble" || ko "34"

# 35. A payload with no source at all, and one with a source this hook has never
# heard of. Both take the fresh-start preamble: claiming a precedence on a start
# whose shape is unknown is the one thing worse than claiming none.
no_src=$(printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart"}' "$HOME_DIR/proj-alpha" \
  | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
odd_src=$(printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"teleport"}' "$HOME_DIR/proj-alpha" \
  | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$no_src" | grep -q 'state the previous session left behind' \
   && ! printf '%s' "$no_src" | grep -q 'read back after a' \
   && printf '%s' "$odd_src" | grep -q 'state the previous session left behind' \
   && ! printf '%s' "$odd_src" | grep -q 'read back after a'; then
  ok "35 absent or unknown source: fresh-start preamble"
else
  ko "35"
fi

# 36. No jq, so the source cannot be read. Same fallback as the cwd on that
# branch: the hook stops guessing and takes the preamble that asserts nothing.
# The handoff itself must still come out, on the plain-text path.
if [ -z "$NO_JQ" ]; then
  sk "36 (could not build a PATH without jq on this machine)"
else
  # The path is pinned for the same reason case 6 pins it: with no jq the hook
  # cannot read cwd out of the payload either, and falls back to $PWD. This case
  # is about the preamble, not about the derived name.
  out=$(printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"compact"}' "$HOME_DIR/proj-alpha" \
    | env PATH="$NO_JQ" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK")
  if printf '%s' "$out" | grep -q 'state the previous session left behind' \
     && ! printf '%s' "$out" | grep -q 'read back after a' \
     && printf '%s' "$out" | grep -q '04:12 backup'; then
    ok "36 no jq: source unreadable, fresh-start preamble, handoff still emitted"
  else
    ko "36"; printf '%s\n' "$out"
  fi
fi

# 37. --path creates the directory it names, and has to say so when it cannot.
# The mkdir was `|| true`, so a read-only state directory produced a confident
# path inside a directory that does not exist: exit 0, stderr empty, and the
# agent's first write then died on "No such file or directory" with nothing
# pointing at the cause. The exit code stays 0 on purpose, a SessionStart hook
# that fails the session is worse than one that warns.
RO=$TMP/ro-home
mkdir -p "$RO/.local/state"
chmod 555 "$RO/.local/state" 2>/dev/null
p=$(cd "$TMP" && HOME="$RO" "$HOOK" --path 2>"$TMP/ro.err"); rc=$?
err=$(cat "$TMP/ro.err")
if [ -d "$RO/.local/state/persistent-handoff" ]; then
  sk "37 (a 555 directory is still writable here: root, or no POSIX file modes)"
elif [ "$rc" -eq 0 ] && [ -n "$p" ] && printf '%s' "$err" | grep -q 'could not create'; then
  ok "37 --path reports the directory it could not create"
else
  ko "37 (rc=$rc path=<$p> stderr=<$err>)"
fi
chmod 755 "$RO/.local/state" 2>/dev/null

# 38. The derived path is outside ~/.claude. Claude Code treats that whole
# directory as protected: a session in default or acceptEdits is prompted before
# the agent writes there, and a session set to refuse never writes at all. The
# handoff the agent must write unprompted at a milestone cannot live behind that.
p=$(cd "$HOME_DIR/proj-alpha" && HOME="$HOME_DIR" "$HOOK" --path)
case $p in
  "$STATE/proj-alpha-$(digest_of "$HOME_DIR/proj-alpha").md")
    ok "38 derived path is ~/.local/state/persistent-handoff, outside .claude" ;;
  *) ko "38 (--path=<$p>)" ;;
esac

# 39. XDG_STATE_HOME moves the state directory, which is the point of naming it.
# A machine that sets it keeps every other state file there and would be the one
# machine where this one is somewhere else.
XDG=$TMP/xdg
p=$(cd "$HOME_DIR/proj-alpha" && HOME="$HOME_DIR" XDG_STATE_HOME="$XDG" "$HOOK" --path)
[ "$p" = "$XDG/persistent-handoff/proj-alpha-$(digest_of "$HOME_DIR/proj-alpha").md" ] \
  && ok "39 XDG_STATE_HOME moves the derived path" || ko "39 (--path=<$p>)"

# 40. A handoff written before the path moved is still under ~/.claude, where
# nothing reads it any more. The hook says so, naming the file and where it
# belongs. It does not hand the content over: see case 42 for why.
LEG_HOME=$TMP/legacy-home
LEG_STATE=$LEG_HOME/.local/state/persistent-handoff
mkdir -p "$LEG_HOME/.claude/handoffs" "$LEG_HOME/proj"
LEG_NAME=proj-$(digest_of "$LEG_HOME/proj").md
printf 'legacy state\n' > "$LEG_HOME/.claude/handoffs/$LEG_NAME"
c=$(payload_for "$LEG_HOME/proj" | HOME="$LEG_HOME" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$c" | grep -qF "$LEG_HOME/.claude/handoffs/$LEG_NAME" \
   && printf '%s' "$c" | grep -qF "$LEG_STATE/$LEG_NAME" \
   && printf '%s' "$c" | grep -q 'sits at' \
   && ! printf '%s' "$c" | grep -q 'legacy state'; then
  ok "40 handoff left at the old path: reported, not injected"
else
  ko "40 (ctx=<$c>)"
fi

# 41. Once the current path holds a handoff, it is the only one that speaks. The
# old file is left where it is and nothing about it reaches the session: two
# states with a rule saying which wins is what this plugin refuses everywhere.
mkdir -p "$LEG_STATE"
printf 'current state\n' > "$LEG_STATE/$LEG_NAME"
c=$(payload_for "$LEG_HOME/proj" | HOME="$LEG_HOME" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$c" | grep -q 'current state' \
   && ! printf '%s' "$c" | grep -q 'legacy state' \
   && ! printf '%s' "$c" | grep -q 'sits at'; then
  ok "41 current path wins over the old one, with no notice"
else
  ko "41 (ctx=<$c>)"
fi

# 42. REGRESSION: the old file must never come back as state. Deleting the
# handoff is how this plugin says nothing is in flight, and the old file has no
# expiry, so a hook that injected it would hand a finished agent its pre-upgrade
# work back at every start, for as long as the file existed. The notice names
# the file instead, which cannot go stale, and the session ends it by moving the
# file. The body has to stay out of the session either way.
rm "$LEG_STATE/$LEG_NAME"
c=$(payload_for "$LEG_HOME/proj" | HOME="$LEG_HOME" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
if ! printf '%s' "$c" | grep -q 'legacy state' \
   && ! printf '%s' "$c" | grep -q 'state the previous session left behind' \
   && printf '%s' "$c" | grep -q 'sits at'; then
  ok "42 deleted handoff is not resurrected from the old path"
else
  ko "42 (ctx=<$c>)"
fi
printf 'current state\n' > "$LEG_STATE/$LEG_NAME"

# 43. XDG_STATE_HOME is normalised the way $HOME is. The spec says a relative
# value is invalid and must be ignored, and ignoring it matters more here than
# elsewhere: a relative handoff path resolves against the process's directory,
# which is not the cwd the payload names, so the hook would write and read two
# different files and go silent instead of saying anything. A trailing slash
# doubles in a path the preamble prints.
WANT=$STATE/proj-alpha-$(digest_of "$HOME_DIR/proj-alpha").md
rel=$(cd "$HOME_DIR/proj-alpha" && HOME="$HOME_DIR" XDG_STATE_HOME="rel/state" "$HOOK" --path)
slash=$(cd "$HOME_DIR/proj-alpha" && HOME="$HOME_DIR" XDG_STATE_HOME="$HOME_DIR/.local/state/" "$HOOK" --path)
[ "$rel" = "$WANT" ] && [ "$slash" = "$WANT" ] \
  && ok "43 XDG_STATE_HOME: a relative value is ignored, a trailing slash does not double" \
  || ko "43 (relative=<$rel> trailing-slash=<$slash> expected=<$WANT>)"

# 44. A handoff that grew into a journal is told its own size. The skill says
# prune on every update, and nothing made that true: a file that only grows is
# read at every session start until a session skips it. The line is advisory,
# the hook prunes nothing, and the handoff still comes through whole.
BIG_DIR=$HOME_DIR/proj-big
mkdir -p "$BIG_DIR"
# MARKER plus a newline is 7 characters, so the file is 8001: one past the
# threshold, which is where a -ge would pass and a -gt is meant to.
big=$(printf 'MARKER\n%*s' 7994 '' | tr ' ' x)
handoff_for "$BIG_DIR" proj-big "$big"
c=$(payload_for "$BIG_DIR" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$c" | grep -q 'This file is 8001 characters, over the 8000 a handoff stays under. Prune what is resolved before you go further.' \
   && printf '%s' "$c" | grep -q 'MARKER' \
   && printf '%s' "$c" | grep -q 'state the previous session left behind'; then
  ok "44 a handoff over 8000 characters is told its size, and still injected"
else
  ko "44 (ctx=<$(printf '%s' "$c" | head -c 400)>)"
fi

# A compact, a resume and a fork read the same file and take the other preamble.
# A file that grew is the same file whichever start reads it.
c=$(printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"compact"}' "$BIG_DIR" \
  | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
printf '%s' "$c" | grep -q 'This file is 8001 characters, over the 8000' \
  && ok "44b the size line is on the compact, resume and fork preamble too" \
  || ko "44b (ctx=<$(printf '%s' "$c" | head -c 400)>)"

# 45. Exactly at the threshold is silent. The size line costs context of its own
# and repeats at every session start, so the boundary has to be a size a handoff
# is allowed to be, not one it is nagged about.
printf 'MARKER\n%*s' 7993 '' | tr ' ' x > "$STATE/proj-big-$(digest_of "$BIG_DIR").md"
c=$(payload_for "$BIG_DIR" | HOME="$HOME_DIR" "$HOOK" | jq -r '.hookSpecificOutput.additionalContext')
if ! printf '%s' "$c" | grep -q 'characters, over the' \
   && printf '%s' "$c" | grep -q 'MARKER'; then
  ok "45 a handoff of exactly 8000 characters says nothing about its size"
else
  ko "45 (ctx=<$(printf '%s' "$c" | head -c 400)>)"
fi

echo "---"
[ "$skipped" -eq 0 ] || echo "$skipped case(s) skipped: they asserted nothing here"
[ "$fail" -eq 0 ] && echo "ALL TESTS PASS" || echo "SOME TESTS FAILED"
exit "$fail"
