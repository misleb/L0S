# 0043: `agentd`, an agent's loop and its tools on L0S

Track: Agent · Status: blocked · Needs: 0042, 0051 · Spec: agent.md (new), programs.md, demo.md, testing.md

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
- the tools, each a request to a server L0S already has: read, write,
  list and make directories in the agent's home, run a program and
  read what it wrote, a line at `sh`.

The model is Anthropic's, through 0042's proxy and its `model.l0`,
which keeps the provider behind one interface. Running a model on the
board itself is not part of this.

What it is, as decided with the user:

- **It only answers.** It acts when someone talks to it and at no other
  time; waking on its own, and what it did while no one watched, are
  [0052](0052-agent-on-its-own.md)'s.
- **The console talks to it**, `run agent` at a shell. The desktop is
  0049's; the network later.
- **Nothing asks the person's yes.** Every tool runs freely, and safety
  is confinement: the file tools reach only the agent's home,
  `/home/agent`, and every program it runs is started confined to that
  home ([0051](0051-confined-process.md)), from `/bin` or
  `/Applications` (none of `/sbin`'s servers), with no `dev` line, no
  port of `agentd`'s and no server's, its current directory the home.
  Without 0051 a program it ran could open any file and ask any
  server, which is why it is a Need.

## Done when

- `agentd` serves a protocol of its own, `agent`: a conversation's
  turns in, the answer streamed back as notices, each tool told as it
  runs and as it ends.
- `run agent` talks to it from a shell, on QEMU and on a Pi 5, through
  the proxy to the real API.
- Its tools are `read_file`, `write_file`, `list_dir`, `make_dir`,
  `run` and `sh`. The file tools reach only its home; `run` and `sh`
  start programs confined to it.
- The system prompt and tools are cached (`cache_control`), and a
  conversation past a configured size is compacted: the model
  summarizes the older turns, and the summary and the recent turns are
  kept.
- Host tests drive the loop with a stand-in model that asks for tools,
  so that the loop, compaction and every tool are tested without the
  network; an e2e case runs `run agent` against the stand-in through
  the proxy, its tools writing and running in a home on the case's
  disk. `make check`, `make test` and `make e2e` pass.

## Steps

- [ ] **`sh -c`.** `sh -c LINE` runs one line of the shell's commands,
  with no `/etc/motd` and no prompt, and exits with its status (`run`'s
  child's, or 1 for a command that failed); `sh` alone and `sh TTY` are
  as now. For the `sh` tool, and any program. sh_test's parse of `-c`;
  the `shell` e2e case runs `run sh -c "ls /etc"`. programs.md's `sh`
  row.
- [ ] **The conversation.** `user/sbin/agentd/conv.l0`, pure: `(data
  Block (BText bytes) (BToolUse bytes bytes Json) (BToolResult bytes
  bytes bool))` (a text; a tool's use, its id, name and input; its
  result, the use's id, the text and whether it failed), `(data Turn
  (Turn bool (list Block)))`, the person's (or the tools' results) or
  the model's, and a `Conv`, the turns, newest first, and the last
  answer's usage. `conv_messages c`, the turns as the API's `messages`
  (`Json`), oldest first, with `cache_control: {"type": "ephemeral"}`
  on the last block of the last turn; `conv_system text`, the system
  prompt as one block with `cache_control`; and the tools' definitions
  with `cache_control` on the last, so the prompt and tools are cached
  and each turn reads the conversation so far from the cache. The
  system prompt is built in: where it is (L0S, on what board), its home,
  its tools, and that it answers at a console; 0044 reads its
  personality from the home in its place. Tests: a conversation of a
  text, a tool use and its result as JSON, compared as text; the
  breakpoints where they should be, three at most with the system's.
- [ ] **The loop.** `user/sbin/agentd/loop.l0`, pure: `(data Loop
  ...)`, the conversation, the answer being built from `ModelEvent`s
  (each block by its index: text appended, a tool's input's
  `partial_json` pieces joined and read as JSON at `MBlockStop`), the
  rounds this turn. `loop_say l text` and `loop_event l e` give `(l,
  acts)`: `(ActAsk request)` (a request to send, `model_request`'s
  bytes), `(ActTell notice)`, `(ActTool id name input)`, `(ActDone
  reason)`. At `MStop tool_use` it asks for each tool the answer used,
  and `loop_result l id text failed` takes each result; once all are in
  they are one turn and it asks again. `end_turn` and `stop_sequence`
  are done; `max_tokens` done saying so; `MError` done with its
  message; past 32 rounds of tools in one turn it stops, saying so. A
  tool use whose input is not JSON is answered as a failed result, not
  run. Tests, with a stand-in model, `loop_standin script tools`: a
  script of answers, each `ModelEvent`s, and a table of tools' results;
  it drives the loop to its end and gives the requests sent and the
  notices. A plain answer; one tool; two tools in one answer, results
  in order; a tool's input in pieces cut mid-string; a round that asks
  again and then ends; the round limit; an error event; a result that
  failed.
- [ ] **The file tools.** `user/sbin/agentd/tools.l0`: the agent's
  home from the configuration (`home PATH`, `/home/agent` if none), and
  `home_path home p`, the absolute path p names from the home (as
  `path_resolve` makes it, a relative path from the home), or none if
  it is not the home or under it, is over 1024 bytes or holds a NUL.
  `read_file {path}` (its text, at most 64 KB, saying so if cut),
  `write_file {path, content}` (the file written anew; its directory
  must be there), `list_dir {path}` (a line `NAME SIZE` each, a
  directory's with a `/`, from `fs_list`), `make_dir {path}`
  (`fs_mkdir`). Each answers a text, or a failure the model reads; each
  definition's `input_schema` is JSON Schema. Tests: `home_path` on
  `..` out of the home, an absolute path outside, `/home/agentx`, the
  home itself; read and write in a directory under `build/` on this
  host, as `l0 test` has files; a file over 64 KB cut; the definitions'
  JSON compared as text; under `l0 test` `list_dir` and `make_dir`
  fail and say so, as there is no `fs`.
- [ ] **Running programs.** In tools.l0, `run {program, args}` and `sh
  {command}`: the program found by name in `/bin` or `/Applications`
  only (`program_found`, then refused if its path is not under one of
  them, so no `/sbin/fs` and no path elsewhere); `sh` is `/bin/sh -c
  COMMAND`. It is started with `spawn_path_confined` (0051), confined
  to the home, its terminal a port `agentd` makes for it: `agentd`
  answers that port as a terminal (`tty.l0`'s protocol), its `r` with
  input's end at once, its `p` and `i`, and keeps what it writes, 64 KB
  at most, saying how much more was dropped. The program's exit comes
  by `proc_watch`; one still running after `run_timeout` seconds (the
  configuration's, 60 if none) is killed with `proc_kill`, which 0051
  lets `agentd` do, as it is not confined, and the result says so. The
  result is `exit N`, then what it wrote. A `(data Run ...)` keeps the
  pid, its terminal port, the output and the deadline, pure: `run_heard
  r m` on what came to the terminal port or the watch, tested on
  messages built with `message_new` (a write, two writes, an `r`, the
  exit notice, output past 64 KB). Under `l0 test` spawning fails, and
  the tool says so.
- [ ] **`agentd`, the server.** `user/sbin/agentd/agentd.l0` and
  `main.l0`; `LIBS_agentd` is `MODEL`, `PATHS` and `AGENTLIB`. It reads
  `/etc/agent/config` (0042's, and its own keys: `home`, `compact`,
  `keep`, `run_timeout`) and `/etc/agent/token`; with neither it says
  so in the log and exits 0, as a driver with no device does. It makes
  its home if it is not there (`fs_mkdir`, each missing directory of
  the path), registers `agent`, and waits on its port, the HTTP
  connection's notice port and a running program's terminal and watch
  ports, with `port_receive_set` (0031). The protocol, in
  [proto/agent.l0](../user/lib/proto/agent.l0) (`AGENTLIB`), each a
  request: `open NPORT` → `conv ID`, a conversation whose notices go
  to NPORT; `say ID` and a newline and the text → `ok`, or `error:
  busy` while it answers; `stop ID` → `ok`, the turn ended (the HTTP
  connection reset, a program running killed) with `done stopped`;
  `close ID` → `ok`. The notices, to NPORT: `agent ID text` and a
  newline and a piece of the answer (at most 4000 bytes a notice);
  `agent ID tool NAME` and a newline and its input (cut to 1 KB);
  `agent ID result NAME ok|failed` and a newline and the start of what
  it gave (1 KB); `agent ID compacted BEFORE AFTER` (tokens); `agent ID
  done REASON`; `agent ID error` and a newline and why. One turn runs
  at a time, of any conversation; conversations live as long as
  `agentd`, which 0044 keeps. Each answer's usage is a debug line in
  the log. `agent.l0`'s client: `agent_open`, `agent_say`,
  `agent_stop`, `agent_close`, `agent_event_of` (an `AgentEvent`, read
  in place); host tests of the requests and every notice's round trip.
  agentd_test: its configuration read, the entry point's 1 under
  `l0 test` (no kernel). `demo/etc/system` and `pi5/etc/system` start
  `/sbin/agentd` last; demo.md's pids and table of who talks to whom.
- [ ] **`agent`, at the console.** `user/bin/agent`: `run agent` opens
  a conversation, writes `> ` and reads a line, says it, and writes the
  notices as they come until `done`: text as it is, a tool as `[NAME
  INPUT]` on a line of its own, its result `[ok]` or `[failed: FIRST
  LINE]`, `compacted` as `[compacted]`, an error as `agent: WHY`; then
  the next `> `. Ctrl-C while it answers (the terminal's `i`) sends
  `stop`; the input's end, or a line `/exit`, closes the conversation
  and exits 0. No `agentd` is "the agent is not running (no
  /etc/agent/config?)". The notices' text is a pure function, tested.
  programs.md's `agent` and `agentd` rows; agent.md, new: `agentd`, its
  protocol, its tools and their confinement, `agent`.
- [ ] **The e2e case.** The stand-in of 0042 runs a script whose
  answers ask for tools, and checks each request: the `tool_result`s
  answer the last answer's `tool_use` ids, in order, and the
  `cache_control` breakpoints are there; a request that fails a check
  is answered 400 with why, which the case would show. The case
  `agent`: a disk; `net` user; `serve` `e2e_serve.py` with
  `tests/e2e/agent/script.json`; `etc/agent/config` with `api
  10.0.2.2:@PORT@` and `home /Volumes/data/agent`, the token, and an
  inittab starting `agentd` after `fs` and `inet`. `typed`: `run
  agent`, one line, to which the script answers with `make_dir notes`,
  `write_file notes/today.txt`, `list_dir notes`, `run hello`, `sh
  "cat notes/today.txt"` and `read_file /etc/motd` (refused: outside
  the home), then a text; then `/exit`, and outside it `cat
  /Volumes/data/agent/notes/today.txt`. `expected` follows. testing.md's
  case.
- [ ] **Compaction.** In conv.l0 and loop.l0: once an answer's usage
  (input, cache written and cache read) passes `compact` tokens (the
  configuration's, 100000 if none), before the next turn is sent the
  loop asks the model, with no tools, to summarize every turn but the
  last `keep` (8 if none), cut only before a turn of the person's own
  text, never between a tool's use and its result; the summary becomes
  the first turn, the person's, "The conversation so far, summarized:
  ...", followed by the kept turns, and `compacted` is told. Too few
  turns to cut is no compaction. Tests with the stand-in: a
  conversation past the size compacts once, its next request holding
  the summary and the kept turns; the cut never parts a tool use and
  its result; a summary request that fails leaves the conversation as
  it was and says so. agent.md: compaction.
- [ ] **On QEMU and a Pi 5, with the real API** (the user): `make
  proxy-run`, then `run agent` on `make demo NET=user` with `make
  agent-etc API=10.0.2.2:8765` and a system volume (`make
  demo-system`), so the home is on `/`; and on a Pi 5 through the
  proxy on the host's LAN address, as 0042's last step. A conversation
  that makes a file in its home, runs a program and a line at `sh`,
  and is refused outside the home. Logged when done, with its usage and
  cost from the proxy's `--day`.

## Spec changes

- agent.md (new): `agentd`, its configuration, its protocol and
  notices, its tools and their confinement (0051), prompt caching,
  compaction, and `agent`; Limits: one turn at a time, conversations
  kept only while `agentd` runs (until 0044), a program's output cut
  at 64 KB, the round limit, no person's yes for anything.
- programs.md: `agentd`, `agent`, `sh -c`, and `proto/agent.l0`.
- demo.md: `agentd`'s pid, and who it talks to (`inet`, `fs`, the
  programs it starts).
- testing.md: the `agent` case, and the stand-in's checks.

## Log

- 2026-10-29: written, with 0041, 0042 and 0044 to 0049.
- 2026-10-29: steps written, the open questions settled with the user:
  it only answers (acting on its own is 0052, a new idea); the console
  talks to it; nothing asks the person's yes, and confinement is the
  safety: file tools only in `/home/agent`, programs from `/bin` and
  `/Applications` started confined to it. L0S could not confine a
  program, so that is 0051, a Need. The home is a path in
  `/etc/agent/config`, `/home/agent` by default, on `/` once it is a
  system volume, and made by `agentd` at its first start; a board
  booted from the initramfs alone, whose `/` cannot be written, names a
  volume's (the e2e case's is `/Volumes/data/agent`). Compaction is by
  the model's summary of the older turns. The goal stays active until
  its last step has run on a Pi 5 as well as on QEMU.
