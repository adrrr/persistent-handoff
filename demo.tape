# Recording for the README demo. Run it from the root of the repo:
#
#   ./demo/setup.sh && vhs demo.tape
#
# demo/homelab is the project it records: a throwaway homelab repo with the hook
# installed at project scope, the way the "Install by hand" section describes it. setup.sh puts
# the hook and the skill in place, .claude/settings.json wires SessionStart with
# the inline PERSISTENT_HANDOFF_FILE form, and .claude/handoff.md is the handoff.
#
# The claude flags keep the recording clean, not the answer: they load only the
# project's settings, skip the recorder's own MCP servers, and leave the session
# read-only so it stays inside the repo. Nothing about the reply is scripted.

Output demo.gif

Require claude

Set Shell "bash"
Set FontSize 16
Set Width 1120
Set Height 780
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set Framerate 12
Set PlaybackSpeed 0.7
Set WaitTimeout 3m

# Boot is hidden: it carries the recorder's account banner. /clear redraws a clean
# header and fires SessionStart again, which is where the handoff comes back in.
Hide
Type "cd demo/homelab && clear"
Enter
Sleep 2s
Type "claude --model claude-sonnet-5 --setting-sources project,local --strict-mcp-config --tools Read,Glob,Grep"
Enter
Wait+Screen@90s /auto mode on/
Sleep 3s
Type "/clear"
Enter
Sleep 5s
Ctrl+L
Sleep 2s
Show

Sleep 2s
Type "where were we?"
Sleep 1s
Enter
Wait+Screen@180s /done \d/
Sleep 5s
