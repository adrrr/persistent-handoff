# persistent-handoff

A handoff file that outlives the session that wrote it. One file per agent, updated at milestones, read back automatically at every session start, and deleted when nothing is left in flight.

This is for agents that keep running: a personal assistant that has been up for six months, a fleet of Claude Code sessions in tmux, a daemon that wakes on a cron. They lose their context constantly, and they lose it without warning. What they need is not a summary of the conversation, it is the state of the work.

## Disposable handoff, persistent handoff

The handoff pattern most people have seen is deliberately throwaway. You are near the end of a coding session, you write a markdown file somewhere temporary, and you hand it to the session that takes over. [Matt Pocock's `handoff` skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md) says it plainly: "Save to the temporary directory of the user's OS - not the current workspace." For a coding session you will close today, that is the right call. Use it.

This repo takes the opposite bet on lifetime.

| | Disposable | Persistent |
|---|---|---|
| Location | the OS temp directory | `~/.claude/handoffs/<agent>.md` or the project repo |
| How many | one per handoff event | one per agent, ever |
| Read back | you hand it to the next session | a `SessionStart` hook, every session, automatically |
| Written | once, when the session is ending | at milestones, as the work advances |
| Lifetime | until the next session picks it up | until the work it describes is done |
| Deleted | by the OS, eventually | by the agent, the moment it is empty |

The row that matters is the second one. A disposable handoff is an event, so having ten of them is normal. A persistent handoff is a state, so having two is a bug: the next session reads the stale one and acts on work that finished last week.

## Quick start

Copy the skill and the hook, then wire the hook into your settings.

```bash
git clone https://github.com/adrrr/persistent-handoff /tmp/persistent-handoff
mkdir -p ~/.claude/skills ~/.claude/hooks ~/.claude/handoffs
cp -r /tmp/persistent-handoff/skills/persistent-handoff ~/.claude/skills/
install -m 755 /tmp/persistent-handoff/hooks/session-start-handoff.sh ~/.claude/hooks/
```

Then add the hook to `~/.claude/settings.json` (or a project `.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/session-start-handoff.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

There is no `matcher`, so the hook runs on every kind of start: `startup`, `resume`, `clear`, `compact` and `fork`. Firing after a compact is the point, not an accident. That is the moment the session has just lost the detail the handoff carries.

By default the hook reads `~/.claude/handoffs/<basename of the working directory>.md`, which gives each project its own handoff with no configuration. Export `PERSISTENT_HANDOFF_FILE` to pin an explicit path instead, which is what you want for an agent that is not tied to one directory. The hook uses `jq` when it is installed, and falls back to plain stdout when it is not.

Nothing happens until a handoff exists. The hook stays silent when the file is missing or empty, so installing it costs nothing on sessions that have no state to carry.

## The contract

1. One handoff per agent, never two. It is a state, not a journal, and a state has one current value.
2. It is read automatically at every session start. If a human has to remember to load it, it will be forgotten on the session where it mattered.
3. It is written at milestones, by the agent, unprompted: a decision made, a PR opened or merged, an investigation concluded, a blocker hit, a question left with a human. Not after every message.
4. Five sections. Where I am (the real state, not the narrative), next action (executable as written), open questions (what waits on a human), traps (what was learned the hard way: exact paths, gotchas, verified facts), and the skills the next session should load before resuming.
5. Every update removes what is resolved. A handoff that only grows stops being read.
6. Emptiness is legitimate. When nothing is left in flight, the file is deleted. There is no handoff written for the form of it.

Point 6 is the one people skip, and it is the one that keeps the rest honest. A file that is always there is a file nobody reads.

## What one looks like

```markdown
# Handoff - homelab

## Where I am
The nightly backup to the NAS has been failing since Aug 19. Cause found: restic is
fine, the SMB mount drops when the router hands the NAS a new DHCP lease. Address
pinned to 192.168.1.40 in the router config. One clean run since (Aug 22, 04:12),
which is not enough to call it fixed.

## Next action
Read /var/log/restic-nightly.log after the Aug 24 run. Three consecutive clean runs
closes this. Anything else means the mount was not the whole story.

## Open questions
Whether the daily snapshots from before Aug 19 get pruned or kept for the year.
Asked Aug 22, no answer yet. Blocks nothing until the disk passes 80% (61% today).

## Traps
- The restic password is in the keychain, not in the environment:
  `security find-generic-password -s restic-nas -w`
- `restic check` on this repo takes about 25 minutes. Never in a foreground turn.
- The NAS answers ping after its SMB share is already gone. Ping is not a health
  check here, `mount | grep nas` is.

## Skills to invoke on resume
systematic-debugging, if the Aug 24 run fails again.
```

Around 300 to 500 tokens is the useful range. Below that you are usually hiding a vague next action. Above it you are writing the journal.

## FAQ

**Why not just use `/compact`?**

Compaction summarizes the transcript, and the model decides what survives. A handoff records what you decided matters, in your words, and it is a file: it survives a crash, a `kill -9`, a machine reboot and a fresh clone, none of which give the model a chance to summarize anything. The two are not in competition. Compact when the context is full, and keep a handoff so that it does not matter if you never get the chance.

**Why delete the file when it is empty?**

Because it is read at every single session start. A handoff that is always present, half stale, describing work that finished last week, teaches every new session to skim it. Deleting it makes its presence meaningful: if the file is there, something is genuinely in flight. The absence is the signal.

**My agent is a coding session I close at the end of the day. Do I want this?**

Probably not. Persistence buys you nothing when the agent dies on purpose after one task, and the bookkeeping (edit in place, prune what is resolved, delete when empty) is real work. Use a disposable handoff instead.

## Credits

The disposable handoff pattern comes from [Matt Pocock's skills repo](https://github.com/mattpocock/skills) (MIT), and so does the idea of naming the skills the next agent should load: "Include a 'suggested skills' section in the document, naming which skills the next agent should call the Skill tool for." That repo is worth reading whether or not you keep agents running. This one disagrees with exactly one of its design choices, the lifetime, and only because it aims at a different kind of agent.

## License

MIT
