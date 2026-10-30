# The agent

`agentd` (`user/sbin/agentd`) is the agent's program: a conversation
with a model, reached through the host's proxy and
[proto/model.l0](../user/lib/proto/model.l0) ([network.md](network.md)),
and tools that act on the board. What it has today is its parts, each
tested on the host; the program itself serves nothing, and, started,
says so in the log and exits 1. No inittab starts it.

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

A failure is the path and why, in words. What goes to the model is
UTF-8, as JSON's strings must be: a byte that is not part of UTF-8 is
sent as `?`, and a cut moves back to where a character starts.

## Limits

- `agentd` serves nothing yet: there is no protocol, no `agent` command,
  and no inittab starts it.
- At most 32 rounds of tools in one turn.
- Its limits are its rules only: the tools take any path.
- `read_file` gives at most 64 KB of a file, and text only: a binary
  file's bytes that are not UTF-8 come as `?`.
