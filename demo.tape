# Recording for the README demo. Run it from the root of the repo:
#
#   ./demo/setup.sh && vhs demo.tape
#   ffmpeg -i demo.gif -filter_complex \
#     "[0:v]setpts=PTS/1.2,fps=12,split[a][b];\
#      [a]palettegen=max_colors=64:stats_mode=diff[p];\
#      [b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 demo.opt.gif \
#     && mv demo.opt.gif demo.gif
#
# The ffmpeg pass is the whole reason the GIF fits: the raw capture runs 52.6s
# and 1.17 MB, and comes out of it at 43.8s and 878 KB with nothing dropped.
#
# Beware when tuning the Sleep values: a Sleep is divided twice before it reaches
# the viewer, once by Set PlaybackSpeed and once by that setpts. Sleep 9s is 6.0
# seconds on screen (9 / 1.25 / 1.2). The two Sleep 9s at the end of each act are
# the only time the reader has to read the answer, so they are the last thing to
# shorten.
#
# Two acts, and the cut between them is the restart. Act one, the user answers
# the handoff's open question and says a restart is coming. The skill fires by
# itself and rewrites .claude/handoff.md on screen, question gone. Then /exit,
# and `claude` again. Act two, the fresh session answers "where were we?" out of
# the file act one wrote, without opening it. The Read on screen there is the log
# the handoff points at, not the handoff.
#
# demo/homelab is the project it records: a throwaway homelab repo with the hook
# installed at project scope, the way docs/INSTALL.md describes it. setup.sh puts
# the hook and the skill in place, .claude/settings.json wires SessionStart with
# the inline PERSISTENT_HANDOFF_FILE form, and .claude/handoff.md is the handoff.
#
# Nothing on the model's side is scripted. The tape waits for the Skill line and
# then for the turn to end, so a take where the skill does not fire on its own
# times out and fails rather than shipping. Record it again, and do not name the
# skill in the prompt.
#
# Expect to record more than once. Height is sized for a Write whose diff is
# small. When the model rewrites the whole file instead, the diff is twice as
# tall, Claude Code clips its own render rather than scrolling, the last line of
# the turn never reaches the screen and the second Wait times out. That is the
# tape refusing a take whose payoff the viewer would not have seen either.
#
# The flags sit in a shell function so the restart can show `claude` and nothing
# else. Same flags as the README's "Try it". Skill and Write are in there because
# act one writes the handoff. Nothing scopes Write to that file, the auto mode
# classifier is what let it through, and the GIF shows it saying so.
#
# Three things this tape does not do for you. Accept the trust prompt for
# demo/homelab once by hand first, the hidden boot does not answer it. Record
# outside tmux, or put `set -g focus-events on` in ~/.tmux.conf first, otherwise
# Claude Code prints a tmux warning in the footer of every frame. And afterwards,
# `git checkout -- demo/homelab/.claude/handoff.md`: the recording rewrites it,
# and the copy in the repo is the "before" state.

Output demo.gif

Require claude

Set Shell "bash"
Set FontSize 16
Set Width 1120
Set Height 1040
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms
Set Framerate 12
Set PlaybackSpeed 1.25
Set WaitTimeout 3m

# Boot is hidden: it carries the recorder's account banner. Ctrl+L clears it and
# leaves the header, and SessionStart has already put the handoff in the context.
Hide
Type "cd demo/homelab && PS1='homelab$ ' && clear"
Enter
Sleep 2s
Type 'claude() { clear; command claude --model claude-sonnet-5 --setting-sources project,local --strict-mcp-config --tools Read,Glob,Grep,Skill,Write "$@"; }; clear'
Enter
Sleep 2s
Type "claude"
Enter
Wait+Screen@90s /auto mode on/
Sleep 3s
Ctrl+L
Sleep 2s
Show

# Act one. The open question in the handoff gets an answer, and a restart is
# announced. No slash command, no skill named.
Sleep 2s
Type "Keep the daily snapshots for the year, that's decided. I'm going to restart you in a minute."
Sleep 1s
Enter
Wait+Screen@90s /Skill\(persistent-handoff\)/
Wait+Screen@120s /done \d/
Sleep 9s

# The cut. The process really dies and really comes back. Typing a slash opens
# the command palette over most of the screen, and it lists whatever commands
# and skills the recorder happens to have installed, so the whole thing is typed
# off camera. The trailing space closes the palette again. The viewer comes back
# to a prompt reading `/exit ` and watches the session go. Ctrl+D was tried
# instead and is not dependable here, it left the session up and sent "claude"
# to the model as a message.
Hide
Type "/exit "
Show
Sleep 2s
Enter
Sleep 2s
Type "claude"
Sleep 1s
Enter
Sleep 1s
Hide
Wait+Screen@90s /auto mode on/
Sleep 3s
Ctrl+L
Sleep 2s
Show

# Act two. Nothing of act one is in this session except the file.
Sleep 2s
Type "where were we?"
Sleep 1s
Enter
Wait+Screen@120s /done \d/
Sleep 9s
