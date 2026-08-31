# Installing by hand

The plugin install in the [README](../README.md#install) is one command and wires the hook for you. This page is the same result without plugins: copy two files, add one entry to `settings.json`.

## Plugin commands

Inside a running session, `/plugin marketplace add adrrr/persistent-handoff` then `/plugin install persistent-handoff@persistent-handoff` do the same as the README command. Start a new session and the skill and the hook are live. `claude plugin uninstall persistent-handoff@persistent-handoff` removes the plugin, `claude plugin marketplace remove persistent-handoff` drops the marketplace entry.

## Claude Code version

The plugin needs Claude Code 2.1.69 or newer. It's developed and tested on 2.1.251. `${CLAUDE_SKILL_DIR}`, which the skill uses to name the hook, landed in 2.1.69. Before 2.1.214 a fork reports `resume`, which takes the same preamble.

The hook needs `bash` on `PATH`. It uses no BSD-only flags and `jq` is optional. The shebang is `bash`, not `sh`, so a container image without bash won't run it.

## Copy the skill and the hook

```bash
src=$(mktemp -d) && git clone https://github.com/adrrr/persistent-handoff "$src"
mkdir -p ~/.claude/skills/persistent-handoff ~/.claude/hooks ~/.claude/handoffs
cp -r "$src"/skills/persistent-handoff/. ~/.claude/skills/persistent-handoff/
install -m 755 "$src"/hooks/session-start-handoff.sh ~/.claude/hooks/
```

The `cp` copies the contents, not the directory, so a second run updates the skill instead of nesting a copy inside it.

## Wire the hook

Add it to `~/.claude/settings.json` or a project `.claude/settings.json`. In a repo you share, use `.claude/settings.local.json`, same shape, and it stays out of the commit.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$HOME\"/.claude/hooks/session-start-handoff.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

No `matcher`, so the hook runs on all five `SessionStart` sources, `startup`, `clear`, `compact`, `resume` and `fork`. It reads the source from the payload and switches its preamble on the last three, where the session already holds a context of its own.

## Do not run both installs

The plugin on top of this leaves two handlers and injects the handoff twice. Remove the `SessionStart` entry from your `settings.json` and delete `~/.claude/skills/persistent-handoff/` first.

## Windows

WSL is the recommended path. Claude Code inside WSL is Linux, so everything here applies unchanged.

On native Windows, Claude Code runs a `command` hook through Git Bash when [Git for Windows](https://git-scm.com/downloads/win) is installed, and through PowerShell when it isn't. Install Git for Windows first, PowerShell won't run a bash script.

## Upgrading from 0.1.0

The derived filename gained a digest, so the hook won't find a handoff written by 0.1.0 and nothing warns you. The [0.2.0 changelog entry](../CHANGELOG.md#upgrading-from-010) says what to rename.
