# persistent-handoff

[![tests](https://github.com/adrrr/persistent-handoff/actions/workflows/tests.yml/badge.svg)](https://github.com/adrrr/persistent-handoff/actions/workflows/tests.yml)
[![release](https://img.shields.io/github/v/release/adrrr/persistent-handoff)](https://github.com/adrrr/persistent-handoff/releases)

![demo](demo.gif)

`/clear` wipes the context, the `SessionStart` hook puts the handoff back, and the next question is answered from where the work stands.

Your agent keeps one file, always the same one. It updates it at milestones, reads it back automatically at every session start, and drops from it whatever it has resolved. This is for agents that keep running: a personal assistant that has been up for six months, a fleet of Claude Code sessions in tmux, a daemon that wakes on a cron. Their context dies often and rarely with a warning.

## Install

The repo is its own plugin marketplace. One command adds it and installs the plugin, and the `SessionStart` hook is wired for you.

```bash
claude plugin marketplace add adrrr/persistent-handoff && claude plugin install persistent-handoff@persistent-handoff
```

Inside a running session, `/plugin marketplace add adrrr/persistent-handoff` then `/plugin install persistent-handoff@persistent-handoff` do the same thing. Start a new session and both the skill and the hook are live. Remove it with `claude plugin uninstall persistent-handoff@persistent-handoff`. If you would rather not use plugins, [install it by hand](#install-by-hand).

Upgrading from 0.1.0? The derived filename gained a digest, so the hook will not find your existing handoff. Run `--path` in the directory and rename the file to what it prints, or pin `PERSISTENT_HANDOFF_FILE` to the old path. Nothing warns you otherwise: the hook reads the new name, finds nothing, and stays silent. Coming from the hand install? Remove the `SessionStart` entry from your `settings.json` and delete `~/.claude/skills/persistent-handoff/`, or the two handlers inject the handoff twice.

Requires Claude Code 2.1.69 or newer, developed and tested on 2.1.251. `${CLAUDE_SKILL_DIR}`, which the skill uses to name the hook, landed in 2.1.69. Before 2.1.214 a fork reports `resume`, which takes the same preamble, so nothing else changes.

The hook needs `bash` on `PATH`. It uses no BSD-only flags and `jq` is optional, but the shebang is `bash`, not `sh`, so a container image without it will not run the hook at all.

### Windows

WSL is the recommended path. Claude Code inside WSL is a Linux environment, so everything here applies unchanged.

On native Windows, Claude Code runs a `command` hook through Git Bash when [Git for Windows](https://git-scm.com/downloads/win) is installed, and through PowerShell when it is not. Install Git for Windows first. Without it the hook lands in PowerShell, which will not run a bash script.

## Try it

The demo is a fictional homelab project with a real handoff in it. Clone, install the hook into it, and ask the agent where things stand:

```bash
git clone https://github.com/adrrr/persistent-handoff && cd persistent-handoff
./demo/setup.sh && cd demo/homelab
claude --model claude-sonnet-5 --setting-sources project,local --strict-mcp-config --tools Read,Glob,Grep
```

Then ask `where were we?`. Those are the flags the GIF was recorded with. They load only the demo's own settings and leave the session read-only.

Claude Code will ask you to trust the folder, because the demo carries a project hook. The prompt preselects the option that exits, and it is right to be careful. The hook feeds the handoff straight into a fresh session as context, and the file tells that session what to do next: treat it as executable input, and read [`hooks/session-start-handoff.sh`](hooks/session-start-handoff.sh) first. That is fine in `~/.claude/handoffs`, which only you write to. A handoff committed to a repo means anyone who can push there can write into your agent's context, so keep that to repos whose writers you trust.

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

By default the hook names the file after the working directory, relative to your home directory, with the separators turned into dashes and a short digest of the full path on the end. An agent running in `/home/alice/work/acme/api` reads `~/.claude/handoffs/work-acme-api-32817b.md`.

The dashed part lets you read the directory off the filename. The six hex characters carry what it loses: without them `~/my project` and `~/my-project` are one file, and so are `~/abs/var/tmp/x` and `/var/tmp/x`. The digest covers the absolute path, so yours will not match the example above. Twenty-four bits is not a uniqueness proof, it makes a clash a coincidence rather than a certainty. A `cksum` collision can also be constructed on purpose by anyone who wants one, and a handoff is executable input. Pin `PERSISTENT_HANDOFF_FILE` if you need a guarantee. The digest needs `cksum`, which is POSIX and present everywhere this is tested. Without it the name falls back to the dashed part alone, and the hook says so on stderr.

To read the name for a directory rather than work it out, run `session-start-handoff.sh --path` there. That is how the skill finds the path before its first write. After that, the hook names the path in the line it injects above the content.

For an agent that is not tied to one directory, pin the path instead. The hook reads `PERSISTENT_HANDOFF_FILE`, and the place to set it is the `env` block of the same `settings.json`:

```json
{
  "env": {
    "PERSISTENT_HANDOFF_FILE": "/home/alice/.claude/handoffs/fleet.md"
  }
}
```

Write an absolute path there. `${CLAUDE_PROJECT_DIR}` is expanded in a hook's `command` string but not inside the `env` block, so a path using it there arrives at the hook literally and finds no file. The demo sets the variable inline in the hook command instead, where the expansion does happen. That form sets it for the hook only, so the agent never sees it and writes its first handoff somewhere else. Use it only when you tell the agent outright where its handoff lives, which is why the demo names its own handoff in its README.

Nothing happens until a handoff exists. The hook stays silent when the file is missing or holds nothing but whitespace, so installing it costs nothing on sessions with no state to carry. Three sessions in one directory are one agent by this design, and the last writer wins. Writing to a temporary file and moving it over prevents a torn read, not a lost update, so pin `PERSISTENT_HANDOFF_FILE` per session if they hold genuinely separate work.

Claude Code caps a hook's output at 10,000 characters and injects a truncated preview plus a path past that. This is Claude Code's limit rather than this repo's, so it can move in a future release with nothing to warn you. The preamble takes 259 characters plus the path on a fresh start, and 404 to 407 after a compact, a resume or a fork. A handoff kept to 300 to 500 tokens sits far below the limit; one grown into a journal arrives as a preview.

## FAQ

**Why not just use `/compact`?**

A compaction summary lives in the session that holds it and dies with it. The file survives a crash, a `kill -9` and a reboot, none of which give the model a chance to summarize anything. They also work on different material: compaction keeps what the model judged worth keeping, the handoff keeps what you decided matters, in your words. Use both.

**What happens after a compact or a resume?**

The hook fires there too, about 500 tokens, so the handoff is present whatever the compaction summary happened to keep. The preamble says which side wins: your context is newer for what you did in this session, the file is the reference for everything else. If the two disagree, update the file.

Repeated resumes do not stack copies. Claude Code drops a `SessionStart` `additionalContext` whose exact text is already in the transcript it reloaded. The two preambles are two different strings, so a session that started fresh and was then resumed carries both, and every resume after that is deduplicated for as long as the file does not change. That is read out of the 2.1.251 binary and documented nowhere, so take it as an observation rather than a contract.

**Why delete the file when it is empty?**

Because every session start reads it. A handoff that is always present, half stale, describing work that finished last week, teaches every new session to skim it. Deleting it keeps the file meaningful: if it is there, something is genuinely in flight. For an agent whose work never ends, and which therefore never gets to delete it, pruning every update does the same job.

**Why not just keep this in CLAUDE.md or the agent's memory?**

Different lifetimes. CLAUDE.md and memory hold what stays true: mechanisms, commands, preferences. The handoff holds what is in flight right now, and gets deleted when it lands. Put a stable fact in the handoff and it dies with the work. Put the current blocker in memory and it outlives its own resolution.

**My agent is a coding session I close at the end of the day. Do I want this?**

Probably not. Persistence buys you nothing when the agent dies on purpose after one task, and the bookkeeping is real work. Use a disposable handoff instead.

**I deleted the project. Is its handoff still there?**

Yes. Nothing prunes `~/.claude/handoffs/`, so a handoff named after a directory outlives that directory. The hook puts no date in the preamble, so date the content the way the example above does and a stale file says so when you open it.

**What does it cost on every session start?**

On the derived path, seven short-lived processes when a handoff is there: two `cat`, three `jq`, one `cksum`, one `tr`. Five when there is none. Between 10 and 25 ms depending on the machine and what else it is doing. Zero tokens when no handoff exists, which is the normal case. With one, roughly 400 to 600 tokens.

## Install by hand

Copy the skill and the hook, then wire the hook into your settings.

```bash
src=$(mktemp -d) && git clone https://github.com/adrrr/persistent-handoff "$src"
mkdir -p ~/.claude/skills/persistent-handoff ~/.claude/hooks ~/.claude/handoffs
cp -r "$src"/skills/persistent-handoff/. ~/.claude/skills/persistent-handoff/
install -m 755 "$src"/hooks/session-start-handoff.sh ~/.claude/hooks/
```

The `cp` copies the contents rather than the directory, so running the install twice updates the skill instead of nesting a copy inside it. Then add the hook to `~/.claude/settings.json`, or to a project `.claude/settings.json`. In a repo you share with other people, use `.claude/settings.local.json` instead: same shape, and it is the file meant to stay out of the commit.

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

There is no `matcher`, so the hook runs on all five `SessionStart` sources: `startup`, `clear`, `compact`, `resume` and `fork`. It reads the source out of the payload and switches its preamble on the last three, the ones where the session already holds a context of its own.

## Related

Handoff files for Claude Code are a crowded shelf. What is specific here is the contract: one canonical file, rewritten in place, deleted when nothing is in flight. The neighbours keep history instead.

- [Matt Pocock's `handoff`](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md) writes to the OS temp directory, once, on a manual invocation. Disposable by design, and the right tool for a session you will close today.
- [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) is the closest on mechanism: one file per repo, loaded at startup, with a nudge when the context fills. It keeps the last five handoffs as history, where this one keeps a single current state.
- [blader/baton](https://github.com/blader/baton) has you drop and grab a baton by hand, into timestamped files under `.baton/`, and works with Codex as well as Claude Code. Manual on both ends, one file per session.
- [REMvisual/claude-handoff](https://github.com/REMvisual/claude-handoff) mines the conversation on a `/handoff` command and chains the results in sequence. You paste the result into the next session.
- [rupaut98/unforget](https://github.com/rupaut98/unforget) hooks `SessionStart` on compaction only and digests the transcript JSONL itself. It is the opposite mechanism: extracted automatically rather than written by the agent.

Want an agent to record what it decided? This repo. Want a record of how it got there? Most of the others fit better. The disposable pattern, and the idea of naming the skills the next agent should load, come from [Matt Pocock's skills repo](https://github.com/mattpocock/skills) (MIT). No code from it is reused here, the credit is for the ideas.

## Tests

`bash tests/hook.sh`, 37 cases covering the hook's failure modes and its two preambles: path-slug collisions inside and outside `$HOME`, a `$HOME` containing glob metacharacters, a `jq` that exists but fails, a directory where the file should be, a dangling symlink, unreadable handoffs surfaced to the session instead of swallowed, a 2 MB handoff still emitting valid JSON, the fallback taken when no `cksum` is available, a `--path` that cannot create the directory it names, and the preamble chosen for each `SessionStart` source, including an absent one and an unknown one.

`bash tests/manifests.sh`, 14 cases pinning the plugin manifests: valid JSON, the plugin root variable in the hook command, the script's exec bit, one matcher-less `SessionStart` entry in all three copies, the plugin, the demo and the README snippet, the two names the install id is built from, the skill's location, the `${CLAUDE_SKILL_DIR}` path SKILL.md hands the agent, and the changelog agreeing with the shipped version.

Both run on `ubuntu-latest`, `macos-latest` and `windows-latest`, on every pull request, on every push to `main`, and on demand, 51 assertions each, minus three on Windows where NTFS will not stage what they need: a `chmod 000` that actually denies a read, a `chmod 555` directory, and a dangling symlink. A skipped case asserted nothing, so the suite prints how many it skipped alongside the pass.

The same workflow runs `./demo/setup.sh` and calls the hook it installs the way the demo's `settings.json` calls it, and runs `shellcheck` on the Linux leg. See [`.github/workflows/tests.yml`](.github/workflows/tests.yml).

## License

MIT
