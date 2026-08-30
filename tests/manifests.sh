#!/usr/bin/env bash
# Test harness for the plugin manifests. Run: bash tests/manifests.sh
#
# The manifests are only read by Claude Code at install time, so a typo in one
# of them fails for the user and never for us. These checks are the cheap part
# of that feedback loop; `claude plugin validate .` is the authoritative one.
set -u
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
fail=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; fail=1; }

# Every assertion below reads JSON with jq, so no jq means this suite proves
# nothing. Reporting that as success is worse than having no suite at all.
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is not on PATH, and every check in this file needs it."
  echo "      Install jq (apt install jq, brew install jq, choco install jq) and re-run."
  exit 1
fi

PLUGIN=$ROOT/.claude-plugin/plugin.json
HOOKS=$ROOT/hooks/hooks.json
MARKET=$ROOT/.claude-plugin/marketplace.json

# 1. All three manifests parse. A trailing comma here breaks the install and
# nothing else, so it has to be caught here.
for f in "$PLUGIN" "$HOOKS" "$MARKET"; do
  jq -e . "$f" >/dev/null 2>&1 || ko "1 $f is not valid JSON"
done
[ "$fail" -eq 0 ] && ok "1 the three manifests are valid JSON"

# 2. plugin.json carries the one field Claude Code requires, in kebab-case.
n=$(jq -r '.name // empty' "$PLUGIN")
[ "$n" = "persistent-handoff" ] && ok "2 plugin name" || ko "2 (name=<$n>)"

# 3. The hook points at the script through ${CLAUDE_PLUGIN_ROOT}. An absolute
# or relative path would resolve against the user's machine, not the installed
# plugin, and the hook would silently never fire.
cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$HOOKS")
case $cmd in
  *'${CLAUDE_PLUGIN_ROOT}'*hooks/session-start-handoff.sh)
    ok "3 SessionStart command uses \${CLAUDE_PLUGIN_ROOT}" ;;
  *) ko "3 (command=<$cmd>)" ;;
esac

# 4. REGRESSION: the script the hook names must exist and be executable. The
# plugin is copied to a cache directory as-is, so a lost exec bit ships broken.
script=$ROOT/hooks/session-start-handoff.sh
[ -x "$script" ] && ok "4 hook script exists and is executable" || ko "4 ($script)"

# 5. One SessionStart entry, and no matcher on it. The hook must run on all five
# sources: the handoff has to be present after a compaction, where the summary
# decides on its own what survives. The preamble carries the precedence rule
# instead, which is what keeps that from being a double state. A matcher added
# here would take the guarantee away silently, and a second entry would inject
# the handoff twice.
jq -e '.hooks.SessionStart | length == 1 and all(has("matcher") | not)' "$HOOKS" >/dev/null \
  && ok "5 one SessionStart entry, no matcher" || ko "5 (entries=$(jq -c '.hooks.SessionStart' "$HOOKS"))"

# 6. The marketplace entry points at the repository root, which is where
# plugin.json lives. Any other source path resolves to a directory with no
# manifest in it.
src=$(jq -r '.plugins[0].source // empty' "$MARKET")
[ "$src" = "./" ] && ok "6 marketplace source is the repo root" || ko "6 (source=<$src>)"

# 7. The install command in the README is `<plugin>@<marketplace>`, built from
# these two names. They are what users type, so a rename here is a breaking
# change and must break a test.
mn=$(jq -r '.name // empty' "$MARKET")
pn=$(jq -r '.plugins[0].name // empty' "$MARKET")
[ "$mn" = "persistent-handoff" ] && [ "$pn" = "persistent-handoff" ] \
  && ok "7 install id is persistent-handoff@persistent-handoff" || ko "7 (mn=$mn pn=$pn)"

# 8. The marketplace requires an owner with a name.
jq -e '.owner.name | type == "string" and length > 0' "$MARKET" >/dev/null \
  && ok "8 marketplace owner named" || ko "8 owner missing"

# 9. Versions agree. The marketplace entry pins the version users get, so a
# plugin.json bumped alone would ship the old string forever.
pv=$(jq -r '.version // empty' "$PLUGIN")
mv=$(jq -r '.plugins[0].version // empty' "$MARKET")
[ -n "$pv" ] && [ "$pv" = "$mv" ] && ok "9 versions agree ($pv)" || ko "9 (plugin=$pv marketplace=$mv)"

# 10. The skill stays where both install paths expect it. The plugin loader
# auto-discovers skills/<name>/SKILL.md at the plugin root, and the hand install
# in docs/INSTALL.md copies the same directory. Moving it breaks both at once.
[ -f "$ROOT/skills/persistent-handoff/SKILL.md" ] \
  && ok "10 skill at skills/persistent-handoff/SKILL.md" || ko "10 skill moved"

# 11. The changelog's top entry is the version the manifests ship. v0.1.0 was
# tagged on a tree that did not contain the plugin, because nothing tied the
# version string to a record of what changed. This is that tie.
cv=$(grep -m1 -o '^## \[[0-9][0-9.]*\]' "$ROOT/CHANGELOG.md" 2>/dev/null | tr -d '#[] ')
[ -n "$cv" ] && [ "$cv" = "$pv" ] \
  && ok "11 changelog's top entry is $pv" || ko "11 (changelog=<$cv> plugin=<$pv>)"

# 12. The demo wires the same hook through settings.json. Second copy of the
# same shape, and it drifts the moment one of the two is edited alone.
DEMO=$ROOT/demo/homelab/.claude/settings.json
jq -e '.hooks.SessionStart | length == 1 and all(has("matcher") | not)' "$DEMO" >/dev/null \
  && ok "12 demo settings: one entry, no matcher" || ko "12 (demo=$(jq -c '.hooks.SessionStart' "$DEMO"))"

# 13. The hand-install snippet is the third copy, and the one users actually
# paste. It moved out of the README into docs/INSTALL.md in 0.2.3; the block is
# pulled back out of the prose there and held to the same shape.
DOC=$ROOT/docs/INSTALL.md
snippet=$(awk '/^```json$/{b=1;s="";next} b&&/^```$/{if(s~/SessionStart/){print s;exit} b=0;s="";next} b{s=s $0 "\n"}' "$DOC")
if printf '%s' "$snippet" | jq -e '.hooks.SessionStart | length == 1 and all(has("matcher") | not)' >/dev/null 2>&1; then
  ok "13 docs/INSTALL.md snippet: one entry, no matcher"
else
  ko "13 (install doc=$(printf '%s' "$snippet" | jq -c '.hooks.SessionStart' 2>&1))"
fi

# 14. The one path in the repo that nothing else resolves. SKILL.md tells the
# agent to run the hook through ${CLAUDE_SKILL_DIR}, which Claude Code expands
# when it loads the file, so a wrong suffix breaks on the user's machine and
# never here. Pull the suffix back out of the prose and resolve it against the
# skill's own directory, which is what ${CLAUDE_SKILL_DIR} stands for.
# It has to be the hook itself, and it has to ask for --path: [ -x ] alone is
# true of a directory, and without --path the agent's call reads stdin until
# something kills it, which is what cases 28 and 32 defend at the CLI level.
SKILL=$ROOT/skills/persistent-handoff/SKILL.md
ref=$(grep -o '\${CLAUDE_SKILL_DIR}/[^"'\''`[:space:]]*' "$SKILL" | head -1)
suffix=${ref#'${CLAUDE_SKILL_DIR}/'}
target=$ROOT/skills/persistent-handoff/$suffix
# cd normalises the ../.. without needing realpath, which macOS does not ship.
# `-ef` would be one line and is not dependable under Git Bash.
resolve() { [ -n "${1:-}" ] && [ -f "$1" ] && ( cd "$(dirname "$1")" && printf '%s/%s' "$(pwd -P)" "$(basename "$1")" ); }
got=$(resolve "$target")
want=$(resolve "$script")
if [ -n "$got" ] && [ "$got" = "$want" ] && [ -x "$target" ] \
   && grep -qF "$ref\" --path" "$SKILL"; then
  ok "14 SKILL.md runs the hook itself, with --path ($suffix)"
else
  ko "14 (suffix=<$suffix> resolved=<$got> expected=<$want>)"
fi

echo "---"
[ "$fail" -eq 0 ] && echo "ALL TESTS PASS" || echo "SOME TESTS FAILED"
exit "$fail"
