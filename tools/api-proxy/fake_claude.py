"""fake_claude.py -- a stand-in for `claude -p` in stream-json, for the
builder's tests (test_proxy.py): no model, no network.

It writes how it was started, {"argv", "cwd", "api_env"} (the API's
variables it was given), as a line of FAKE_CLAUDE_LOG; then the events a
session gives: init (its apiKeySource FAKE_CLAUDE_KEY_SOURCE, none unless
set), an assistant's text and tool use, and after FAKE_CLAUDE_SLEEP
seconds a result, "built NAME". With FAKE_CLAUDE_EDIT, a path in its
L0S tree (L0S_TREE), it adds a line to that file, as a session changing
a library in place; with FAKE_CLAUDE_RESOLVE, another such path, it
drops that file's conflict markers, keeping both sides, as a session
resolving the merge it was told of. With FAKE_CLAUDE_PREVIEW, a PNG's path, it first
copies that to preview/main.png, as l0s-app-preview paints a scene,
before it says anything, so the builder finds it at its first line; with
FAKE_CLAUDE_PREVIEW_LATE too, a second after its tool use instead, then
silent for FAKE_CLAUDE_SLEEP, as a session previewing then building in
one command. Unless
FAKE_CLAUDE_BUILD is no it first
writes ./NAME, NAME its folder's, as a program: a copy of the file
FAKE_CLAUDE_IMAGE names, a real one for an e2e case's board, or else an
ELF header and the prompt."""

import json
import os
import sys
import time

API = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL")


def say(e):
    print(json.dumps(e), flush=True)


def previewed(png):
    """png's file copied to preview/main.png, a scene painted."""
    os.makedirs("preview", exist_ok=True)
    with open(png, "rb") as f, open(os.path.join("preview", "main.png"), "wb") as g:
        g.write(f.read())


def main(argv):
    log = os.environ.get("FAKE_CLAUDE_LOG")
    if log:
        with open(log, "a") as f:
            f.write(json.dumps({"argv": argv, "cwd": os.getcwd(),
                                "api_env": [k for k in API if k in os.environ]}) + "\n")
    model = argv[argv.index("--model") + 1] if "--model" in argv else "?"
    prompt = argv[argv.index("-p") + 1] if "-p" in argv else ""
    name = os.path.basename(os.getcwd())
    preview = os.environ.get("FAKE_CLAUDE_PREVIEW")
    late = os.environ.get("FAKE_CLAUDE_PREVIEW_LATE")
    if preview and not late:
        previewed(preview)
    say({"type": "system", "subtype": "init", "model": model,
         "apiKeySource": os.environ.get("FAKE_CLAUDE_KEY_SOURCE", "none")})
    say({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "Writing the app."},
        {"type": "tool_use", "name": "Bash", "input": {"command": "l0s-app-build " + name}}]}})
    if preview and late:
        time.sleep(1)
        previewed(preview)
    resolve = os.environ.get("FAKE_CLAUDE_RESOLVE")
    if resolve:
        p = os.path.join(os.environ["L0S_TREE"], resolve)
        with open(p) as f:
            kept = [x for x in f.read().splitlines(True)
                    if not (x.startswith(("<<<<<<< ", ">>>>>>> ")) or x.rstrip("\n") == "=======")]
        with open(p, "w") as f:
            f.write("".join(kept))
    edit = os.environ.get("FAKE_CLAUDE_EDIT")
    if edit:
        with open(os.path.join(os.environ["L0S_TREE"], edit), "a") as f:
            f.write("changed for " + name + "\n")
    if os.environ.get("FAKE_CLAUDE_BUILD") != "no":
        image = os.environ.get("FAKE_CLAUDE_IMAGE")
        if image:
            with open(image, "rb") as f:
                body = f.read()
        else:
            body = b"\x7fELF" + prompt.encode()
        with open(name, "wb") as f:
            f.write(body)
    time.sleep(float(os.environ.get("FAKE_CLAUDE_SLEEP", "0")))
    say({"type": "result", "subtype": "success", "is_error": False, "result": "built " + name})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
