"""cpio.py -- the agent's home as a cpio archive in the newc format, as
L0S's common/initramfs.l0 reads and agent backup writes one: each entry a
header of 110 bytes ("070701" and thirteen fields of eight hexadecimal
digits), its name and a NUL padded to 4 bytes, then its contents padded
the same; TRAILER!!! ends it. Pure: pack a directory's files as entries,
and read entries back, refusing a name that would leave the directory."""

import os

MAGIC = b"070701"
TRAILER = "TRAILER!!!"
DIR_MODE = 0o040755
FILE_MODE = 0o100644


def _pad(n):
    """The zeros after n bytes, to a multiple of 4."""
    return b"\0" * ((4 - n % 4) % 4)


def entry(name, mode, data=b""):
    """One entry's bytes: its header, name and contents, padded."""
    fields = [0, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name.encode()) + 1, 0]
    head = MAGIC + b"".join(b"%08x" % f for f in fields) + name.encode() + b"\0"
    return head + _pad(len(head)) + data + _pad(len(data))


def pack(entries):
    """An archive of entries, each (name, data), data None for a
    directory, then the trailer."""
    out = [entry(n, DIR_MODE if d is None else FILE_MODE, d or b"") for n, d in entries]
    out.append(entry(TRAILER, 0))
    return b"".join(out)


def unpack(b):
    """The entries of archive b, each (name, data), data None for a
    directory, up to its trailer; or raise ValueError saying why it is not
    one, or names a path that is absolute or holds .."""
    out, i = [], 0
    while True:
        if b[i:i + 6] != MAGIC or len(b) < i + 110:
            raise ValueError("no entry header at byte %d" % i)
        try:
            f = [int(b[i + 6 + 8 * k:i + 14 + 8 * k], 16) for k in range(13)]
        except ValueError:
            raise ValueError("a header that is not hexadecimal at byte %d" % i)
        mode, size, namesize = f[1], f[6], f[11]
        name = b[i + 110:i + 110 + namesize - 1].decode("utf-8", "replace")
        start = i + 110 + namesize
        start += (4 - start % 4) % 4
        if name == TRAILER:
            return out
        if start + size > len(b):
            raise ValueError("%s runs past the archive's end" % name)
        name = name[2:] if name.startswith("./") else name
        parts = name.split("/")
        if name.startswith("/") or ".." in parts or not name:
            raise ValueError("%r would be outside the home" % name)
        kind = mode & 0o170000
        if kind == 0o040000:
            out.append((name.rstrip("/"), None))
        elif kind == 0o100000:
            out.append((name, b[start:start + size]))
        else:
            raise ValueError("%s is neither a file nor a directory" % name)
        i = start + size
        i += (4 - i % 4) % 4


def gather(root):
    """The entries of the directory root, each directory before what is in
    it, in name order: as pack takes them."""
    out = []
    for d, dirs, files in os.walk(root):
        dirs.sort()
        rel = os.path.relpath(d, root)
        if rel != ".":
            out.append((rel.replace(os.sep, "/"), None))
        for n in sorted(files):
            with open(os.path.join(d, n), "rb") as f:
                out.append(((n if rel == "." else os.path.join(rel, n)).replace(os.sep, "/"), f.read()))
    return out


def write_tree(root, entries):
    """entries, as unpack gives them, written under root, which is made."""
    os.makedirs(root, exist_ok=True)
    for n, d in entries:
        p = os.path.join(root, *n.split("/"))
        if d is None:
            os.makedirs(p, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(d)
