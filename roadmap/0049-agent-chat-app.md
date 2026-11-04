# 0049: Talking to the agent from the desktop

Track: Agent · Status: done · Needs: 0043 · Spec: agent.md, programs.md, boot.md, toolkit.md, testing.md

## Why

0043's `run agent` is a shell's. On the desktop the agent wants an app
of its own: a conversation that scrolls, an entry to write in, each
tool it runs shown as it runs, and a way to see what it did while no
one watched (0053). Nothing it does asks the person's yes (0043), so
the app asks none either.

The app and the console are two windows on one agent, so `agentd`
holds one conversation for both, which outlives it, rather than one a
client that comes and goes.

## Done when

- `agentd` keeps one conversation, every client's, in its home, and
  reads it back when it starts.
- An app, launched from the launcher, holds that conversation with
  `agentd` through its protocol, what was said before it opened shown,
  its answers drawn as they stream.
- A tool's run is shown as a row that opens on what it did, and the
  turn can be stopped by a button.
- A screen test drives it with a stand-in model.

## Steps

- [x] One conversation, kept: `agentd` holds a single conversation for
  every client, its notices to every port opened (`open NPORT`, `close
  NPORT`), `say` and `stop` with no ID, and `clear` (the console's
  `/clear`); it keeps it in the home's `.history/conversation.json`,
  written whole and renamed over, at each request and turn's end, reads
  it back at start, and makes the system prompt anew at each turn. The
  `agent` e2e case kills and restarts `agentd`, and its next request
  holds the first turn.
- [x] What was said before: a client that opens is told the
  conversation so far, as the notices would have told it (`said` for
  the person's texts, then `opened busy|idle`), so a window opened late
  shows it; and every client is told `said` as a turn begins, whoever
  began it.
- [x] The app: Agent, `Agent.app` and its program `chat`, a window of
  the conversation in lines that wrap and scroll, following the end (the
  toolkit's new `lines.l0`), and an entry with Send that says a line,
  as wide as the window (0013's scrolling entry is not needed for it);
  the notices drawn as they stream, its asks replies in 0033's loop.
- [x] Each tool a row that opens on its input and result, a failed one
  red, and Stop in Send's place while a turn runs.
- [x] Its screen test, against the stand-in: `tests/agent.sh`, a turn
  said at the console drawn in both panes, the conversation's bubble
  and the Images pane's preview (0066).

## Spec changes

All moved into spec/.

## Log

- 2026-10-29: written, with 0041 to 0048.
- 2026-10-29: no yes-or-no buttons for tools: the user decided nothing
  the agent does asks the person's yes (0043).
- 2026-10-30: steps written; step 1 done, one conversation for every
  client, kept in the home through `agentd`'s restarts (agent.md's
  Kept), as the user asked before the app.
- 2026-10-31: steps 2 to 4 done: the conversation told on open and
  `said` to every client (agent.md's protocol); Agent (agent.md's
  "Agent, the app"), on the toolkit's new lines (toolkit.md). Seen on
  the screen by hand against the stand-in, a turn streaming, a tool row
  opened, a second window replaying the conversation, and Stop; the
  launcher's screen tests moved for its ninth cell. The console still
  shows no turn another client began.
- 2026-10-31: the tool rows moved, as the user asked, from the
  conversation to a Tools pane beside it, the conversation keeping a
  dimmed "Ran ..." line for each run of tools, and the window grown to
  960 by 560 (0058, done in the same change with the agent's new tools
  and the prompts' sources). The screen test, step 5, draws both panes.
- 2026-11-03: the conversation drawn as a phone's messages, its tools
  only in the side pane, which toggles with Images (0066); step 5 done
  with 0066's tests/agent.sh, and the goal.
