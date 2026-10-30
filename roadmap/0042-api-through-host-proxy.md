# 0042: A model's API reached through a proxy on the host

Track: Agent · Status: active · Needs: 0041 · Spec: network.md, programs.md, testing.md, pi5.md

## Why

A model's API is HTTPS only, and L0S has no TLS (0048 gives it one,
a goal of its own). Until then a small proxy on the development host
takes the board's plain HTTP on the local network, adds the API key,
and forwards it over TLS, so 0043's agent can run long before L0S
speaks TLS itself. The key stays on the host, and the board is tied to
it; 0048 lifts both.

The API is Anthropic's Messages API: `POST /v1/messages`, answered as
server-sent events with `stream: true`, with tool use and prompt
caching (`cache_control`). The proxy forwards to one base URL it is
given, so another provider's could sit behind it, but only this one is
built; on the board the provider is behind one small library (a
request built, its streamed events read), which 0043's `agentd` uses.

## Done when

- `tools/api-proxy/` has the proxy, Python in its own venv
  (`build/proxy/venv`, from its `requirements.txt`, as `make mcp` makes
  the MCP server's). It listens on one address it is given, a loopback
  or private one only; takes `POST /v1/messages` and
  `/v1/messages/count_tokens` and nothing else; refuses any request
  without the board's bearer token; adds `x-api-key` from the host's
  `ANTHROPIC_API_KEY`; and streams the answer back as it comes.
- It counts what is spent and refuses nothing for it: each answer's
  `usage` (input, output, cache written, cache read) is a line in its
  log, and `--day` totals a day's.
- The board finds the proxy and its token in `/etc/agent/config` and
  `/etc/agent/token`. `run ask TEXT` sends a message to the model
  through it and writes the answer as it streams, on QEMU (through
  10.0.2.2) and on a Pi 5 (through the host's address on the LAN), each
  against the real API once, logged.
- The proxy's own tests run with `make test`, against a stand-in for
  the API, and an e2e case runs `ask` through the proxy to the
  stand-in, so no test needs a key or the network.

## Steps

- [x] **The proxy.** `tools/api-proxy/`: `requirements.txt`
  (`aiohttp`, its server and its client, both streaming), `proxy.py`,
  `usage.py` (pure: the usage of an event stream or a JSON answer, a
  log line, a day's totals) and `standin.py` (a stand-in API: answers
  `/v1/messages` from a script of answers, each a JSON answer or a list
  of events with a delay before each, and keeps every request it got).
  `proxy.py --listen ADDR:PORT --token-file FILE [--upstream URL]
  [--usage FILE]`: the upstream is `https://api.anthropic.com` unless
  given; the address must be loopback or private (RFC 1918), never
  `0.0.0.0`, or it says so and exits; it will not start without
  `ANTHROPIC_API_KEY` (a stand-in's run gives it one of its own). For
  each request: a path or method other than the two is 404; a missing
  or wrong `Authorization: Bearer` is 401 (compared with
  `hmac.compare_digest`); otherwise the body is sent upstream as it is,
  with `content-type`, `anthropic-version` and `anthropic-beta` passed
  and no other header of the board's, `x-api-key` added; the answer's
  status and `content-type` are passed back, and its body as each piece
  comes (`iter_any`), never gathered. The answer's usage, from
  `message_start`'s and `message_delta`'s, or a JSON answer's, is a
  JSON line in the usage file (time, path, model, status, the four
  counts); `proxy.py --day [YYYY-MM-DD] [--usage FILE]` totals a day's.
  Makefile: `PROXY_VENV := $(BUILD)/proxy/venv` and its `.installed`
  from `requirements.txt`, as `MCP_VENV`'s; `make proxy` makes it and
  `$(BUILD)/proxy/token`, 32 random hex digits made once (mode 600);
  `make proxy-run [PROXY_LISTEN=ADDR:PORT]` runs it with that token,
  127.0.0.1:8765 unless given. `test_proxy.py`, `unittest`, run by
  `$(BUILD)/test/api-proxy.ok` in `test-each` with the venv's Python,
  which it depends on, so the first `make test` after a clean needs the
  network once, for pip, and none after: a request without the token,
  with a wrong one, to another path, by `GET`; the key added and the
  token not passed on (the stand-in's record); an event stream whose
  first event reaches the test before the stand-in sends its last (the
  stand-in waits 300 ms between them); an upstream 429 or 500 passed
  through with its body; usage lines for a stream and a JSON answer,
  and a day's totals; refusing `0.0.0.0` and starting without a key.
  testing.md's `make test` row.
- [x] **The board's side of the API.** [proto/model.l0](../user/lib/proto/model.l0)
  (`MODEL` is `JSON`, `SSE` and `HTTP`), the provider behind one
  interface: `(data ModelConf ...)`, read by `model_conf_of text token`
  from `/etc/agent/config`, a line each, `#` a comment (`api HOST:PORT`,
  the proxy; `model NAME`, `claude-sonnet-5-5` if none; `max_tokens N`,
  8192 if none; other keys are left for their programs), and the token,
  the first line of `/etc/agent/token`; `model_conf_read` reads both and
  says which is missing. `model_request c system messages tools`, the
  request's bytes: `POST /v1/messages`, `Authorization: Bearer TOKEN`,
  `anthropic-version: 2023-06-01`, the body's JSON with `model`,
  `max_tokens`, `stream: true`, and `system`, `messages` and `tools` as
  given (`Json`, so 0043 adds `cache_control` where it wants it).
  `model_events e`, an `SseEvent` read as `ModelEvent`s: `(MText i
  text)`, `(MToolStart i id name)`, `(MToolInput i partial)`,
  `(MBlockStop i)`, `(MStop reason)`, `(MUsage input output cwrite
  cread)`, `(MError kind message)`, `ping` none. Another provider would
  be another `model_request` and `model_events` with the same types.
  Tests: a Messages API stream as its documentation lays one out
  (text, then a `tool_use` whose input comes in three `partial_json`
  pieces, then `message_delta` with `stop_reason` and usage) read event
  by event; an `error` event; a request's JSON for a system prompt, two
  messages and a tool, compared as text; a config with comments and
  without `model`. programs.md's row.
- [x] **`ask`, and the e2e case.** `user/bin/ask`: `run ask TEXT...`
  reads the configuration, opens `api`, posts one user message, and
  writes each text piece as it comes, then a newline; a 401 is "the
  proxy refused this board's token", any other refusal the API's
  error `message`, and no configuration says which file is missing.
  `tests/e2e.sh`: a case's etc is copied into `build/e2e` and `@PORT@`
  in its files made the port, as `typed` is. The case `ask`: `net`
  user; `serve` `build/proxy/venv/bin/python -I
  tools/api-proxy/e2e_serve.py @PORT@ tests/e2e/ask`, which runs the
  stand-in, with the script in `tests/e2e/ask/script.json`, and the
  proxy in front of it on 127.0.0.1:@PORT@ with the token in the
  case's `etc/agent/token`; `etc/agent/config` is `api 10.0.2.2:@PORT@`;
  `typed` runs `ask` once to a stream of four text pieces, and once to
  a 529 overloaded error. `make e2e` depends on the proxy's venv.
  testing.md's case; network.md's "Reaching a model's API": the proxy,
  `/etc/agent`, `ask`; programs.md's `ask` row.
- [ ] **The agent's etc on a board, and the real API on QEMU.** `make
  agent-etc API=HOST:PORT [MODEL=NAME]` writes `build/agent-etc/config`
  and copies `build/proxy/token` beside it; when that directory is
  there, the demo's initramfs (`stage_etc`) and `pi5-initramfs` take it
  as `/etc/agent`, so `install` carries it onto a system volume; on a
  `/` that can be written, the two files may be written at a shell too
  (`write /etc/agent/token ...`). The token is never in the tree: it
  is made in `build/`, and `tests/e2e/ask`'s is a test's own, which
  the stand-in alone takes. Then, by the user with a key: `make
  proxy-run`, `make agent-etc API=10.0.2.2:8765`, `make demo NET=user`,
  `run ask` a question, and `proxy.py --day`; logged here with what it
  cost. network.md says how a board is given the proxy.
- [ ] **The Pi 5** (the user, on the board): the proxy on the host's
  LAN address (`make proxy-run PROXY_LISTEN=192.168.1.10:8765`, the
  host's address on the network the Pi's DHCP lease is on), `make
  agent-etc API=192.168.1.10:8765`, a netboot (`make pi5-netboot`,
  `tools/pi5-boot --console`) or a card installed from it; at the
  serial shell `run net` shows the lease, `run ask` a question streams
  its answer, and the proxy's usage file has its line. Logged when
  done, with anything the Pi's `gem` or `inet` needed. pi5.md says the
  agent's proxy is reached over the LAN.

## Spec changes

- network.md: reaching a model's API, through the proxy: what it takes
  and refuses, `/etc/agent/config` and `/etc/agent/token`, how a board
  on QEMU (10.0.2.2) and a Pi 5 (the host's LAN address) reach it, and
  in Limits that the key and the TLS are the host's (until 0048).
- programs.md: `ask`'s row, `proto/model.l0`'s.
- testing.md: the proxy's tests in `make test`, which need pip once;
  the `ask` e2e case and the stand-in; `@PORT@` in a case's etc.
- pi5.md: the proxy on the host's LAN address.

## Log

- 2026-10-29: written, with 0041 and 0043 to 0049.
- 2026-10-29: steps written, the open questions settled with the user:
  Anthropic's Messages API (streamed, tools, prompt caching), behind
  one library on the board so another could be added; the proxy in
  Python in its own venv, as the MCP server is, forwarding to one base
  URL; the board's token a file, `/etc/agent/token`, made on the host
  in `build/` and given to boards by `make agent-etc`; the budget
  counted only, logged per answer and per day, nothing refused for it
  (an agent acting on its own, 0051, may want a cap). The goal stays
  active until its last step has run on a Pi 5 as well as on QEMU. An
  e2e case's etc gets `@PORT@`, so the board finds the stand-in's proxy
  at 10.0.2.2 on the boot's free port, as `typed` does.
- 2026-10-29: step 1, the proxy: `tools/api-proxy/` in aiohttp 3, its
  venv `build/proxy/venv` made by `make proxy` with the token, and
  `make proxy-run`. Beyond the plan: the stand-in takes a third kind of
  answer, `{"text": [pieces], "delay": S}`, made the events the API
  streams for a text answer (`standin.text_events`), and with `--key`
  refuses a request without that `x-api-key`, as the API does, so the
  tests check the key reached it twice over; the proxy's own refusals
  (401, 404, a 502 when the upstream cannot be reached) are JSON in the
  API's error form, so a board reads them as it reads the API's; an
  upstream answer that breaks off closes the board's connection rather
  than ending its body, so the board sees it cut short. The usage file
  is `build/proxy/usage.jsonl` unless `--usage` is given, and times and
  `--day` are UTC. Its tests, 20, pass with `make test`.
- 2026-10-29: step 2, `proto/model.l0`, as planned, with these choices:
  text, ids, names and partial JSON stay `bytes` in `ModelEvent`s; an
  `MUsage` count an event does not say is -1 (message_start says all
  four, message_delta the output's, the answer's whole so far), so a
  caller puts the later over the earlier; `system` is left out of the
  body when it is `JNull`, and `tools` when it is not a non-empty
  array; the request also sends `Accept: text/event-stream`. Added for
  `ask` and 0043: `model_message role text`, a message's `Json`, and
  `model_refusal code body`, a refused request's words (the API's error
  `message` when the body has one, else for a 401 that the proxy
  refused the board's token, else the status); the proxy's own 401
  carries that same message, so an upstream 401 for a bad key still
  says what it is. Its 16 tests pass.
- 2026-10-29: step 3, `ask` and the e2e case `ask`, as planned:
  `e2e.sh` copies a case's etc to `build/e2e/CASE.etc` when a file in
  it holds `@PORT@`, and makes it the port; `e2e_serve.py PORT CASE`
  runs the stand-in on a free port with a key of its own and the proxy
  on `127.0.0.1:PORT` in front of it, writing each request and usage
  line to `build/e2e/ask.serve` and the usage file to
  `build/e2e/ask.usage.jsonl`. `ask` is written as `http` is, its parts
  read by a pure `answer_part` that its tests drive: text written and
  flushed as each body piece comes, an `error` event or a refusal said
  with `model_refusal`'s words. The proxy now asks upstream for no
  content coding (`Accept-Encoding: identity`), so nothing waits on a
  decompressor. The Makefile's library variable is `MODELLIB`, not
  `MODEL`, which step 4's `make agent-etc MODEL=NAME` takes. The case
  passes on 1 CPU and on 4; `make check`, `make test` pass.
- 2026-10-29: step 4's build part: `make agent-etc API=HOST:PORT
  [MODEL=NAME]` writes `build/agent-etc/config` (`api`, and `model` if
  given) and copies `build/proxy/token` beside it, making the token
  first if there is none; `stage_agent` puts that directory in the demo's
  initramfs and `pi5-initramfs` as `/etc/agent` while it exists (the
  test initramfses never take it); `rm -rf build/agent-etc` leaves it
  out. network.md says how a board is given the proxy. Tried on QEMU
  as the user will, against the stand-in in place of the API
  (`e2e_serve.py 18765` with the build's token, `make agent-etc
  API=10.0.2.2:18765`, `make initramfs`, a boot typing `run ask what is
  L0S`): the answer streamed and the usage line was written. Not tried:
  `pi5-initramfs` itself, which takes `/etc/agent` by the same line as
  `initramfs`. `make e2e` passes, every case and the 19 screen tests,
  once the cases that list `/bin` or count `/`'s files (`fs`, `shell`,
  `install`, `install_boot`, `rootboot_tmpfs`) were told of step 3's
  `/bin/ask`; `jobs` failed once under the full run's load, its
  Ctrl-C missed, and passed alone and after. The step stays open for
  the run against the real API, the user's, with a key:

      make proxy                                 # once: the venv and build/proxy/token
      export ANTHROPIC_API_KEY=sk-ant-...        # the host's key; never on the board
      make proxy-run                             # the proxy on 127.0.0.1:8765; leave it running
      # in another terminal:
      make agent-etc API=10.0.2.2:8765           # MODEL=NAME for another than claude-sonnet-5-5
      make demo NET=user                         # then, at the serial shell:
      #   run ask what is a microkernel, in two sentences
      build/proxy/venv/bin/python -I tools/api-proxy/proxy.py --day   # what today cost, UTC
      rm -rf build/agent-etc                     # afterwards, to leave /etc/agent out again

  Log here what `ask` wrote, the usage line from
  `build/proxy/usage.jsonl` and `--day`'s totals.
- 2026-10-29: step 5, the user's, on the Pi 5, with the host on the
  LAN at 192.168.1.10 (its address on the network the Pi's DHCP lease
  is on; `ip -4 addr` says it):

      export ANTHROPIC_API_KEY=sk-ant-...
      make proxy-run PROXY_LISTEN=192.168.1.10:8765    # a private address only; leave it running
      make agent-etc API=192.168.1.10:8765
      make pi5-netboot && tools/pi5-boot --console     # or make pi5-card, or install from it
      # at the serial shell:
      #   run net                    the lease, an address on 192.168.1.0/24
      #   run ask what board are you running on
      build/proxy/venv/bin/python -I tools/api-proxy/proxy.py --day

  The host's firewall must let the Pi reach port 8765. Log what `ask`
  wrote, the usage line, and anything `gem` or `inet` needed.
