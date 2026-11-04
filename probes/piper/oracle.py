"""oracle.py -- Piper's own synthesis, run on the host for roadmap 0062:
what L0S's port of a Piper voice must give for a sentence.

  oracle.py VOICE.onnx OUTDIR NAME=TEXT...

For each NAME=TEXT, OUTDIR/NAME/ gets, from Piper's own phonemizer
(espeak-ng, voice en-us; see README.md for why not the config's "en")
and the voice run by onnxruntime with its noise at 0 (scales 0, 1, 0, so
it is deterministic):

  phonemes.txt   a sentence a line, its phonemes as Piper gives them
  ids.txt        a sentence a line, its phoneme IDs, spaces between
  and for the first sentence only, the stages, each a file of
  little-endian binary32s, channel-last (a time step's channels after
  one another), its rows and columns in shapes.txt:
  enc.f32        the text encoder's output x, before the projection
  m_p.f32        the prior's means, a phoneme a row
  logs_p.f32     the prior's log deviations
  logw.f32       the duration predictor's log durations, a phoneme a row
  w_ceil.f32     the durations in frames
  z_p.f32        the means stretched over the frames (noise 0)
  z.f32          the flow's output, reversed
  audio.f32      the samples, as the vocoder makes them, in -1 to 1
  audio.wav      the same as 16-bit PCM at the voice's rate, unnormalized

Run in a venv with piper-tts, onnx, onnxruntime and numpy installed.
"""
import json
import os
import struct
import sys

import numpy as np
import onnx
import onnxruntime as ort
from piper.phonemize_espeak import EspeakPhonemizer
from piper.phoneme_ids import phonemes_to_ids

VOICE = "en-us"
STAGES = {
    "enc": "/enc_p/encoder/Mul_2_output_0",
    "m_p": "/enc_p/Split_output_0",
    "logs_p": "/enc_p/Split_output_1",
    "logw": "/dp/Split_output_0",
    "w_ceil": "/Ceil_output_0",
    "z_p": "/Add_output_0",
    "z": "/Mul_7_output_0",
}


def session(path):
    """The voice with each stage made an output of the graph too."""
    m = onnx.load(path)
    for name in STAGES.values():
        m.graph.output.append(onnx.helper.make_tensor_value_info(name, onnx.TensorProto.FLOAT, None))
    return ort.InferenceSession(m.SerializeToString(), providers=["CPUExecutionProvider"])


def channel_last(a):
    """A [1, C, T] tensor as rows of T by C, binary32."""
    a = np.asarray(a, np.float32)
    return a.reshape(a.shape[-2], a.shape[-1]).T.copy()


def write_wav(path, rate, samples):
    q = np.clip(np.round(samples * 32767.0), -32768, 32767).astype("<i2")
    n = len(q) * 2
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", n + 36) + b"WAVEfmt "
                + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
                + b"data" + struct.pack("<I", n) + q.tobytes())


def main():
    voice, out = sys.argv[1], sys.argv[2]
    config = json.load(open(voice + ".json"))
    rate = config["audio"]["sample_rate"]
    id_map = config["phoneme_id_map"]
    sess = session(voice)
    outputs = ["output"] + list(STAGES.values())
    phonemizer = EspeakPhonemizer()
    for arg in sys.argv[3:]:
        name, text = arg.split("=", 1)
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        sentences = phonemizer.phonemize(VOICE, text)
        ids = [phonemes_to_ids(s, id_map) for s in sentences]
        with open(os.path.join(d, "text.txt"), "w") as f:
            f.write(text + "\n")
        with open(os.path.join(d, "phonemes.txt"), "w") as f:
            f.write("".join("".join(s) + "\n" for s in sentences))
        with open(os.path.join(d, "ids.txt"), "w") as f:
            f.write("".join(" ".join(map(str, i)) + "\n" for i in ids))
        x = np.array([ids[0]], np.int64)
        res = sess.run(outputs, {
            "input": x,
            "input_lengths": np.array([x.shape[1]], np.int64),
            "scales": np.array([0.0, 1.0, 0.0], np.float32),
        })
        shapes = []
        for (stage, _), value in zip(STAGES.items(), res[1:]):
            rows = channel_last(value)
            rows.astype("<f4").tofile(os.path.join(d, stage + ".f32"))
            shapes.append("%s %d %d\n" % (stage, rows.shape[0], rows.shape[1]))
        audio = np.asarray(res[0], np.float32).reshape(-1)
        audio.astype("<f4").tofile(os.path.join(d, "audio.f32"))
        shapes.append("audio %d 1\n" % len(audio))
        with open(os.path.join(d, "shapes.txt"), "w") as f:
            f.write("".join(shapes))
        write_wav(os.path.join(d, "audio.wav"), rate, audio)
        print("%s: %d sentences, %d IDs, %d frames, %d samples" % (
            name, len(ids), len(ids[0]), int(res[1 + 4].sum()), len(audio)))


main()
