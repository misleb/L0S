# 0046: The agent learns how it and L0S work

Track: Agent · Status: idea · Needs: 0045 · Spec: agent.md

## Why

To write L0 at all the agent needs what any agent writing L0 here
needs, since there is no L0 in a model's training: L0's spec and its
standard library's documentation, and the `l0-code` skill. To change
itself well it needs L0S's own: the spec, `make doc`, the knowledge
graph's `explain` and `affected`, and the source. All of it is on the
host, so 0045's server gives it, read-only.

## Done when

- The server answers `l0_spec`, `l0_doc`, `doc` (as `make -s doc Q=`),
  `spec` (a page of `spec/`), `explain` and `affected` (the graph's),
  and `source` (a file of the tree, read-only), and each is one of the
  agent's tools.
- The agent has the `l0-code` skill among its own, copied from the
  host's, and knows when it changed there.
- With a stand-in model, a test asks each tool and checks what comes
  back.

## Steps

To be written. Open: whether the agent keeps copies on its card so it
can read them without the host, and how they are kept current.

## Spec changes

- agent.md: the tools that tell it about L0 and L0S.

## Log

- 2026-10-29: written, with 0041 to 0045 and 0047 to 0049.
