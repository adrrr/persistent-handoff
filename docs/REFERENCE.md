# Reference

The short answers in the README, in full. All of it is behaviour of [`hooks/session-start-handoff.sh`](../hooks/session-start-handoff.sh).

## The derived name

By default the hook names the file after the working directory relative to your home, separators turned into dashes, plus a short digest of the full path. An agent in `/home/alice/work/acme/api` reads `~/.claude/handoffs/work-acme-api-32817b.md`.

The dashed part lets you read the directory off the filename. The six hex characters separate what it merges, `~/my project` and `~/my-project`, or `~/abs/var/tmp/x` and `/var/tmp/x`. The digest covers the absolute path, so yours won't match the example. Twenty-four bits is not a uniqueness proof, it makes a clash a coincidence. A `cksum` collision can also be constructed on purpose, and a handoff is executable input. Pin `PERSISTENT_HANDOFF_FILE` if you need a guarantee. The digest needs `cksum`, which is POSIX and present everywhere this is tested. Without it the name falls back to the dashed part and the hook says so on stderr.

`session-start-handoff.sh --path` prints the name for the directory you run it in. The skill uses it before its first write. After that, the hook names the path in the line it injects above the content.

## Pinning the path

For an agent not tied to one directory, set `PERSISTENT_HANDOFF_FILE` in the `env` block of the same `settings.json`:

```json
{
  "env": {
    "PERSISTENT_HANDOFF_FILE": "/home/alice/.claude/handoffs/fleet.md"
  }
}
```

Write an absolute path. `${CLAUDE_PROJECT_DIR}` is expanded in a hook's `command` string but not in the `env` block, so a path using it there reaches the hook literally and finds no file. The demo sets the variable inline in the hook command, where it does expand. That sets it for the hook only, the agent never sees it and writes its first handoff somewhere else. Use that form only when you tell the agent where its handoff lives, which is why the demo names its handoff in its README.

## An empty path, and several sessions on one

Nothing happens until a handoff exists. The hook is silent when the file is missing or holds only whitespace, so it costs nothing on sessions with no state to carry.

Three sessions in one directory are one agent, and the last writer wins. Writing to a temporary file and moving it over prevents a torn read, not a lost update. Pin `PERSISTENT_HANDOFF_FILE` per session if they hold separate work.

## The 10,000 character cap

Claude Code caps a hook's output at 10,000 characters and injects a truncated preview plus a path past that. The limit is Claude Code's and can move in a release without warning. The preamble takes 259 characters plus the path on a fresh start, 404 to 407 after a compact, a resume or a fork. A handoff of 300 to 500 tokens sits far below the cap. One grown into a journal arrives as a preview.

## Repeated resumes do not stack copies

Claude Code drops a `SessionStart` `additionalContext` whose exact text is already in the reloaded transcript. The two preambles are different strings, so a session started fresh and then resumed carries both, and every later resume is deduplicated as long as the file doesn't change. This is read out of the 2.1.251 binary and documented nowhere, take it as an observation.

## The handoff is input the agent acts on

The hook feeds the handoff into a fresh session as context, and the file tells that session what to do next. Treat it as executable input and read [`hooks/session-start-handoff.sh`](../hooks/session-start-handoff.sh) before installing. That's fine in `~/.claude/handoffs`, which only you write to. A handoff committed to a repo means anyone who can push there writes into your agent's context, so keep that to repos whose writers you trust. The demo's trust prompt preselects the option that exits, because the demo carries a project hook.

Claude Code treats anything under `.claude/` as sensitive, so a session set to ask will ask before the skill writes `.claude/handoff.md`. The GIF ran in auto mode, which allowed the write and printed that it had.
