# Reference

The short answers in the README, in full. All of it is behaviour of
[`hooks/session-start-handoff.sh`](../hooks/session-start-handoff.sh).

## The derived name

By default the hook names the file after the working directory, relative to your home directory, with the separators turned into dashes and a short digest of the full path on the end. An agent running in `/home/alice/work/acme/api` reads `~/.claude/handoffs/work-acme-api-32817b.md`.

The dashed part lets you read the directory off the filename. The six hex characters carry what it loses: without them `~/my project` and `~/my-project` are one file, and so are `~/abs/var/tmp/x` and `/var/tmp/x`. The digest covers the absolute path, so yours will not match the example above. Twenty-four bits is not a uniqueness proof, it makes a clash a coincidence rather than a certainty. A `cksum` collision can also be constructed on purpose by anyone who wants one, and a handoff is executable input. Pin `PERSISTENT_HANDOFF_FILE` if you need a guarantee. The digest needs `cksum`, which is POSIX and present everywhere this is tested. Without it the name falls back to the dashed part alone, and the hook says so on stderr.

To read the name for a directory rather than work it out, run `session-start-handoff.sh --path` there. That is how the skill finds the path before its first write. After that, the hook names the path in the line it injects above the content.

## Pinning the path

For an agent that is not tied to one directory, pin the path instead. The hook reads `PERSISTENT_HANDOFF_FILE`, and the place to set it is the `env` block of the same `settings.json`:

```json
{
  "env": {
    "PERSISTENT_HANDOFF_FILE": "/home/alice/.claude/handoffs/fleet.md"
  }
}
```

Write an absolute path there. `${CLAUDE_PROJECT_DIR}` is expanded in a hook's `command` string but not inside the `env` block, so a path using it there arrives at the hook literally and finds no file. The demo sets the variable inline in the hook command instead, where the expansion does happen. That form sets it for the hook only, so the agent never sees it and writes its first handoff somewhere else. Use it only when you tell the agent outright where its handoff lives, which is why the demo names its own handoff in its README.

## An empty path, and several sessions on one

Nothing happens until a handoff exists. The hook stays silent when the file is missing or holds nothing but whitespace, so installing it costs nothing on sessions with no state to carry.

Three sessions in one directory are one agent by this design, and the last writer wins. Writing to a temporary file and moving it over prevents a torn read, not a lost update, so pin `PERSISTENT_HANDOFF_FILE` per session if they hold genuinely separate work.

## The 10,000 character cap

Claude Code caps a hook's output at 10,000 characters and injects a truncated preview plus a path past that. This is Claude Code's limit rather than this repo's, so it can move in a future release with nothing to warn you. The preamble takes 259 characters plus the path on a fresh start, and 404 to 407 after a compact, a resume or a fork. A handoff kept to 300 to 500 tokens sits far below the limit. One grown into a journal arrives as a preview.

## Repeated resumes do not stack copies

Claude Code drops a `SessionStart` `additionalContext` whose exact text is already in the transcript it reloaded. The two preambles are two different strings, so a session that started fresh and was then resumed carries both, and every resume after that is deduplicated for as long as the file does not change. That is read out of the 2.1.251 binary and documented nowhere, so take it as an observation rather than a contract.
