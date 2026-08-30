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
demo/homelab is ready. Run it read-only, the way the GIF was recorded:

  cd demo/homelab
  claude --model claude-sonnet-5 --setting-sources project,local \
         --strict-mcp-config --tools Read,Glob,Grep

then ask: where were we?

Claude Code will ask you to trust this folder, because it carries a project hook
in .claude/settings.json, and the prompt preselects the option that exits. The
hook is ../../hooks/session-start-handoff.sh: it reads one file and prints it.
Read it before you accept, the same as any repo you clone.
EOF
