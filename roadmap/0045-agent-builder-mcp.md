# 0045: The agent builds programs for itself, through an MCP server on the host

Track: Agent · Status: idea · Needs: 0043 · Spec: agent.md, programs.md, testing.md

## Why

L0's compiler and toolchain run on the host, not on L0S, and will for a
long time. For the agent to write programs for itself it asks the host
to build them: an MCP server there, beside `tools/l0s-mcp` but apart
from it, since its client is the board and it is trusted less, and an
MCP client in L0 on the board (JSON-RPC over 0041's HTTP, MCP's
streamable HTTP transport). The agent then writes a program's files,
has them checked, tested and built, copies the image to its home and
starts it with `spawn_path`, without a reboot.

The agent's tests are code it wrote, so they never run on the host
natively: `l0 test` there runs as the host's user. They run with
`--target virt`, on QEMU, which is the sandbox.

## Done when

- The server offers `check`, `test` (on QEMU only) and `build` (with
  `--target proc`, for the board's CPU), each taking a program's files
  and answering with the diagnostics, the tests' TAP, or the image.
- It listens on the local network only, refuses a request without the
  board's token, and keeps each request's files in a directory of its
  own that it deletes.
- `agentd` reaches it as tools: the agent writes, checks, tests, builds
  and starts a program of its own, on QEMU and on a Pi 5, which a
  screen-free e2e case shows with a stand-in model.

## Steps

To be written. Open: where the programs it builds live in its home,
and how it is told which it already has; whether its programs are
started by `agentd` alone or put among `/`'s for the shell too (0017).

## Spec changes

- agent.md: the builder's tools, and the MCP client.
- programs.md: the MCP client's library.
- testing.md: the server's tests.

## Log

- 2026-10-29: written, with 0041 to 0044 and 0046 to 0049.
