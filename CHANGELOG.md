# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `.github/workflows/tests.yml`: a `Prose` step on the Linux leg fails when any
  tracked text file contains U+2014 (`git grep -I`).

### Changed

- README: the example (`## What one looks like`) comes before Install, and the
  anchor row starts with a link to it.
- README: voice pass on the whole file. Requirements and Try it are shorter. The
  facts they lost are in `docs/INSTALL.md` (version floor, `bash` shebang) and
  `docs/REFERENCE.md` (the handoff as executable input, the `.claude/` write
  prompt). `SECURITY.md` links there instead of at Try it.
- README: the intro says some sessions restart themselves when their context gets
  heavy, and that the plugin is for agents that get their messages through
  `claude --channels` or Remote Control.
- Demo GIF: rerecorded. The user answers the handoff's open question and says a
  restart is coming, the skill fires on its own and rewrites
  `.claude/handoff.md`, then `/exit`, `claude` again, and the new session
  answers `where were we?` from the file.
- Demo: runs with `--tools Read,Glob,Grep,Skill,Write`. `demo/setup.sh` and the
  README print the same flags and both say to restart with them. Nothing scopes
  `Write` to the handoff, so the README says to keep the session to the demo
  project.
- `demo.tape`: waits on the `Skill(persistent-handoff)` line, so a take where
  the skill does not fire times out. Carries the ffmpeg pass and lists what it
  cannot do (accept the trust prompt, record outside tmux, restore the demo
  handoff).
- Skill: the rewrite rule covers a session with no shell. The write tool with
  the full content is fine, the temporary file moved over the handoff stays the
  way when a shell exists.
- `CONTRIBUTING.md`: the em-dash bullet is removed.
- `CHANGELOG.md`: every entry rewritten as bullets, facts unchanged.

## [0.2.3] - 2026-08-30

### Changed

- README: rebuilt around its first screen (pitch, GIF with caption, anchor row,
  Install). 204 lines down to 129. Reference material moved to `docs/`. The only
  cut is the Tests section's list of what each case covers.
- `docs/REFERENCE.md`: new. The derived name and its digest, pinning
  `PERSISTENT_HANDOFF_FILE`, the `${CLAUDE_PROJECT_DIR}` expansion that does not
  happen inside an `env` block, several sessions sharing one path, the 10,000
  character cap with the preamble byte counts, the resume deduplication.
- `docs/INSTALL.md`: new. The hand install (two copy commands, the
  `settings.json` snippet), the five `SessionStart` sources a missing `matcher`
  covers, the double injection a plugin installed on top causes, the Windows
  note.
- `tests/manifests.sh` case 13 reads the hand-install snippet from
  `docs/INSTALL.md`. `CONTRIBUTING.md`, `demo.tape` and the hook's install
  comment name the same file.
- README: the "upgrading from 0.1.0" paragraph is a link to the 0.2.0 changelog
  entry.

## [0.2.2] - 2026-08-30

### Added

- `RELEASING.md`, `CONTRIBUTING.md` and `SECURITY.md`. `RELEASING.md` records
  that `main` is the release channel, since the marketplace clones the default
  branch.
- `tests/manifests.sh` case 14 resolves the `${CLAUDE_SKILL_DIR}` path SKILL.md
  hands the agent and asserts an executable file is there. 14 cases.
- `tests/hook.sh` case 37 pins the `--path` warning below. 37 cases.
- CI runs `./demo/setup.sh`, then calls the hook it installs the way the demo's
  `settings.json` calls it.
- CI runs `shellcheck` on the Linux leg at warning severity. SC2015 (the
  `&& ok || ko` of the test harness) and SC2016 (the literal
  `${CLAUDE_PLUGIN_ROOT}` that `manifests.sh` matches the hook command against)
  are info-level and deliberate.
- A `concurrency` group per ref. A second push cancels the run before it.

### Changed

- README: Claude Code floor 2.1.69 or newer, developed and tested on 2.1.251.
  `${CLAUDE_SKILL_DIR}` landed in 2.1.69. Before 2.1.214 a fork reports
  `resume`, which takes the same preamble. The hook needs `bash` on `PATH`, the
  shebang is `bash`.
- Skill: the write-to-a-temporary-file-then-move is unconditional. It used to
  depend on whether several sessions could be alive at once. A read landing
  mid-rewrite returns a truncated handoff.
- README: `.claude/settings.local.json` for wiring the hook into a repo shared
  with other people.
- README: what the derived path costs, and what happens to a handoff whose
  directory is deleted (nothing prunes `~/.claude/handoffs/`, date the content).
  Claude Code drops a `SessionStart` `additionalContext` already present in the
  transcript it reloaded, read out of the 2.1.251 binary, not documented.

### Fixed

- `--path` warns on stderr when it cannot create the directory it names. The
  `mkdir` was `|| true`, so a read-only `~/.claude` produced a path inside a
  directory that does not exist, and the agent's first write failed on "No such
  file or directory". The exit code stays 0.
- `tests/hook.sh` case 27 reads a flag of its own instead of the global counter.
  An earlier failure used to swallow it, no PASS and no FAIL.
- Four README numbers: seven short-lived processes with a handoff and five
  without (not four), fresh-start preamble 259 characters plus the path (not
  260), 404 to 407 after a compact (not 415), the workflow runs on pushes to
  `main` and on demand as well as on pull requests.
- `tests/hook.sh` unsets `PERSISTENT_HANDOFF_FILE`. A pinned one inherited from
  the shell won twelve cases.
- `cancel-in-progress` is scoped to pull requests. On `main` it could cut the
  run for a commit installers already had.

## [0.2.1] - 2026-08-30

### Changed

- The hook picks its preamble from the `SessionStart` source. On `compact`,
  `resume` and `fork` it says the session's own context is newer than the file
  for what that session did, the file is the reference for everything else, and
  a disagreement is settled by updating the file. It repeats the other
  preamble's instructions (start from "Next action", prune on update, delete
  when nothing is in flight). On `startup` and `clear` the preamble is
  unchanged. An absent, unreadable or unknown source, or no `jq`, takes the
  `startup` preamble.
- The hook still runs on all five sources. Narrowing it to `startup|clear` was
  tried and dropped. A full compaction keeps no message verbatim, so the handoff
  would only survive inside the summary. Presence costs about 500 tokens.
- `tests/hook.sh` is 36 cases. The four new ones pin the preamble for each
  source, for an absent and an unknown source, and for the no-`jq` fallback.
  `tests/manifests.sh` is 13. Cases 5, 12 and 13 hold `hooks/hooks.json`, the
  demo's `settings.json` and the README's hand-install snippet to a single
  matcher-less `SessionStart` entry.
- README: the passages that re-explained the contract in prose are removed.
  Install, the contract, the example, the file's location, the cap, the FAQ and
  the tests stay.
- A release badge next to the tests badge.

## [0.2.0] - 2026-08-30

### Added

- Plugin packaging: `.claude-plugin/plugin.json`, a marketplace manifest at the
  repo root, and `hooks/hooks.json`. Install is one command, no `settings.json`
  to edit.
- Demo: `demo/setup.sh` installs the hook and the skill into `demo/homelab`, a
  fictional homelab project carrying a real handoff.
- `tests/manifests.sh`, 11 cases pinning the manifests, including that this
  file's top entry is the version the manifests ship.
- `.github/workflows/tests.yml` runs both suites on Ubuntu, macOS and Windows.
- `session-start-handoff.sh --path` prints the handoff path for the current
  directory, creates the directory it names, and exits. Nothing else created
  `~/.claude/handoffs/` on the plugin install, so the first write used to fail.
- Any argument other than `--path` prints a usage line and exits 2. The hook
  reads stdin otherwise, so a mistyped flag hung on a terminal.

### Changed

- **Breaking.** The handoff name derived from the working directory ends in six
  hex characters of a digest of the full path. An agent in
  `/home/alice/work/acme/api` moves from `~/.claude/handoffs/work-acme-api.md`
  to `~/.claude/handoffs/work-acme-api-32817b.md`. The digest covers the
  absolute path, so it differs per machine. Run `session-start-handoff.sh --path`
  in the directory to get the new name. Rename existing handoffs, or set
  `PERSISTENT_HANDOFF_FILE` to keep the old path. The slug alone was lossy,
  `~/my project` and `~/my-project` were one file, and so were `~/abs/var/tmp/x`
  and `/var/tmp/x`. Twenty-four bits is not a uniqueness proof. Pin
  `PERSISTENT_HANDOFF_FILE` if you need a guarantee. The digest needs `cksum`.
  Without it the name falls back to the dashed part alone and the hook says so
  on stderr.
- Three defects in the digest fixed before release: a trailing slash split one
  directory into two handoffs, an unvalidated `cksum` output aborted the
  arithmetic, and a `shasum` fallback was a third name for the same directory.
- A cwd equal to `$HOME` is named `home-<digest>`. It used to be named after its
  own absolute path, which collided with that path spelled out under `$HOME`.
- `tests/manifests.sh` exits non-zero when `jq` is missing. It used to print
  `SKIP all` and exit 0.
- Demo: the hook is wired through `${CLAUDE_PROJECT_DIR}`. The relative paths it
  used resolved against the session's working directory, so a session opened in
  a subdirectory of the demo read no handoff.

### Fixed

- The handoff reaches `jq` on stdin instead of in `argv`. Linux caps a single
  argument at 128 KB, so a large handoff failed the exec and the hook fell
  through to its plain-text branch with `jq`'s error on stderr at every session
  start.
- A dangling symlink at the handoff path is reported instead of read as an
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

- Initial release: the `persistent-handoff` skill, the `SessionStart` hook, and
  `tests/hook.sh`. Installed by hand, by copying two files and adding a
  `SessionStart` entry to `settings.json`.

[Unreleased]: https://github.com/adrrr/persistent-handoff/compare/v0.2.3...HEAD
[0.2.3]: https://github.com/adrrr/persistent-handoff/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/adrrr/persistent-handoff/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/adrrr/persistent-handoff/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/adrrr/persistent-handoff/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/adrrr/persistent-handoff/releases/tag/v0.1.0
