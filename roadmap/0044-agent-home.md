# 0044: The agent's home: its personality, its history, and a backup

Track: Agent · Status: idea · Needs: 0043 · Spec: agent.md, storage.md

## Why

The model is stateless: what makes this agent itself is its files.
Kept in Claude Code's own conventions (rules in a `CLAUDE.md`, a
`memory/` of one fact a file with its frontmatter and a `MEMORY.md`
index, `skills/NAME/SKILL.md` each with a description read up front and
a body read when used), the personality can be read and changed on the
host from its card, backed up to git, and loaded into Claude Code to
compare how it behaves there.

An agent that rewrites its own memory and rules drifts, so every change
it makes has to be seen and undone.

## Done when

- The home's layout is fixed on the card, and `agentd` reads it in at
  the start of every conversation: rules and the memory index whole,
  skills by their descriptions, the rest on demand.
- A part of it the agent cannot change (its constitution, and the rules
  about its rules), which `agentd` refuses to write.
- Every write of the agent's to its home is kept in a history: what
  changed, when, and in which conversation, and any change can be
  undone from a shell.
- A backup of the home is copied to the host and back, and the host's
  copy opens in Claude Code as it is.

## Steps

To be written. Open: the history's form, a log of whole files or of
differences, or a small git; the backup's way off the board (through
0045's server, or a file the person copies).

## Spec changes

- agent.md: the home, its layout, what is fixed and its history.
- storage.md: where on the card the home is, if a volume of its own.

## Log

- 2026-10-29: written, with 0041 to 0043 and 0045 to 0049.
