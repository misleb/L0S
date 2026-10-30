# The agent

`agentd` (`user/sbin/agentd`) is to be the home of an agent on L0S: a
conversation with a model, reached through the host's proxy and
[proto/model.l0](../user/lib/proto/model.l0) ([network.md](network.md)),
and tools that act on the board. What is written of it so far is its
parts, each tested on the host; the program itself serves nothing, and,
started, says so in the log and exits 1. No inittab starts it.

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

## Limits

- `agentd` serves nothing yet: there is no protocol, no `agent` command,
  and no inittab starts it.
