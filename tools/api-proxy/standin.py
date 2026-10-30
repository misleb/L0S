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

An answer asked for past the script's end is a 500 that says so. With
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


def expanded(answer):
    """An answer of the script with a text answer made its events."""
    if "text" in answer:
        return {"status": answer.get("status", 200),
                "events": text_events(answer["text"], answer.get("delay", 0.0), answer.get("stop_reason", "end_turn"),
                                      answer.get("usage"), answer.get("model", "claude-sonnet-5-5"))}
    return answer


class Standin:
    """The stand-in: its script, the requests it got, and when it sent
    each event of the streams it answered (sent, (time, name) pairs)."""

    def __init__(self, script, key=None, log=None):
        self.script = [expanded(a) for a in script]
        self.next = 0
        self.key = key
        self.log = log
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
            if self.next >= len(self.script):
                return self.error(500, "api_error", "the stand-in's script has no answer %d" % (self.next + 1))
            answer = self.script[self.next]
            self.next += 1
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
