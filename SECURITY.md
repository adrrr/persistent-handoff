# Security

The handoff is executable input. The hook feeds it into a fresh session as context, and the file tells that session what to do next. The README says it under "Try it": that is fine in `~/.claude/handoffs`, which only you write to, and a handoff committed to a repo means anyone who can push there can write into your agent's context.

Report a problem by opening an issue: https://github.com/adrrr/persistent-handoff/issues.

There is no private channel. For something you would rather not describe in the open, open an issue saying only that much and I will find another way to talk.
