"""proxy.py -- the board's way to a model's API until L0S speaks TLS
(roadmap 0048): plain HTTP from the board on the local network, forwarded
over HTTPS with the host's key.

  proxy.py --listen ADDR:PORT --token-file FILE [--upstream URL] [--usage FILE]
           [--backup DIR] [--builder-dir DIR] [--builder-model M] [--builder-effort E]
  proxy.py --day [YYYY-MM-DD] [--usage FILE]

It listens on ADDR, which must be a loopback or a private (RFC 1918)
address, never 0.0.0.0, and takes POST /v1/messages and
/v1/messages/count_tokens, PUT and GET /backup, POST /build and GET
/build/NAME/image, and nothing else
(404). A request without Authorization: Bearer TOKEN, the first line of
the token file, is 401.

/backup keeps the agent's home (roadmap 0044) in DIR, build/proxy/backup
unless given: a PUT's body, the home as a cpio archive (cpio.py), is
unpacked into DIR/home, replacing it whole, and kept as
DIR/archive/STAMP.cpio; one that is not a home's archive, or names a
path outside it, is 400 and changes nothing. A GET answers DIR/home
packed as it is now, so a copy edited on the host goes back; 404 if
there is none.

POST /build, {"name": NAME, "prompt": TEXT}, has an app of the agent's
built (roadmap 0045) by a Claude Code session on this host, the app's
own, in --builder-dir (~/.local/state/l0s-builder unless given), on
--builder-model (claude-opus-5-5) at --builder-effort (medium), logged in
as this host's Claude Code is, never with ANTHROPIC_API_KEY (builder.py).
The answer is server-sent events: progress, each {"text"}, as the
session works, then done, {"summary", "size"}, or failed, {"why"}; a
comment every 15 s it says nothing. GET /build/NAME/image is the program
then. A name that is not a program's is 400; a build while another runs
409, as one runs at a time.

For the API's paths:
Otherwise its body goes upstream (https://api.anthropic.com unless given)
as it is, with its content-type, anthropic-version and anthropic-beta and
no other header of the board's, and x-api-key from ANTHROPIC_API_KEY,
without which it will not start. The answer's status and content-type
come back, and its body as each piece comes, never gathered.

What each answer spent is a JSON line in the usage file (build/proxy/
usage.jsonl unless given): time, path, model, status and the four counts.
Nothing is refused for it. --day totals a day's lines, today's (UTC)
unless one is given. make proxy-run runs it with build/proxy/token."""

import argparse
import asyncio
import hmac
import ipaddress
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's own directory out

import builder as builders  # noqa: E402
import cpio  # noqa: E402
import usage  # noqa: E402

DEFAULT_USAGE = os.path.join(HERE, "..", "..", "build", "proxy", "usage.jsonl")
DEFAULT_BACKUP = os.path.join(HERE, "..", "..", "build", "proxy", "backup")
DEFAULT_BUILDER = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "l0s-builder")
DEFAULT_UPSTREAM = "https://api.anthropic.com"
PATHS = ("/v1/messages", "/v1/messages/count_tokens")
PASSED = ("content-type", "anthropic-version", "anthropic-beta")
PRIVATE = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]


def listen_address(text):
    """The host and port ADDR:PORT names, or why it may not be listened
    on: the host must be an address, loopback or private."""
    host, sep, port = text.rpartition(":")
    if not sep or not port.isdigit() or not 0 < int(port) < 65536:
        return None, "not ADDR:PORT: %s" % text
    host = host.strip("[]")
    try:
        a = ipaddress.ip_address(host)
    except ValueError:
        return None, "not an address: %s" % host
    if a.is_loopback or (a.version == 4 and any(a in n for n in PRIVATE)):
        return (host, int(port)), ""
    return None, "%s is neither loopback nor private (RFC 1918); the proxy listens on no other" % host


def token_of(path):
    """The token, the first line of the file at path, or why there is
    none."""
    try:
        with open(path) as f:
            t = f.readline().strip()
    except OSError as e:
        return None, "%s: %s" % (path, e.strerror)
    if not t:
        return None, "%s: no token in it" % path
    return t, ""


def error_body(kind, message):
    """An answer's body for a refusal, in the API's own form."""
    return json.dumps({"type": "error", "error": {"type": kind, "message": message}}).encode()


def bearer_ok(header, token):
    """Whether an Authorization header carries the token."""
    if not header.startswith("Bearer "):
        return False
    return hmac.compare_digest(header[7:].strip().encode(), token.encode())


def backup_put(root, body, when):
    """The archive body, the agent's home, unpacked into root/home, which
    it replaces whole, and kept as root/archive/STAMP.cpio, STAMP from the
    time when: how many entries it held. ValueError, before anything is
    written, if it is not a home's archive."""
    entries = cpio.unpack(body)
    home, new, old = (os.path.join(root, n) for n in ("home", "home.new", "home.old"))
    for p in (new, old):
        shutil.rmtree(p, ignore_errors=True)
    cpio.write_tree(new, entries)
    if os.path.isdir(home):
        os.rename(home, old)
    os.rename(new, home)
    shutil.rmtree(old, ignore_errors=True)
    archive = os.path.join(root, "archive")
    os.makedirs(archive, exist_ok=True)
    stamp = when.replace("-", "").replace(":", "")
    with open(os.path.join(archive, stamp + ".cpio"), "wb") as f:
        f.write(body)
    return len(entries)


def backup_get(root):
    """root/home packed as an archive, as it is now, or None if there is
    none."""
    home = os.path.join(root, "home")
    if not os.path.isdir(home):
        return None
    return cpio.pack(cpio.gather(home))


def sse(kind, data):
    """One server-sent event of kind, its data data as JSON."""
    return ("event: %s\ndata: %s\n\n" % (kind, json.dumps(data))).encode()


def make_app(token, upstream, key, usage_path, log=None, backup_dir=None, builder=None, beat=15.0):
    """The proxy as an aiohttp application: the token boards must give,
    the upstream's base URL, the key it adds, and the usage file. log, if
    given, is called with each usage line too. With backup_dir, it also
    keeps the agent's home there: PUT /backup and GET /backup. With
    builder (builder.py's Builder), it builds the agent's apps: POST
    /build and GET /build/NAME/image, a comment sent every beat seconds
    a build says nothing, so the board's connection is not idle."""
    from aiohttp import ClientError, ClientSession, ClientTimeout, web
    client = web.AppKey("client", ClientSession)

    async def start(app):
        app[client] = ClientSession(timeout=ClientTimeout(total=None, sock_connect=30, sock_read=600),
                                      auto_decompress=True)

    async def stop(app):
        await app[client].close()

    def refuse(status, kind, message):
        return web.Response(status=status, body=error_body(kind, message), content_type="application/json")

    async def backup(request):
        if not bearer_ok(request.headers.get("Authorization", ""), token):
            return refuse(401, "authentication_error", "the proxy refused this board's token")
        if request.method == "GET":
            body = backup_get(backup_dir)
            if body is None:
                return refuse(404, "not_found_error", "the host has no backup of the agent's home")
            return web.Response(status=200, body=body, content_type="application/octet-stream")
        try:
            n = backup_put(backup_dir, await request.read(), usage.stamp())
        except ValueError as e:
            return refuse(400, "invalid_request_error", "the backup is not a home's archive: %s" % e)
        print("proxy: backup of %d entries in %s" % (n, os.path.join(backup_dir, "home")), file=sys.stderr, flush=True)
        return web.Response(status=200, body=json.dumps({"entries": n}).encode(), content_type="application/json")

    async def build(request):
        if not bearer_ok(request.headers.get("Authorization", ""), token):
            return refuse(401, "authentication_error", "the proxy refused this board's token")
        try:
            ask = json.loads(await request.read())
        except ValueError:
            ask = None
        if not isinstance(ask, dict) or not isinstance(ask.get("prompt"), str) or not ask["prompt"].strip():
            return refuse(400, "invalid_request_error", "a build is {\"name\": NAME, \"prompt\": TEXT}")
        name = ask.get("name")
        if not builders.name_ok(name):
            return refuse(400, "invalid_request_error", "an app's name is lowercase letters, digits and -, a letter first, at most 32")
        if builder.busy:
            return refuse(409, "busy_error", "another app is being built; one is built at a time")
        builder.busy = True
        try:
            out = web.StreamResponse(status=200)
            out.headers["Content-Type"] = "text/event-stream"
            await out.prepare(request)
            events = asyncio.Queue()

            async def pump():
                try:
                    async for e in builder.build(name, ask["prompt"]):
                        await events.put(e)
                except Exception as e:  # a session that could not start
                    await events.put(("failed", "the session could not run: %s" % e))
                await events.put(None)

            task = asyncio.create_task(pump())
            try:
                while True:
                    try:
                        e = await asyncio.wait_for(events.get(), beat)
                    except asyncio.TimeoutError:
                        await out.write(b": building\n\n")
                        continue
                    if e is None:
                        break
                    kind, text = e
                    if kind == "done":
                        await out.write(sse("done", {"summary": text, "size": len(builder.image(name) or b"")}))
                    elif kind == "failed":
                        await out.write(sse("failed", {"why": text}))
                    else:
                        await out.write(sse("progress", {"text": text}))
                    if kind != "progress":
                        print("proxy: build %s: %s" % (name, kind), file=sys.stderr, flush=True)
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
            await out.write_eof()
            return out
        finally:
            builder.busy = False

    async def image(request, name):
        if not bearer_ok(request.headers.get("Authorization", ""), token):
            return refuse(401, "authentication_error", "the proxy refused this board's token")
        body = builder.image(name) if builders.name_ok(name) else None
        if body is None:
            return refuse(404, "not_found_error", "no app %s has been built" % name)
        return web.Response(status=200, body=body, content_type="application/octet-stream")

    async def handle(request):
        if request.path == "/backup" and backup_dir and request.method in ("GET", "PUT"):
            return await backup(request)
        if builder and request.path == "/build" and request.method == "POST":
            return await build(request)
        parts = request.path.split("/")
        if builder and request.method == "GET" and len(parts) == 4 and parts[1] == "build" and parts[3] == "image":
            return await image(request, parts[2])
        if request.method != "POST" or request.path not in PATHS:
            return refuse(404, "not_found_error", "the proxy forwards only POST %s" % " and ".join(PATHS))
        if not bearer_ok(request.headers.get("Authorization", ""), token):
            return refuse(401, "authentication_error", "the proxy refused this board's token")
        body = await request.read()
        headers = {h: request.headers[h] for h in PASSED if h in request.headers}
        headers["x-api-key"] = key
        # No content coding, so each piece is passed on as it comes.
        headers["Accept-Encoding"] = "identity"
        model = usage.request_model(body)
        url = upstream.rstrip("/") + request.path
        try:
            up = await app[client].post(url, data=body, headers=headers)
        except Exception as e:
            return refuse(502, "api_error", "the proxy could not reach %s: %s" % (upstream, e))
        async with up:
            ctype = up.headers.get("Content-Type", "application/octet-stream")
            out = web.StreamResponse(status=up.status)
            out.headers["Content-Type"] = ctype
            await out.prepare(request)
            streamed = ctype.startswith("text/event-stream")
            counter = usage.StreamUsage()
            whole = []
            cut = False
            try:
                async for piece in up.content.iter_any():
                    if streamed:
                        counter.feed(piece)
                    else:
                        whole.append(piece)
                    await out.write(piece)
            except ClientError as e:
                # The upstream's answer broke off: the board's connection
                # is closed, not ended, so it sees the answer cut short.
                print("proxy: the answer from %s broke off: %s" % (upstream, e), file=sys.stderr, flush=True)
                cut = True
            finally:
                if streamed:
                    counter.feed(b"\n\n")
                    spent = counter.usage
                else:
                    spent = usage.json_usage(b"".join(whole))
                line = usage.log_line(usage.stamp(), request.path, model or counter.model, up.status, spent)
                write_usage(usage_path, line)
                if log:
                    log(line)
            if cut:
                request.transport.close()
                return out
            await out.write_eof()
            return out

    app = web.Application(client_max_size=64 * 1024 * 1024)
    app.on_startup.append(start)
    app.on_cleanup.append(stop)
    app.router.add_route("*", "/{tail:.*}", handle)
    return app


def write_usage(path, line):
    """line added to the usage file at path, its directory made if need
    be."""
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    with open(path, "a") as f:
        f.write(line + "\n")


async def serve(app, host, port):
    """app served on host and port until the process is stopped."""
    from aiohttp import web
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, host, port).start()
    return runner


def day(path, when):
    """The day's totals, as a line: 0 once said, 1 if the file cannot be
    read."""
    try:
        with open(path) as f:
            lines = f.readlines()
    except FileNotFoundError:
        lines = []
    except OSError as e:
        print("proxy: %s: %s" % (path, e.strerror), file=sys.stderr)
        return 1
    print(usage.totals_text(usage.day_totals(lines, when or usage.stamp()[:10])))
    return 0


def main(argv):
    """The proxy as asked: the exit status."""
    p = argparse.ArgumentParser(prog="proxy.py", description="the board's proxy to a model's API")
    p.add_argument("--listen")
    p.add_argument("--token-file")
    p.add_argument("--upstream", default=DEFAULT_UPSTREAM)
    p.add_argument("--usage", default=DEFAULT_USAGE)
    p.add_argument("--backup", default=DEFAULT_BACKUP)
    p.add_argument("--builder-dir", default=DEFAULT_BUILDER)
    p.add_argument("--builder-model", default=builders.DEFAULT_MODEL)
    p.add_argument("--builder-effort", default=builders.DEFAULT_EFFORT)
    p.add_argument("--day", nargs="?", const="", default=None, metavar="YYYY-MM-DD")
    a = p.parse_args(argv)
    if a.day is not None:
        return day(a.usage, a.day)
    if not a.listen or not a.token_file:
        print("proxy: --listen ADDR:PORT and --token-file FILE are needed", file=sys.stderr)
        return 2
    where, why = listen_address(a.listen)
    if where is None:
        print("proxy: " + why, file=sys.stderr)
        return 1
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        print("proxy: ANTHROPIC_API_KEY is not set; the proxy adds it to every request", file=sys.stderr)
        return 1
    token, why = token_of(a.token_file)
    if token is None:
        print("proxy: " + why, file=sys.stderr)
        return 1
    b = builders.Builder(a.builder_dir, a.builder_model, a.builder_effort)
    app = make_app(token, a.upstream, key, a.usage, log=lambda line: print(line, flush=True), backup_dir=a.backup,
                   builder=b)

    async def run():
        await serve(app, where[0], where[1])
        print("proxy: on %s:%d, to %s, usage in %s, the agent's backup in %s, its apps built in %s by %s"
              % (where[0], where[1], a.upstream, a.usage, a.backup, a.builder_dir, a.builder_model), flush=True)
        await asyncio.Event().wait()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
