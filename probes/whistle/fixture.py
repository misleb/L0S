"""fixture.py -- the front end's test fixture for user/lib/speech/mel.l0:
half a second of a chirp from 200 Hz to 4 kHz with a little noise, at
16 kHz, 16 bits, as OUT/chirp.wav; and what cactus-needle's whistle.py
makes of it, OUT/chirp.features (its first line T and 80, then a frame
a line, 4 places), and its mel matrix's every 37th entry, row-major,
OUT/mel.sample (6 places).

  fixture.py OUT

Run in the venv oracle.py runs in.
"""
import os
import struct
import sys

import numpy as np
import jax.numpy as jnp
from needle.model.whistle import WhistleConfig, features, mel_matrix

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
n = 8000
t = np.arange(n) / 16000.0
chirp = 0.5 * np.sin(2 * np.pi * (200.0 * t + (3800.0 / 1.0) * t * t))
rng = np.random.default_rng(7)
x = chirp + 0.01 * rng.standard_normal(n)
q = np.clip(np.round(x * 32768.0), -32768, 32767).astype("<i2")
with open(os.path.join(out, "chirp.wav"), "wb") as f:
    f.write(b"RIFF" + struct.pack("<I", 2 * n + 36) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16)
            + b"data" + struct.pack("<I", 2 * n) + q.tobytes())
cfg = WhistleConfig()
feats, lengths = features(cfg, jnp.asarray(q.astype(np.float32) / 32768.0)[None], jnp.asarray([n]))
frames = int(lengths[0])
with open(os.path.join(out, "chirp.features"), "w") as f:
    f.write(f"{frames} 80\n")
    for row in np.asarray(feats[0, :frames]):
        f.write(" ".join(f"{v:.4f}" for v in row) + "\n")
m = mel_matrix(cfg).reshape(-1)
with open(os.path.join(out, "mel.sample"), "w") as f:
    f.write(" ".join(f"{v:.6f}" for v in m[::37]) + "\n")
print(f"{n} samples, {frames} frames, {len(m[::37])} mel entries")
