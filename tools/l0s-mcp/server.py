"""server.py -- the l0s MCP server: boots L0S on QEMU and lets an agent
read and type at its serial line, look at its screen, type on its
keyboard and move its pointer. One board at a time; it stops when the
server does. Run by .mcp.json, from the venv make mcp builds."""

import atexit
import functools
import pathlib
import subprocess

from mcp.server.mcpserver import Image, MCPServer
from mcp.server.mcpserver.exceptions import ToolError

from board import Board, BoardError, parse_combo, parse_ps, parse_windows

INSTRUCTIONS = """\
Drives L0S, the L0 microkernel, booted on QEMU's aarch64 virt board.
Build first (make initramfs for the demo, make screen-initramfs for the
screen tests' image); boot does not build. Then boot, and use shell for
commands at the serial shell (the demo's pid 12, which boot, pid 1,
starts and waits for; prompt "l0s> "): it waits for the
next prompt and returns what was printed. ps and windows parse those
commands' output. serial_send/serial_read are for anything that is not
a command that returns to the prompt (a program reading its input,
Ctrl-C, output of background jobs). The screen is 1280x800; screenshot
shows it, pixels gives exact colors. type_keys and press_keys go to the
virtio keyboard, so to the front window, not the serial line; click,
drag, move and scroll (the wheel) drive the virtio tablet. Everything the serial line shows
is also saved in build/mcp/serial.out.

doc needs no board: it looks up L0S's own code, as make -s doc Q=...
does, before you grep for a helper or a name."""

ROOT = pathlib.Path(__file__).resolve().parents[2]

mcp = MCPServer("l0s", instructions=INSTRUCTIONS)
board = Board()
atexit.register(board.stop)


def tool(fn):
    """An MCP tool whose board errors reach the agent as what they say;
    the SDK reports any other exception only as having happened. An
    OSError is the serial line or QMP gone with QEMU."""
    @functools.wraps(fn)
    def run(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except (BoardError, OSError) as e:
            raise ToolError(str(e)) from e
    return mcp.tool()(run)


@mcp.tool()
def doc(query: str = "") -> str:
    """L0S's own documentation, as make -s doc Q=query gives it and as l0
    doc gives the L0 standard library's: with no query, every documented
    name in the libraries, one line each; a def, data type or constructor
    in full, with its signature; a file by its stem (l0s, widget) or the
    end of its path (proto/wm, sbin/wm/wm); or else every name or doc
    line mentioning the text, ignoring case. Queries search the
    programs' and tools' own sources too, after the libraries; a name
    there is that program's, which no other program can link."""
    run = subprocess.run(["make", "-s", "doc", f"Q={query}"], cwd=ROOT,
                         capture_output=True, text=True, timeout=300)
    if run.returncode != 0:
        raise ToolError(run.stderr.strip() or f"make doc exited {run.returncode}")
    return run.stdout


@tool
def boot(image: str = "demo", display: str = "none", until: str = "^l0s> ",
         timeout: float = 60, settle: float = 1) -> dict:
    """Boots L0S, stopping any board already running, and returns what
    the serial line showed by the time it matched until (a regular
    expression, the shell's prompt by default; "" waits for nothing),
    and settle seconds more, for the rest of the inittab to come up: the
    windows' shells start after the serial one, so look at the screen
    before typing into a window. If the kernel already exited, as it
    does once pid 1 ends (the demo's, when its serial shell does),
    running is false and status is its exit
    status. image is demo (build/initramfs.cpio),
    screen (build/screen.cpio), a .cpio, or an etc directory holding an
    inittab, such as tests/e2e/ipc/etc, packed with every program as
    make root stages them in build/root. display is none, or cocoa to also show QEMU's window on
    this Mac."""
    return board.boot(image, display, until, timeout, settle)


@tool
def shutdown(graceful: bool = False) -> dict:
    """Stops the board: exit at the serial shell if graceful (the
    kernel's status is then the shell's), else QEMU is killed. Returns
    the exit status and what the serial line showed since last read."""
    status = board.stop(graceful)
    return {"status": status, "text": board.take()}


@tool
def status() -> dict:
    """Whether a board is running, what it booted, its exit status if it
    stopped, how much of the serial line is unread, and QEMU's stderr."""
    return board.state()


@tool
def shell(command: str, timeout: float = 15) -> dict:
    """Types a command at the serial shell and returns what it printed
    before the next prompt. finished is false if no prompt came within
    timeout seconds, as when the program is still running in the
    foreground; serial_read then gets the rest."""
    return board.shell(command, timeout)


@tool
def serial_send(text: str, newline: bool = True) -> str:
    """Types text at the serial line, as is: \\x03 is Ctrl-C, \\x04
    Ctrl-D. A newline is added unless newline is false. Pauses after
    each line so what one starts runs before the next arrives."""
    board.send(text + ("\n" if newline else ""))
    return "sent"


@tool
def serial_read(until: str = "", timeout: float = 10) -> dict:
    """What the serial line showed since it was last read (by this, shell
    or boot). Given until, a regular expression, waits up to timeout
    seconds for it to show first; matched says whether it did."""
    return board.read(until or None, timeout)


@tool
def ps() -> dict:
    """The processes that have not exited, as the serial shell's ps
    lists them: pid, parent, program and what each waits for."""
    reply = board.shell("ps")
    return {"processes": parse_ps(reply["output"]), "raw": reply["output"]}


@tool
def windows() -> dict:
    """The compositor's windows, front first (id, title, x, y, width and
    height of the content, front), and where the pointer is, from run
    windows at the serial shell. A window's title bar is the 46 rows
    above y, and its frame 2 pixels around the content."""
    reply = board.shell("run windows")
    return parse_windows(reply["output"]) | {"raw": reply["output"]}


@tool
def screenshot(x: int = 0, y: int = 0, width: int = 0, height: int = 0) -> Image:
    """The screen as a PNG, by QEMU's screendump: the whole 1280x800, or
    the part width by height from x, y to see detail."""
    data = board.screenshot(x, y, width or None, height or None)
    return Image(data=data, format="png")


@tool
def pixels(points: list[list[int]]) -> dict:
    """The exact colors of screen pixels, each point [x, y], as the
    screen tests check them."""
    return {"pixels": board.pixels([(p[0], p[1]) for p in points])}


@tool
def type_keys(text: str, enter: bool = True) -> str:
    """Types text on the virtio keyboard, as typing in QEMU's window
    would, so the front window's terminal gets it; then Enter unless
    enter is false. Letters, digits, space, US punctuation, \\n, \\t."""
    n = board.type_keys(text, enter)
    return f"typed {n} keys"


@tool
def press_keys(keys: list[str]) -> str:
    """Presses key combinations on the virtio keyboard, one after
    another, each as QEMU's sendkey names it: esc, ret, ctrl-c, shift-tab,
    up, f1."""
    for combo in keys:
        board.press(parse_combo(combo))
    return f"pressed {len(keys)}"


@tool
def move(x: int, y: int) -> str:
    """Moves the pointer to screen pixel x, y."""
    board.move(x, y)
    return f"pointer at {x}, {y}"


@tool
def click(x: int, y: int, button: str = "left") -> str:
    """Moves the pointer to x, y and clicks: left, right or middle."""
    board.click(x, y, button)
    return f"clicked {button} at {x}, {y}"


@tool
def scroll(x: int, y: int, dy: int = 1, dx: int = 0) -> str:
    """Moves the pointer to x, y and turns the scroll wheel dy steps:
    positive down, toward the end of what is shown, negative up; dx
    steps right, or left if negative."""
    board.scroll(x, y, dy, dx)
    return f"scrolled {dy} down, {dx} right at {x}, {y}"


@tool
def drag(x0: int, y0: int, x1: int, y1: int, steps: int = 8, button: str = "left") -> str:
    """Presses the button at x0, y0, moves to x1, y1 in steps, and lets
    go there, as dragging a window by its title bar."""
    board.drag(x0, y0, x1, y1, steps, button)
    return f"dragged from {x0}, {y0} to {x1}, {y1}"


if __name__ == "__main__":
    mcp.run()
