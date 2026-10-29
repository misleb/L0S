# 0049: Talking to the agent from the desktop

Track: Agent · Status: idea · Needs: 0043 · Spec: agent.md, programs.md, desktop.md, testing.md

## Why

0043's `run agent` is a shell's. On the desktop the agent wants an app
of its own: a conversation that scrolls, an entry to write in, each
tool it runs shown as it runs, its yes-or-no questions asked as
buttons, and a way to see what it did while no one watched.

## Done when

- An app, launched from the launcher, holds a conversation with
  `agentd` through its protocol, its answers drawn as they stream.
- A tool's run is shown as a row that opens on what it did, and a
  question for the person is answered by a button.
- A screen test drives it with a stand-in model.

## Steps

To be written. Leads: a long, growing conversation is 0013's entry
and the toolkit's scrolling; drawing as it streams is 0033's loop.

## Spec changes

- agent.md: the app.
- programs.md and desktop.md: its rows and its manifest.
- testing.md: its screen test.

## Log

- 2026-10-29: written, with 0041 to 0048.
