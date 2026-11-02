# 0045: The agent has apps built for itself, by a Claude Code session on the host

Track: Agent · Status: done · Needs: 0043 · Spec: agent.md, network.md, programs.md, testing.md

## Why

L0's compiler runs on the host, not on L0S, and will for a long time.
For the agent on the board to have a desktop app of its own, one that
is not part of L0S as installed, it asks the host to make it: the API
proxy (0042), which it already reaches with its token, hands the
request to a Claude Code session there, on a stronger model than the
chat's, which writes the app against L0S's libraries, builds it for the
board and gives the program back. These apps are ad hoc: they need
`l0 check` and a build, not L0S's tests, spec or roadmap.

## Done when

- The proxy takes `POST /build` (an app's name and a prompt, with the
  board's token) and runs a Claude Code session for that app in a
  folder of its own on the host, outside the L0S tree: the first prompt
  starts it, each later one resumes it, so "make the button blue"
  changes the same app. Its progress comes back as server-sent events,
  then the result, the session's summary or why it failed; `GET
  /build/NAME/image` gives the program. One build runs at a time.
- The session runs `claude -p` with the model `claude-opus-5-5` at
  effort medium unless the proxy is told otherwise, logged in as the
  host's Claude Code is (claude.ai), never with the proxy's
  `ANTHROPIC_API_KEY`, which it is started without: a session whose
  first event says it has an API key is ended and the build refused.
- It is confined by Claude Code's `--restricted` mode and an
  allowlist (`dontAsk`): files read in its folder and the L0S tree,
  written in its folder only; `l0 check`, `fmt`, `doc` and `spec`, `make
  -s doc`, `graphify explain` and `affected`, read-only inspection (`ls`,
  `cat`, `head`, `tail`, `wc`, `grep`, `file`), and `l0s-app-build`,
  which builds the app with `l0 build --target proc` and the libraries
  a window app links, and any more it names. Its source stays on the
  host.
- `agentd` has a tool, `build_app` (`name`, `prompt`): it asks the
  proxy, tells the Tools pane the session's progress as it comes,
  writes the program to `apps/NAME` in its home, and answers the
  summary and how to start it (`run apps/NAME`).
- Tested: the proxy's routes, its refusals and the session's command
  and environment against a stand-in `claude`; `agentd`'s tool against
  the stand-in API; an e2e case of a build through the stand-ins; and
  once by hand, a real session building an app the board then runs on
  QEMU.

## Steps

- [x] The builder on the host: `tools/api-proxy/builder.py`, a session
  per app (its folder, its session ID kept there), `claude`'s command
  line, environment and allowlist, its stream-json read into progress
  and a result; `tools/l0s-app-build` and the Makefile's list of a
  window app's libraries; tested with a stand-in `claude`.
- [x] The proxy's routes: `POST /build` as server-sent events, `GET
  /build/NAME/image`, a name checked (letters, digits, `-`), one build
  at a time (`409`), `--builder-dir`, `--builder-model`,
  `--builder-effort`; tested in `test_proxy.py`.
- [x] `agentd`'s `build_app`: the request, the events read as they
  come and told as progress, the image fetched and written to
  `apps/NAME`; host tests, and an e2e case through the stand-ins.
- [x] By hand: a real session builds an app from the board's agent on
  QEMU, which `run` starts and the screen shows.
- [x] Apps that need more than the toolkit has: the session writes
  what it can in the app itself, and otherwise changes the library in
  place in its app's git worktree of L0S, on the branch `app/NAME`,
  whose libraries `l0s-app-build` links; the builder commits the change
  there after the build, for the person to merge by hand or not.

Left open: whether an app built so is ever shown in the launcher or
installed (the user chose the home only, for now); how many apps and
sessions the host keeps; and how a change an app made to its copy of a
library on its branch reaches L0S's, which is a merge by hand.

## Spec changes

- In: agent.md (`build_app`, the progress notice), network.md (the
  proxy's `/build`, the session, `l0s-app-build`), programs.md
  (`agentd`'s row), testing.md (the builder's tests, `agent_build`).
- network.md: the worktrees (in).

## Log

- 2026-10-29: written, with 0041 to 0044 and 0046 to 0049, as an MCP
  server on the host offering `check`, `test` and `build`.
- 2026-10-31: rewritten as the user asked: the API proxy drives a
  Claude Code session that writes and builds the app from the agent's
  prompt, on a stronger model, and sends back the program, without
  L0S's testing requirements. The user chose: apps in the agent's home
  only, a session kept per app, the source kept on the host, Claude
  Code's allowlist (with read-only tools to look at how UI programs are
  made) rather than a container, Opus 5.5 at effort medium, and the
  host's Claude Code login, not the API key.
- 2026-10-31: steps 1 to 4 done. The builder, the proxy's routes and
  `l0s-app-build`, with 7 tests against `fake_claude.py`; `agentd`'s
  `build_app` (`build.l0`), its progress a notice of its own (`agent
  progress`), shown at the console and in the Agent app's Tools, and
  the program marked one once written; the e2e case `agent_build`. By
  hand on QEMU, through the real proxy: the board's agent (Sonnet 5.5)
  called `build_app` for a counter; Opus 5.5 at effort medium, on the
  host's claude.ai login, read the skills and Widgets, wrote and built
  it in about a minute and a half; the agent started it (`sh: run
  apps/counter &`), and its window showed on the desktop. The user
  asked how an app that needs more than the toolkit is handled: step 5.
- 2026-10-31: step 5 done, as the user chose: first an app's own
  changed copy of a library's file, linked in its place; then, as the
  user chose instead, the library changed in place in a git worktree of
  L0S on the app's own branch, committed there, to be merged by hand or
  not. No request is filed.
  The user decided against having agentd's conversation go through a
  Claude Code session in place of the API. Done.
