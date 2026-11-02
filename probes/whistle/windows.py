"""windows.py -- the reference's text of a clip over 30 s, for roadmap
0060: the clip cut where L0S's transcribe.l0 cuts it, each window heard
by rebuild.py, and their texts joined by a space, as L0S joins them.

  windows.py WEIGHTS CLIPDIR

CLIPDIR holds clip16.wav, 16 kHz mono of 16 bits, as oracle.py writes
it. Its windows are transcribe_windows's: 30 s or less, each cut at the
middle of the quietest 100 ms of its last 5 s (frames of 1600 samples
from 25 s on, the first of any equal, by the sum of squares), a last
piece under 0.1 s left out. Each is written as CLIPDIR/winK/clip16.wav
and rebuild.py run on it, so winK holds its rows and greedy.txt; then
CLIPDIR/greedy.txt is the windows, S-E each, on its first line, and the
joined text on its second, which tests/listen.sh compares. Run in
oracle.py's venv, with NEEDLE_TELEMETRY=0.
"""
import os
import subprocess
import sys
import wave

import numpy as np

MOST, LEAST, LOOK, FRAME = 480000, 1600, 80000, 1600

weights, clip = sys.argv[1], sys.argv[2]
os.environ["NEEDLE_TELEMETRY"] = "0"
with wave.open(os.path.join(clip, "clip16.wav")) as w:
    q = np.frombuffer(w.readframes(w.getnframes()), "<i2")
x = q.astype(np.float64) / 32768.0


def windows(n):
    s, out = 0, []
    while n - s > MOST:
        a, b = s + MOST - LOOK, s + MOST
        best, energy, at = a, None, a
        while at + FRAME <= b:
            e = float(np.sum(x[at:at + FRAME] ** 2))
            if energy is None or e < energy:
                energy, best = e, at
            at += FRAME
        cut = best + FRAME // 2
        out.append((s, cut))
        s = cut
    if n - s >= LEAST:
        out.append((s, n))
    return out


texts = []
spans = windows(len(q))
rebuild = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rebuild.py")
for k, (a, b) in enumerate(spans):
    d = os.path.join(clip, f"win{k}")
    os.makedirs(d, exist_ok=True)
    with wave.open(os.path.join(d, "clip16.wav"), "wb") as o:
        o.setnchannels(1)
        o.setsampwidth(2)
        o.setframerate(16000)
        o.writeframes(q[a:b].tobytes())
    subprocess.run([sys.executable, "-I", rebuild, weights, d], check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(d, "greedy.txt")) as f:
        text = f.read().splitlines()[1]
    if text:
        texts.append(text)
joined = " ".join(texts)
with open(os.path.join(clip, "greedy.txt"), "w") as f:
    f.write(" ".join(f"{a}-{b}" for a, b in spans) + "\n" + joined + "\n")
print(f"{clip}: {len(spans)} windows; greedy: {joined}")
