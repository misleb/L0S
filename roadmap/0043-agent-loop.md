# 0043: `agentd`, an agent's loop and its tools on L0S

Track: Agent · Status: idea · Needs: 0042 · Spec: agent.md (new), programs.md, demo.md

## Why

The aim of this track is an L0S installation, a Pi 5's first, as the
home of an agent: its memories, skills and rules kept on the board,
the model reached over the network, everything else done there. Claude's
Agent SDK is not ported: it is Claude Code's harness, TypeScript on
Node. What makes an agent is small, and is written here in L0:

- the loop: send the conversation and the tools, run each tool the
  answer asks for, send the results back, until the answer is done;
- the context: the personality read in at the start (0044), prompt
  caching so that it is not paid for on every turn, and the
  conversation compacted when it grows long;
- the tools, each a request to a server L0S already has: read, write
  and list files in the agent's home, run a program and read what it
  wrote, a command at `sh`.

The model and its provider sit behind one interface, since neither is
chosen yet. Running a model on the board itself is not part of this.

## Done when

- `agentd` serves a protocol of its own: a conversation's turns in, the
  answer streamed back as notices, each tool it runs told as it runs.
- `run agent` talks to it from a shell, on QEMU and on a Pi 5.
- Its tools reach only the agent's home and the programs it is given;
  what it runs is started with no more than it needs (no `dev` lines,
  no ports of `agentd`'s).
- Host tests drive the loop with a stand-in model that asks for tools,
  so that the loop, compaction and every tool are tested without the
  network.

## Steps

To be written. Open: whether the agent only answers or also acts on its
own (a time of its own to wake, through `alarm_at`), and if so its
budget and how what it did while no one watched is shown; who may talk
to it (the console, the desktop of 0049, the network); what a tool may
ask without the person's yes, and how that yes is asked.

## Spec changes

- agent.md (new): `agentd`, its protocol and its tools.
- programs.md: `agentd` and `agent`, and their libraries.
- demo.md: `agentd`'s pid, if the demo starts it.

## Log

- 2026-10-29: written, with 0041, 0042 and 0044 to 0049.
