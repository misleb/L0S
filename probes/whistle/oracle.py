"""oracle.py -- Whistle's reference, cactus-needle, run on the host for
roadmap 0060: what L0S's port of Whistle must give for a clip.

  oracle.py WEIGHTS IN.wav OUTDIR

IN.wav, any rate and channels, is made mono and 16 kHz as the engine
makes it (soxr), then 16-bit, and written as OUTDIR/clip16.wav, the
input L0S reads; from those very samples it writes OUTDIR/features.txt,
the log-mel front end of cactus-needle's whistle.py (its first line T
and 80, then a frame a line, 6 places), OUTDIR/text.txt, what the
engine transcribes, and OUTDIR/tokens.txt, the reference tokenizer's
IDs for that text and its decoding of them back.

Run in a venv with cactus-needle[train] installed, NEEDLE_TELEMETRY=0
so it reports nothing, and NEEDLE_WHISTLE_WEIGHTS set to WEIGHTS.
"""
import os
import struct
import sys

import numpy as np

weights, src, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.environ["NEEDLE_TELEMETRY"] = "0"
os.environ["NEEDLE_WHISTLE_WEIGHTS"] = weights
os.makedirs(out, exist_ok=True)

import jax.numpy as jnp
import needle
from needle.agent.whistle import _read_wav
from needle.model.export import RefTokenizer
from needle.model.whistle import WhistleConfig, features

mono = np.asarray(_read_wav(src), np.float32)
q = np.clip(np.round(mono * 32768.0), -32768, 32767).astype("<i2")
with open(os.path.join(out, "clip16.wav"), "wb") as f:
    n = len(q) * 2
    f.write(b"RIFF" + struct.pack("<I", n + 36) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16)
            + b"data" + struct.pack("<I", n) + q.tobytes())
samples = q.astype(np.float32) / 32768.0

x, lengths = features(WhistleConfig(), jnp.asarray(samples)[None], jnp.asarray([len(samples)]))
t = int(lengths[0])
with open(os.path.join(out, "features.txt"), "w") as f:
    f.write(f"{t} 80\n")
    for row in np.asarray(x[0, :t]):
        f.write(" ".join(f"{v:.6f}" for v in row) + "\n")

text = needle.transcribe(samples)["text"]
with open(os.path.join(out, "text.txt"), "w") as f:
    f.write(text + "\n")

tok = RefTokenizer.from_cact(weights)
ids = tok.encode(text)
with open(os.path.join(out, "tokens.txt"), "w") as f:
    f.write(" ".join(str(i) for i in ids) + "\n" + tok.decode(ids) + "\n")
print(f"{src}: {len(samples)} samples, {t} frames: {text}")
