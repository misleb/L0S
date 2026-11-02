# The agent

`agentd` (`user/sbin/agentd`) is the agent's program: one
conversation with a model, which every client shares and which is kept
in its home, so that it outlives `agentd`; the model reached through
the host's proxy and
[proto/model.l0](../user/lib/proto/model.l0) ([network.md](network.md)),
and tools that act on the board. It only answers: it acts when someone
talks to it, through its protocol, `agent`, which `run agent` speaks at
a console and the Agent app in a window, and at no other time.
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
   are the agent's and the person's to change; each turn reads them
   afresh, so a change holds from the next.
5. makes what is missing of the home's other parts ([The
   home](#the-home)), and writes its `CONSTITUTION.md` from
   `/etc/agent/CONSTITUTION.md` whenever the two differ, saying each in
   the log.
6. reads back the conversation kept in the home's
   `.history/conversation.json` ([Kept](#kept)), saying in the log how
   many turns it has, or "a new conversation" if there is none.
7. registers `agent` and waits on three ports at once
   (`port_receive_set`): its own, for requests; the one its HTTP
   connections' notices come to; and the one that is the terminal of
   the program a tool runs. So a `stop` is heard, and acted on, while
   an answer streams or a program runs.

One turn runs at a time. A turn's acts, as the
loop gives them, are done in order: a request is sent to the proxy on
the connection kept from the last, or a new one, and its streamed
answer read as it comes (`model_events`), each event told to the loop;
a file tool is done at once; `run` and `sh` start their program, and
the turn waits for its exit, its terminal answered meanwhile. An answer
silent for 120 s is given up, and the turn fails; so does a refusal
(`model_refusal`'s words), a connection lost mid-answer, or a stream
that ends before its stop. A request the loop asks while the last
response is still ending (its stop came, its end not yet) waits for
that end, and a turn done before its response ended resets the
connection, so a kept connection never carries the rest of one answer
into the next request. Each turn's usage is a debug line in the
log (`dmesg`).

### Kept

The conversation is kept in the home's `.history/conversation.json`,
part of the home's fixed part, as a JSON object: `began`, the clock's
seconds at its first turn (0 with no clock); `said`, how many times the
person has spoken in it; `usage`, the last answer's four counts, so
that compaction goes on as it would have; and `messages`, its turns as
the Messages API's, without breakpoints (`conv_kept_bytes`). `agentd`
writes it whole, as `conversation.json.new` renamed over the last, so a
write cut short leaves the last whole, each time the conversation is
one the API takes: as each request of the model is sent but a
summary's, after the person's text or each round of tools' results,
and at each turn's end, however it ended. A file that is not one
(`conv_kept_of`'s why) is moved aside to `conversation.json.bad`,
warned of, and a new conversation begun; `clear` begins one too, and
keeps it at once. So a turn cut short by `agentd`'s end, or the
board's, loses at most what came after its last request.

## The home

The model is stateless: what makes the agent itself is its home's
files. They are kept in Claude Code's conventions, so a copy of the
home (`agent backup`) opens there as it is
([sys/agenthome.l0](../user/lib/sys/agenthome.l0)):

| Part | What it is |
|---|---|
| `CLAUDE.md` | its rules, the agent's and the person's to change; the default begins with `@CONSTITUTION.md` and `@memory/MEMORY.md`, Claude Code's imports |
| `CONSTITUTION.md` | the fixed part, L0S's ([demo/etc/agent/CONSTITUTION.md](../demo/etc/agent/CONSTITUTION.md), the Pi 5's the same), written from `/etc/agent/CONSTITUTION.md` at each start when they differ: what the home is, what the agent may change (its rules, memory and skills, through its file tools) and what not |
| `memory/MEMORY.md` | the memory's index, made at first saying it is empty; `memory/NAME.md` a fact each, with its frontmatter |
| `.claude/skills/NAME/SKILL.md` | a skill each, its frontmatter's `description` read up front, its body read with `read_file` when used |
| `.history/` | `log`, every write of the agent's file tools in the home; `N`, the file before entry N; `conversation.json`, `agentd`'s conversation ([Kept](#kept)) |

**The system prompt** is made anew at each turn: the
built-in part, then the constitution, the rules and the memory's
index, each whole under a heading, then a line for each skill, its
name, its description and where its body is (`home_prompt`). So a
change to the home holds from the next turn, and a prompt the same as
the last turn's is read from the cache. The rest of the home is read
on demand.

**The fixed part** is the constitution, and `.history` and all in it
(`home_fixed`): `write_file` and `make_dir` refuse such a path, by any
spelling, before touching anything, saying it is fixed. It is read as
any other.

**The history.** Each write of `write_file` and `make_dir` inside the
home is a line of `.history/log`, `N TIME CONV KIND PATH`: N from 1,
one more than the highest; TIME the clock's seconds (`rtc clock`'s, 0
with none); CONV `B.N`, B when the conversation began and N which time
the person spoke in it, the turn that wrote it, or what else made it,
`undo:N` or `restore`; KIND `new`
(no file was there), `changed` (the file before kept whole as
`.history/N`), `removed` (the same, the file gone), `dir` or `rmdir`.
A write whose file is not written leaves no line; a write outside the
home is not the home's and leaves none.

**At a shell**, `agent` does these itself, without `agentd`:

| Command | Does |
|---|---|
| `agent history [PATH]` | the log, the newest last, as `N DATE TIME CONV KIND PATH` (`-` for a time with no clock), only PATH's if given, a relative path from the home |
| `agent undo N` | entry N undone by its inverse, itself kept (`undo:N`), so an undo is undone in turn: `new` by removing the file, `changed` and `removed` by writing `.history/N` back, `dir` by removing the directory if empty, `rmdir` by making it; `undid N: WHAT` |
| `agent backup` | the home, every directory and file, `.history` with them, as a cpio archive (newc), `PUT /backup` to the proxy `/etc/agent/config` names, with its token: `backed up HOME: N files and D directories, SIZE to the host` |
| `agent restore` | `GET /backup`, written into the home: `.history` first, as it is, then each other file that differs through the history (`restore`), a directory not there made; `restored N files (M the same already) and D directories`, and a line for each file of the home the backup has not, left as it was |

The host keeps the backup ([network.md](network.md#reaching-a-models-api)):
in `build/proxy/backup/home`, which Claude Code opens as it is, and
which `restore` packs as it is then, edited on the host or not.

## Its protocol

[proto/agent.l0](../user/lib/proto/agent.l0) (`AGENTLIB`) has both
sides: the requests' bodies and the notices, made and read, and the
client. There is one conversation, `agentd`'s, and every client talks
in it and hears all of it. Each request is a request (`l0s.l0`'s), its
answer to its reply port:

| Request | Answer |
|---|---|
| `open NPORT` | `ok`; then the conversation so far told to NPORT as its notices would have told it (`conv_replay`: the person's texts as `said`, from the source their turn's line names (`unknown` for a turn kept before there were sources), a summary compaction made as `compacted 0 0`, the model's texts, each tool's use and its result, named by the use it answers), then `opened busy` or `opened idle`; and its notices go to NPORT from then on, as to every port opened before it. A port gone before all that is told is not kept |
| `say [SOURCE]` a newline and the text | `ok`, the text told to every NPORT open as `said`, and the answer streamed to them; `error: busy` while a turn runs, whoever said it. SOURCE, one word, says where the text came from ([Where a prompt came from](#where-a-prompt-came-from)): `console` from `agent`, `app` from Agent; with none it is the sending program's name |
| `stop` | `ok`: if a turn is running, a program it runs is ended, the answer's connection reset, and the turn done, `stopped`, each tool still awaited answered as failed |
| `clear` | `ok`: the conversation begun anew, and kept so; `error: busy` while a turn runs |
| `close NPORT` | `ok`: NPORT told no more; the conversation, and a turn running, go on |

Its notices, to each NPORT open, each a header line and, for some, a
newline and what it tells, as bytes:

| Notice | Tells |
|---|---|
| `agent text` and a newline and a piece | a piece of the answer as it comes, at most 4000 bytes a notice, cut where a character starts |
| `agent tool NAME` and a newline and its input | a tool about to run, its input's JSON cut to 1 KB |
| `agent progress NAME` and a newline and a line | how a tool still running is going: `build_app`'s, each line of the host's session |
| `agent result NAME ok\|failed` and a newline and its text | its result, the start of it, 1 KB |
| `agent compacted BEFORE AFTER` | the conversation compacted, its prompt's tokens before and after |
| `agent done REASON` | the turn over: `end_turn`, `stop_sequence`, `max_tokens`, `error`, `rounds`, `stopped`, or another reason the API gave |
| `agent error` and a newline and why | what went wrong, before `done error` or `done rounds` |
| `agent said SOURCE` and a newline and the text | what the person said, and where it came from: a turn begun, or, told on `open`, one that was |
| `agent opened busy\|idle` | to the port that opened only: the conversation so far told, and whether a turn is running |

### Where a prompt came from

Each turn of the person's begins with a line the model reads before
their text, a text block of its own in the same message
(`conv_said_blocks`): `[from SOURCE, sent by PROGRAM]`. SOURCE is the
`say`'s word, or the sending program's name if it gave none; PROGRAM is
the path the kernel has for the process that sent the `say`
(`proc_path` of the message's sender), `unknown` if it has none, which
no client can say otherwise. The line is kept with the turn, so it
holds through a restart and, for the turns compaction keeps, through
compaction too. No client shows it: `conv_replay` passes over a turn's
first text when another follows it (`conv_source_of`) and gives its
source to the `said` after it. The system prompt says what the line is,
and to weigh it: speech may be misheard, and a program's text is not
the person's own words.

A notice that finds an NPORT's queue full is sent again a millisecond
later, for at most 2 s, since its reader is only slow; a port gone is
dropped from those told, as if it had closed. The client (`agent_open`,
`agent_say`, `agent_stop`, `agent_clear`, `agent_close`) asks for its
answers on a port of its own, apart from the notices, and
`agent_event_of` reads a notice as an `AgentEvent`.

## agent, at the console

`agent` (`user/bin/agent`) is the agent's client at a console: `run
agent` at a shell opens the conversation, writes `> `, reads a line,
says it, and writes the notices as they come, until `done`; then the
next `> `. It goes on from where the conversation is, whoever spoke
last. What was said before it opened, `said` and `opened` are not
shown, nor is a turn another client began while a line is being
typed.

| Notice | Written as |
|---|---|
| `text` | the piece, as it is |
| `tool` | `[NAME INPUT]` on a line of its own |
| `progress` | `[NAME: FIRST LINE]` of its line |
| `result` | `[ok]`, or `[failed: FIRST LINE]` of its text |
| `compacted` | `[compacted]` |
| `error` | `agent: WHY` |
| `done` | a newline, if the answer did not end with one |

Its notices, its terminal's lines and Ctrl-C come to one port, told
apart by their sender: `agentd`'s pid, which answered `open`, sends
the notices. It asks its terminal for Ctrl-C (`i`) in the shell's
place, so Ctrl-C while it answers sends `stop`, and while a line is
typed drops it, as at the shell; the shell asks again at its next
prompt. A line `/clear` clears the conversation and writes `[cleared]`.
The input's end (Ctrl-D), or a line `/exit`, closes its port, the
conversation kept, and exits 0; a blank line says nothing. With no `agentd`
registered within 15 s it says "the agent is not running (no
/etc/agent/config?)" and fails.

## Agent, the app

Agent (`user/apps/chat`, `Agent.app`, its program `chat`) is the same
conversation in a window of the desktop, 960 by 560, launched from the
launcher. It looks up `agent` as it opens, and opens the conversation
with a port of its own for the notices (`ui_win_ports`), each request
asked without waiting (`ui_win_ask`), its answer a reply; it says with
the source `app`. What `agentd` tells on `open` and every notice after
are drawn as they come, in two panes side by side, each of lines that
wrap and scroll ([toolkit.md](toolkit.md), `lines.l0`), the end kept in
view until the person scrolls up: the conversation, and Tools, the
tools' log, under its heading, "No tools have run yet." until one has.

| What came | In the conversation | In Tools |
|---|---|---|
| `said` | a blank row, then "From SOURCE", dimmed, if SOURCE is neither `app` nor `console`, then the text in bold | a blank row, then `> ` and the text's first line, at most 48 bytes, dimmed |
| `text` | joined onto the model's text before it, a paragraph a line, wrapped | |
| `tool` | "Ran NAME, NAME...", dimmed, a line for each run of tools the text does not part | a row, dimmed, an arrow then its name and its input's first 60 bytes; a press opens it on "Input:" and its input, then "Running...", and once its result has come "Result:" or "Failed:" and its text; a press again closes it |
| `progress` | | given to the newest run of its tool still waiting: open, it shows "Running:" and the latest line in place of "Running..." |
| `result` | | given to the newest run of its tool still waiting; a failed one's row in red |
| `compacted` | "The conversation was compacted.", dimmed | |
| `error` | its text, in red | |
| `done` | the turn over; "Stopped." or "The answer was cut off at its most tokens.", dimmed, for `stopped` and `max_tokens` | |
| `opened` | whether a turn is running | |

Along its foot, an entry ("Ask the agent") and Send, suggested, which
Enter presses too, sensitive while a turn is not running and the entry
holds more than spaces; while one runs, whoever began it, Stop, red, in
its place, which sends `stop`. A say refused, as `error: busy`, is
said in red. With no `agentd` registered, or once it stops answering,
the window is a page, "The Agent Is Not Running", and Retry looks
again.

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
  its tools by name, that it answers at a console or in a window, and
  what the line before each of the person's texts says) and then its
  rules;
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
- After 128 rounds of tools in one turn (`loop_rounds_max`) the turn is
  done, `rounds`, saying so, the last results kept.
- `loop_cancel` ends a turn, `stopped`: each tool still awaited is
  answered as failed, so the conversation stays one the API takes.

`loop_standin` drives a loop against a stand-in model, a script of
answers (each a list of `ModelEvent`s) and a table of tools' results by
use id, and gives the requests sent, the notices told and how it ended:
the loop's host tests are written with it.

### Compaction

A conversation past a size is compacted before its next turn is sent.
When the person says something and the last answer's prompt (its input,
the cache written and the cache read: `usage_prompt`) passed `compact`
tokens (the configuration's, 100000 if none), the loop first asks the
model to summarize every turn but the last `keep` (8 if none). The cut
(`conv_cut`) is moved earlier until the turn after it is the person's
own text, a turn of theirs with a text and no tool's result, so a
tool's use is never parted from its result; with no such cut, too few
turns, there is no compaction, and the turn is sent as it is.

The summary request has the same system prompt and no tools, and one
message: the ask, then the older turns as a transcript
(`conv_transcript`: who said each, its texts, each tool's use as `[tool
NAME INPUT]` and its result, cut to 2000 bytes), since tool blocks need
the tools the request leaves out. The summary's text is told to no one.
At its stop, the older turns are replaced by one of the person's, "The
conversation so far, summarized:" and the summary, which the first kept
turn, the person's own text, joins (`conv_compacted`); the usage is
unknown until the next answer says it. `compacted BEFORE AFTER` is
told, BEFORE the last prompt's tokens and AFTER an estimate, BEFORE in
the proportion of the new prompt's bytes (system, tools and turns as
JSON) to the old's; then the person's text is said, and the turn goes
on as any other. A summary that fails (an error, or no text) leaves the
conversation as it was and says so (`error`, "compaction failed, the
conversation kept whole: WHY"), and the text is said all the same; a
`stop` while the summary comes drops it, the text unsaid.

## The tools

[tools.l0](../user/sbin/agentd/tools.l0). Each tool takes its input as
JSON and answers a `ToolAnswer`, a text, or a failure the model reads.
Its definition (`file_tool_defs`, `run_tool_defs`, `desk_tool_defs`)
is a name, a description and its input's JSON Schema, an object whose
properties are all required but those said to be optional.

The agent's **home** is the configuration's `home PATH`
(`/etc/agent/config`, a key `model_conf_of` passes over), or
`/Volumes/data/agent`. A relative path is from the home (`tool_path`,
by `path_resolve`, `..` included); any path is taken, as nothing is
enforced here: what the agent should and should not touch is its
rules'.

| Tool | Input | Answers |
|---|---|---|
| `read_file` | `path` | the file's text, at most 64 KB, then a line `[cut: N more bytes]` if it was cut |
| `write_file` | `path`, `content` | the file made anew to hold content (its directory must be there): `wrote N bytes to PATH`; in the home, kept in its history, and refused on its fixed part |
| `list_dir` | `path` | a line for each entry, `NAME SIZE`, a directory's `NAME/`, from its file server; on the initramfs, while `/` is it, the names alone |
| `make_dir` | `path` | the directory made, on a volume: `made PATH`; in the home, kept and refused as `write_file` is |
| `remove` | `path` | the file removed, or the directory if it is empty, as its file server's `stat` says which: `removed PATH`; in the home, kept (`removed` or `rmdir`, so `agent undo` puts it back) and refused as `write_file` is; on the initramfs refused |
| `rename` | `from`, `to` | the file or directory given the new name, on the same volume (the kernel's `rename_file`): `renamed FROM to TO`. A file in the home, or going into it, is written anew at `to` and removed at `from` with the home's writes, so the history keeps both and each can be undone; a directory there is refused, as the history keeps files. Either name on the fixed part, or on the initramfs, is refused |
| `file_info` | `path` | what is there, from its file server's `stat`: `PATH: a directory`, or `PATH: a file of N bytes`, `, a program` if it is one; on the initramfs, which of the two, without a size |
| `volumes` | none | a line for each volume mounted, from its server's `df`: `/Volumes/LABEL: SIZE, FREE free, N files`, in clusters of 4096 bytes |
| `run` | `program`, `args` (optional, an array of strings) | the program found as the shell's `run` finds it (`program_found`: `/bin/NAME`, `/sbin/NAME`, an app's, or a path, a relative one from the home), started with `args` in place of its own: `exit N`, then what it wrote |
| `sh` | `command` | the line run as `/bin/sh -c COMMAND`: the same |

A failure is the path and why, in words.

### The desktop and the clock

[desk.l0](../user/sbin/agentd/desk.l0). These ask the compositor
(`compositor`, [desktop.md](desktop.md)'s protocol) or the clock
(`clock`) on `agentd`'s asking port, the clock's own, found by name each
time, and wait for the answer, as the file tools wait for theirs. With
no compositor each fails "no compositor: the desktop is not running".
Places and sizes are the desktop's pixels, a window's its content's.

| Tool | Input | Asks | Answers |
|---|---|---|---|
| `windows` | none | `windows` | `ID TITLE X Y WIDTH HEIGHT FRONT PID`, then a line a window, front first, without its buffers' words, then the pointer's line |
| `open_app` | `name`, `args` (optional, words) | `launch NAME ARG...`, then `windows` every 50 ms for 3 s at most | `opened NAME: its window is ID, in front`, once a window not there before, or another than was, is in front; or that none came in 3 s |
| `place_window` | `id`, `x`, `y`, `width`, `height` | `place` | `window ID asked to be placed; windows says where it is`: the window's program is asked for the size, and it moves once it answers |
| `raise_window` | `id` | `raise` | `window ID raised` |
| `close_window` | `id` | `dismiss` | `window ID's program asked to close it`, as its close button asks |
| `draw_desktop` | `svg`, `x`, `y`, `width`, `height` | `paste` | `drawn at X, Y`: the document drawn by the SVG library ([svg.l0](../user/lib/gfx/svg.l0)) in `agentd`, `width` by `height` at the desktop's scale, as ARGB words in a buffer shared with the compositor, which draws it over the desktop by its alpha; at most 256000 of the screen's pixels (640 by 400) at once. A document the library refuses is said so |
| `clear_desktop` | none | `desktop size`, then `desktop restore 0 0 W H` | the wallpaper the compositor holds put back over all of the desktop |
| `time` | none | the clock's `time` and `zone` | the date and time to the second in UTC and the weekday, the same in the clock's zone (US Pacific) with its offset, and the seconds since 1970 |

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

### Building an app

[build.l0](../user/sbin/agentd/build.l0). `build_app` (`name`,
`prompt`) has a desktop app of the agent's own written and built on
the host, by a Claude Code session the proxy drives on a stronger model
than the chat's ([network.md](network.md#reaching-a-models-api)): a new
app from what the prompt says, or, for a name built before, the same
app changed, its session remembering it. The app is not part of L0S,
and its source stays on the host, as does any change to L0S's
libraries the app needed, made on a branch of its own there
(`app/NAME`) for the person to merge or not.

`agentd` sends `POST /build` on its connection to the proxy, once the
model's answer before has ended on it, and the turn waits on the build
as on a program: the events' `progress` lines are told to every port
open as `agent progress build_app`, so the console and the Agent app
show the session working; `done` is followed by `GET
/build/NAME/image`, whose program is written whole to `apps/NAME` in
the home (the directory made if need be; not kept in the home's
history, as the host makes it again) and marked a program, as `cp`
marks one. The answer is `built NAME, in apps/NAME of your home; start
it with sh: run apps/NAME &`, a blank line, and the session's summary.
A name not a program's, a refusal of the proxy's (its status and
message), the build's `failed`, or a minute with nothing from the
proxy, which says something every 15 s, fails it; `stop` resets its
connection, and the proxy ends the session.

## Limits

- One conversation, and one turn of it at a time; a `say` while one
  runs is `error: busy`, from any client.
- The kept conversation is written whole at each request and each
  turn's end, and so grows to what compaction lets it, about the
  compaction size's tokens as JSON. A turn cut short loses what came
  after its last request: a program a tool ran then is not run again,
  and the model does not know it ran.
- A client that opens while a turn runs is told the conversation as it
  was kept at that turn's last request: the text and tools of the answer
  coming then are told only from where they are when it opens.
- The conversation so far is told on `open` whole, notice by notice, as
  `agentd`'s one step, so a long one keeps `agentd` from its other
  ports while it is told; a client that does not read it holds it up
  for 2 s a notice.
- Agent shows ASCII only, as the toolkit's faces hold, so other
  characters of an answer are not drawn; its entry does not scroll
  (toolkit.md's Limits), and it shows the whole conversation, wrapped
  anew at each step. It has no way to clear the conversation, as the
  console's `/clear` does, and a window does not hear of a clear
  another client made until it opens again.
- `agent restore` while `agentd` runs writes the backup's conversation
  under it, and `agentd`'s next write puts its own back: a restored
  conversation holds from `agentd`'s next start only.
- A `say`'s text is at most what one message holds, some 4 KB.
- At most 128 rounds of tools in one turn.
- Its limits are its rules only: the tools take any path and any
  window, and nothing asks the person's yes.
- A prompt's source is any word its client names, vouched for only by
  the program's path beside it, and no tool is refused by the source of
  the turn it runs in: weighing it is the model's.
- The tools of the desktop and the clock hold `agentd` while they wait,
  `open_app` up to 3 s for the app's window, so a `stop` or a notice
  waits for them. `place_window` answers before the window has moved.
- The agent sees no pixels: `windows` gives places and titles, and what
  `draw_desktop` drew is not read back. It draws at most 640 by 400 of
  the screen's pixels at once, and what it drew stays until
  `clear_desktop`, or anything that paints the desktop again.
- `read_file` gives at most 64 KB of a file, and text only: a binary
  file's bytes that are not UTF-8 come as `?`.
- A program `run` or `sh` starts has no input, and what it writes is
  kept to 64 KB. One that `proc_kill` refuses to end, a driver, is
  waited for past its deadline, until a `stop`.
- The system prompt names the board by its CPU only: L0 has no call
  that tells QEMU's board from a Pi 5.
- Compaction happens only as a turn begins, so one turn of many rounds
  of tools can grow past the size until it ends; and the tokens after
  it are an estimate, from bytes.
- The history keeps only the file tools' writes: one by `sh` or `run`
  is not kept, which the constitution forbids for the home's parts but
  nothing enforces. Its log is read and written whole at each write.
- `agent backup` and `restore` hold the whole home in memory, and the
  host keeps one backup to restore from, the last, with every archive
  sent beside it. `restore` removes nothing the backup has not.
- Its tests run against the stand-in only: the real API has been
  talked to by hand, on QEMU and on a Pi 5, never by a test.
