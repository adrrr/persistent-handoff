---
name: persistent-handoff
description: 'Use when an agent''s work must survive the death of its context, or when a fresh session must learn where the work stands before acting: after a restart, recycle, crash or reboot of a long-running agent (personal assistant, fleet session, cron daemon), before a planned /clear on a project that continues, when a compact or auto-compact is near, at any milestone of multi-session work (a decision made, a PR opened or merged, an investigation concluded, a blocker hit, a question left waiting on a human), or when the user says "write a handoff", "note where you are", "prepare a restart".'
---

# Persistent handoff

An agent that runs for weeks loses its context at every restart, compact, crash and reboot. The handoff is the one file that survives. It holds where the work stands, what to do next, and what a fresh session would otherwise relearn.

An agent has one handoff file, always the same one. It holds the current state and no history.

## Quick reference

| Rule | In practice |
|---|---|
| The same file, always | Rewrite it at the same path. Never a second file, never a dated copy |
| Read at every session start | The `SessionStart` hook injects it, you rarely open it to read |
| Written at milestones | Decision, PR, conclusion, blocker, unanswered question |
| State, not narrative | Where things stand, not how they got there |
| 300-500 tokens | Below: vague. Above: journal |
| Prune on every update | Resolved items go, the file shrinks as work completes |
| Empty means delete | No file is a valid state: nothing in flight |

## When to write

At milestones, on your own, without being asked:

- a decision is made
- a PR is opened or merged
- an investigation reaches a conclusion
- you hit a blocker
- you asked the human something and the answer has not come yet

Not after every message. The transcript already keeps the conversation. The handoff keeps what a new session needs to act.

## Where it lives

One path, chosen once, used by every session of this agent. The `SessionStart` hook reads that exact path, and a handoff written anywhere else is never read by anyone.

The hook shipped with this skill uses `PERSISTENT_HANDOFF_FILE` when that variable is set. Otherwise it builds the name from the working directory: the path relative to the home directory with the separators turned into dashes, then a short digest of the full path. An agent in `/home/alice/work/acme/api` gets `~/.claude/handoffs/work-acme-api-32817b.md`. The whole path is used rather than the last segment alone, so `~/work/beta/api` is a different agent with its own file, and the digest separates directories the dashed part alone would merge.

Do not try to compute that digest yourself. When a handoff already exists, the hook injects its path in the line above the content, so read it there. When you are writing the first one and nothing exists yet, ask the hook:

```bash
"${CLAUDE_SKILL_DIR}/../../hooks/session-start-handoff.sh" --path
```

It prints the path for the current directory, creates the directory it names, and exits.

The hook ships beside this skill, two directories up from this file, and that is true of both install layouts: as a plugin the skill sits at `<plugin>/skills/persistent-handoff/`, installed by hand at `~/.claude/skills/persistent-handoff/`. Claude Code replaces `${CLAUDE_SKILL_DIR}` when it loads this file. If you ever see it unexpanded, resolve `../../hooks/session-start-handoff.sh` yourself against the directory you read this skill from. Do not go hunting for the hook by name: a plugin cache keeps old versions alongside the current one, and the first match is usually the wrong one.

That answer is only correct for an agent whose path is not pinned. If a human set `PERSISTENT_HANDOFF_FILE` in the hook's own command rather than for the whole session, the hook reads the pinned path and `--path` does not know it. The line the hook injects above an existing handoff is the authority whenever the two could disagree. If there is no handoff yet and you have any reason to think the path was pinned, ask the human instead of writing.

A handoff at a path the hook does not read is never read by anyone, and it fails silently: the hook goes on reporting that nothing is in flight.

Never two files. If a handoff already exists, rewrite the one that is there. Do not stamp it with a date, do not keep the previous one for reference, do not open a second one for a second subject. Two handoffs mean the next session reads the wrong one.

## What goes in it

Roughly 300 to 500 tokens, four sections plus a fifth when it applies:

**Where I am.** The real state, not the story of how you got there.

**Next action.** The first thing to do on resume, written so it can be executed rather than interpreted.

**Open questions.** What waits on a human, phrased as the question you would ask.

**Traps.** What was learned the hard way and would be paid for twice: exact paths, gotchas, facts you verified, approaches that failed and why.

**Skills to invoke on resume.** Name the skills the current work depends on, so the next session loads them before starting instead of rediscovering them halfway. Omit the section if none apply.

The shape, filled in with whatever the work actually is:

```markdown
# Handoff: <agent>

## Where I am
<the state, with dates and numbers, not the story>

## Next action
<one step, executable as written>

## Open questions
<what waits on a human, and since when>

## Traps
- <exact path, verified fact, or failed approach, one line each>

## Skills to invoke on resume
<names, only if the work depends on them>
```

## Clean as you advance

Every update deletes what is resolved or stale. A file that only grows becomes a journal, and the next session skips it.

Rewrite it at the same path, the whole file every time. With a shell, write the new content to `<handoff>.tmp` in the same directory, then `mv` it over the handoff. A session starting mid-write then never reads a truncated file, and nothing in a truncated handoff says it is one. Without a shell, the write tool with the full content is fine. Never patch it with an edit tool, that is how stale lines survive.

If an update empties the handoff, delete the file. An empty handoff costs context at every session start and says nothing. Its absence already says nothing is in flight.

The same rule applies before writing the first one. A milestone with nothing in flight writes no handoff.

## On resume

When the hook is installed, the handoff is already in your context and you do not need to open the file to know where things stand. Start from "Next action" and raise the open questions if any of them block you. If nothing was injected and you have reason to expect a handoff, read the file yourself rather than concluding there is none: a hook that was never wired up looks exactly like an agent with nothing in flight. Same reflex if the injected text looks cut short: hook output is capped, the file is the full version.

Opening it again is for updating, not for catching up. At the next milestone, read the file, then rewrite it the way "Clean as you advance" says, dropping what you resolved along the way.

## When the preamble says your context is newer

After a compact, a resume or a fork, the hook injects the handoff under a preamble saying your context above wins for what you did in this session, and the file wins for everything else. Reconcile the two before your next action, and if they diverge, update the file. Your context is newer than what you wrote yourself, not newer than the file, since another session of this agent may have written it while you worked. If nothing diverges, write nothing.

## Common mistakes

| Mistake | Why it hurts |
|---|---|
| One handoff per session or per date | The next session picks the wrong file, or reads three |
| Writing the narrative of the session | Nobody needs the path you took, only where it ended |
| Keeping resolved items "for history" | The file grows until it is skipped at boot |
| Writing a handoff with nothing in it | Burns context at every session start to say nothing |
| Vague next action ("continue the migration") | A fresh session spends its first ten minutes deciding what that means |
| Putting durable knowledge in the handoff | Mechanisms, ops commands and stable facts belong in a README, an instructions file or the agent's memory. The handoff carries what is in flight |
| "I'll keep the old handoff for reference" | That is two files, and the next session cannot tell which one is current. The transcript is the reference |
| "This milestone is too small to note" | If it changed the next action or answered an open question, it is not |

## What this skill does not cover

This skill does not restart the agent, schedule it or supervise the process. It only keeps the state alive across whatever kills the session.

If your agent is a coding session you will close today and the work ends with it, you want a disposable handoff instead. A file in a temp directory, written once, read once. Matt Pocock's `handoff` skill does that well.
