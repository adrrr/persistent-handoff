# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The demo GIF is two acts, and the cut between them is a restart. The first act
  is the half that was missing: the user answers the handoff's open question and
  says a restart is coming, the skill fires on its own, and `.claude/handoff.md`
  is rewritten on screen with the question gone. Then `/exit`, `claude` again,
  and the fresh session answers `where were we?` from the file the previous one
  wrote. 43.8 seconds, 878 KB.
- The demo runs with `--tools Read,Glob,Grep,Skill,Write`. Writing the handoff is
  the point of the first act. Nothing scopes Write to the handoff, so the README
  says to keep the session to the demo project. `demo/setup.sh` and the README
  print the same flags, and both say to restart with them.
- `demo.tape` waits on the `Skill(persistent-handoff)` line, so a take where the
  skill does not fire by itself times out instead of shipping. It also carries
  the ffmpeg pass, which is what takes the raw capture from 52.6 s and 1.17 MB
  down to what ships, and the three things it cannot do for you: accept the
  folder's trust prompt, record outside tmux, and restore the demo handoff
  afterwards.
- The skill's rewrite rule now says what to do without a shell: the write tool
  with the full content is fine, and the temporary file moved over the handoff
  stays the way to go when a shell exists. The GIF's session has no Bash, and the
  old wording called the tool it uses the wrong one.
- The README says what the plugin was built for: agents that run for weeks and
  get their messages through `claude --channels` or Remote Control, where a
  restart has to go unnoticed from the other end.

## [0.2.3] - 2026-08-30

### Changed

- The README is built around its first screen: the pitch, the GIF with a
  caption, an anchor row, then Install. 204 lines down to 129. The reference material moved into `docs/`; the only cut is the Tests section's list of what each case covers.
- `docs/REFERENCE.md` is new and holds what the README used to explain inline:
  the derived name and its digest, pinning `PERSISTENT_HANDOFF_FILE`, the
  `${CLAUDE_PROJECT_DIR}` expansion that does not happen inside an `env` block,
  several sessions sharing one path, the 10,000 character cap with the preamble
  byte counts, and the resume deduplication. The README keeps one sentence on
  each and links here.
- `docs/INSTALL.md` is new and holds the hand install: the two copy commands,
  the `settings.json` snippet, the five `SessionStart` sources a missing
  `matcher` covers, the double injection a plugin installed on top of it causes,
  and the Windows note. The README keeps the WSL-or-Git-for-Windows sentence,
  since a hook that lands in PowerShell runs nothing at all.
- Case 13 of `tests/manifests.sh` reads the hand-install snippet from
  `docs/INSTALL.md`. It went red on the move before it was pointed at the new
  file, which is the only evidence that it pins anything. `CONTRIBUTING.md`,
  `demo.tape` and the hook's own install comment name the same file now.
- The "upgrading from 0.1.0" paragraph in Install is a link to the 0.2.0
  changelog entry, which already carried it word for word.

## [0.2.2] - 2026-08-30

### Added

- `RELEASING.md`, `CONTRIBUTING.md` and `SECURITY.md`. The release checklist
  lived in one head, and the fact that `main` is the release channel, since the
  marketplace clones the default branch, was written down nowhere.
- `tests/manifests.sh` case 14 resolves the `${CLAUDE_SKILL_DIR}` path SKILL.md
  hands the agent, and asserts an executable file is there. 14 cases. Editing
  that suffix used to break nothing: Claude Code expands the variable when it
  loads the skill, so a wrong path failed on the user's machine and never here.
- `tests/hook.sh` case 37 pins the `--path` warning below. 37 cases.
- CI runs `./demo/setup.sh`, then calls the hook it installs the way the demo's
  own `settings.json` calls it. Nothing exercised the demo before, and it is the
  first thing the README tells people to run.
- CI runs `shellcheck` on the Linux leg, at warning severity. The two info-level
  codes this repo trips are deliberate and would be noise: the `&& ok || ko` of
  the test harness, and the literal `${CLAUDE_PLUGIN_ROOT}` that `manifests.sh`
  matches the hook command against.
- A `concurrency` group per ref, so a second push cancels the run before it.

### Changed

- The README states the Claude Code floor: 2.1.69 or newer, developed and tested
  on 2.1.251. `${CLAUDE_SKILL_DIR}` landed in 2.1.69, and before 2.1.214 a fork
  reports `resume`, which takes the same preamble. It also says the hook needs
  `bash` on `PATH` rather than only a portable shell, since the shebang is
  `bash` and an image without it runs nothing.
- The skill asks for the write-to-a-temporary-file-then-move unconditionally. It
  used to depend on whether several sessions of the agent could be alive at
  once, which the agent has no way to know. A read landing mid-rewrite returns a
  truncated handoff and nothing in it says so.
- The README points at `.claude/settings.local.json` for wiring the hook into a
  repo you share with other people, which is the file meant to stay out of the
  commit.
- The README documents what the derived path costs, and answers what happens to
  a handoff whose directory is deleted: nothing prunes `~/.claude/handoffs/`, so
  date the content. It also records that Claude Code drops a `SessionStart`
  `additionalContext` already present in the transcript it reloaded, which is
  read out of the 2.1.251 binary rather than documented.

### Fixed

- `--path` says on stderr when it cannot create the directory it names. The
  `mkdir` was `|| true`, so a read-only `~/.claude` produced a confident path
  inside a directory that does not exist, exit 0 and stderr empty, and the
  agent's first write then died on "No such file or directory" with nothing
  pointing at the cause. The exit code stays 0: a `SessionStart` hook that fails
  the session is worse than one that warns.
- `tests/hook.sh` case 27 reads a flag of its own instead of the global counter.
  Any earlier failure swallowed it whole, no PASS and no FAIL, and the run
  printed one line fewer without saying so.
- Four numbers in the README that were wrong. The hook spawns seven short-lived
  processes with a handoff and five without, not four. The fresh-start preamble
  is 259 characters plus the path, not 260, and the one after a compact is 404
  to 407, not 415. The workflow runs on pushes to `main` and on demand as well
  as on pull requests.
- `tests/hook.sh` unsets `PERSISTENT_HANDOFF_FILE`. The suite stages handoffs at
  derived paths, so a pinned one inherited from the shell won twelve cases, and
  a pinned one is exactly what the README tells a fleet operator to export.
- `cancel-in-progress` is scoped to pull requests. On `main` it could have cut
  the run for a commit that installers already had.

## [0.2.1] - 2026-08-30

### Changed

- The hook picks its preamble from the `SessionStart` source and states a
  precedence. On `compact`, `resume` and `fork` it says the session's own
  context is newer than the file for what that session did, and the file is the
  reference for everything else, so a disagreement is settled by updating the
  file. It repeats the instructions the other preamble carries, start from
  "Next action", prune on update, delete when nothing is in flight, since a
  compacted session is precisely the one that no longer has them. On `startup`
  and `clear` the preamble is unchanged. An absent, an
  unreadable or an unknown source takes the `startup` preamble, which asserts no
  precedence; that is also what happens with no `jq` to read the payload with,
  the same fallback the derived path already takes.
  The hook still runs on all five sources. Narrowing it to `startup|clear` was
  tried and dropped: a full compaction keeps no message verbatim, so the handoff
  would survive only inside the summary, at the summarizer's discretion, and a
  second compaction would summarize the first. Presence is worth the ~500 tokens
  it costs; the double state it used to create is what the preamble now settles.
- `tests/hook.sh` is 36 cases. The four new ones pin the preamble for each
  source, for an absent and an unknown source, and for the no-`jq` fallback.
  `tests/manifests.sh` is 13: cases 5, 12 and 13 hold `hooks/hooks.json`, the
  demo's `settings.json` and the README's hand-install snippet to a single
  matcher-less `SessionStart` entry.
- The README lost about a hundred lines. The passages that re-explained the
  contract in prose are gone; install, the contract, the example, the file's
  location, the cap, the FAQ and the tests all stay.
- A release badge sits next to the tests badge.

## [0.2.0] - 2026-08-30

### Added

- Claude Code plugin packaging: `.claude-plugin/plugin.json`, a marketplace
  manifest at the repo root, and `hooks/hooks.json`, which Claude Code discovers
  on its own. Install is one command and there is no `settings.json` to edit.
- A runnable demo: `demo/setup.sh` installs the hook and the skill into
  `demo/homelab`, a fictional homelab project carrying a real handoff.
- `tests/manifests.sh`, 11 cases pinning the manifests, including a check that
  this file's top entry is the version the manifests ship.
- `.github/workflows/tests.yml` runs both suites on Ubuntu, macOS and Windows.
- `session-start-handoff.sh --path` prints the handoff path for the current
  directory and exits, and creates the directory it names. The derived name now
  ends in a digest, so an agent writing its first handoff asks the hook instead
  of recomputing the rule. Nothing else created `~/.claude/handoffs/` on the
  plugin install, so that first write used to fail.
- Any argument other than `--path` prints a usage line and exits 2. The hook
  reads stdin unconditionally otherwise, so a mistyped flag hung on a terminal.

### Changed

- **Breaking.** The handoff name derived from the working directory now ends in
  six hex characters of a digest of the full path. An agent in
  `/home/alice/work/acme/api` moves from `~/.claude/handoffs/work-acme-api.md`
  to `~/.claude/handoffs/work-acme-api-32817b.md`. The digest covers the
  absolute path, so it differs per machine: run
  `session-start-handoff.sh --path` in the directory to get the new name.
  Rename existing handoffs, or set `PERSISTENT_HANDOFF_FILE` to keep the old
  path. The readable slug is lossy:
  `~/my project` and `~/my-project` used to be one file, and so did
  `~/abs/var/tmp/x` and `/var/tmp/x`. Twenty-four bits is not a uniqueness
  proof, it makes a clash a coincidence rather than a certainty; pin
  `PERSISTENT_HANDOFF_FILE` if you need a guarantee. The digest needs `cksum`;
  without it the name falls back to the dashed part alone and the hook says so
  on stderr. Three defects in this mechanism were found and fixed before
  release rather than shipped: a trailing slash splitting one directory into two
  handoffs, an unvalidated `cksum` output aborting the arithmetic, and a
  `shasum` fallback that was a third silent name for the same directory.
- A cwd equal to `$HOME` is named `home-<digest>` instead of being named after
  its own absolute path, which collided with that same path spelled out under
  `$HOME`.
- `tests/manifests.sh` exits non-zero when `jq` is missing. It used to print
  `SKIP all` and exit 0, so a runner without `jq` was green having asserted
  nothing.
- The demo wires its hook through `${CLAUDE_PROJECT_DIR}`. The relative paths it
  used before resolved against the session's working directory, so opening a
  session in a subdirectory of the demo read no handoff and said nothing.

### Fixed

- The handoff reaches `jq` on stdin instead of in `argv`. Linux caps a single
  argument at 128 KB, so a large handoff failed the exec and the hook fell
  through to its plain-text branch with `jq`'s error on stderr at every session
  start. Found by the new CI matrix on its first run.
- A dangling symlink at the handoff path is reported instead of being read as an
  absence. `[ -e ]` is false for a broken link, so the hook exited silently.
- A handoff containing only whitespace is treated as empty. It used to emit the
  preamble with nothing behind it.

### Upgrading from 0.1.0

The derived filename gained a digest, so the hook will not find a handoff
written by 0.1.0. Nothing warns you: the hook reads the new name, finds nothing,
and stays silent. In each directory that has a handoff, run
`session-start-handoff.sh --path` and rename the file to what it prints, or set
`PERSISTENT_HANDOFF_FILE` to the old path. Agents already pinned with
`PERSISTENT_HANDOFF_FILE` are unaffected.

## [0.1.0] - 2026-08-23

Initial release: the `persistent-handoff` skill, the `SessionStart` hook, and
`tests/hook.sh`. Installed by hand, by copying two files and adding a
`SessionStart` entry to `settings.json`.

[Unreleased]: https://github.com/adrrr/persistent-handoff/compare/v0.2.3...HEAD
[0.2.3]: https://github.com/adrrr/persistent-handoff/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/adrrr/persistent-handoff/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/adrrr/persistent-handoff/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/adrrr/persistent-handoff/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/adrrr/persistent-handoff/releases/tag/v0.1.0
