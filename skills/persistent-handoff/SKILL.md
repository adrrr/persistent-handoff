---
name: persistent-handoff
description: Use when an agent works across many sessions and its context will not survive - at a milestone (a decision made, a PR opened or merged, an investigation concluded, a blocker hit, a question left with the human), when context grows heavy and a restart or compact is coming, when the user says "write a handoff", "note where you are", "prepare a restart", or at the start of a session that resumes earlier work.
---

# Persistent handoff

An agent that runs for weeks loses its context many times: restarts, compacts, crashes, machine reboots. The handoff is the one file that survives those deaths. It holds where the work stands, what to do next, and what a fresh session would otherwise have to relearn the hard way.

One handoff per agent. It is a state, not a journal.

## When to write

At milestones, on your own, without being asked:

- a decision is made
- a PR is opened or merged
- an investigation reaches a conclusion
- you hit a blocker
- you asked the human something and the answer has not come yet

Not after every message. The transcript already keeps the conversation. The handoff keeps what a new session needs to act.

## Where it lives

One path, chosen once, used by every session of this agent. Default `~/.claude/handoffs/<agent-name>.md`, or a path in the project repo if the agent is bound to one. The `SessionStart` hook reads that exact path. A handoff written anywhere else is never read.

Never two files. If a handoff already exists, edit it in place. Do not stamp it with a date, do not keep the previous one for reference, do not open a second one for a second subject. Two handoffs mean the next session reads the wrong one.

## What goes in it

Roughly 300 to 500 tokens, five sections:

**Where I am.** The real state, not the story of how you got there.

**Next action.** The first thing to do on resume, written so it can be executed rather than interpreted.

**Open questions.** What waits on a human, phrased as the question you would ask.

**Traps.** What was learned the hard way and would be paid for twice: exact paths, gotchas, facts you verified, approaches that failed and why.

**Skills to invoke on resume.** Name the skills the current work depends on, so the next session loads them before starting instead of rediscovering them halfway. Omit the section if none apply.

## Clean as you advance

Every update deletes what is resolved or stale. A file that only grows is a journal, and nobody reads a journal at boot.

Emptiness is legitimate. If an update empties the handoff, delete the file. An empty handoff still costs context at every session start and tells the next session nothing. Its absence is the signal: nothing is in flight.

The same rule applies before writing the first one. A milestone with nothing in flight writes no handoff.

## On resume

The hook has already placed the handoff in context. Do not re-read the file. Start from "Next action", raise the open questions if any block you, and delete what you have just resolved.

## Common mistakes

| Mistake | Why it hurts |
|---|---|
| One handoff per session or per date | The next session picks the wrong file, or reads three |
| Writing the narrative of the session | Nobody needs the path you took, only where it ended |
| Keeping resolved items "for history" | The file grows until it is skipped at boot |
| Writing a handoff with nothing in it | Burns context at every start to say nothing |
| Vague next action ("continue the migration") | A fresh session spends its first ten minutes deciding what that means |
| Putting durable knowledge in the handoff | Mechanisms, ops commands and stable facts belong in a README, an instructions file or the agent's memory. The handoff carries what is in flight |

## What this skill does not cover

Restarting the agent, scheduling, and process supervision are someone else's job. This skill only makes sure that whatever kills the session does not take the state with it.

If your agent is a coding session you will close today, you want a disposable handoff instead. A file in a temp directory, written once, read once. Matt Pocock's `handoff` skill does that well.
