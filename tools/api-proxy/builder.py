"""builder.py -- apps built for the board's agent (roadmap 0045) by a
Claude Code session on this host, which the proxy's POST /build drives.

Each app has a folder of its own, DIR/NAME, outside the L0S tree, so the
session reads none of L0S's own rules for its changes: the app's source,
written there by the session; its session ID (.session); and l0s/, a git
worktree of L0S on the app's own branch, app/NAME, made from L0S's HEAD
at the app's first build. The session reads L0S there and may change
its libraries there, in place, when the app needs more than they have;
l0s-app-build links that tree's libraries. After a build that made a
program, whatever the session changed in the worktree is committed on
app/NAME, for the person to merge, or not, by hand. The first prompt to
an app starts its session, each later one resumes it, so a follow-up
changes the same app.

The session is `claude -p`, its events read as stream-json, with:

- the model and effort the proxy was given (claude-opus-5-5, medium);
- the host's own Claude Code login: it is started without the proxy's
  ANTHROPIC_API_KEY or any other of the API's variables, and a session
  whose first event says it has a key anyway is ended, the build
  refused;
- --restricted, --strict-mcp-config and --permission-mode dontAsk, so
  only the tools named run: the file tools, reading and writing in its
  folder and its worktree only, and as commands L0's check, fmt, doc and
  spec, make -s doc, graphify's explain and affected, read-only
  inspection (ls, cat, head, tail, wc, grep, file), and l0s-app-build
  (bin/), which builds the app for the board; never git, which the
  builder alone runs;
- a system prompt added to Claude Code's: what an app of L0S's is, the
  skills and examples to read, to build with l0s-app-build, with no
  tests, spec or roadmap, and that the worktree is its to change.

A build yields events: ("progress", text) as the session works, then
("done", summary) once a program was built, its bytes then in
image(NAME), or ("failed", why)."""

import asyncio
import json
import os
import re
import subprocess
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
L0S = os.path.abspath(os.path.join(HERE, "..", ".."))
BIN = os.path.join(HERE, "bin")
DEFAULT_MODEL = "claude-opus-5-5"
DEFAULT_EFFORT = "medium"
DEFAULT_TIMEOUT = 1800
NAME = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
TRAILER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"

# The environment's ways to the API, none of which the session gets: it
# uses the host's Claude Code login.
API_ENV = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "ANTHROPIC_MODEL",
           "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY")

# The commands the session may run, each a prefix.
COMMANDS = ("l0 check", "l0 fmt", "l0 doc", "l0 spec", "l0s-app-build", "make -s -C %s doc" % L0S,
            "graphify explain", "graphify affected", "ls", "cat", "head", "tail", "wc", "grep", "file")

PROMPT = """You build desktop apps for L0S, the operating system, for the
agent that runs on it, which asked for this one. The app is %(name)s, in
this folder, which is its own. %(tree)s is L0S, a git worktree on
the branch %(branch)s, which is this app's own too: read L0S there.

- L0S and its libraries are written in L0, which is not in your
  training data: read %(tree)s/AGENTS.md's L0 block, `l0 spec`, and the
  skills %(tree)s/.claude/skills/l0-code/SKILL.md and
  %(tree)s/.claude/skills/l0s-ui/SKILL.md before writing any. Find
  library names with `make -s -C %(l0s)s doc Q=WORD` and `l0 doc NAME`;
  who calls what with `graphify explain "NAME()" --graph
  %(l0s)s/graphify-out/graph.json`.
- Copy the shape of a toolkit app: %(tree)s/user/apps/widgets is the
  smallest. Write %(name)s.l0 and main.l0 (only main, calling into it),
  and more .l0 files if you need them, in this folder; no tests are
  needed.
- Build with `l0s-app-build %(name)s`, which checks and builds every .l0
  here with the libraries of %(tree)s a window app links, into
  ./%(name)s. If the app needs another library, name its Makefile
  variable after the name: `l0s-app-build %(name)s CLOCK`.
- If the app needs more than the toolkit or another library has, first
  write it in the app itself (a widget of your own can be a
  UiDrawingArea the app paints). If that is not enough, change the
  library in place in %(tree)s: the change is committed on %(branch)s
  after the build, and the person decides later whether to merge it
  into L0S. Change only what the app needs, keep the library's
  idioms, and never run git yourself. Say in your summary which files
  you changed there, and why.
- L0S's own rules for its changes (make check, make test, the spec, the
  roadmap) are not yours: this app is not part of L0S. It is done when
  l0s-app-build succeeds.
- End with a few lines on what the app does and how it is used, which
  the agent is given."""


def name_ok(name):
    """Whether name may be an app's: a program's name on L0S, lowercase."""
    return bool(NAME.match(name or ""))


def git(repo, *args):
    """git run in repo: its exit status and what it wrote."""
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()


class Builder:
    """Apps' folders under root, built by sessions of cli (an argv
    prefix, claude unless given) on model at effort, each with a
    worktree of the git repository repo (L0S unless given; None for
    none, the session then reading L0S itself)."""

    def __init__(self, root, model=DEFAULT_MODEL, effort=DEFAULT_EFFORT, cli=("claude",), timeout=DEFAULT_TIMEOUT,
                 repo=L0S):
        self.root, self.model, self.effort, self.cli, self.timeout = root, model, effort, list(cli), timeout
        self.repo = repo
        self.busy = False

    def folder(self, name):
        return os.path.join(self.root, name)

    def tree(self, name):
        """The app's worktree of L0S, or L0S itself with no repo."""
        return os.path.join(self.folder(name), "l0s") if self.repo else L0S

    @staticmethod
    def branch(name):
        return "app/" + name

    def session_of(self, name):
        """The app's session ID, or None before its first build."""
        try:
            with open(os.path.join(self.folder(name), ".session")) as f:
                return f.readline().strip() or None
        except OSError:
            return None

    def tree_made(self, name):
        """The app's worktree made, if it is not there: on its branch,
        which is made from the repository's HEAD if it is not there
        either. Why not, or empty."""
        t = self.tree(name)
        if not self.repo or os.path.exists(t):
            return ""
        b = self.branch(name)
        code, _ = git(self.repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + b)
        code, out = (git(self.repo, "worktree", "add", t, b) if code == 0
                     else git(self.repo, "worktree", "add", "-b", b, t, "HEAD"))
        return "" if code == 0 else "the worktree for %s could not be made: %s" % (name, out)

    def tree_committed(self, name, prompt):
        """What the session changed in the app's worktree committed on its
        branch, hooks skipped: the files changed, none if nothing was, or
        why not, as (files, why)."""
        if not self.repo:
            return [], ""
        t = self.tree(name)
        code, out = git(t, "add", "-A")
        if code != 0:
            return [], "the worktree's changes could not be added: " + out
        code, out = git(t, "diff", "--cached", "--name-only")
        files = [f for f in out.splitlines() if f]
        if code != 0 or not files:
            return [], ""
        line = cut(" ".join(prompt.split()), 60)
        msg = "app %s: %s\n\nMade by the app builder's session (roadmap 0045) for the board's agent.\n\n%s\n" % (
            name, line, TRAILER)
        code, out = git(t, "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", msg)
        return (files, "") if code == 0 else ([], "the worktree's changes could not be committed: " + out)

    def command(self, name, prompt, session, resume):
        """The session's command line: started as session, or resumed."""
        t = self.tree(name)
        mine = ["Write(./**)", "Edit(./**)"] + (["Write(/%s/**)" % t, "Edit(/%s/**)" % t] if self.repo else [])
        allowed = ["Read", "Glob", "Grep"] + mine + ["Bash(%s:*)" % c for c in COMMANDS]
        return self.cli + [
            "-p", prompt, "--output-format", "stream-json", "--verbose",
            "--model", self.model, "--effort", self.effort,
            "--restricted", "--strict-mcp-config", "--permission-mode", "dontAsk",
            "--tools", "Read,Write,Edit,Glob,Grep,Bash",
            "--allowedTools", ",".join(allowed),
            "--add-dir", t,
            "--append-system-prompt", PROMPT % {"l0s": L0S, "tree": t, "branch": self.branch(name), "name": name},
        ] + (["--resume", session] if resume else ["--session-id", session])

    def environment(self, env, name):
        """env without the API's variables, bin/ first on its PATH, and
        L0S_TREE the app's worktree, whose libraries l0s-app-build links."""
        out = {k: v for k, v in env.items() if k not in API_ENV}
        out["PATH"] = BIN + os.pathsep + env.get("PATH", "")
        out["L0S_TREE"] = self.tree(name)
        return out

    def image(self, name):
        """The app's program as built, or None."""
        try:
            with open(os.path.join(self.folder(name), name), "rb") as f:
                return f.read()
        except OSError:
            return None

    async def build(self, name, prompt):
        """The app built from prompt: its events, as the module says."""
        d = self.folder(name)
        os.makedirs(d, exist_ok=True)
        why = self.tree_made(name)
        if why:
            yield ("failed", why)
            return
        old = self.session_of(name)
        session = old or str(uuid.uuid4())
        if not old:
            with open(os.path.join(d, ".session"), "w") as f:
                f.write(session + "\n")
        before = os.path.getmtime(os.path.join(d, name)) if os.path.exists(os.path.join(d, name)) else None
        proc = await asyncio.create_subprocess_exec(
            *self.command(name, prompt, session, old is not None), cwd=d, env=self.environment(os.environ, name),
            stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
            limit=16 * 1024 * 1024)
        result = None
        try:
            async with asyncio.timeout(self.timeout):
                async for raw in proc.stdout:
                    e = event_of(raw)
                    if e is None:
                        continue
                    if e.get("type") == "system" and e.get("subtype") == "init":
                        if e.get("apiKeySource", "none") != "none":
                            yield ("failed", "the session had an API key (%s); it runs on the host's Claude Code login only"
                                   % e.get("apiKeySource"))
                            return
                        yield ("progress", "session %s on %s" % ("resumed" if old else "started", e.get("model", self.model)))
                    elif e.get("type") == "assistant":
                        for line in progress_of(e):
                            yield ("progress", line)
                    elif e.get("type") == "result":
                        result = e
                await proc.wait()
        except TimeoutError:
            yield ("failed", "the session took more than %d s" % self.timeout)
            return
        finally:
            if proc.returncode is None:
                proc.kill()
                await proc.wait()
        if result is None:
            err = (await proc.stderr.read()).decode(errors="replace").strip()
            yield ("failed", "the session ended with no result (exit %s)%s" % (proc.returncode, ": " + err[-500:] if err else ""))
            return
        summary = str(result.get("result", "")).strip()
        if result.get("is_error"):
            yield ("failed", "the session failed: %s" % (summary or result.get("subtype", "")))
            return
        p = os.path.join(d, name)
        built = os.path.exists(p) and (before is None or os.path.getmtime(p) > before)
        img = self.image(name) if built else None
        if not img or not img.startswith(b"\x7fELF"):
            yield ("failed", "the session built no program%s" % (": " + summary if summary else ""))
            return
        files, why = self.tree_committed(name, prompt)
        if why:
            yield ("progress", why)
        elif files:
            line = "L0S changed for it on the host's branch %s: %s" % (self.branch(name), ", ".join(files))
            yield ("progress", line)
            summary = summary + "\n\n" + line if summary else line
        yield ("done", summary)


def event_of(raw):
    """A line of stream-json as an event, or None if it is none."""
    try:
        e = json.loads(raw)
    except ValueError:
        return None
    return e if isinstance(e, dict) else None


def progress_of(e):
    """An assistant event's text and tool uses, a short line each."""
    out = []
    for b in (e.get("message") or {}).get("content") or []:
        if b.get("type") == "text" and b.get("text", "").strip():
            out.append(cut(" ".join(b["text"].split()), 200))
        elif b.get("type") == "tool_use":
            i = b.get("input") or {}
            what = i.get("command") or i.get("file_path") or i.get("pattern") or ""
            out.append(cut("%s %s" % (b.get("name", "?"), what), 200))
    return out


def cut(s, n):
    """s cut to n characters, with ... if it was longer."""
    return s if len(s) <= n else s[:n - 3] + "..."
