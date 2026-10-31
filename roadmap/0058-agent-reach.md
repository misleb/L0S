# 0058: The agent's reach: where a prompt came from, and the desktop, the files and the clock

Track: Agent · Status: done · Needs: 0043, 0049 · Spec: agent.md, desktop.md, programs.md, testing.md

## Why

0043's agent reaches the system through `sh` and `run`, and the
desktop only through `draw`'s few shapes: it cannot see the windows,
open an app, move one, or draw what it likes, and it learns the time
only from a program's output. Prompts will come from more than the
console and the Agent app, from speech to text and from other
programs, and the agent should know which it is answering and weigh it.
The Agent app's rows of tools crowd the conversation they belong to.

## Done when

- Each prompt carries where it came from, a word the client names and
  the program the kernel says sent it, kept in the conversation as a
  line before the text the model reads, and shown by no window but as a
  dimmed line in Agent when it came from elsewhere.
- The agent has tools of the compositor (the windows, an app opened, a
  window placed, raised or closed, an SVG drawn over the desktop, the
  wallpaper put back), of the files (remove, rename, what is at a path,
  the volumes) and of the clock (the time).
- Agent shows the tools in a pane of their own beside the conversation.
- An e2e case drives every new tool against the stand-in and checks
  each result, and the agent case checks the console's source line.

## Steps

- [x] Prompt sources: `say SOURCE`, `said SOURCE`, the source line
  (`conv_said_blocks`) with the sending program's path from the kernel,
  the replay telling it again, the system prompt saying what it means.
- [x] The compositor's `place`, `raise`, `dismiss` and `paste`, any
  client's, and the agent's tools of the desktop over them (agentd's
  `desk.l0`), `draw_desktop` drawn by the SVG library in agentd.
- [x] The file tools `remove`, `rename`, `file_info` and `volumes`,
  the home's history keeping a remove and a rename there.
- [x] The clock's `time` tool.
- [x] Agent's Tools pane, and a dimmed line in the conversation naming
  each run of tools.
- [x] The `agent_desk` e2e case, and the source line checked in `agent`.

## Spec changes

None left: all moved into agent.md, desktop.md, programs.md and
testing.md.

## Log

- 2026-10-31: written and done in one change, as the user asked: the
  source of a prompt, so speech and other programs can say theirs; the
  agent's tools of the desktop, the files and the clock; Agent's Tools
  pane. Seen on the screen by hand against the stand-in: a sun drawn on
  the desktop, Files opened, a window placed and another raised, and
  the two panes. Left for later: a prompt's source is any word its
  client names, vouched for only by the program's path beside it, and
  nothing limits a tool by the source of the turn it runs in; the
  tools of the desktop and the clock hold `agentd` while they wait (up
  to 3 s for `open_app`'s window); `draw_desktop` draws at most 640 by
  400 of the screen's pixels at once.
