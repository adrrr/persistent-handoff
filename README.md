# persistent-handoff

A handoff file that outlives the session that wrote it. Your agent keeps one single file, always the same one: updated at milestones, read back automatically at every session start, deleted when nothing is left in flight.

This is for agents that keep running: a personal assistant that has been up for six months, a fleet of Claude Code sessions in tmux, a daemon that wakes on a cron. Their context dies often, rarely with a warning: compaction, a crash, a nightly restart. The next session needs the state of the work, not a summary of a dead conversation.

## Disposable handoff, persistent handoff

The usual handoff is deliberately throwaway. At a crossing (end of a coding session, or a fork where you hand a copy of the context to a second agent working in parallel) you write a markdown file somewhere temporary, and its job ends when the receiving session has read it. [Matt Pocock's `handoff` skill](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md) says it plainly: "Save to the temporary directory of the user's OS - not the current workspace." For a coding session you will close today, that is the right call. Use it.

This repo makes the opposite bet on lifetime. The left column below describes the throwaway approach; the right column is what this repo does instead, and everything in it follows from that one choice.

| | Disposable | Persistent |
|---|---|---|
| Location | a temp directory | `~/.claude/handoffs/<agent>.md` or the project repo |
| How many | a new file each time | the same file, updated |
| Read back | you hand it to the next session | a `SessionStart` hook, every session, automatically |
| Written | once, at a crossing (session end, or a fork to a parallel agent) | at milestones, as the work advances |
| Lifetime | until the next session picks it up | until the work it describes is done |
| Deleted | when the OS clears its temp files | by the agent, the moment it is empty |

The second row is the important one. A disposable handoff is an event, so having ten of them is normal. A persistent handoff is a state, so having two is a bug: the next session reads the stale one and acts on work that finished last week.

## Quick start

Copy the skill and the hook, then wire the hook into your settings.

```bash
src=$(mktemp -d) && git clone https://github.com/adrrr/persistent-handoff "$src"
mkdir -p ~/.claude/skills/persistent-handoff ~/.claude/hooks ~/.claude/handoffs
cp -r "$src"/skills/persistent-handoff/. ~/.claude/skills/persistent-handoff/
install -m 755 "$src"/hooks/session-start-handoff.sh ~/.claude/hooks/
```

The `cp` copies the contents rather than the directory, so running the install twice updates the skill instead of nesting a copy inside it.

Then add the hook to `~/.claude/settings.json` (or a project `.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME\"/.claude/hooks/session-start-handoff.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

There is no `matcher`, so the hook runs on every kind of start: `startup`, `resume`, `clear`, `compact` and `fork`. Firing after a compact is the point, not an accident. That is the moment the session has just lost the detail the handoff carries.

By default the hook names the handoff after the working directory, relative to your home directory, with the separators turned into dashes: an agent running in `~/work/acme/api` reads `~/.claude/handoffs/work-acme-api.md`. It uses the whole path rather than the last segment, so `~/work/beta/api` gets its own file instead of quietly sharing one with every other directory called `api`.

For an agent that is not tied to one directory, pin the path instead. The hook reads `PERSISTENT_HANDOFF_FILE`, and the shell form of the hook command is the simplest place to set it:

```json
"command": "PERSISTENT_HANDOFF_FILE=\"$HOME\"/.claude/handoffs/assistant.md \"$HOME\"/.claude/hooks/session-start-handoff.sh"
```

One catch with the inline form: it sets the variable for the hook only. The agent never sees it, and the skill tells the agent to fall back on the directory slug when the variable is unset. The first handoff it ever writes would land in the slug-named file while the hook keeps reading the pinned one, silently, forever. If the agent has to work out the path by itself, export the variable somewhere both the hook and the agent's shell inherit it (your shell profile, the launchd or systemd unit that starts the agent). The inline form is fine when you tell the agent explicitly where its handoff lives.

Nothing happens until a handoff exists. The hook stays silent when the file is missing or empty, so installing it costs nothing on sessions with no state to carry. It uses `jq` when available and falls back to plain stdout otherwise, which Claude Code also accepts as context from a `SessionStart` hook.

One limit worth knowing: Claude Code caps hook output at 10,000 characters and replaces anything longer with a preview and a file path. A handoff kept to the 300 to 500 tokens this skill asks for sits far below that, but a file that has been allowed to grow into a journal will arrive as a preview instead of its content.

## The contract

1. One file, always the same one, never two. A state has one current value.
2. It is read automatically at every session start. If a human has to remember to load it, it will be forgotten on the session where it mattered.
3. It is written at milestones, by the agent, unprompted: a decision made, a PR opened or merged, an investigation concluded, a blocker hit, a question left with a human. Not after every message.
4. Four sections, plus a fifth when it applies. Where I am (where the work actually stands), next action (executable as written), open questions (what waits on a human), traps (what was learned the hard way: exact paths, gotchas, verified facts), and, when the work depends on them, the skills the next session should load before resuming.
5. Every update removes what is resolved. A handoff that only grows stops being read.
6. Emptiness is legitimate. When nothing is left in flight, the file is deleted. There is no handoff written for the form of it.

Point 6 is the first one people drop, and the rest leans on it, see the FAQ for why.

## What one looks like

```markdown
# Handoff: homelab

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

Compaction summarizes the transcript, and the model decides what survives. A handoff records what you decided matters, in your words, and it is a file: it survives a crash, a `kill -9`, a machine reboot and a fresh clone, none of which give the model a chance to summarize anything. Use both: compact when the context fills up, keep a handoff for the times nothing gets the chance to run.

**Why delete the file when it is empty?**

Because it is read at every single session start. A handoff that is always present, half stale, describing work that finished last week, teaches every new session to skim it. Deleting it keeps the file meaningful: if it is there, something is genuinely in flight.

**My agent is a coding session I close at the end of the day. Do I want this?**

Probably not. Persistence buys you nothing when the agent dies on purpose after one task, and the bookkeeping (edit in place, prune what is resolved, delete when empty) is real work. Use a disposable handoff instead.

## One caution about where you put it

The hook feeds the handoff straight into a fresh session as context, and the file tells that session what to do next. Treat it as executable input, not as documentation.

That is fine for `~/.claude/handoffs`, which only you write to. It is worth a second thought inside a repo: a handoff committed to a project means anyone who can push to that project can write text that lands in your agent's context the next time you open a session there. Keep a versioned handoff to repos whose writers you trust, and use the home directory for anything else.

## Credits

The disposable handoff pattern comes from [Matt Pocock's skills repo](https://github.com/mattpocock/skills) (MIT), and so does the idea of naming the skills the next agent should load: "Include a 'suggested skills' section in the document, naming which skills the next agent should call the Skill tool for." That repo is worth reading whether or not you keep agents running. No code from it is reused here; the credit is for the ideas.

The disagreement is about one root choice, the lifetime, and the rest of the table follows from it. We aim at different kinds of agent, that is the whole disagreement. (His repo also carries an in-progress `claude-handoff` skill that turns a handoff into a background agent's prompt without saving it anywhere, a third lifetime, shorter still.)

## Tests

`bash tests/hook.sh`, 18 cases covering the hook's failure modes: path-slug collisions inside and outside `$HOME`, a `$HOME` containing glob metacharacters, a `jq` that exists but fails, a directory where the file should be, unreadable handoffs surfaced to the session instead of swallowed, and the 10,000-character context cap.

## License

MIT
