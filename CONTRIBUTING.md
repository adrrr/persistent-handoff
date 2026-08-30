# Contributing

- Run both suites before you push: `bash tests/hook.sh` and `bash tests/manifests.sh`. CI runs the same two on Ubuntu, macOS and Windows, plus `shellcheck` and a real `demo/setup.sh` install.
- New behaviour in the hook comes with a case in `tests/hook.sh`. Break the hook on purpose first and watch your case go red, a case that has never failed proves nothing.
- The `SessionStart` block lives in three copies: `hooks/hooks.json`, the hand-install snippet in `docs/INSTALL.md`, and `demo/homelab/.claude/settings.json`. Cases 5, 12 and 13 of `tests/manifests.sh` hold them to one shape, so they move together or CI says so.
- No em-dashes (U+2014) in the prose. A comma, a parenthesis, or a new sentence. The character appears nowhere in this repo, which is what makes a grep for it worth running.
- Keep PRs short. One thing per PR, and say in the body what breaks if it is wrong.
- Releases follow [`RELEASING.md`](RELEASING.md).
