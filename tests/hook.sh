#!/usr/bin/env bash
# Test harness for hooks/session-start-handoff.sh. Run: bash tests/hook.sh
set -u
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK=$SCRIPT_DIR/../hooks/session-start-handoff.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.claude/handoffs" "$HOME_DIR/proj-alpha"
fail=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; fail=1; }

# A minimal PATH without jq, to exercise the fallback branch. macOS ships jq in
# /usr/bin, so restricting PATH is the only way to hide it.
mkdir -p "$TMP/bin"
for b in /bin/cat /usr/bin/basename /bin/bash /usr/bin/tr; do ln -sf "$b" "$TMP/bin/"; done

payload_for() { printf '{"session_id":"abc","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"; }
PAYLOAD=$(payload_for "$HOME_DIR/proj-alpha")
run() { printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" "$HOOK"; }
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

# 1. No handoff at the derived path: silent, exit 0.
out=$(run); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "1 missing file: silent, exit 0" || ko "1 (rc=$rc out=<$out>)"

# 2. Empty handoff file: still silent. Emptiness is legitimate.
: > "$HOME_DIR/.claude/handoffs/proj-alpha.md"
out=$(run); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "2 empty file: silent, exit 0" || ko "2 (rc=$rc out=<$out>)"

# 3. Handoff at the path derived from cwd, with JSON-hostile characters.
cat > "$HOME_DIR/.claude/handoffs/proj-alpha.md" <<'EOF'
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
printf '# Handoff\n\nacme state\n' > "$HOME_DIR/.claude/handoffs/acme-api.md"
printf '# Handoff\n\nbeta state\n' > "$HOME_DIR/.claude/handoffs/beta-api.md"
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
out=$(printf '%s' "$PAYLOAD" | env PATH="$TMP/bin" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && [ "${out:0:1}" != "{" ] && echo "$out" | grep -q '04:12 backup' \
  && ok "6 no-jq fallback: raw text, no leading brace" || ko "6 (rc=$rc out=<$out>)"

# 7. REGRESSION: jq present but failing must fall back, not swallow the handoff.
mkdir -p "$TMP/badbin"
for b in /bin/cat /usr/bin/basename /bin/bash /usr/bin/tr; do ln -sf "$b" "$TMP/badbin/"; done
printf '#!/bin/sh\nexit 3\n' > "$TMP/badbin/jq"; chmod +x "$TMP/badbin/jq"
out=$(printf '%s' "$PAYLOAD" | env PATH="$TMP/badbin" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/pinned.md" "$HOOK"); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '04:12 backup' \
  && ok "7 failing jq: falls back to plain text" || ko "7 (rc=$rc out=<$out>)"

# 8. REGRESSION: a directory must not produce a preamble with an empty body.
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$HOME_DIR/.claude/handoffs" "$HOOK"); rc=$?
c=$(ctx_of "$out")
[ "$rc" -eq 0 ] && echo "$c" | grep -q 'could not be read' && ! echo "$c" | grep -q 'Start from' \
  && ok "8 directory: reports unreadable, no hollow preamble" || ko "8 (rc=$rc ctx=<$c>)"

# 9. Unreadable file: the warning reaches Claude via additionalContext, since
# stderr from a hook that exits 0 never leaves the debug log. Root ignores file
# modes entirely, so under root this scenario cannot be staged: skip, not fail.
if [ "$(id -u)" -ne 0 ]; then
  printf 'secret\n' > "$TMP/noread.md"; chmod 000 "$TMP/noread.md"
  out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/noread.md" "$HOOK"); rc=$?
  [ "$rc" -eq 0 ] && ctx_of "$out" | grep -q 'could not be read' \
    && ok "9 unreadable file: reported in additionalContext" || ko "9 (rc=$rc)"
  chmod 644 "$TMP/noread.md"
else
  echo "SKIP 9 (running as root: chmod 000 does not block reads)"
fi

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
out=$(printf '%s' "$PAYLOAD" | env PATH="$TMP/bin" HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/jsonish.md" "$HOOK")
[ "${out:0:1}" != "{" ] && echo "$out" | grep -q 'looks like hook output' \
  && ok "14 JSON-looking handoff stays behind the preamble" || ko "14"

# 15. Exotic cwd values must not crash the derived-path branch.
for c in "/" "." "$HOME_DIR/proj-alpha/" "$HOME_DIR/w e i r d"; do
  payload_for "$c" | HOME="$HOME_DIR" "$HOOK" >/dev/null 2>&1 || ko "15 cwd=$c"
done
ok "15 exotic cwd values tolerated"

# 16. A handoff over the 10k character cap still emits valid JSON. Claude Code
# replaces anything past 10k with a preview and a file path, which is why the
# skill targets 300-500 tokens.
awk 'BEGIN { print "# Handoff"; line = sprintf("%100s", ""); gsub(/ /, "x", line); for (i = 0; i < 2000; i++) print line }' > "$TMP/big.md"
out=$(printf '%s' "$PAYLOAD" | HOME="$HOME_DIR" PERSISTENT_HANDOFF_FILE="$TMP/big.md" "$HOOK")
printf '%s' "$out" | jq -e . >/dev/null 2>&1 && ok "16 oversized handoff: valid JSON" || ko "16"

# 17. A cwd outside $HOME must not share a file with the same path under $HOME:
# /var/tmp/x and ~/var/tmp/x collide without the abs- prefix (the leading dash
# of the absolute path is stripped, leaving the same slug). The hook never
# stats the cwd, so a fictive path stages the scenario exactly.
mkdir -p "$HOME_DIR/var/tmp/x"
printf 'inside home\n' > "$HOME_DIR/.claude/handoffs/var-tmp-x.md"
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
mkdir -p "$GLOB_HOME/.claude/handoffs" "$GLOB_HOME/proj"
printf 'glob home works\n' > "$GLOB_HOME/.claude/handoffs/proj.md"
out=$(payload_for "$GLOB_HOME/proj" | HOME="$GLOB_HOME" "$HOOK")
printf '%s' "$out" | grep -q 'glob home works' \
  && ok "18 \$HOME with glob metacharacters" || ko "18"

echo "---"
[ "$fail" -eq 0 ] && echo "ALL TESTS PASS" || echo "SOME TESTS FAILED"
exit "$fail"
