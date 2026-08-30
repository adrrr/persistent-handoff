#!/usr/bin/env bash
set -euo pipefail

REPO=/repo
LOG=$(cd "$(dirname "$0")/.." && pwd)/logs/restic-nightly.log

mount | grep -q nas || { echo "$(date -Is) nas share not mounted" >>"$LOG"; exit 1; }

restic -r "$REPO" backup /mnt/nas/media --tag nightly >>"$LOG" 2>&1
restic -r "$REPO" forget --keep-daily 7 --keep-weekly 8 >>"$LOG" 2>&1
