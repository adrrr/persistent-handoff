---
name: persistent-handoff
description: Use when an agent's work must survive the death of its context, or when a fresh session must learn where the work stands before acting: after a restart, recycle, crash or reboot of a long-running agent (personal assistant, fleet session, cron daemon), when a compact or auto-compact is near, at any milestone of multi-session work (a decision made, a PR opened or merged, an investigation concluded, a blocker hit, a question left waiting on a human), or when the user says "write a handoff", "note where you are", "prepare a restart".
---

# Persistent handoff

An agent that runs for weeks loses its context many times: restarts, compacts, crashes, machine reboots. The handoff is the one file that survives those deaths. It holds where the work stands, what to do next, and what a fresh session would otherwise have to relearn the hard way.

An agent has one handoff file, always the same one. It is a state, not a journal.

## Quick reference

| Rule | In practice |
|---|---|
| The same file, always | Edit it in place. Never a second file, never a dated copy |
| Read at every session start | The `SessionStart` hook injects it; you rarely open it to read |
| Written at milestones | Decision, PR, conclusion, blocker, unanswered question |
| State, not narrative | Where things stand, not how they got there |
| 300-500 tokens | Below: vague. Above: journal |
| Prune on every update | Resolved items go; the file shrinks as work completes |
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

The hook shipped with this skill uses `PERSISTENT_HANDOFF_FILE` when that variable is set. Otherwise it builds the name from the working directory, relative to the home directory, with the separators turned into dashes: an agent running in `~/work/acme/api` gets `~/.claude/handoffs/work-acme-api.md`. The whole path is used rather than the last segment alone, so `~/work/beta/api` is a different agent with its own file.

When you write the first handoff and nothing exists yet, that rule is how you work out where it goes.

Never two files. If a handoff already exists, edit it in place. Do not stamp it with a date, do not keep the previous one for reference, do not open a second one for a second subject. Two handoffs mean the next session reads the wrong one.

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

Every update deletes what is resolved or stale. A file that only grows is a journal, and nobody reads a journal at boot.

Rewrite it in place. If several sessions of the same agent can be alive at once, write to a temporary file and move it over the handoff, so a session that starts mid-write never reads half a file.

Emptiness is legitimate. If an update empties the handoff, delete the file. An empty handoff still costs context at every session start and tells the next session nothing; its absence already says it: nothing is in flight.

The same rule applies before writing the first one. A milestone with nothing in flight writes no handoff.

## On resume

When the hook is installed, the handoff is already in your context and you do not need to open the file to know where things stand. Start from "Next action" and raise the open questions if any of them block you. If nothing was injected and you have reason to expect a handoff, read the file yourself rather than concluding there is none: a hook that was never wired up looks exactly like an agent with nothing in flight.

Opening it again is for updating, not for catching up. At the next milestone, read the file (most edit tools require it) and rewrite it in place, dropping what you resolved along the way.

## Common mistakes

| Mistake | Why it hurts |
|---|---|
| One handoff per session or per date | The next session picks the wrong file, or reads three |
| Writing the narrative of the session | Nobody needs the path you took, only where it ended |
| Keeping resolved items "for history" | The file grows until it is skipped at boot |
| Writing a handoff with nothing in it | Burns context at every start to say nothing |
| Vague next action ("continue the migration") | A fresh session spends its first ten minutes deciding what that means |
| Putting durable knowledge in the handoff | Mechanisms, ops commands and stable facts belong in a README, an instructions file or the agent's memory. The handoff carries what is in flight |
| "I'll keep the old handoff for reference" | That is two files, and the next session cannot tell which one is current. The transcript is the reference |
| "This milestone is too small to note" | If it changed the next action or answered an open question, it is not |

## What this skill does not cover

Restarting the agent, scheduling, and process supervision are someone else's job. This skill only makes sure that whatever kills the session does not take the state with it.

If your agent is a coding session you will close today, you want a disposable handoff instead. A file in a temp directory, written once, read once. Matt Pocock's `handoff` skill does that well.
