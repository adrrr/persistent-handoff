# Handoff: homelab

## Where I am
The nightly restic backup to the NAS failed every night from Aug 25 to Aug 27. Cause
found: restic is fine, the SMB mount drops when the router hands the NAS a new DHCP
lease. Address pinned to 192.168.1.40 in the router config on Aug 27. Two clean runs
since (Aug 28, Aug 29), which is not enough to call it fixed.

## Next action
Read logs/restic-nightly.log after tonight's 23:40 run. Three consecutive clean runs
close this. Anything else means the mount was not the whole story.

## Open questions
Whether the daily snapshots from before Aug 25 get pruned or kept for the year. Asked
Aug 28, no answer yet. Blocks nothing until the disk passes 80% (61% today).

## Traps
- The restic password is in the keychain, not in the environment:
  `security find-generic-password -s restic-nas -w`
- `restic check` on this repo takes about 25 minutes. Never in a foreground turn.
- The NAS answers ping after its SMB share is already gone. Ping is not a health check
  here, `mount | grep nas` is.

## Skills to invoke on resume
systematic-debugging, if tonight's run fails again.
