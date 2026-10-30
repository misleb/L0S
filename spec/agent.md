# The agent

`agentd` (`user/sbin/agentd`) is the agent's program: a conversation
with a model, reached through the host's proxy and
[proto/model.l0](../user/lib/proto/model.l0) ([network.md](network.md)),
and tools that act on the board. It only answers: it acts when someone
talks to it, through its protocol, `agent`, which `run agent` speaks at
a console, and at no other time.
`/etc/system` starts it last, in the demo and on the Pi 5.

## agentd

At its start `agentd`:

1. reads `/etc/agent/config` (`model.l0`'s keys, `api`, `model` and
   `max_tokens`, and its own: `home PATH`, `compact N`, `keep N`,
   `run_timeout N`) and `/etc/agent/token`. With neither it says so in
   the log and exits 0, as a driver with no device does: a board not
   set up for the agent (`make agent-etc` makes the two) runs without
   it. A configuration that is wrong is a failure, exit 1.
2. waits for its home's volume: the home is `/Volumes/data/agent`
   unless `home` says otherwise, on a data volume and not on `/`, so
   that the agent's files outlive a reinstall: `install` writes only
   onto the system volume it is given, and a reinstall formats that
   volume, while any other is left as it was. A home under
   `/Volumes/LABEL` waits for that volume to be mounted, as `boot`
   waits for `fs`, at most 10 s, after which it says so and exits 1.
3. makes the home if it is not there (`fs_mkdir`), and makes it its
   current directory.
4. makes the home's `CLAUDE.md`, its **rules**, if it is not there, from
   `/etc/agent/CLAUDE.md`, the default L0S ships
   ([demo/etc/agent/CLAUDE.md](../demo/etc/agent/CLAUDE.md), the Pi
   5's the same): keep its files in its home, leave the system's alone,
   never format, partition or reinstall, say what it ran. The rules
   are the agent's and the person's to change; each conversation reads
   them afresh, so a change holds from the next.
5. registers `agent` and waits on three ports at once
   (`port_receive_set`): its own, for requests; the one its HTTP
   connections' notices come to; and the one that is the terminal of
   the program a tool runs. So a `stop` is heard, and acted on, while
   an answer streams or a program runs.

One turn runs at a time, of any conversation. A turn's acts, as the
loop gives them, are done in order: a request is sent to the proxy on
the connection kept from the last, or a new one, and its streamed
answer read as it comes (`model_events`), each event told to the loop;
a file tool is done at once; `run` and `sh` start their program, and
the turn waits for its exit, its terminal answered meanwhile. An answer
silent for 120 s is given up, and the turn fails; so does a refusal
(`model_refusal`'s words), a connection lost mid-answer, or a stream
that ends before its stop. Each turn's usage is a debug line in the
log (`dmesg`). Conversations live as long as `agentd`.

## Its protocol

[proto/agent.l0](../user/lib/proto/agent.l0) (`AGENTLIB`) has both
sides: the requests' bodies and the notices, made and read, and the
client. Each request is a request (`l0s.l0`'s), its answer to its reply
port:

| Request | Answer |
|---|---|
| `open NPORT` | `conv ID`: a conversation, whose notices go to NPORT, its system prompt made now, with the home's rules as they are |
| `say ID` a newline and the text | `ok`, and the answer streamed to NPORT; `error: busy` while a turn of any conversation runs; `error: no conversation ID` |
| `stop ID` | `ok`: if ID's turn is running, a program it runs is ended, the answer's connection reset, and the turn done, `stopped`, each tool still awaited answered as failed |
| `close ID` | `ok`: the conversation gone, its turn stopped first |

Its notices, to NPORT, each a header line and, for some, a newline and
what it tells, as bytes:

| Notice | Tells |
|---|---|
| `agent ID text` and a newline and a piece | a piece of the answer as it comes, at most 4000 bytes a notice, cut where a character starts |
| `agent ID tool NAME` and a newline and its input | a tool about to run, its input's JSON cut to 1 KB |
| `agent ID result NAME ok\|failed` and a newline and its text | its result, the start of it, 1 KB |
| `agent ID compacted BEFORE AFTER` | the conversation compacted, its prompt's tokens before and after |
| `agent ID done REASON` | the turn over: `end_turn`, `stop_sequence`, `max_tokens`, `error`, `rounds`, `stopped`, or another reason the API gave |
| `agent ID error` and a newline and why | what went wrong, before `done error` or `done rounds` |

A notice that finds NPORT's queue full is sent again a millisecond
later, for at most 2 s, since its reader is only slow; one to a port
gone is dropped. The client (`agent_open`, `agent_say`, `agent_stop`,
`agent_close`) asks for its answers on a port of its own, apart from
the notices, and `agent_event_of` reads a notice as an `AgentEvent`.

## agent, at the console

`agent` (`user/bin/agent`) is the agent's client at a console: `run
agent` at a shell opens a conversation, writes `> `, reads a line, says
it, and writes the notices as they come, until `done`; then the next
`> `.

| Notice | Written as |
|---|---|
| `text` | the piece, as it is |
| `tool` | `[NAME INPUT]` on a line of its own |
| `result` | `[ok]`, or `[failed: FIRST LINE]` of its text |
| `compacted` | `[compacted]` |
| `error` | `agent: WHY` |
| `done` | a newline, if the answer did not end with one |

Its notices, its terminal's lines and Ctrl-C come to one port, told
apart by their sender: `agentd`'s pid, which answered `open`, sends
the notices. It asks its terminal for Ctrl-C (`i`) in the shell's
place, so Ctrl-C while it answers sends `stop`, and while a line is
typed drops it, as at the shell; the shell asks again at its next
prompt. The input's end (Ctrl-D), or a line `/exit`, closes the
conversation and exits 0; a blank line says nothing. With no `agentd`
registered within 15 s it says "the agent is not running (no
/etc/agent/config?)" and fails.

## The conversation

[conv.l0](../user/sbin/agentd/conv.l0), pure. A conversation is its
turns, newest first, and the last answer's usage (input, output, cache
written and cache read, in tokens). A turn is the person's, whose blocks
are texts and tools' results, or the model's, texts and tools' uses:

| Block | Holds | As the Messages API's content block |
|---|---|---|
| `BText` | a text | `{"type":"text","text":...}`; an empty one is left out, as the API refuses it |
| `BToolUse` | a use's id, the tool's name, its input (`Json`) | `{"type":"tool_use","id":...,"name":...,"input":...}` |
| `BToolResult` | the use's id, the text, whether it failed | `{"type":"tool_result","tool_use_id":...,"content":...}`, with `"is_error":true` if it failed |

A turn added on the same side as the newest is joined onto it, since
the API takes the two sides in turn, and a turn of no blocks adds
nothing.

### Prompt caching

Every request marks three breakpoints with `"cache_control":
{"type":"ephemeral"}`, of the API's four:

- the system prompt, one text block (`conv_system`): a built-in part
  (`conv_base`: that it is an agent on L0S and on what board, its home,
  its tools by name, that it answers at a console) and then its rules;
- the last tool's definition (`conv_tools`), so the prompt and the
  tools are one cached prefix;
- the last block of the last turn (`conv_messages`), so that each
  request reads the conversation so far from the cache and writes only
  what is new.

## The loop

[loop.l0](../user/sbin/agentd/loop.l0), pure. A `Loop` holds where the
model is (`ModelConf`), the system prompt and tools as JSON, the
conversation, the answer being built, the tools it used awaiting their
results, and the rounds of tools in this turn. Each step gives the loop
after it and its acts, which the caller does in order:

| Act | Means |
|---|---|
| `ActAsk REQUEST` | send the request, `model_request`'s bytes, of the conversation so far |
| `ActTell NOTICE` | tell the person: `TellText` a piece of the answer as it comes, `TellTool NAME INPUT` a tool about to run, `TellResult NAME FAILED TEXT` its result, `TellError WHY` |
| `ActTool ID NAME INPUT` | run the tool, and give its result to `loop_result` |
| `ActDone REASON` | the turn is over |

- `loop_say` adds the person's text as their turn and asks.
- `loop_event` reads each `ModelEvent` of the answer: a text block's
  pieces are told as they come and joined; a tool use's input arrives
  as pieces of JSON, joined and read at its block's end (no input is
  `{}`); usage replaces the conversation's counts.
- At the answer's stop: `tool_use` keeps the model's turn and runs each
  tool it used, in order; a use whose input is not a JSON object is not
  run but answered at once as failed, saying why. `loop_result` takes
  each result, told as it comes; once all are in they are the person's
  next turn, in the order of the uses, and the model is asked again.
  Any other reason keeps the answer's texts and is done with that
  reason: `end_turn`, `stop_sequence`, `max_tokens` and the rest.
- An error event is told, and the turn is done, `error`; what had come
  of the answer is dropped.
- After 32 rounds of tools in one turn (`loop_rounds_max`) the turn is
  done, `rounds`, saying so, the last results kept.
- `loop_cancel` ends a turn, `stopped`: each tool still awaited is
  answered as failed, so the conversation stays one the API takes.

`loop_standin` drives a loop against a stand-in model, a script of
answers (each a list of `ModelEvent`s) and a table of tools' results by
use id, and gives the requests sent, the notices told and how it ended:
the loop's host tests are written with it.

## The tools

[tools.l0](../user/sbin/agentd/tools.l0). Each tool takes its input as
JSON and answers a `ToolAnswer`, a text, or a failure the model reads.
Its definition (`file_tool_defs`) is a name, a description and its
input's JSON Schema, an object whose properties are all required.

The agent's **home** is the configuration's `home PATH`
(`/etc/agent/config`, a key `model_conf_of` passes over), or
`/Volumes/data/agent`. A relative path is from the home (`tool_path`,
by `path_resolve`, `..` included); any path is taken, as nothing is
enforced here: what the agent should and should not touch is its
rules'.

| Tool | Input | Answers |
|---|---|---|
| `read_file` | `path` | the file's text, at most 64 KB, then a line `[cut: N more bytes]` if it was cut |
| `write_file` | `path`, `content` | the file made anew to hold content (its directory must be there): `wrote N bytes to PATH` |
| `list_dir` | `path` | a line for each entry, `NAME SIZE`, a directory's `NAME/`, from its file server; on the initramfs, while `/` is it, the names alone |
| `make_dir` | `path` | the directory made, on a volume: `made PATH` |

| `run` | `program`, `args` (optional, an array of strings) | the program found as the shell's `run` finds it (`program_found`: `/bin/NAME`, `/sbin/NAME`, an app's, or a path, a relative one from the home), started with `args` in place of its own: `exit N`, then what it wrote |
| `sh` | `command` | the line run as `/bin/sh -c COMMAND`: the same |

A failure is the path and why, in words.

### Running a program

`run` and `sh` start the program with `spawn_path`, its current
directory the home (`chdir`), and its terminal a port of `agentd`'s,
one for all its programs, as one runs at a time: `agentd` makes that
port its own terminal (`tty_set`) for the spawn, so the program
inherits it as its standard input, output and error, and sets its own
back after, the one `tty_get` said at its start. It then answers that port as a
terminal (`tty.l0`'s protocol): a write is kept, 64 KB at most, and
what comes past that only counted; an `r` is answered at once with the
end of input, so a program reading its input sees none; a `p` with
`tty`; an `i` with nothing. The same port is told of the program's
exit (`proc_watch`) and of its deadline (`alarm_at`), `run_timeout`
seconds from its start (the configuration's, 60 if none): one still
running then is ended with `proc_kill`, and its exit waited for; an
alarm before a run's deadline, left from an earlier run, is passed
over. The
answer is `exit N` and what it wrote, a line `[dropped: N more
bytes]` after if any was, and before them `ended: still running when
its time was up` for one ended; it is a failure unless it exited 0.
A `Run` keeps all this, pure: `run_heard` takes each message that came
to its port, and `run_result` gives the answer. What goes to the model is
UTF-8, as JSON's strings must be: a byte that is not part of UTF-8 is
sent as `?`, and a cut moves back to where a character starts.

## Limits

- One turn at a time, of any conversation; another's `say` is `error:
  busy`.
- Conversations are kept only while `agentd` runs, in its memory.
- A `say`'s text is at most what one message holds, some 4 KB.
- At most 32 rounds of tools in one turn.
- Its limits are its rules only: the tools take any path, and nothing
  asks the person's yes.
- `read_file` gives at most 64 KB of a file, and text only: a binary
  file's bytes that are not UTF-8 come as `?`.
- A program `run` or `sh` starts has no input, and what it writes is
  kept to 64 KB. One that `proc_kill` refuses to end, a driver, is
  waited for past its deadline, until a `stop`.
- The system prompt names the board by its CPU only: L0 has no call
  that tells QEMU's board from a Pi 5.
