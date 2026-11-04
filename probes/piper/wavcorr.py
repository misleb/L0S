"""wavcorr.py -- how alike two WAV files of 16-bit mono samples are, for
roadmap 0062's speak test: their correlation, the dot of their samples
over the root of their squares' product, so a scale (speak normalizes,
the oracle does not) does not count. Python's own library only.

  wavcorr.py A.wav B.wav [LEAST]

Prints the rates, the lengths and the correlation; with LEAST, exits 1
unless the rates and lengths are the same and the correlation is at
least LEAST.
"""
import array
import math
import sys
import wave


def samples(path):
    with wave.open(path, "rb") as w:
        if w.getsampwidth() != 2 or w.getnchannels() != 1:
            sys.exit("wavcorr: %s is not 16-bit mono" % path)
        a = array.array("h")
        a.frombytes(w.readframes(w.getnframes()))
        if sys.byteorder == "big":
            a.byteswap()
        return w.getframerate(), a


def main():
    ra, a = samples(sys.argv[1])
    rb, b = samples(sys.argv[2])
    ab = sum(x * y for x, y in zip(a, b))
    aa = sum(x * x for x in a)
    bb = sum(y * y for y in b)
    c = ab / math.sqrt(aa * bb) if aa and bb else 0.0
    print("rates %d %d, samples %d %d, correlation %.6f" % (ra, rb, len(a), len(b), c))
    if len(sys.argv) > 3 and not (ra == rb and len(a) == len(b) and c >= float(sys.argv[3])):
        sys.exit(1)


main()
