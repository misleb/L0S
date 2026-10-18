"""board.py -- an L0S board on QEMU, for the l0s MCP server: boots it with
tools/qemu-boot.sh, and a fresh disk from tools/mkdisk at build/mcp/disk.img,
keeps everything its serial line shows, types at the
serial shell, and drives the screen, the virtio keyboard and the virtio
tablet through QMP, as the screen tests in tests/*.sh do with the monitor
and nc.

Nothing here imports the MCP SDK, so the pure parts can be tested with
plain python3 (test_board.py)."""

import json
import os
import re
import shutil
import socket
import struct
import subprocess
import threading
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
STATE = BUILD / "mcp"

# The screen the compositor makes, which the tablet's axes are scaled to.
WIDTH, HEIGHT = 1280, 800

# The serial shell's prompt, at the start of a line.
PROMPT = re.compile(r"(?m)^l0s> ")

# The initramfses make builds, by the names boot takes.
IMAGES = {
    "demo": (BUILD / "initramfs.cpio", "make initramfs"),
    "screen": (BUILD / "screen.cpio", "make screen-initramfs"),
}

# How long a key is held, and the pause after it, in seconds.
KEY_HOLD = 0.03
KEY_GAP = 0.03
# The pause between pointer events, so the driver and wm take each one.
POINTER_GAP = 0.15


class BoardError(Exception):
    pass


# Keys -------------------------------------------------------------------

# Characters typed with one key, by its QEMU qcode, and those typed with
# shift and a key.
_PLAIN = {
    " ": "spc", "\n": "ret", "\t": "tab", "\b": "backspace",
    "-": "minus", "=": "equal", "[": "bracket_left", "]": "bracket_right",
    "\\": "backslash", ";": "semicolon", "'": "apostrophe",
    "`": "grave_accent", ",": "comma", ".": "dot", "/": "slash",
}
_SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal",
    "{": "bracket_left", "}": "bracket_right", "|": "backslash",
    ":": "semicolon", '"': "apostrophe", "~": "grave_accent",
    "<": "comma", ">": "dot", "?": "slash",
}


def key_combo(ch):
    """The qcodes pressed together to type the character ch."""
    if "a" <= ch <= "z" or "0" <= ch <= "9":
        return [ch]
    if "A" <= ch <= "Z":
        return ["shift", ch.lower()]
    if ch in _PLAIN:
        return [_PLAIN[ch]]
    if ch in _SHIFTED:
        return ["shift", _SHIFTED[ch]]
    raise BoardError(f"no key types {ch!r}")


def parse_combo(name):
    """A combination as sendkey writes it, such as ctrl-c or shift-tab,
    as its qcodes."""
    keys = [k for k in name.strip().lower().split("-") if k]
    if not keys:
        raise BoardError(f"no keys in {name!r}")
    return keys


# The tablet -------------------------------------------------------------

def axis(pixel, size):
    """Where a screen pixel is on the tablet's axis, 0 to 32767."""
    pixel = max(0, min(size - 1, pixel))
    return pixel * 32767 // (size - 1)


def at(x, y):
    """The input events that put the pointer at screen pixel x, y."""
    return [
        {"type": "abs", "data": {"axis": "x", "value": axis(x, WIDTH)}},
        {"type": "abs", "data": {"axis": "y", "value": axis(y, HEIGHT)}},
    ]


def button(down, which="left"):
    return [{"type": "btn", "data": {"down": down, "button": which}}]


def wheel(dx, dy):
    """The input events of turning the wheel dy steps down, toward the end
    of what is shown, and dx right; negative is up and left. QEMU's tablet
    reports each press of a wheel button as a step of REL_WHEEL or
    REL_HWHEEL."""
    steps = []
    for n, plus, minus in ((dy, "wheel-down", "wheel-up"), (dx, "wheel-right", "wheel-left")):
        for _ in range(abs(n)):
            steps += button(True, plus if n > 0 else minus) + button(False, plus if n > 0 else minus)
    return steps


# Pictures ---------------------------------------------------------------

def parse_ppm(data):
    """A binary PPM's width, height and RGB bytes."""
    fields, i = [], 0
    while len(fields) < 4:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while i < len(data) and data[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while j < len(data) and not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b"P6" or fields[3] != b"255":
        raise BoardError("the screendump is not a P6 PPM of maxval 255")
    w, h = int(fields[1]), int(fields[2])
    rgb = data[i + 1:i + 1 + w * h * 3]
    if len(rgb) != w * h * 3:
        raise BoardError("the screendump is cut short")
    return w, h, rgb


def crop(w, h, rgb, x, y, cw, ch):
    """The part of an RGB picture from x, y, cw by ch, cut to fit it."""
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(w, x + cw), min(h, y + ch)
    if x1 <= x0 or y1 <= y0:
        raise BoardError(f"{cw}x{ch} at {x}, {y} is off the {w}x{h} screen")
    rows = [rgb[(r * w + x0) * 3:(r * w + x1) * 3] for r in range(y0, y1)]
    return x1 - x0, y1 - y0, b"".join(rows)


def png(w, h, rgb):
    """An RGB picture as a PNG."""
    stride = w * 3
    raw = b"".join(b"\x00" + rgb[r * stride:(r + 1) * stride] for r in range(h))

    def chunk(kind, body):
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6))
            + chunk(b"IEND", b""))


# What the shell says ----------------------------------------------------

def clean(raw):
    """Serial bytes as text, with carriage returns gone."""
    return raw.decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "")


def reply_of(region, command):
    """What a command typed at the serial shell printed: region is the
    serial line from just before it was typed, up to the next prompt
    (excluded), with the echo of the command itself taken off."""
    m = PROMPT.search(region)
    body = region[:m.start()] if m else region
    first, nl, rest = body.partition("\n")
    if nl and first.strip() == command.strip():
        return rest
    return body


_PS = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*?)\s*$")


def parse_ps(text):
    """ps's lines as processes: pid, parent, program, state."""
    procs = []
    for line in text.splitlines():
        m = _PS.match(line)
        if m:
            procs.append({"pid": int(m[1]), "parent": int(m[2]),
                          "program": m[3], "state": m[4]})
    return procs


def parse_windows(text):
    """run windows's lines: the windows, front first, and the pointer."""
    wins, pointer, errors = [], None, []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "pointer" and parts[1].isdigit() and parts[2].isdigit():
            pointer = {"x": int(parts[1]), "y": int(parts[2])}
        elif (len(parts) >= 7 and parts[0].isdigit() and parts[-1] in ("front", "-")
              and all(p.isdigit() for p in parts[-5:-1])):
            x, y, w, h = (int(p) for p in parts[-5:-1])
            wins.append({"id": int(parts[0]), "title": " ".join(parts[1:-5]),
                         "x": x, "y": y, "width": w, "height": h,
                         "front": parts[-1] == "front"})
        elif line.startswith("windows: "):
            errors.append(line[len("windows: "):])
    return {"windows": wins, "pointer": pointer, "errors": errors}


# QMP --------------------------------------------------------------------

class Qmp:
    """A connection to QEMU's QMP socket."""

    def __init__(self, path, alive, timeout=10.0):
        deadline = time.monotonic() + timeout
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.settimeout(timeout)
                self.sock.connect(str(path))
                break
            except OSError:
                self.sock.close()
                if not alive():
                    raise BoardError("QEMU stopped before QMP listened")
                if time.monotonic() > deadline:
                    raise BoardError(f"QMP never listened at {path}")
                time.sleep(0.1)
        self.file = self.sock.makefile("rwb")
        self._message()  # the greeting
        self.execute("qmp_capabilities")

    def _message(self):
        line = self.file.readline()
        if not line:
            raise BoardError("QMP closed: QEMU has stopped")
        return json.loads(line)

    def execute(self, command, **arguments):
        msg = {"execute": command}
        if arguments:
            msg["arguments"] = arguments
        self.file.write(json.dumps(msg).encode() + b"\n")
        self.file.flush()
        while True:
            reply = self._message()
            if "return" in reply:
                return reply["return"]
            if "error" in reply:
                raise BoardError(f"QMP {command}: {reply['error'].get('desc')}")
            # anything else is an event, such as a key's

    def close(self):
        try:
            self.file.close()
            self.sock.close()
        except OSError:
            pass


# The board --------------------------------------------------------------

def resolve_image(image):
    """The initramfs to boot for image: demo, screen, a .cpio, or an etc
    directory holding an inittab, packed with every program as make root
    stages them in build/root, /bin, /sbin and /Applications, as
    tests/e2e.sh packs a case."""
    if image in IMAGES:
        path, how = IMAGES[image]
        if not path.exists():
            raise BoardError(f"{path.relative_to(ROOT)} is not built; run {how}")
        return path
    path = (ROOT / image).resolve()
    if path.is_file():
        return path
    if path.is_dir() and (path / "inittab").is_file():
        tree = BUILD / "root"
        if not (tree / "bin").is_dir():
            raise BoardError("build/root has no programs; run make root")
        etc = STATE / "etc"
        shutil.rmtree(etc, ignore_errors=True)
        shutil.copytree(path, etc)
        if not (etc / "font.txt").exists():
            shutil.copy(ROOT / "fonts" / "l0s-8x16.txt", etc / "font.txt")
        splash = BUILD / "splash.ppm"
        if not (etc / "splash.ppm").exists() and splash.exists():
            shutil.copy(splash, etc / "splash.ppm")
        out = STATE / "custom.cpio"
        made = subprocess.run([str(ROOT / "tools" / "mkinitramfs"), str(out), str(etc), str(tree)],
                              cwd=ROOT, capture_output=True, text=True)
        if made.returncode != 0:
            raise BoardError(f"mkinitramfs failed: {made.stderr.strip()}")
        return out
    raise BoardError(f"no image {image!r}: give demo, screen, a .cpio, or an etc directory with an inittab")


class Board:
    """At most one L0S board on QEMU at a time."""

    def __init__(self):
        self.proc = None
        self.qmp = None
        self.out = bytearray()
        self.read_at = 0
        self.status = None
        self.image = None
        self.cond = threading.Condition()

    # Starting and stopping

    def running(self):
        return self.proc is not None and self.proc.poll() is None

    def boot(self, image="demo", display="none", until=PROMPT.pattern, timeout=60.0, settle=1.0):
        self.stop()
        cpio = resolve_image(image)
        kernel = BUILD / "kernel.img"
        if not kernel.exists():
            raise BoardError("build/kernel.img is not built; run make images")
        STATE.mkdir(parents=True, exist_ok=True)
        qmp_path = STATE / "qmp.sock"
        qmp_path.unlink(missing_ok=True)
        # A fresh disk each boot, as tools/mkdisk makes it, for virtio-blk.
        disk = STATE / "disk.img"
        subprocess.run([str(ROOT / "tools" / "mkdisk"), str(disk)], cwd=ROOT, check=True)
        env = dict(os.environ, QEMU_DISPLAY=display, QEMU_DISK=str(disk),
                   QEMU_QMP=f"unix:{qmp_path},server=on,wait=off")
        with self.cond:
            self.out = bytearray()
            self.read_at = 0
            self.status = None
        self.image = str(cpio.relative_to(ROOT)) if cpio.is_relative_to(ROOT) else str(cpio)
        self.err_path = STATE / "qemu.err"
        self.log = open(STATE / "serial.out", "wb")
        with open(self.err_path, "wb") as err:
            self.proc = subprocess.Popen(
                [str(ROOT / "tools" / "qemu-boot.sh"), str(cpio), str(kernel)],
                cwd=ROOT, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=err, start_new_session=True)
        threading.Thread(target=self._read, args=(self.proc,), daemon=True).start()
        try:
            self.qmp = Qmp(qmp_path, self.running)
        except BoardError as e:
            # A board may stop at once, as one whose inittab runs only
            # programs that end does, or whose kernel refuses its
            # inittab: that is reported as a boot, with its status and
            # standard error. QMP not coming up on a running QEMU is not.
            if self.running():
                self.stop()
                raise BoardError(f"{e}\n{self._stderr()}")
        if until:
            self.wait_for(until, 0, timeout)
        if self.running():
            # The rest of the inittab, such as the windows' shells, comes
            # up after the serial shell's prompt.
            time.sleep(settle)
        else:
            self.drain()
        return {"text": self.take(), "running": self.running(), "status": self.status,
                "stderr": self._stderr()}

    def drain(self, timeout=5.0):
        """Waits for the reader to take the last of a stopped board's output."""
        deadline = time.monotonic() + timeout
        with self.cond:
            while self.status is None and time.monotonic() < deadline:
                self.cond.wait(deadline - time.monotonic())

    def stop(self, graceful=False, timeout=10.0):
        """Ends the board: exit at its shell if graceful, else killed."""
        if self.proc is None:
            return None
        if graceful and self.running():
            self.send("exit\n")
            try:
                self.proc.wait(timeout)
            except subprocess.TimeoutExpired:
                pass
        if self.running():
            self.proc.kill()
        self.proc.wait()
        if self.qmp:
            self.qmp.close()
            self.qmp = None
        (STATE / "qmp.sock").unlink(missing_ok=True)
        with self.cond:
            if self.status is None:
                self.status = self.proc.returncode
            status = self.status
            self.proc = None
            self.log.close()
        return status

    def _read(self, proc):
        fd = proc.stdout.fileno()
        while True:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                chunk = b""
            if not chunk:
                break
            with self.cond:
                if proc is self.proc:
                    self.out += chunk
                    self.log.write(chunk)
                    self.log.flush()
                self.cond.notify_all()
        code = proc.wait()
        with self.cond:
            if proc is self.proc:
                self.status = code
            self.cond.notify_all()

    def _stderr(self):
        try:
            return self.err_path.read_text(errors="replace").strip()
        except (OSError, AttributeError):
            return ""

    def _need(self):
        if not self.running():
            why = "no board is running; boot one"
            if self.status is not None:
                why = f"the board stopped, status {self.status}; boot it again"
            raise BoardError(why)

    def state(self):
        """Whether the board runs, what it booted, and where its logs are."""
        with self.cond:
            return {"running": self.running(), "image": self.image,
                    "status": self.status, "serial_bytes": len(self.out),
                    "unread_bytes": len(self.out) - self.read_at,
                    "serial_log": str((STATE / "serial.out").relative_to(ROOT)),
                    "qemu_stderr": self._stderr()}

    # The serial line

    def send(self, text):
        """Types text at the serial line, pausing after each newline and
        Ctrl-C as tools/slowtype does, so what a line starts runs first."""
        self._need()
        data = text.encode()
        start = 0
        for i, b in enumerate(data):
            if b in (0x0A, 0x03):
                self.proc.stdin.write(data[start:i + 1])
                self.proc.stdin.flush()
                start = i + 1
                if i + 1 < len(data):
                    time.sleep(0.25)
        if start < len(data):
            self.proc.stdin.write(data[start:])
            self.proc.stdin.flush()

    def wait_for(self, pattern, start, timeout):
        """Waits until the serial line from byte start matches pattern, or
        the board stops, or timeout seconds pass. Whether it matched."""
        regex = re.compile(pattern, re.M)
        deadline = time.monotonic() + timeout
        with self.cond:
            while True:
                if regex.search(clean(bytes(self.out[start:]))):
                    return True
                left = deadline - time.monotonic()
                if left <= 0 or self.status is not None:
                    return False
                self.cond.wait(left)

    def take(self):
        """What the serial line showed since it was last taken."""
        with self.cond:
            text = clean(bytes(self.out[self.read_at:]))
            self.read_at = len(self.out)
            return text

    def read(self, until=None, timeout=10.0):
        """What the serial line showed since it was last read, waiting
        for until, a regular expression, if given."""
        matched = None
        if until:
            matched = self.wait_for(until, self.read_at, timeout)
        return {"text": self.take(), "matched": matched,
                "running": self.running(), "status": self.status}

    def shell(self, command, timeout=15.0):
        """Types command at the serial shell and returns what it printed
        before its next prompt."""
        self._need()
        with self.cond:
            mark = len(self.out)
        self.send(command.rstrip("\n") + "\n")
        done = self.wait_for(PROMPT.pattern, mark, timeout)
        with self.cond:
            region = clean(bytes(self.out[mark:]))
            self.read_at = max(self.read_at, len(self.out))
        return {"output": reply_of(region, command), "finished": done,
                "running": self.running(), "status": self.status}

    # The screen, keyboard and tablet

    def screendump(self):
        self._need()
        path = STATE / "screen.ppm"
        path.unlink(missing_ok=True)
        self.qmp.execute("screendump", filename=str(path))
        deadline = time.monotonic() + 5
        while not (path.exists() and path.stat().st_size > 0):
            if time.monotonic() > deadline:
                raise BoardError("screendump wrote nothing; is there a display?")
            time.sleep(0.05)
        return parse_ppm(path.read_bytes())

    def screenshot(self, x=0, y=0, width=None, height=None):
        w, h, rgb = self.screendump()
        if (x, y, width, height) != (0, 0, None, None):
            w, h, rgb = crop(w, h, rgb, x, y, width or w - x, height or h - y)
        return png(w, h, rgb)

    def pixels(self, points):
        w, h, rgb = self.screendump()
        out = []
        for x, y in points:
            if not (0 <= x < w and 0 <= y < h):
                raise BoardError(f"{x}, {y} is off the {w}x{h} screen")
            i = (y * w + x) * 3
            out.append({"x": x, "y": y, "r": rgb[i], "g": rgb[i + 1], "b": rgb[i + 2]})
        return out

    def press(self, keys):
        """Presses the qcodes keys together, then lets them go."""
        self._need()
        hold = int(KEY_HOLD * 1000)
        self.qmp.execute("send-key", keys=[{"type": "qcode", "data": k} for k in keys],
                         **{"hold-time": hold})
        time.sleep(KEY_HOLD + KEY_GAP)

    def type_keys(self, text, enter=True):
        combos = [key_combo(ch) for ch in text]  # every key known before any is typed
        if enter:
            combos.append(["ret"])
        for keys in combos:
            self.press(keys)
        return len(combos)

    def events(self, events):
        self._need()
        self.qmp.execute("input-send-event", events=events)
        time.sleep(POINTER_GAP)

    def move(self, x, y):
        self.events(at(x, y))

    def click(self, x, y, which="left"):
        self.move(x, y)
        self.events(button(True, which))
        self.events(button(False, which))

    def scroll(self, x, y, dy, dx=0):
        """Turns the wheel with the pointer at x, y, a step at a time."""
        self.move(x, y)
        for i in range(abs(dy)):
            self.events(wheel(0, 1 if dy > 0 else -1))
        for i in range(abs(dx)):
            self.events(wheel(1 if dx > 0 else -1, 0))

    def drag(self, x0, y0, x1, y1, steps=8, which="left"):
        self.move(x0, y0)
        self.events(button(True, which))
        for i in range(1, steps + 1):
            self.move(x0 + (x1 - x0) * i // steps, y0 + (y1 - y0) * i // steps)
        self.events(button(False, which))
