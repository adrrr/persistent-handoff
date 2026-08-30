# persistent-handoff

[![tests](https://github.com/adrrr/persistent-handoff/actions/workflows/tests.yml/badge.svg)](https://github.com/adrrr/persistent-handoff/actions/workflows/tests.yml)
[![release](https://img.shields.io/github/v/release/adrrr/persistent-handoff)](https://github.com/adrrr/persistent-handoff/releases)

Your agent starts every session knowing where the work stands. It keeps one handoff file, writes to it at milestones, and a `SessionStart` hook reads it back before you ask the first question.

![Animated terminal recording of the agent loading the persistent-handoff skill, writing .claude/handoff.md, exiting, and a new session answering from that file](demo.gif)

*Two acts, and the cut between them is a restart. Act one, the agent rewrites its handoff. Act two, a new session answers `where were we?` from that file.*

I run eight Claude Code sessions in tmux, and a cron restarts the idle ones every night. They used to wake up with no idea what they had spent the previous day on. Context dies often, and rarely with a warning.

It is for the agents that keep running: an assistant that has been up for six months, a daemon that wakes on a cron, a fleet like mine. They get their messages from wherever you are, through `claude --channels` (Telegram, Discord, iMessage…) or Remote Control from the Claude app. On your side, a restart, a crash or a compact on the machine goes unnoticed. You send the next message and the agent picks up where it left off. Without the handoff, that message is you explaining what it was doing. Nothing in the plugin depends on tmux or channels, it just started there.

[Install](#install) · [Try it](#try-it) · [Contract](#the-contract) · [FAQ](#faq) · [Related](#related)

## Install

The repo is its own plugin marketplace. One command adds it and installs the plugin, and the `SessionStart` hook is wired for you.

```bash
claude plugin marketplace add adrrr/persistent-handoff && claude plugin install persistent-handoff@persistent-handoff
```

Requires Claude Code 2.1.69 or newer, developed and tested on 2.1.251. `${CLAUDE_SKILL_DIR}`, which the skill uses to name the hook, landed in 2.1.69. Before 2.1.214 a fork reports `resume`, which takes the same preamble, so nothing else changes.

The hook needs `bash` on `PATH`. It uses no BSD-only flags and `jq` is optional, but the shebang is `bash`, not `sh`, so a container image without it will not run the hook at all. On Windows that means WSL, or [Git for Windows](https://git-scm.com/downloads/win) installed first: without it a `command` hook lands in PowerShell, which will not run a bash script either. [`docs/INSTALL.md`](docs/INSTALL.md#windows) has both cases.

Inside a running session, `/plugin marketplace add adrrr/persistent-handoff` then `/plugin install persistent-handoff@persistent-handoff` do the same thing. Start a new session and both the skill and the hook are live. Remove it with `claude plugin uninstall persistent-handoff@persistent-handoff`, then `claude plugin marketplace remove persistent-handoff` to drop the marketplace entry. Would rather not use plugins, or already installed it by hand? [`docs/INSTALL.md`](docs/INSTALL.md). Upgrading from 0.1.0? The derived filename gained a digest, and the [0.2.0 changelog entry](CHANGELOG.md#upgrading-from-010) says what to rename.

Nothing happens until a handoff exists. The hook stays silent when the file is missing or holds nothing but whitespace, so installing it costs nothing on sessions with no state to carry.

## Try it

The demo is a fictional homelab project with a real handoff in it. Clone, install the hook into it, and talk to the agent:

```bash
git clone https://github.com/adrrr/persistent-handoff && cd persistent-handoff
./demo/setup.sh && cd demo/homelab
claude --model claude-sonnet-5 --setting-sources project,local --strict-mcp-config --tools Read,Glob,Grep,Skill,Write
```

Claude Code will ask you to trust the folder, because the demo carries a project hook. The prompt preselects the option that exits, and it is right to be careful. The hook feeds the handoff straight into a fresh session as context, and the file tells that session what to do next: treat it as executable input, and read [`hooks/session-start-handoff.sh`](hooks/session-start-handoff.sh) first. That is fine in `~/.claude/handoffs`, which only you write to. A handoff committed to a repo means anyone who can push there can write into your agent's context, so keep that to repos whose writers you trust.

Those are the flags the GIF was recorded with. They load only the demo's own settings and none of your MCP servers. `Write` is there because act 1 writes the handoff, and nothing scopes it to that one file, so keep the session to the demo project.

Answer the handoff's open question the way the GIF does: `Keep the daily snapshots for the year, that's decided. I'm going to restart you in a minute.` The skill loads on its own and rewrites `.claude/handoff.md`, question gone. Claude Code treats anything under `.claude/` as sensitive, so a session set to ask will ask you first. The GIF ran in auto mode, which allowed the write and printed that it had. Then `/exit`, start `claude` again with the same flags, and ask `where were we?`. That answer comes out of the handoff the hook fed the session, not out of a file the agent opened. The one `Read` on screen in act 2 is the log the handoff points at. To run it again, `git checkout -- demo/homelab/.claude/handoff.md` puts the open question back.

## The contract

1. One file, always the same one, never two. A state has one current value.
2. It is read automatically at every session start. If a human has to remember to load it, it will be forgotten on the session where it mattered.
3. It is written at milestones, by the agent, unprompted: a decision made, a PR opened or merged, an investigation concluded, a blocker hit, a question left with a human. Not after every message.
4. Four sections, plus a fifth when it applies. Where I am, next action, open questions, traps, and the skills the next session should load.
5. Every update removes what is resolved. A handoff that only grows stops being read.
6. Emptiness is legitimate. When nothing is left in flight, the file is deleted.

Point 6 is the first one people drop, and the FAQ says why it matters.

## What one looks like

```markdown
# Handoff: homelab

## Where I am
The nightly restic backup to the NAS failed every night from Aug 25 to Aug 27.
Cause found: restic is fine, the SMB mount drops when the router hands the NAS a
new DHCP lease. Address pinned to 192.168.1.40 in the router config on Aug 27.
Two clean runs since (Aug 28, Aug 29), which is not enough to call it fixed.

## Next action
Read logs/restic-nightly.log after tonight's 23:40 run. Three consecutive clean
runs close this. Anything else means the mount was not the whole story.

## Open questions
Whether the daily snapshots from before Aug 25 get pruned or kept for the year.
Asked Aug 28, no answer yet. Blocks nothing until the disk passes 80% (61% today).

## Traps
- The restic password is in the keychain, not in the environment:
  `security find-generic-password -s restic-nas -w`
- `restic check` on this repo takes about 25 minutes. Never in a foreground turn.
- The NAS answers ping after its SMB share is already gone. Ping is not a health
  check here, `mount | grep nas` is.

## Skills to invoke on resume
systematic-debugging, if tonight's run fails again.
```

That is the demo's handoff, and `./demo/setup.sh` puts it in a project you can open. Around 300 to 500 tokens is the useful range. Below that you are usually hiding a vague next action. Above it you are writing the journal.

## Where the handoff lives

By default the hook names the file after the working directory, relative to your home directory, with the separators turned into dashes and a short digest of the full path on the end. An agent running in `/home/alice/work/acme/api` reads `~/.claude/handoffs/work-acme-api-32817b.md`. Run `session-start-handoff.sh --path` in a directory to read that name rather than work it out.

An agent that is not tied to one directory pins `PERSISTENT_HANDOFF_FILE` to an absolute path instead. There is one expansion trap in doing that, and the digest is a coincidence guard rather than a uniqueness proof. [`docs/REFERENCE.md`](docs/REFERENCE.md) has both, plus what happens when several sessions share one path and what Claude Code's 10,000 character cap on hook output does to a handoff grown into a journal.

## FAQ

**Why not just use `/compact`?** A compaction summary lives in the session that holds it and dies with it. The file survives a crash, a `kill -9` and a reboot, none of which give the model a chance to summarize anything. They also work on different material: compaction keeps what the model judged worth keeping, the handoff keeps what you decided matters, in your words. Use both.

**What happens after a compact or a resume?** The hook fires there too, about 500 tokens, so the handoff is present whatever the compaction summary happened to keep, and nothing the summary dropped is lost. The preamble says which side wins: your context is newer for what you did in this session, the file is the reference for everything else. If the two disagree, update the file. Repeated resumes do not stack copies, for the reason [`docs/REFERENCE.md`](docs/REFERENCE.md) spells out.

**Why delete the file when it is empty?** Because every session start reads it. A handoff that is always present, half stale, describing work that finished last week, teaches every new session to skim it. Deleting it keeps the file meaningful: if it is there, something is genuinely in flight. For an agent whose work never ends, and which therefore never gets to delete it, pruning every update does the same job.

**Why not just keep this in CLAUDE.md or the agent's memory?** Different lifetimes. CLAUDE.md and memory hold what stays true: mechanisms, commands, preferences. The handoff holds what is in flight right now, and gets deleted when it lands. Put a stable fact in the handoff and it dies with the work. Put the current blocker in memory and it outlives its own resolution.

**My agent is a coding session I close at the end of the day. Do I want this?** Probably not. Persistence buys you nothing when the agent dies on purpose after one task, and the bookkeeping is real work. Use a disposable handoff instead.

**I deleted the project. Is its handoff still there?** Yes. Nothing prunes `~/.claude/handoffs/`, so a handoff named after a directory outlives that directory. The hook puts no date in the preamble, so date the content the way the example above does and a stale file says so when you open it.

**What does it cost on every session start?** On the derived path, seven short-lived processes when a handoff is there: two `cat`, three `jq`, one `cksum`, one `tr`. Five when there is none. Between 10 and 25 ms depending on the machine and what else it is doing. Zero tokens when no handoff exists, which is the normal case. With one, roughly 400 to 600 tokens.

## Related

Handoff files for Claude Code are a crowded shelf. What is specific here is the contract: one canonical file, rewritten in place, deleted when nothing is in flight. The neighbours keep history instead.

- [Matt Pocock's `handoff`](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md) writes to the OS temp directory, once, on a manual invocation. Disposable by design, and the right tool for a session you will close today.
- [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) is the closest on mechanism: one file per repo, loaded at startup, with a nudge when the context fills. It keeps the last five handoffs as history, where this one keeps a single current state.
- [blader/baton](https://github.com/blader/baton) has you drop and grab a baton by hand, into timestamped files under `.baton/`, and works with Codex as well as Claude Code. Manual on both ends, one file per session.
- [REMvisual/claude-handoff](https://github.com/REMvisual/claude-handoff) mines the conversation on a `/handoff` command and chains the results in sequence. You paste the result into the next session.
- [rupaut98/unforget](https://github.com/rupaut98/unforget) hooks `SessionStart` on compaction only and digests the transcript JSONL itself. It is the opposite mechanism: extracted automatically rather than written by the agent.

Want an agent to record what it decided? This repo. Want a record of how it got there? Most of the others fit better. The disposable pattern, and the idea of naming the skills the next agent should load, come from [Matt Pocock's skills repo](https://github.com/mattpocock/skills) (MIT). No code from it is reused here, the credit is for the ideas.

## Tests

`bash tests/hook.sh` is 37 cases on the hook's failure modes and its two preambles. `bash tests/manifests.sh` is 14 pinning the plugin manifests, and holding the `SessionStart` block to one shape in all three copies: the plugin, the demo, and the hand-install snippet in [`docs/INSTALL.md`](docs/INSTALL.md).

Both run on `ubuntu-latest`, `macos-latest` and `windows-latest`, on every pull request, on every push to `main`, and on demand, 51 assertions each, minus three on Windows where NTFS will not stage what they need: a `chmod 000` that actually denies a read, a `chmod 555` directory, and a dangling symlink. A skipped case asserted nothing, so the suite prints how many it skipped alongside the pass. The same workflow runs `./demo/setup.sh`, calls the hook it installs the way the demo's `settings.json` calls it, and runs `shellcheck` on the Linux leg. See [`.github/workflows/tests.yml`](.github/workflows/tests.yml).

## License

MIT
