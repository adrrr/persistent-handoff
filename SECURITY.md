# Security

The handoff is executable input. The hook feeds it into a fresh session as context, and the file tells that session what to do next. That's fine in `~/.claude/handoffs`, which only you write to. A handoff committed to a repo means anyone who can push there can write into your agent's context. [`docs/REFERENCE.md`](docs/REFERENCE.md#the-handoff-is-input-the-agent-acts-on) has the details.

Report a problem by opening an issue: https://github.com/adrrr/persistent-handoff/issues.

There is no private channel. For something you would rather not describe in the open, open an issue saying only that much and I will find another way to talk.
