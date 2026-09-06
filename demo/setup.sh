#!/usr/bin/env bash
#
# Puts the skill into demo/homelab so the demo project is a real install. It
# lives once in the repo; that copy is gitignored. The hook is not copied: the
# demo's settings.json calls the one at the repo root, so a fresh clone is
# already wired.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
project="$here/homelab"

mkdir -p "$project/.claude/skills/persistent-handoff"
cp -R "$root/skills/persistent-handoff/." "$project/.claude/skills/persistent-handoff/"

cat <<'EOF'
demo/homelab is ready. Run it the way the GIF was recorded:

  cd demo/homelab
  claude --model claude-sonnet-5 --setting-sources project,local \
         --strict-mcp-config --tools Read,Glob,Grep,Skill,Write

then answer the handoff's open question and announce a restart, the way the GIF
does: "Keep the daily snapshots for the year, that's decided. I'm going to
restart you in a minute." The skill fires on its own and rewrites
demo/homelab/handoff.md. Then /exit, start claude again with the same flags, and
ask: where were we?

Claude Code will ask you to trust this folder, because it carries a project hook
in .claude/settings.json. The prompt preselects the option that exits, so pick
the one that trusts the folder. The hook is ../../hooks/session-start-handoff.sh:
it reads one file and prints it. Read it before you accept, the same as any repo
you clone.

Outside auto mode, the first rewrite asks you to approve a write to handoff.md.
Accept it: that write is the demo.
EOF
