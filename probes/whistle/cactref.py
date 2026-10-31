"""cactref.py -- a decoder of Needle 3's .cact CQ rows, written from the
format export.py describes, independent of cactus-needle's code, to
check format/cact.l0 against: the same lines cactdump.l0 prints."""
import math, struct, sys

raw = open(sys.argv[1], "rb").read()
hdr = struct.unpack_from("<48If", raw, 0)
n, cbn = hdr[1], hdr[2]
cb = struct.unpack_from("<%df" % cbn, raw, 196)
off = 196 + 4 * cbn
recs = [struct.unpack_from("<BBHIIIIQQII", raw, off + 44 * i) for i in range(n)]
f16 = lambda b: struct.unpack("<e", b)[0]

def row(k, r):
    dt, nd, _, o, i, _, _, at, size, g, bits = recs[k]
    pad = (i + g - 1) // g * g
    rb = pad * bits // 8
    groups = pad // g
    base = {2: 0, 3: 4, 4: 12}[bits]
    out = []
    for j in range(groups):
        norm = f16(raw[at + o * rb + 2 * (r * groups + j) : at + o * rb + 2 * (r * groups + j) + 2])
        u = []
        for t in range(g):
            kk = j * g + t
            p = at + r * rb + (kk // 8) * bits
            word = int.from_bytes(raw[p : p + bits], "little")
            u.append(cb[base + ((word >> ((kk % 8) * bits)) & ((1 << bits) - 1))] * norm)
        for x in range(g):
            out.append(sum(u[y] * (-1) ** bin(x & y).count("1") for y in range(g)) / math.sqrt(g))
    return out[:i]

def f6(x):
    v = int(x * 1000000.0)
    return str(v)

print("tensors", n)
m = struct.unpack_from("<13f", raw, recs[237][7])
print("manifest", " ".join(str(int(x)) for x in m))
for k, r in ((2, 0), (2, 383), (0, 1000), (0, 8198)):
    a = row(k, r)
    print(k, r, *[f6(x) for x in a[:4]], f6(sum(a)))
