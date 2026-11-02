"""test_proxy.py -- the proxy's tests, against the stand-in on this host's
loopback: no key and no network. Run by make test with the venv's Python
(build/proxy/venv), which has aiohttp."""

import asyncio
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aiohttp  # noqa: E402

import builder as builders  # noqa: E402
import cpio  # noqa: E402
import proxy  # noqa: E402
import standin  # noqa: E402
import usage  # noqa: E402

TOKEN = "0123456789abcdef0123456789abcdef"
KEY = "sk-standin-key"
REQ = json.dumps({"model": "claude-sonnet-5-5", "max_tokens": 64, "stream": True,
                  "messages": [{"role": "user", "content": "hi"}]}).encode()


class Proxied(unittest.IsolatedAsyncioTestCase):
    """The stand-in with script, and the proxy in front of it."""

    script = []

    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.usage = os.path.join(self.tmp.name, "usage.jsonl")
        self.standin = standin.Standin(self.script, key=KEY)
        self.up_runner, up_port = await standin.serve(self.standin.app(), "127.0.0.1", 0)
        self.backup = os.path.join(self.tmp.name, "backup")
        app = proxy.make_app(TOKEN, "http://127.0.0.1:%d" % up_port, KEY, self.usage, backup_dir=self.backup)
        self.runner, port = await standin.serve(app, "127.0.0.1", 0)
        self.base = "http://127.0.0.1:%d" % port
        self.client = aiohttp.ClientSession()

    async def asyncTearDown(self):
        await self.client.close()
        await self.runner.cleanup()
        await self.up_runner.cleanup()
        self.tmp.cleanup()

    def auth(self, token=TOKEN, **more):
        h = {"Authorization": "Bearer " + token, "content-type": "application/json",
             "anthropic-version": "2023-06-01"}
        h.update(more)
        return h

    def usage_lines(self):
        with open(self.usage) as f:
            return [json.loads(line) for line in f]


class Refusals(Proxied):
    script = [{"json": {"usage": {"input_tokens": 1, "output_tokens": 1}}}]

    async def test_no_token(self):
        async with self.client.post(self.base + "/v1/messages", data=REQ) as r:
            self.assertEqual(r.status, 401)
            body = await r.json()
        self.assertEqual(body["error"]["message"], "the proxy refused this board's token")
        self.assertEqual(self.standin.requests, [])

    async def test_wrong_token(self):
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=self.auth("f" * 32)) as r:
            self.assertEqual(r.status, 401)
        self.assertEqual(self.standin.requests, [])

    async def test_other_path(self):
        async with self.client.post(self.base + "/v1/models", data=REQ, headers=self.auth()) as r:
            self.assertEqual(r.status, 404)
        self.assertEqual(self.standin.requests, [])

    async def test_get(self):
        async with self.client.get(self.base + "/v1/messages", headers=self.auth()) as r:
            self.assertEqual(r.status, 404)
        self.assertEqual(self.standin.requests, [])


class Forwarding(Proxied):
    script = [{"json": {"id": "msg_1", "usage": {"input_tokens": 12, "output_tokens": 5,
                                                  "cache_creation_input_tokens": 3, "cache_read_input_tokens": 7}}}]

    async def test_key_added_token_not_passed(self):
        h = self.auth(**{"anthropic-beta": "prompt-caching-2024-07-31", "X-Board": "secret", "Cookie": "c=1"})
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=h) as r:
            self.assertEqual(r.status, 200)
            self.assertEqual((await r.json())["id"], "msg_1")
        got = self.standin.requests[0]
        self.assertEqual(got["headers"]["x-api-key"], KEY)
        self.assertEqual(got["headers"]["anthropic-version"], "2023-06-01")
        self.assertEqual(got["headers"]["anthropic-beta"], "prompt-caching-2024-07-31")
        self.assertNotIn("authorization", got["headers"])
        self.assertNotIn("x-board", got["headers"])
        self.assertNotIn("cookie", got["headers"])
        self.assertNotIn(TOKEN, json.dumps({k: v for k, v in got["headers"].items()}))
        self.assertEqual(got["body"], REQ)

    async def test_json_usage_line(self):
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=self.auth()) as r:
            await r.read()
        [line] = self.usage_lines()
        self.assertEqual(line["path"], "/v1/messages")
        self.assertEqual(line["model"], "claude-sonnet-5-5")
        self.assertEqual(line["status"], 200)
        self.assertEqual((line["input_tokens"], line["output_tokens"], line["cache_creation_input_tokens"],
                          line["cache_read_input_tokens"]), (12, 5, 3, 7))

    async def test_count_tokens(self):
        async with self.client.post(self.base + "/v1/messages/count_tokens", data=REQ, headers=self.auth()) as r:
            self.assertEqual(r.status, 200)
            self.assertEqual((await r.json())["input_tokens"], len(REQ) // 4)


class Streaming(Proxied):
    script = [{"text": ["one ", "two ", "three"], "delay": 0.3,
               "usage": {"input_tokens": 20, "output_tokens": 9, "cache_read_input_tokens": 4}}]

    async def test_first_event_before_last_is_sent(self):
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=self.auth()) as r:
            self.assertEqual(r.status, 200)
            self.assertTrue(r.headers["Content-Type"].startswith("text/event-stream"))
            first = await r.content.readuntil(b"\n\n")
            seen_at = time.monotonic()
            sent_then = [name for _, name in self.standin.sent]
            rest = await r.read()
        self.assertTrue(first.startswith(b"event: message_start"))
        self.assertNotIn("message_stop", sent_then)
        last_sent = self.standin.sent[-1][0]
        self.assertGreater(last_sent - seen_at, 0.5)
        self.assertIn(b"event: message_stop", rest)

    async def test_stream_usage_line(self):
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=self.auth()) as r:
            await r.read()
        [line] = self.usage_lines()
        self.assertEqual((line["input_tokens"], line["output_tokens"], line["cache_creation_input_tokens"],
                          line["cache_read_input_tokens"]), (20, 9, 0, 4))


class Upstream(Proxied):
    script = [{"status": 429, "json": {"type": "error", "error": {"type": "rate_limit_error", "message": "slow down"}}},
              {"status": 500, "json": {"type": "error", "error": {"type": "api_error", "message": "broken"}}}]

    async def test_429_and_500_passed(self):
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=self.auth()) as r:
            self.assertEqual(r.status, 429)
            self.assertEqual((await r.json())["error"]["message"], "slow down")
        async with self.client.post(self.base + "/v1/messages", data=REQ, headers=self.auth()) as r:
            self.assertEqual(r.status, 500)
            self.assertEqual((await r.json())["error"]["type"], "api_error")
        self.assertEqual([line["status"] for line in self.usage_lines()], [429, 500])


class Usage(unittest.TestCase):
    def test_stream_in_pieces(self):
        body = b"".join(standin.sse(e["event"], e["data"])
                        for e in standin.text_events(["a", "b"], usage={"input_tokens": 3, "output_tokens": 8}))
        s = usage.StreamUsage()
        for i in range(0, len(body), 7):
            s.feed(body[i:i + 7])
        self.assertEqual(s.usage["input_tokens"], 3)
        self.assertEqual(s.usage["output_tokens"], 8)
        self.assertEqual(s.model, "claude-sonnet-5-5")

    def test_crlf_and_comments(self):
        body = (b": hello\r\nevent: message_start\r\ndata: {\"message\":{\"usage\":{\"input_tokens\":4}}}\r\n\r\n"
                b"event: message_delta\r\ndata: {\"usage\":{\"output_tokens\":6}}\r\n\r\n")
        u = usage.stream_usage(body)
        self.assertEqual((u["input_tokens"], u["output_tokens"]), (4, 6))

    def test_json(self):
        self.assertEqual(usage.json_usage(b'{"usage":{"input_tokens":2,"output_tokens":3}}')["output_tokens"], 3)
        self.assertEqual(usage.json_usage(b"not json"), usage.zero())

    def test_log_line(self):
        line = usage.log_line("2026-10-29T10:00:00Z", "/v1/messages", "m", 200, dict(usage.zero(), input_tokens=5))
        self.assertEqual(line, '{"time":"2026-10-29T10:00:00Z","path":"/v1/messages","model":"m","status":200,'
                               '"input_tokens":5,"output_tokens":0,"cache_creation_input_tokens":0,'
                               '"cache_read_input_tokens":0}')

    def test_day_totals(self):
        u = dict(usage.zero(), input_tokens=10, output_tokens=2, cache_read_input_tokens=1)
        lines = [usage.log_line("2026-10-29T10:00:00Z", "/v1/messages", "m", 200, u),
                 usage.log_line("2026-10-29T23:59:59Z", "/v1/messages", "m", 200, u),
                 usage.log_line("2026-10-30T00:00:00Z", "/v1/messages", "m", 200, u),
                 "garbage"]
        t = usage.day_totals(lines, "2026-10-29")
        self.assertEqual((t["answers"], t["input_tokens"], t["output_tokens"], t["cache_read_input_tokens"]),
                         (2, 20, 4, 2))
        self.assertEqual(usage.totals_text(t),
                         "2026-10-29: 2 answers, input 20, output 4, cache written 0, cache read 2")

    def test_day_command(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "usage.jsonl")
            proxy.write_usage(path, usage.log_line("2026-10-29T10:00:00Z", "/v1/messages", "m", 200,
                                                   dict(usage.zero(), output_tokens=7)))
            r = run_proxy(["--day", "2026-10-29", "--usage", path])
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "2026-10-29: 1 answers, input 0, output 7, cache written 0, cache read 0\n")


def run_proxy(args, env=None):
    """proxy.py run with args, as a command: its result."""
    e = dict(os.environ)
    e.pop("ANTHROPIC_API_KEY", None)
    e.update(env or {})
    return subprocess.run([sys.executable, "-I", os.path.join(HERE, "proxy.py")] + args,
                          capture_output=True, text=True, env=e, timeout=30)


class Starting(unittest.TestCase):
    def test_addresses(self):
        self.assertEqual(proxy.listen_address("127.0.0.1:8765")[0], ("127.0.0.1", 8765))
        self.assertEqual(proxy.listen_address("192.168.1.10:8765")[0], ("192.168.1.10", 8765))
        self.assertEqual(proxy.listen_address("10.1.2.3:1")[0], ("10.1.2.3", 1))
        self.assertEqual(proxy.listen_address("172.31.0.1:80")[0], ("172.31.0.1", 80))
        self.assertEqual(proxy.listen_address("[::1]:80")[0], ("::1", 80))
        for bad in ("0.0.0.0:8765", "8.8.8.8:80", "172.32.0.1:80", "localhost:80", "127.0.0.1", "127.0.0.1:0"):
            self.assertIsNone(proxy.listen_address(bad)[0], bad)

    def test_refuses_any_address(self):
        with tempfile.NamedTemporaryFile("w") as t:
            t.write(TOKEN + "\n")
            t.flush()
            r = run_proxy(["--listen", "0.0.0.0:8765", "--token-file", t.name], {"ANTHROPIC_API_KEY": KEY})
        self.assertEqual(r.returncode, 1)
        self.assertIn("0.0.0.0 is neither loopback nor private", r.stderr)

    def test_refuses_without_key(self):
        with tempfile.NamedTemporaryFile("w") as t:
            t.write(TOKEN + "\n")
            t.flush()
            r = run_proxy(["--listen", "127.0.0.1:8765", "--token-file", t.name])
        self.assertEqual(r.returncode, 1)
        self.assertIn("ANTHROPIC_API_KEY is not set", r.stderr)

    def test_bearer(self):
        self.assertTrue(proxy.bearer_ok("Bearer " + TOKEN, TOKEN))
        self.assertFalse(proxy.bearer_ok("Basic " + TOKEN, TOKEN))
        self.assertFalse(proxy.bearer_ok("Bearer ", TOKEN))
        self.assertFalse(proxy.bearer_ok(TOKEN, TOKEN))


def marked(block):
    """block with a cache breakpoint."""
    return dict(block, cache_control={"type": "ephemeral"})


def good_request():
    """A request that passes every check: a tool used and answered, the
    breakpoints where they should be, the rules in the system prompt."""
    return {"system": [marked({"type": "text", "text": "rules: keep your files in your home"})],
            "tools": [{"name": "a"}, marked({"name": "b"})],
            "messages": [{"role": "user", "content": [{"type": "text", "text": "hi"}]},
                         {"role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "a", "input": {}},
                                                           {"type": "tool_use", "id": "t2", "name": "b", "input": {}}]},
                         {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "x"},
                                                      marked({"type": "tool_result", "tool_use_id": "t2", "content": "y"})]}]}


ALL = {"tool_results": True, "cache_control": True, "system_contains": "keep your files"}


class Checks(unittest.TestCase):
    def test_good(self):
        self.assertIsNone(standin.checked(good_request(), ALL, ["t1", "t2"]))

    def test_results_out_of_order(self):
        r = good_request()
        r["messages"][2]["content"].reverse()
        self.assertIn("do not answer", standin.checked(r, ALL, ["t1", "t2"]))

    def test_not_the_last_sent(self):
        self.assertIn("not those answered last", standin.checked(good_request(), ALL, ["t9"]))

    def test_no_breakpoint(self):
        r = good_request()
        del r["tools"][1]["cache_control"]
        self.assertEqual(standin.checked(r, ALL, []), "no cache_control on the last tool")

    def test_rules_missing(self):
        r = good_request()
        r["system"][0]["text"] = "nothing"
        self.assertIn("does not hold", standin.checked(r, ALL, []))

    def test_results_contain(self):
        self.assertIsNone(standin.checked(good_request(), {"results_contain": {"t2": "y"}}, []))
        self.assertIn("does not hold", standin.checked(good_request(), {"results_contain": {"t1": "z"}}, []))

    def test_results_failed(self):
        req = good_request()
        self.assertIn("did not fail", standin.checked(req, {"results_failed": {"t2": "y"}}, []))

    def test_system_contains_list(self):
        req = good_request()
        system = "".join(b["text"] for b in req["system"])
        self.assertIsNone(standin.checked(req, {"system_contains": [system[:5], system[-5:]]}, []))
        self.assertIn("does not hold", standin.checked(req, {"system_contains": [system[:5], "nowhere"]}, []))

    def test_system_contains_at(self):
        at = {"system_contains_at": {"2": ["nowhere"]}}
        self.assertIsNone(standin.checked(good_request(), at, [], 1))
        self.assertIn("request 2 does not hold", standin.checked(good_request(), at, [], 2))

    def test_messages_contain_at(self):
        said = good_request()["messages"][0]["content"][0]["text"]
        at = {"messages_contain_at": {"2": [said[:4]], "3": ["nowhere"]}}
        self.assertIsNone(standin.checked(good_request(), at, [], 2))
        self.assertIn("messages of request 3 do not hold", standin.checked(good_request(), at, [], 3))

    def test_tool_events(self):
        ev = standin.tool_events([{"id": "t1", "name": "make_dir", "input": {"path": "notes"}}], text="Making it.")
        pieces = "".join(e["data"]["delta"]["partial_json"] for e in ev
                         if e["event"] == "content_block_delta" and e["data"]["delta"]["type"] == "input_json_delta")
        self.assertEqual(json.loads(pieces), {"path": "notes"})
        self.assertEqual(standin.tool_ids({"events": ev}), ["t1"])
        self.assertEqual(ev[-2]["data"]["delta"]["stop_reason"], "tool_use")


HOME = [("CLAUDE.md", b"# Rules\n"), ("memory", None), ("memory/MEMORY.md", b"# Memory\n"),
        (".history", None), (".history/log", b"1 0 c new /h/x\n")]


class Cpio(unittest.TestCase):
    def test_round_trip(self):
        self.assertEqual(cpio.unpack(cpio.pack(HOME)), HOME)

    def test_empty(self):
        self.assertEqual(cpio.unpack(cpio.pack([])), [])

    def test_refuses_outside(self):
        for name in ("/etc/passwd", "../x", "memory/../../x"):
            with self.assertRaises(ValueError):
                cpio.unpack(cpio.pack([(name, b"x")]))

    def test_refuses_not_one(self):
        with self.assertRaises(ValueError):
            cpio.unpack(b"not an archive")
        with self.assertRaises(ValueError):
            cpio.unpack(cpio.pack(HOME)[:200])

    def test_gather_write(self):
        with tempfile.TemporaryDirectory() as d:
            cpio.write_tree(os.path.join(d, "h"), HOME)
            got = cpio.gather(os.path.join(d, "h"))
        self.assertEqual(sorted(got, key=lambda e: e[0]), sorted(HOME, key=lambda e: e[0]))


class Backup(Proxied):
    script = []

    async def test_put_then_get(self):
        async with self.client.put(self.base + "/backup", data=cpio.pack(HOME), headers=self.auth()) as r:
            self.assertEqual(r.status, 200)
            self.assertEqual((await r.json())["entries"], 5)
        with open(os.path.join(self.backup, "home", "memory", "MEMORY.md"), "rb") as f:
            self.assertEqual(f.read(), b"# Memory\n")
        self.assertEqual(len(os.listdir(os.path.join(self.backup, "archive"))), 1)
        async with self.client.get(self.base + "/backup", headers=self.auth()) as r:
            self.assertEqual(r.status, 200)
            got = cpio.unpack(await r.read())
        self.assertEqual(sorted(got, key=lambda e: e[0]), sorted(HOME, key=lambda e: e[0]))
        self.assertEqual(self.standin.requests, [])

    async def test_put_replaces(self):
        for home in (HOME, [("CLAUDE.md", b"# New\n")]):
            async with self.client.put(self.base + "/backup", data=cpio.pack(home), headers=self.auth()) as r:
                self.assertEqual(r.status, 200)
        self.assertEqual(os.listdir(os.path.join(self.backup, "home")), ["CLAUDE.md"])

    async def test_edited_on_host(self):
        async with self.client.put(self.base + "/backup", data=cpio.pack(HOME), headers=self.auth()) as r:
            self.assertEqual(r.status, 200)
        with open(os.path.join(self.backup, "home", "CLAUDE.md"), "wb") as f:
            f.write(b"# Edited\n")
        async with self.client.get(self.base + "/backup", headers=self.auth()) as r:
            self.assertIn(("CLAUDE.md", b"# Edited\n"), cpio.unpack(await r.read()))

    async def test_no_token(self):
        async with self.client.put(self.base + "/backup", data=cpio.pack(HOME)) as r:
            self.assertEqual(r.status, 401)
        async with self.client.get(self.base + "/backup", headers=self.auth("f" * 32)) as r:
            self.assertEqual(r.status, 401)
        self.assertFalse(os.path.exists(self.backup))

    async def test_none_yet(self):
        async with self.client.get(self.base + "/backup", headers=self.auth()) as r:
            self.assertEqual(r.status, 404)
            self.assertIn("no backup", (await r.json())["error"]["message"])

    async def test_bad_archive(self):
        async with self.client.put(self.base + "/backup", data=cpio.pack([("../x", b"x")]), headers=self.auth()) as r:
            self.assertEqual(r.status, 400)
        self.assertFalse(os.path.exists(os.path.join(self.backup, "home")))

    async def test_other_method(self):
        async with self.client.post(self.base + "/backup", data=b"", headers=self.auth()) as r:
            self.assertEqual(r.status, 404)


FAKE = os.path.join(HERE, "fake_claude.py")


def events_of(body):
    """A server-sent body's events, (kind, data) each, and its comments."""
    out, comments = [], 0
    for block in body.decode().split("\n\n"):
        if block.startswith(":"):
            comments += 1
        elif block.strip():
            fields = dict(line.split(": ", 1) for line in block.split("\n"))
            out.append((fields["event"], json.loads(fields["data"])))
    return out, comments


class Building(unittest.IsolatedAsyncioTestCase):
    """The proxy with a builder whose claude is fake_claude.py; with
    with_repo, its worktrees made of a repository of its own, never
    L0S's."""

    with_repo = False

    def repo_made(self):
        """A repository of one commit, lib.txt, in the test's directory."""
        r = os.path.join(self.tmp.name, "repo")
        os.makedirs(r)
        with open(os.path.join(r, "lib.txt"), "w") as f:
            f.write("a library\n")
        for args in (["init", "-q", "-b", "main"], ["config", "user.name", "Test"],
                     ["config", "user.email", "test@example.com"], ["add", "lib.txt"], ["commit", "-q", "-m", "one"]):
            subprocess.run(["git", "-C", r] + args, check=True, capture_output=True)
        return r

    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, "claude.jsonl")
        self.env = {"FAKE_CLAUDE_LOG": self.log, "ANTHROPIC_API_KEY": KEY}
        self.saved = {k: os.environ.get(k) for k in list(self.env) + ["FAKE_CLAUDE_KEY_SOURCE", "FAKE_CLAUDE_BUILD",
                                                                      "FAKE_CLAUDE_SLEEP", "FAKE_CLAUDE_EDIT"]}
        os.environ.update(self.env)
        self.repo = self.repo_made() if self.with_repo else None
        self.builder = builders.Builder(os.path.join(self.tmp.name, "apps"), cli=[sys.executable, FAKE], repo=self.repo)
        app = proxy.make_app(TOKEN, "http://127.0.0.1:9", KEY, os.path.join(self.tmp.name, "usage.jsonl"),
                             builder=self.builder, beat=0.05)
        self.runner, port = await standin.serve(app, "127.0.0.1", 0)
        self.base = "http://127.0.0.1:%d" % port
        self.client = aiohttp.ClientSession()

    async def asyncTearDown(self):
        await self.client.close()
        await self.runner.cleanup()
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def auth(self, token=TOKEN):
        return {"Authorization": "Bearer " + token, "content-type": "application/json"}

    async def build(self, name="clock", prompt="a clock", token=TOKEN):
        async with self.client.post(self.base + "/build", data=json.dumps({"name": name, "prompt": prompt}),
                                    headers=self.auth(token)) as r:
            return r.status, await r.read()

    def started(self):
        with open(self.log) as f:
            return [json.loads(line) for line in f]

    async def test_built_then_image(self):
        status, body = await self.build()
        self.assertEqual(status, 200)
        events, _ = events_of(body)
        self.assertEqual([k for k, _ in events], ["progress", "progress", "progress", "done"])
        self.assertEqual(events[2][1]["text"], "Bash l0s-app-build clock")
        self.assertEqual(events[-1][1], {"summary": "built clock", "size": 11})
        async with self.client.get(self.base + "/build/clock/image", headers=self.auth()) as r:
            self.assertEqual((r.status, await r.read()), (200, b"\x7fELFa clock"))

    async def test_session_resumed(self):
        await self.build()
        await self.build(prompt="make it blue")
        first, second = (s["argv"] for s in self.started())
        session = first[first.index("--session-id") + 1]
        self.assertEqual(second[second.index("--resume") + 1], session)
        self.assertNotIn("--session-id", second)

    async def test_command_and_environment(self):
        await self.build()
        s = self.started()[0]
        self.assertEqual(s["api_env"], [])
        self.assertEqual(os.path.realpath(s["cwd"]), os.path.realpath(os.path.join(self.tmp.name, "apps", "clock")))
        a = s["argv"]
        self.assertEqual((a[a.index("--model") + 1], a[a.index("--effort") + 1]), ("claude-opus-5-5", "medium"))
        self.assertEqual(a[a.index("--permission-mode") + 1], "dontAsk")
        self.assertIn("--restricted", a)
        allowed = a[a.index("--allowedTools") + 1].split(",")
        self.assertIn("Write(./**)", allowed)
        self.assertIn("Bash(l0s-app-build:*)", allowed)
        self.assertNotIn("Bash", allowed)

    async def test_api_key_refused(self):
        os.environ["FAKE_CLAUDE_KEY_SOURCE"] = "ANTHROPIC_API_KEY"
        status, body = await self.build()
        events, _ = events_of(body)
        self.assertEqual(events[-1][0], "failed")
        self.assertIn("API key", events[-1][1]["why"])

    async def test_no_program(self):
        os.environ["FAKE_CLAUDE_BUILD"] = "no"
        events, _ = events_of((await self.build())[1])
        self.assertEqual(events[-1], ("failed", {"why": "the session built no program: built clock"}))

    async def test_refusals(self):
        self.assertEqual((await self.build(token="f" * 32))[0], 401)
        self.assertEqual((await self.build(name="Clock"))[0], 400)
        self.assertEqual((await self.build(name="../x"))[0], 400)
        self.assertEqual((await self.build(prompt=" "))[0], 400)
        async with self.client.get(self.base + "/build/clock/image", headers=self.auth()) as r:
            self.assertEqual(r.status, 404)

    async def test_one_at_a_time(self):
        os.environ["FAKE_CLAUDE_SLEEP"] = "0.5"
        first = asyncio.create_task(self.build())
        await asyncio.sleep(0.2)
        self.assertEqual((await self.build(name="other"))[0], 409)
        status, body = await first
        events, comments = events_of(body)
        self.assertEqual(events[-1][0], "done")
        self.assertGreater(comments, 0)
        self.assertEqual((await self.build(name="other"))[0], 200)


class BuildingTree(Building):
    """The builder with worktrees, of a repository of the test's own."""

    with_repo = True

    def branch_log(self):
        code, out = builders.git(self.repo, "log", "--format=%s", "app/clock")
        return out.splitlines()

    async def test_worktree_and_commit(self):
        os.environ["FAKE_CLAUDE_EDIT"] = "lib.txt"
        events, _ = events_of((await self.build())[1])
        tree = os.path.join(self.tmp.name, "apps", "clock", "l0s")
        with open(os.path.join(tree, "lib.txt")) as f:
            self.assertEqual(f.read(), "a library\nchanged for clock\n")
        self.assertEqual(self.branch_log(), ["app clock: a clock", "one"])
        self.assertEqual(events[-1], ("done", {"summary": "built clock\n\nL0S changed for it on the host's branch app/clock: lib.txt",
                                               "size": 11}))
        with open(os.path.join(self.repo, "lib.txt")) as f:
            self.assertEqual(f.read(), "a library\n")

    async def test_nothing_changed(self):
        await self.build()
        events, _ = events_of((await self.build(prompt="again"))[1])
        self.assertEqual(self.branch_log(), ["one"])
        self.assertEqual(events[-1][1]["summary"], "built clock")

    async def test_tree_is_the_sessions(self):
        await self.build()
        s = self.started()[0]
        tree = os.path.join(self.tmp.name, "apps", "clock", "l0s")
        a = s["argv"]
        self.assertEqual(a[a.index("--add-dir") + 1], tree)
        self.assertIn("Write(/%s/**)" % tree, a[a.index("--allowedTools") + 1].split(","))
        self.assertNotIn("Bash(git:*)", a[a.index("--allowedTools") + 1].split(","))


L0S = os.path.abspath(os.path.join(HERE, "..", ".."))
APP_BUILD = os.path.join(HERE, "bin", "l0s-app-build")


class AppBuild(unittest.TestCase):
    """l0s-app-build on a copy of the widgets app, as a session's folder,
    with a tree of L0S's libraries of its own as L0S_TREE."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "app")
        self.tree = os.path.join(self.tmp.name, "tree")
        os.makedirs(self.dir)
        for f in ("widgets.l0", "main.l0"):
            self.copy(os.path.join(L0S, "user", "apps", "widgets", f), os.path.join(self.dir, f), "")
        libs = subprocess.run(["make", "-s", "-C", L0S, "app-libs"], capture_output=True, text=True, check=True).stdout.split()
        for f in libs:
            extra = "\n; Only this tree's.\n(def ui_tree_own () int 7)\n" if f == "user/lib/ui/theme.l0" else ""
            self.copy(os.path.join(L0S, f), os.path.join(self.tree, f), extra)
        with open(os.path.join(self.dir, "own.l0"), "w") as f:
            f.write("; own.l0 -- the app's use of its tree's theme.\n\n; Seven.\n(def own_seven () int (ui_tree_own))\n")

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def copy(src, dst, extra):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(src, "rb") as i, open(dst, "wb") as o:
            o.write(i.read() + extra.encode())

    def build(self, tree):
        env = dict(os.environ)
        env.pop("L0S_TREE", None)
        if tree:
            env["L0S_TREE"] = tree
        return subprocess.run([APP_BUILD, "widgets"], cwd=self.dir, capture_output=True, text=True, timeout=300, env=env)

    def test_tree_linked(self):
        # A def only the tree's theme.l0 has, which a file of the app's
        # calls: it builds only from that tree.
        r = self.build(self.tree)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        with open(os.path.join(self.dir, "widgets"), "rb") as f:
            self.assertEqual(f.read(4), b"\x7fELF")

    def test_l0s_without_tree(self):
        r = self.build(None)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("ui_tree_own", r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
