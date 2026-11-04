"""release.py -- a release of L0S as the proxy serves it (roadmap 0027):
a directory DIR/BOARD for each board, pi5 or virt, holding a directory
for each part:

  system/   the system volume's files: bin, sbin, Applications, etc
  boot/     the Pi 5's boot partition: l0.img, config.txt, cmdline.txt,
            the device trees, input.bin
  speech/   the data volume's speech directory: whistle.cact, and speak's
            voice, en_US-ljspeech-medium.onnx and its .json, and
            cmudict.dict
  agent/    the agent's home, seeded: CLAUDE.md, CONSTITUTION.md
  eeprom/   a release pieeprom.bin, for the boot order

any of which may be missing. tools/mkrelease stages one. The manifest
is made from the files as they are, one line each,

  PART SIZE SHA256 MODE PATH

MODE x for a program (any execute bit) and - otherwise, PATH within the
part, in order of part and then path; a file's hash is kept until its
size or time changes, so a manifest asked for again costs a walk."""

import hashlib
import os
import re

PARTS = ("boot", "system", "speech", "agent", "eeprom")
BOARD = re.compile(r"^[a-z0-9]+$")

_hashes = {}


def file_hash(path, st):
    """The SHA-256 in hex of the file at path, st its stat, kept until its
    size or time changes."""
    key = (path, st.st_size, st.st_mtime_ns)
    h = _hashes.get(key)
    if h is None:
        d = hashlib.sha256()
        with open(path, "rb") as f:
            for piece in iter(lambda: f.read(1 << 20), b""):
                d.update(piece)
        h = d.hexdigest()
        _hashes[key] = h
    return h


def board_dir(root, board):
    """root/board, or None if board is not a board's name or has no
    release there."""
    if not BOARD.match(board or ""):
        return None
    d = os.path.join(root, board)
    return d if os.path.isdir(d) else None


def manifest(root, board):
    """The board's manifest, as bytes, or None if it has no release."""
    d = board_dir(root, board)
    if d is None:
        return None
    lines = []
    for part in PARTS:
        top = os.path.join(d, part)
        if not os.path.isdir(top):
            continue
        found = []
        for dirpath, dirnames, filenames in os.walk(top):
            dirnames.sort()
            for n in filenames:
                p = os.path.join(dirpath, n)
                if os.path.isfile(p) and not os.path.islink(p):
                    found.append(os.path.relpath(p, top))
        for rel in sorted(found):
            p = os.path.join(top, rel)
            st = os.stat(p)
            mode = "x" if st.st_mode & 0o111 else "-"
            lines.append("%s %d %s %s %s\n" % (part, st.st_size, file_hash(p, st), mode, rel.replace(os.sep, "/")))
    return "".join(lines).encode()


def resolve(root, board, rel):
    """The file root/board/rel names, PART/PATH, or None if it is not a
    file of a part, or would lie outside the board's release."""
    d = board_dir(root, board)
    if d is None or not rel or rel.split("/")[0] not in PARTS:
        return None
    base = os.path.realpath(d)
    p = os.path.realpath(os.path.join(base, rel))
    if not p.startswith(base + os.sep) or not os.path.isfile(p):
        return None
    return p
