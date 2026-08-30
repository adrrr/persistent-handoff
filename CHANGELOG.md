# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.1]: https://github.com/adrrr/persistent-handoff/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/adrrr/persistent-handoff/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/adrrr/persistent-handoff/releases/tag/v0.1.0
