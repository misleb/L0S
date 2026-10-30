"""e2e_serve.py PORT CASE -- the stand-in for the API and the proxy in
front of it, for an e2e case that a board asks a model through: the
stand-in, answering from CASE/script.json, on a free port of the
loopback, with a key of its own; and the proxy on 127.0.0.1:PORT, which
the board reaches as 10.0.2.2:PORT, taking the token in
CASE/etc/agent/token and adding that key. Each request the stand-in gets
and each usage line is written to standard output, which e2e.sh keeps
in build/e2e/NAME.serve; the usage file is build/e2e/NAME.usage.jsonl.
Runs until it is stopped. tests/e2e/ask's serve line runs it."""

import asyncio
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's own directory out

import proxy  # noqa: E402
import standin  # noqa: E402

KEY = "sk-e2e-standin"


async def run(port, case):
    """The stand-in and the proxy, served until the process is stopped."""
    name = os.path.basename(os.path.normpath(case))
    token, why = proxy.token_of(os.path.join(case, "etc", "agent", "token"))
    if token is None:
        print("e2e_serve: " + why, file=sys.stderr, flush=True)
        return 1
    say = lambda line: print(line, flush=True)  # noqa: E731
    s = standin.Standin(standin.load_script(os.path.join(case, "script.json")), key=KEY, log=say)
    _, up_port = await standin.serve(s.app(), "127.0.0.1", 0)
    usage = os.path.join(HERE, "..", "..", "build", "e2e", name + ".usage.jsonl")
    if os.path.exists(usage):
        os.remove(usage)
    app = proxy.make_app(token, "http://127.0.0.1:%d" % up_port, KEY, usage, log=say)
    await standin.serve(app, "127.0.0.1", port)
    say("e2e_serve: the proxy on 127.0.0.1:%d, the stand-in on %d" % (port, up_port))
    await asyncio.Event().wait()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: e2e_serve.py PORT CASE", file=sys.stderr)
        sys.exit(2)
    sys.exit(asyncio.run(run(int(sys.argv[1]), sys.argv[2])))
