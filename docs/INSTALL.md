# Installing by hand

The plugin install in the [README](../README.md#install) is one command and wires the hook for you. This is the same result without plugins: copy two files, add one entry to `settings.json`.

## Claude Code version

The plugin needs Claude Code 2.1.69 or newer. It's developed and tested on 2.1.251. `${CLAUDE_SKILL_DIR}`, which the skill uses to name the hook, landed in 2.1.69. Before 2.1.214 a fork reports `resume`, which takes the same preamble, so nothing else changes.

The hook needs `bash` on `PATH`. It uses no BSD-only flags and `jq` is optional, but the shebang is `bash`, not `sh`, so a container image without bash won't run the hook at all.

## Copy the skill and the hook

```bash
src=$(mktemp -d) && git clone https://github.com/adrrr/persistent-handoff "$src"
mkdir -p ~/.claude/skills/persistent-handoff ~/.claude/hooks ~/.claude/handoffs
cp -r "$src"/skills/persistent-handoff/. ~/.claude/skills/persistent-handoff/
install -m 755 "$src"/hooks/session-start-handoff.sh ~/.claude/hooks/
```

The `cp` copies the contents rather than the directory, so running the install twice updates the skill instead of nesting a copy inside it.

## Wire the hook

Add it to `~/.claude/settings.json`, or to a project `.claude/settings.json`. In a repo you share with other people, use `.claude/settings.local.json` instead: same shape, and it is the file meant to stay out of the commit.

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

There is no `matcher`, so the hook runs on all five `SessionStart` sources: `startup`, `clear`, `compact`, `resume` and `fork`. It reads the source out of the payload and switches its preamble on the last three, the ones where the session already holds a context of its own.

## Do not run both installs

Installing the plugin on top of this leaves two handlers, and the handoff is injected twice. Remove the `SessionStart` entry from your `settings.json` and delete `~/.claude/skills/persistent-handoff/` first.

## Windows

WSL is the recommended path. Claude Code inside WSL is a Linux environment, so everything here applies unchanged.

On native Windows, Claude Code runs a `command` hook through Git Bash when [Git for Windows](https://git-scm.com/downloads/win) is installed, and through PowerShell when it is not. Install Git for Windows first. Without it the hook lands in PowerShell, which will not run a bash script.

## Upgrading from 0.1.0

The derived filename gained a digest, so the hook will not find a handoff written by 0.1.0, and nothing warns you. The [0.2.0 changelog entry](../CHANGELOG.md#upgrading-from-010) says what to rename.
