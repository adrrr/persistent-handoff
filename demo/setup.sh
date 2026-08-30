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

echo "demo/homelab is ready. cd demo/homelab && claude, then ask: where were we?"
