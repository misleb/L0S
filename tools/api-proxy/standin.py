"""standin.py -- a stand-in for the Messages API, for tests: it answers
POST /v1/messages from a script of answers, in order, and keeps every
request it got, so no test needs a key or the network.

  standin.py --listen 127.0.0.1:PORT --script FILE [--key KEY]

A script is a JSON list of answers, each one of

  {"status": 200, "json": {...}}
        a JSON answer, with that status (200 if none)
  {"status": 200, "events": [{"event": NAME, "data": {...}, "delay": S}, ...]}
        an event stream, text/event-stream, each event sent S seconds
        (0 if none) after the one before
  {"text": ["piece", ...], "delay": S, "stop_reason": "end_turn",
   "usage": {"input_tokens": N, "output_tokens": M, ...}, "model": NAME}
        a text answer as the API streams one: message_start, a text
        block whose pieces are text_deltas S seconds apart, its stop,
        message_delta with the stop reason and output tokens, and
        message_stop (text_events)
  {"tools": [{"id": ID, "name": NAME, "input": {...}}, ...], "text": T,
   "usage": {...}}
        an answer that uses tools: text T first if given, then a
        tool_use block for each, its input in two input_json_delta
        pieces, and the stop reason tool_use (tool_events)

An answer asked for past the script's end is a 500 that says so.
Given checks (Standin's checks; e2e_serve.py reads CASE/checks.json),
each request to /v1/messages is checked first (checked): that its
tool_results answer the tool_uses before them, and the last ones those
the stand-in sent, in order ("tool_results": true); that its
cache_control breakpoints are on the system prompt, the last tool and
the last message, four at most ("cache_control": true); that a tool's
result holds a text and did not fail, once it is there
("results_contain": {ID: TEXT}); that the system
prompt holds a text ("system_contains": TEXT). A request that fails is
answered 400, invalid_request_error, "stand-in: WHY", and the line
"standin: check failed: WHY" logged. With
--key, a request whose x-api-key is not KEY is 401, as the API's would be.
/v1/messages/count_tokens answers {"input_tokens": N}, N the body's
length over 4, from no script. Any other path is 404.

Each request is kept in Standin.requests as {"method", "path",
"headers" (names lowercase), "body" (bytes)} and, run as a command,
written to standard output as a JSON line (the body as text)."""

import argparse
import asyncio
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's own directory out


def sse(name, data):
    """One event of a stream, as its bytes."""
    return b"event: " + name.encode() + b"\ndata: " + json.dumps(data, separators=(",", ":")).encode() + b"\n\n"


def text_events(pieces, delay=0.0, stop_reason="end_turn", usage=None, model="claude-sonnet-5-5"):
    """A text answer's events, as the API streams one: a script's
    events list."""
    u = {"input_tokens": 10, "output_tokens": 1, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    u.update(usage or {})
    out_tokens = u["output_tokens"]
    start = dict(u, output_tokens=1)
    ev = [{"event": "message_start", "data": {"type": "message_start", "message": {
        "id": "msg_standin", "type": "message", "role": "assistant", "model": model, "content": [],
        "stop_reason": None, "stop_sequence": None, "usage": start}}},
        {"event": "content_block_start", "data": {"type": "content_block_start", "index": 0,
                                                  "content_block": {"type": "text", "text": ""}}},
        {"event": "ping", "data": {"type": "ping"}}]
    for p in pieces:
        ev.append({"event": "content_block_delta", "delay": delay, "data": {
            "type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": p}}})
    ev.append({"event": "content_block_stop", "data": {"type": "content_block_stop", "index": 0}})
    ev.append({"event": "message_delta", "data": {"type": "message_delta",
                                                  "delta": {"stop_reason": stop_reason, "stop_sequence": None},
                                                  "usage": {"output_tokens": out_tokens}}})
    ev.append({"event": "message_stop", "data": {"type": "message_stop"}})
    return ev


def tool_events(tools, text=None, usage=None, model="claude-sonnet-5-5"):
    """An answer that uses tools, as the API streams one: message_start,
    a text block first if text is given, then a tool_use block for each
    of tools ({"id", "name", "input"}), its input's JSON sent as two
    input_json_delta pieces cut mid-way, and message_delta's stop
    reason tool_use."""
    u = {"input_tokens": 10, "output_tokens": 1, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    u.update(usage or {})
    ev = [{"event": "message_start", "data": {"type": "message_start", "message": {
        "id": "msg_standin", "type": "message", "role": "assistant", "model": model, "content": [],
        "stop_reason": None, "stop_sequence": None, "usage": dict(u, output_tokens=1)}}}]
    i = 0
    if text:
        ev.append({"event": "content_block_start", "data": {"type": "content_block_start", "index": i,
                                                          "content_block": {"type": "text", "text": ""}}})
        ev.append({"event": "content_block_delta", "data": {"type": "content_block_delta", "index": i,
                                                          "delta": {"type": "text_delta", "text": text}}})
        ev.append({"event": "content_block_stop", "data": {"type": "content_block_stop", "index": i}})
        i += 1
    for t in tools:
        ev.append({"event": "content_block_start", "data": {"type": "content_block_start", "index": i, "content_block": {
            "type": "tool_use", "id": t["id"], "name": t["name"], "input": {}}}})
        js = json.dumps(t.get("input", {}), separators=(",", ":"))
        half = len(js) // 2
        for piece in (js[:half], js[half:]):
            ev.append({"event": "content_block_delta", "data": {"type": "content_block_delta", "index": i,
                                                              "delta": {"type": "input_json_delta", "partial_json": piece}}})
        ev.append({"event": "content_block_stop", "data": {"type": "content_block_stop", "index": i}})
        i += 1
    ev.append({"event": "message_delta", "data": {"type": "message_delta",
                                                  "delta": {"stop_reason": "tool_use", "stop_sequence": None},
                                                  "usage": {"output_tokens": u["output_tokens"]}}})
    ev.append({"event": "message_stop", "data": {"type": "message_stop"}})
    return ev


def tool_ids(answer):
    """The ids of the tool_use blocks an answer's events start, in order."""
    out = []
    for e in answer.get("events", []):
        d = e.get("data", {})
        if e.get("event") == "content_block_start" and d.get("content_block", {}).get("type") == "tool_use":
            out.append(d["content_block"].get("id"))
    return out


def checked(req, checks, last_ids):
    """Why the request body req (JSON) fails checks, or None: tool_results,
    every assistant turn's tool_use ids answered, in order, by the user
    turn after it, and the last assistant turn's by those the stand-in
    sent last (last_ids); cache_control, a breakpoint on the system
    prompt's last block, the last tool and the last message's last block,
    four at most; results_contain, for each tool_use id, a text its
    tool_result holds, which did not fail, once the request has it;
    system_contains, a text the system prompt holds."""
    msgs = req.get("messages", [])
    if checks.get("tool_results"):
        for k, m in enumerate(msgs):
            content = m.get("content")
            if m.get("role") != "assistant" or not isinstance(content, list):
                continue
            uses = [b.get("id") for b in content if b.get("type") == "tool_use"]
            if not uses:
                continue
            nxt = msgs[k + 1] if k + 1 < len(msgs) else None
            got = [b.get("tool_use_id") for b in (nxt or {}).get("content", [])
                   if isinstance(b, dict) and b.get("type") == "tool_result"]
            if got != uses:
                return "tool_results %s do not answer tool_uses %s" % (got, uses)
        if last_ids:
            last = [m for m in msgs if m.get("role") == "assistant"]
            sent = [b.get("id") for b in last[-1].get("content", []) if b.get("type") == "tool_use"] if last else []
            if sent != last_ids:
                return "the last tool_uses %s are not those answered last, %s" % (sent, last_ids)
    if checks.get("cache_control"):
        def marked(b):
            return isinstance(b, dict) and "cache_control" in b
        system = req.get("system")
        tools = req.get("tools", [])
        if not (isinstance(system, list) and system and marked(system[-1])):
            return "no cache_control on the system prompt"
        if not (tools and marked(tools[-1])):
            return "no cache_control on the last tool"
        last = msgs[-1].get("content") if msgs else None
        if not (isinstance(last, list) and last and marked(last[-1])):
            return "no cache_control on the last message's last block"
        n = sum(1 for b in (system or []) if marked(b)) + sum(1 for t in tools if marked(t))
        n += sum(1 for m in msgs if isinstance(m.get("content"), list) for b in m["content"] if marked(b))
        if n > 4:
            return "%d cache_control breakpoints, more than 4" % n
    for tid, text in checks.get("results_contain", {}).items():
        for m in msgs:
            for b in (m.get("content") if isinstance(m.get("content"), list) else []):
                if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") == tid:
                    if text not in str(b.get("content", "")) or b.get("is_error"):
                        return "the result of %s does not hold %r, or failed" % (tid, text)
    want = checks.get("system_contains")
    if want:
        system = req.get("system")
        text = system if isinstance(system, str) else "".join(
            b.get("text", "") for b in (system or []) if isinstance(b, dict))
        if want not in text:
            return "the system prompt does not hold %r" % want
    return None


def expanded(answer):
    """An answer of the script with a text or tools answer made its
    events."""
    if "tools" in answer:
        return {"status": answer.get("status", 200),
                "events": tool_events(answer["tools"], answer.get("text"), answer.get("usage"),
                                      answer.get("model", "claude-sonnet-5-5"))}
    if "text" in answer:
        return {"status": answer.get("status", 200),
                "events": text_events(answer["text"], answer.get("delay", 0.0), answer.get("stop_reason", "end_turn"),
                                      answer.get("usage"), answer.get("model", "claude-sonnet-5-5"))}
    return answer


class Standin:
    """The stand-in: its script, the requests it got, and when it sent
    each event of the streams it answered (sent, (time, name) pairs)."""

    def __init__(self, script, key=None, log=None, checks=None):
        self.script = [expanded(a) for a in script]
        self.next = 0
        self.key = key
        self.log = log
        self.checks = checks or {}
        self.last_ids = []
        self.requests = []
        self.sent = []

    def app(self):
        """The stand-in as an aiohttp application."""
        from aiohttp import web

        async def handle(request):
            body = await request.read()
            rec = {"method": request.method, "path": request.path,
                   "headers": {k.lower(): v for k, v in request.headers.items()}, "body": body}
            self.requests.append(rec)
            if self.log:
                self.log(json.dumps(dict(rec, body=body.decode("utf-8", "replace"))))
            if request.method != "POST" or request.path not in ("/v1/messages", "/v1/messages/count_tokens"):
                return self.error(404, "not_found_error", "no such path: " + request.path)
            if self.key is not None and request.headers.get("x-api-key") != self.key:
                return self.error(401, "authentication_error", "invalid x-api-key")
            if request.path.endswith("/count_tokens"):
                return web.json_response({"input_tokens": len(body) // 4})
            if self.checks:
                try:
                    why = checked(json.loads(body), self.checks, self.last_ids)
                except ValueError as e:
                    why = "the body is not JSON: %s" % e
                if why:
                    if self.log:
                        self.log("standin: check failed: " + why)
                    return self.error(400, "invalid_request_error", "stand-in: " + why)
            if self.next >= len(self.script):
                return self.error(500, "api_error", "the stand-in's script has no answer %d" % (self.next + 1))
            answer = self.script[self.next]
            self.next += 1
            self.last_ids = tool_ids(answer)
            if "events" in answer:
                return await self.stream(request, answer)
            return web.Response(status=answer.get("status", 200), content_type="application/json",
                                body=json.dumps(answer.get("json", {})).encode())

        app = web.Application()
        app.router.add_route("*", "/{tail:.*}", handle)
        return app

    def error(self, status, kind, message):
        """A refusal in the API's form."""
        from aiohttp import web
        return web.Response(status=status, content_type="application/json",
                            body=json.dumps({"type": "error", "error": {"type": kind, "message": message}}).encode())

    async def stream(self, request, answer):
        """An answer of events, each sent after its delay."""
        from aiohttp import web
        out = web.StreamResponse(status=answer.get("status", 200))
        out.headers["Content-Type"] = "text/event-stream"
        out.headers["Cache-Control"] = "no-cache"
        await out.prepare(request)
        for e in answer["events"]:
            if e.get("delay"):
                await asyncio.sleep(e["delay"])
            await out.write(sse(e["event"], e.get("data", {})))
            self.sent.append((time.monotonic(), e["event"]))
        await out.write_eof()
        return out


async def serve(app, host, port):
    """app served on host and port; its runner, and the port it got (port
    0 is any free one)."""
    from aiohttp import web
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    await site.start()
    return runner, site._server.sockets[0].getsockname()[1]


def load_script(path):
    """The script in the file at path."""
    with open(path) as f:
        return json.load(f)


def main(argv):
    """The stand-in as a command, until stopped."""
    p = argparse.ArgumentParser(prog="standin.py", description="a stand-in for the Messages API")
    p.add_argument("--listen", required=True)
    p.add_argument("--script", required=True)
    p.add_argument("--key")
    a = p.parse_args(argv)
    host, _, port = a.listen.rpartition(":")
    s = Standin(load_script(a.script), a.key, log=lambda line: print(line, flush=True))

    async def run():
        await serve(s.app(), host, int(port))
        await asyncio.Event().wait()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
