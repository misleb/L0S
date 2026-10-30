# 0043: `agentd`, an agent's loop and its tools on L0S

Track: Agent · Status: active · Needs: 0042 · Spec: agent.md (new), programs.md, demo.md, testing.md

## Why

The aim of this track is an L0S installation, a Pi 5's first, as the
home of an agent: its memories, skills and rules kept on the board,
the model reached over the network, everything else done there. Claude's
Agent SDK is not ported: it is Claude Code's harness, TypeScript on
Node. What makes an agent is small, and is written here in L0:

- the loop: send the conversation and the tools, run each tool the
  answer asks for, send the results back, until the answer is done;
- the context: its rules read in at the start (0044 grows them into a
  personality), prompt caching so that they are not paid for on every
  turn, and the conversation compacted when it grows long;
- the tools, each a request to a server L0S already has: read, write,
  list and make directories, run a program and read what it wrote, a
  line at `sh`.

The model is Anthropic's, through 0042's proxy and its `model.l0`,
which keeps the provider behind one interface. Running a model on the
board itself is not part of this.

What it is, as decided with the user:

- **It only answers.** It acts when someone talks to it and at no other
  time; waking on its own, and what it did while no one watched, are
  [0051](0051-agent-on-its-own.md)'s.
- **The console talks to it**, `run agent` at a shell. The desktop is
  0049's; the network later.
- **Its limits are soft.** Nothing asks the person's yes, and nothing
  is enforced: the file tools take any path, and `run` and `sh` start
  programs as a shell would. The board is dedicated to the agent, and
  the worst it can do there is make the installed system unbootable,
  which a reinstall fixes. What it should and should not do is said in
  its rules, which the system prompt carries: keep its files in its
  home, leave the system's alone, and the rest the person writes there.
- **Its home is on a data volume, `/Volumes/data/agent`**, not on `/`.
  The home keeps the agent's files apart from the system's, so that
  they outlive a reinstall: `install VOLUME` writes only onto the
  system volume it is given (and copies nothing of `/Volumes`), and a
  reinstall formats that volume, so anything on `/` would go, while
  another volume is left as it was. A Pi 5's card has a `data`
  partition beside `bootfs` and `System` for it; `make sysdisk`'s disk
  has one already.

## Done when

- `agentd` serves a protocol of its own, `agent`: a conversation's
  turns in, the answer streamed back as notices, each tool told as it
  runs and as it ends.
- `run agent` talks to it from a shell, on QEMU and on a Pi 5, through
  the proxy to the real API.
- Its tools are `read_file`, `write_file`, `list_dir`, `make_dir`,
  `run` and `sh`. A relative path is from its home; a program's output
  is kept up to 64 KB, and one that runs too long is ended.
- Its rules are its home's `CLAUDE.md`, made from a default at its
  first start and read into the system prompt at the start of every
  conversation.
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

- [x] **`sh -c`.** `sh -c LINE` runs one line of the shell's commands,
  with no `/etc/motd` and no prompt, and exits with its status (`run`'s
  child's, or 1 for a command that failed); `sh` alone and `sh TTY` are
  as now. For the `sh` tool, and any program. sh_test's parse of `-c`;
  the `shell` e2e case runs `run sh -c "ls /etc"`. programs.md's `sh`
  row.
- [x] **The conversation.** `user/sbin/agentd/conv.l0`, pure: `(data
  Block (BText bytes) (BToolUse bytes bytes Json) (BToolResult bytes
  bytes bool))` (a text; a tool's use, its id, name and input; its
  result, the use's id, the text and whether it failed), `(data Turn
  (Turn bool (list Block)))`, the person's (or the tools' results) or
  the model's, and a `Conv`, the turns, newest first, and the last
  answer's usage. `conv_messages c`, the turns as the API's `messages`
  (`Json`), oldest first, with `cache_control: {"type": "ephemeral"}`
  on the last block of the last turn; `conv_system base rules`, the
  system prompt as one block with `cache_control`: a built-in part
  (where it is, L0S on what board; its home; its tools; that it
  answers at a console) and its rules after; and the tools'
  definitions with `cache_control` on the last, so the prompt and
  tools are cached and each turn reads the conversation so far from
  the cache. Tests: a conversation of a text, a tool use and its
  result as JSON, compared as text; the breakpoints where they should
  be, three at most with the system's.
- [x] **The loop.** `user/sbin/agentd/loop.l0`, pure: `(data Loop
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
- [x] **The file tools.** `user/sbin/agentd/tools.l0`: the home from
  the configuration (`home PATH`, `/Volumes/data/agent` if none), and
  `tool_path home p`, the absolute path p names, a relative one from
  the home (`path_resolve`); any path is taken. `read_file {path}` (its
  text, at most 64 KB, saying so if cut), `write_file {path, content}`
  (the file written anew; its directory must be there), `list_dir
  {path}` (a line `NAME SIZE` each, a directory's with a `/`, from
  `fs_list`), `make_dir {path}` (`fs_mkdir`). Each answers a text, or a
  failure the model reads; each definition's `input_schema` is JSON
  Schema, its description saying a relative path is from the home.
  Tests: `tool_path` on a relative path, `..`, an absolute path; read
  and write in a directory under `build/` on this host, as `l0 test`
  has files; a file over 64 KB cut; the definitions' JSON compared as
  text; under `l0 test` `list_dir` and `make_dir` fail and say so, as
  there is no `fs`.
- [x] **Running programs.** In tools.l0, `run {program, args}` and `sh
  {command}`: the program found as the shell's `run` finds it
  (`program_found`), `sh` being `/bin/sh -c COMMAND`, and started with
  `spawn_path`, its current directory the home (`agentd` is in it), its
  terminal a port `agentd` makes for it: `agentd` sets that port as
  its terminal (`tty_set`) for the spawn and sets its own back after,
  and answers it as a terminal (`tty.l0`'s protocol), its `r` with
  input's end at once, its `p` and `i`, and keeps what it writes, 64 KB
  at most, saying how much more was dropped. The program's exit comes
  by `proc_watch`; one still running after `run_timeout` seconds (the
  configuration's, 60 if none) is ended with `proc_kill`, and the
  result says so. The result is `exit N`, then what it wrote. A `(data
  Run ...)` keeps the pid, its terminal port, the output and the
  deadline, pure: `run_heard r m` on what came to the terminal port or
  the watch, tested on messages built with `message_new` (a write, two
  writes, an `r`, the exit notice, output past 64 KB). Under `l0 test`
  spawning fails, and the tool says so.
- [x] **`agentd`, the server.** `user/sbin/agentd/agentd.l0` and
  `main.l0`; `LIBS_agentd` is `MODEL`, `PATHS` and `AGENTLIB`. It reads
  `/etc/agent/config` (0042's, and its own keys: `home`, `compact`,
  `keep`, `run_timeout`) and `/etc/agent/token`; with neither it says
  so in the log and exits 0, as a driver with no device does. It waits
  for the home's volume (`/Volumes/data` by default) as `boot` waits
  for `fs`, and with none after 10 s says so and exits 1. It makes the
  home if it is not there (`fs_mkdir`), and its `CLAUDE.md` from
  `/etc/agent/CLAUDE.md`, the default rules L0S ships
  (`demo/etc/agent/CLAUDE.md`, `pi5/etc/agent/CLAUDE.md`): keep your
  files in your home, leave `/`'s alone, never format or partition a
  disk, say what you ran. It then registers `agent` and waits on its
  port, the HTTP connection's notice port and a running program's
  terminal and watch ports, with `port_receive_set` (0031). Each
  conversation reads `CLAUDE.md` afresh, so a change to it holds from
  the next. The protocol, in [proto/agent.l0](../user/lib/proto/agent.l0)
  (`AGENTLIB`), each a request: `open NPORT` → `conv ID`, a
  conversation whose notices go to NPORT; `say ID` and a newline and
  the text → `ok`, or `error: busy` while it answers; `stop ID` →
  `ok`, the turn ended (the HTTP connection reset, a program running
  ended) with `done stopped`; `close ID` → `ok`. The notices, to
  NPORT: `agent ID text` and a newline and a piece of the answer (at
  most 4000 bytes a notice); `agent ID tool NAME` and a newline and its
  input (cut to 1 KB); `agent ID result NAME ok|failed` and a newline
  and the start of what it gave (1 KB); `agent ID compacted BEFORE
  AFTER` (tokens); `agent ID done REASON`; `agent ID error` and a
  newline and why. One turn runs at a time, of any conversation;
  conversations live as long as `agentd`, which 0044 keeps. Each
  answer's usage is a debug line in the log. `agent.l0`'s client:
  `agent_open`, `agent_say`, `agent_stop`, `agent_close`,
  `agent_event_of` (an `AgentEvent`, read in place); host tests of the
  requests and every notice's round trip. agentd_test: its
  configuration read, the entry point's 1 under `l0 test` (no kernel).
  `demo/etc/system` and `pi5/etc/system` start `/sbin/agentd` last;
  demo.md's pids and table of who talks to whom.
- [x] **`agent`, at the console.** `user/bin/agent`: `run agent` opens
  a conversation, writes `> ` and reads a line, says it, and writes the
  notices as they come until `done`: text as it is, a tool as `[NAME
  INPUT]` on a line of its own, its result `[ok]` or `[failed: FIRST
  LINE]`, `compacted` as `[compacted]`, an error as `agent: WHY`; then
  the next `> `. Ctrl-C while it answers (the terminal's `i`) sends
  `stop`; the input's end, or a line `/exit`, closes the conversation
  and exits 0. No `agentd` is "the agent is not running (no
  /etc/agent/config?)". The notices' text is a pure function, tested.
  programs.md's `agent` and `agentd` rows; agent.md, new: `agentd`, its
  home and rules, its protocol, its tools, `agent`.
- [x] **The e2e case.** The stand-in of 0042 runs a script whose
  answers ask for tools, and checks each request: the `tool_result`s
  answer the last answer's `tool_use` ids, in order, the
  `cache_control` breakpoints are there, and the system prompt holds
  the home's `CLAUDE.md`; a request that fails a check is answered 400
  with why, which the case would show. The case `agent`: a disk, whose
  `data` volume holds the home; `net` user; `serve` `e2e_serve.py`
  with `tests/e2e/agent/script.json`; `etc/agent/config` with `api
  10.0.2.2:@PORT@`, the token, the default `CLAUDE.md`, and an inittab
  starting `agentd` after `fs` and `inet`. `typed`: `run agent`, one
  line, to which the script answers with `make_dir notes`, `write_file
  notes/today.txt`, `list_dir notes`, `run hello`, `sh "cat
  notes/today.txt"` and `read_file /etc/motd`, then a text; then
  `/exit`, and outside it `cat /Volumes/data/agent/notes/today.txt` and
  `ls /Volumes/data/agent`, which shows `CLAUDE.md` made. `expected`
  follows. testing.md's case.
- [x] **Compaction.** In conv.l0 and loop.l0: once an answer's usage
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
  proxy-run`, then `run agent` on `make demo-system NET=user` with
  `make agent-etc API=10.0.2.2:8765`, the home on the disk's `data`;
  and on a Pi 5 through the proxy on the host's LAN address, as 0042's
  last step, its card given a `data` partition (`partition`, `mkfs
  UUID data`, or Disks) beside `bootfs` and `System`. A conversation
  that makes a file in its home, runs a program and a line at `sh`;
  then `System` reinstalled from a netboot's initramfs (`format
  System`, `install System`, `/etc/agent` with it) and the home found
  as it was. Logged when done, with its usage and cost
  from the proxy's `--day`.

## Spec changes

- agent.md (new): `agentd`, its configuration, its home on a data
  volume and why, its rules (`CLAUDE.md`), its protocol and notices,
  its tools, prompt caching, compaction, and `agent`; Limits: its
  limits are its rules only, nothing enforced; one turn at a time;
  conversations kept only while `agentd` runs (until 0044); a
  program's output cut at 64 KB; the round limit.
- programs.md: `agentd`, `agent`, `sh -c`, and `proto/agent.l0`.
- demo.md: `agentd`'s pid, and who it talks to (`inet`, `fs`, the
  programs it starts).
- testing.md: the `agent` case, and the stand-in's checks.

## Log

- 2026-10-29: written, with 0041, 0042 and 0044 to 0049.
- 2026-10-29: steps written, the open questions settled with the user:
  it only answers (acting on its own is 0051, a new idea); the console
  talks to it; nothing asks the person's yes. Compaction is by the
  model's summary of the older turns. The goal stays active until its
  last step has run on a Pi 5 as well as on QEMU.
- 2026-10-29: no confinement, the user's call: the limits on the agent
  are soft, its rules in the system prompt, since the board is
  dedicated to it and the worst it can do is make the installed system
  unbootable, which a reinstall fixes. A kernel goal that would have
  confined its programs to the home was written and dropped the same
  day. The home is `/Volumes/data/agent`, on a data volume, so that the
  agent's files outlive a reinstall of `System`, which `install`
  writes and a reinstall formats; its rules are the home's
  `CLAUDE.md`, as 0044's layout has them, made from L0S's default.
- 2026-10-29: active, though 0042's runs against the real API (its
  steps 4 and 5) are still the user's: nothing here needs them until
  step 10. Step 1 done: `sh -c LINE` joins the words after `-c` with
  spaces and takes off one pair of double quotes around them, since
  the shell's own `run` splits `run sh -c "ls /etc"` into words, quotes
  and all; a program spawning `sh` passes the line as one argument.
  The status is `run`'s child's, 1 for a line the shell complains of
  (`sh: ...`), else 0.
- 2026-10-29: step 2 done. The Makefile makes a program of any
  directory under `user/sbin`, so `agentd` is one from this step, with
  an entry point that says in the log it serves nothing yet and exits
  1, and `/sbin/agentd` in the listings of the `shell`, `fs` and
  `install` cases and the counts of `install`, `install_boot` and
  `rootboot_tmpfs`; agent.md is
  begun, and programs.md has its row. `LIBS_agentd` is `MODELLIB` (the
  plan's `MODEL`) and `PATHS`; step 6 adds `AGENTLIB`. Beyond the
  plan: a `Usage` (input, output, cache written, cache read) kept by
  `conv_spent`, each count an `MUsage` says replacing the one before,
  and `usage_prompt`, for compaction; a turn on the same side as the
  newest joins it, and empty texts are left out, as the API refuses
  both. The screen test `partitions` typed `partition` at the first
  prompt, which can come before `fs` has the disk; with the larger
  initramfs it did every time, so it now waits for the volumes'
  mounting first.
- 2026-10-29: step 3 done. The notices the loop tells are a `Tell`:
  `TellText`, `TellTool NAME INPUT` (before each `ActTool`),
  `TellResult NAME FAILED TEXT` (as each result is taken), and
  `TellError` (before `ActDone error` and `ActDone rounds`); step 6
  turns them into the protocol's notices. The round limit counts
  rounds of tools whose results are in: after the 32nd the turn stops
  with the results kept, so the conversation stays whole. An answer
  stopped for `max_tokens` (or any reason but `tool_use`) keeps only
  its texts, as a tool use without its result would break the next
  request. Beyond the plan: `loop_cancel`, for step 6's `stop`, which
  answers each tool still awaited as failed, `stopped`; and the
  stand-in's run ends `script_ended` if the loop asks more often than
  the script answers. The stand-in's table of results is by the
  use's id.
- 2026-10-29: step 4 done. A tool answers a `ToolAnswer` (text,
  failed), the type the stand-in's table already had. `list_dir` on a
  path of the initramfs (while `/` is it) lists its entries, without
  sizes, as `ls` does, and `make_dir` there fails, as the initramfs
  cannot change. Text sent to the model must be UTF-8, JSON's strings
  being so: a byte that is not part of UTF-8 becomes `?`
  (`tool_text`), and a cut at 64 KB moves back to where a character
  starts. `tool_conf text key` reads agentd's own configuration keys,
  which `model_conf_of` passes over. The host test writes and reads
  `build/agentd_tools_test.txt` by its relative path, as the host's
  files are not under the paths `tool_path` makes.
- 2026-10-29: step 5 done. One port is the program's terminal and is
  told of its exit and of its deadline (`alarm_at`), as the three are
  told apart by their payloads. `tool_run` runs the program to its end
  itself (`run_wait`, a loop on that port alone), so while a program
  runs `agentd` hears nothing else: step 6, whose `stop` must end a
  running program, either waits on that port among its others
  (`port_receive_set`, feeding `run_heard`, as the plan has it) or
  says it hears `stop` only between tools. A run's answer fails
  unless the program exited 0; `tool_run` takes the terminal to give
  back to `agentd` after the spawn (`back`, 0 the kernel's). Not run
  on the board yet: that is step 8's e2e case.
- 2026-10-29: step 6 done. `agentd` waits on its port, the HTTP
  notices' port and one terminal port for every program its tools run
  (one runs at a time), set once with `port_set`; `tool_run` and
  `run_wait` gave way to `tool_run_start`, which starts the program
  on that port, and `run_took`, which `agentd` feeds each message of it,
  so a `stop` ends a program mid-run and a stream keeps flowing. The
  terminal set back after a spawn is the one `tty_get` gives at its
  start (step 5 thought there was no call to read it). A missing
  config or token is the quiet exit 0; a wrong config is exit 1. A
  request the loop asks while the last answer has not ended waits for
  its end, so a connection kept alive never carries two at once; an
  answer silent for 120 s fails the turn (an alarm on the notices'
  port). A notice to a full queue is retried each millisecond for 2 s.
  The system prompt names the board by its CPU, as nothing tells QEMU's
  board from a Pi 5. Not on the board yet: steps 7 and 8.
- 2026-10-29: step 7 done. A terminal tells one port of Ctrl-C, the
  last to ask (`i`), so `agent` asks in the shell's place, and the
  shell now asks again at each prompt, taking Ctrl-C back from any
  program that took it. `agent`'s notices, its terminal's lines and
  Ctrl-C come to one port, told apart by the sender (`agentd`'s pid,
  from `open`'s answer), and its requests' answers to another, so an
  answer is never mistaken for a notice. It waits 15 s for `agent` to
  register, as `agentd` may still be waiting for its volume. `/bin/agent`
  joins the listings of the `shell`, `fs` and `install` cases and the
  counts of `install`, `install_boot` and `rootboot_tmpfs`. On the
  board from step 8's case.
- 2026-10-29: step 8 done. The stand-in takes an answer that uses
  tools written short (`{"tools": [...], "text": ...}`, `tool_events`,
  each input sent in two pieces) and, given the case's `checks.json`,
  checks each request (`checked`), answering 400 with why; beyond the
  plan it also checks each tool's result holds what it should, so the
  case shows `run` and `sh` really ran. The script answers in three
  rounds of two tools, then a text: four requests. Found on the board:
  the loop moves to its next round as soon as the last result is in,
  while the response whose stop it read may still be ending, so
  `agentd` now marks a response stopped once its stop comes, and its
  end, after, ends nothing early; and a turn done before its response
  ended resets the connection. `hello` read its line from the console
  driver whatever its terminal, so under `agentd` it took the
  console's next line (the case's `/exit`); it now reads its terminal
  when it has one, and its inittab's console otherwise.
- 2026-10-29: step 9 done. The summary request has no tools and one
  message, the ask and the older turns as a transcript (`[tool NAME
  INPUT]`, results cut to 2000 bytes), not the turns themselves, since
  a request holding tool blocks wants the tools it leaves out. The
  summary turn and the first kept turn, both the person's, join, as
  `conv_add` joins two of a side. `compacted`'s AFTER is an estimate,
  BEFORE in proportion to the prompt's bytes, as the real count is
  only known from the next answer. A `stop` while the summary comes
  drops it and the text waiting for it. `loop_new` keeps its
  signature; `loop_compacting` sets the size and the turns kept, which
  `agentd` gives each conversation from its configuration. Host tests
  with the stand-in: a compaction, its request with no tools and the
  transcript, the next request holding the summary and the kept turns;
  the cut moved back from a tool's result, so the use and its result
  stay together; under the size and with too few turns, none; a summary
  that fails, the conversation kept whole and the failure told. Not in
  the e2e case, whose conversation is short.

  Step 10 is the user's, with a key; nothing before it needs one. On
  QEMU, the home on the system disk's `data`:

      make proxy                                 # once: the venv and build/proxy/token
      export ANTHROPIC_API_KEY=sk-ant-...        # the host's key; never on the board
      make proxy-run                             # the proxy on 127.0.0.1:8765; leave it running
      # in another terminal:
      make agent-etc API=10.0.2.2:8765           # MODEL=NAME for another than claude-sonnet-5-5
      make demo-system NET=user                  # a fresh build/system.img: System, and data
      # at the serial shell (dmesg shows agentd's lines; ps shows it waiting on 3 ports):
      #   run agent
      #   > make a directory notes in your home, write today.txt there saying what board you are on, run hello, and at sh, cat notes/today.txt
      #   (each tool shows as [NAME INPUT] and [ok]; Ctrl-C stops a turn)
      #   > /exit
      #   cat /Volumes/data/agent/notes/today.txt
      #   exit
      # a reinstall that keeps the home: the initramfs, the same disk
      make demo NET=user DISK=build/system.img
      #   format System
      #   run install System                     # /etc/agent goes with /etc
      #   ls /Volumes/data/agent                 # CLAUDE.md and notes/, as they were
      #   exit
      make demo NET=user DISK=build/system.img ROOT_UUID=$(cat build/system.uuid)
      #   run agent
      #   > what does notes/today.txt in your home say?
      build/proxy/venv/bin/python -I tools/api-proxy/proxy.py --day   # what today cost, UTC
      rm -rf build/agent-etc                     # afterwards, to leave /etc/agent out again

  On a Pi 5, the proxy on the host's LAN address (192.168.1.10 here;
  `ip -4 addr` says it) and the card in the slot, with `bootfs` and
  `System` as 0022 left it:

      make proxy-run PROXY_LISTEN=192.168.1.10:8765
      make agent-etc API=192.168.1.10:8765
      make pi5-netboot && tools/pi5-boot --console
      # at the serial shell, once, if the card has no data partition:
      #   partition disk1 SECTORS              # room after System; it says the UUID
      #   mkfs UUID data
      #   reboot                               # agentd gave up waiting for /Volumes/data
      #   run agent                            # the same conversation as on QEMU, then /exit
      # the reinstall, from the netboot's initramfs:
      #   format System
      #   run install System
      #   run install --boot bootfs --root System
      #   ls /Volumes/data/agent               # as it was
      # then boot from the card (no netboot), and:
      #   run agent
      #   > what does notes/today.txt in your home say?
      build/proxy/venv/bin/python -I tools/api-proxy/proxy.py --day

  Log what `agent` wrote, the usage lines from
  `build/proxy/usage.jsonl` (the second request of a turn should read
  the cache: `cache_read_input_tokens` above 0) and `--day`'s totals.
