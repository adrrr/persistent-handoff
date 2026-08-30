#!/usr/bin/env bash
#
# Puts the hook and the skill into demo/homelab so the demo project is a real
# install. They live once in the repo; these two copies are gitignored.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
project="$here/homelab"

mkdir -p "$project/.claude/hooks" "$project/.claude/skills/persistent-handoff"
install -m 755 "$root/hooks/session-start-handoff.sh" "$project/.claude/hooks/"
cp -R "$root/skills/persistent-handoff/." "$project/.claude/skills/persistent-handoff/"

cat <<'EOF'
demo/homelab is ready. Run it the way the GIF was recorded:

  cd demo/homelab
  claude --model claude-sonnet-5 --setting-sources project,local \
         --strict-mcp-config --tools Read,Glob,Grep,Skill,Write

then answer the handoff's open question and announce a restart, the way the GIF
does: "Keep the daily snapshots for the year, that's decided. I'm going to
restart you in a minute." The skill fires on its own and rewrites the handoff.
Then /exit, start claude again with the same flags, and ask: where were we?

Claude Code will ask you to trust this folder, because it carries a project hook
in .claude/settings.json, and the prompt preselects the option that exits. The
hook is ../../hooks/session-start-handoff.sh: it reads one file and prints it.
Read it before you accept, the same as any repo you clone.
EOF
