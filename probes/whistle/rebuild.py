"""rebuild.py -- Whistle's reference model, cactus-needle's JAX Whistle,
loaded from whistle.cact itself, for roadmap 0060: the oracle of the
stem's and the encoder's rows, which the reference otherwise gives only
from a training checkpoint.

  rebuild.py WEIGHTS CLIPDIR

export.py writes a checkpoint's parameters into the .cact in a fixed
order, transposed and reshaped; this reads them back (read_export, CQ
rows dequantised) and undoes each step, into the parameter tree
Whistle.init makes, so the weights are the very ones the engine and
L0S read. CLIPDIR is one of oracle.py's: from its clip16.wav it writes

  stem.txt     the stem's rows, T and 512 on the first line, then a row a line
  encoder.txt  the encoder's rows, the same
  encoderK.txt the encoder cut to its first K blocks, K from 1 to 8, the same
  greedy.txt   the reference's greedy token IDs (language tag first) and text
  decoder.txt  the decoder's rows over those tokens, BOS first, from the
               encoder's rows: row i the one whose logits gave token i + 1

all with quantisation simulated as the engine has it (W4A8, the KV
cache at the header's width). Run in oracle.py's venv, with
NEEDLE_TELEMETRY=0.
"""
import os
import struct
import sys

import numpy as np

os.environ["NEEDLE_TELEMETRY"] = "0"
weights, clip = sys.argv[1], sys.argv[2]

import jax
import jax.numpy as jnp
from needle.model import quantize
from needle.model.export import HADAMARD, PROJ, RefTokenizer, read_export
from needle.model.whistle import Whistle, WhistleConfig


def samples_of(path):
    raw = open(path, "rb").read()
    at = raw.index(b"data") + 8
    return np.frombuffer(raw[at:], "<i2").astype(np.float32) / 32768.0


def rebuild(params, ts, cfg):
    """The parameter tree with each leaf taken from the .cact's tensors, in
    export.py's order: _tensors, then _audio_tensors."""
    ts = list(ts)
    take = lambda: ts.pop(0)
    p = jax.tree_util.tree_map(np.array, params)

    def put(node, key, i, value):
        arr = node[key]
        if i is None:
            assert arr.shape == np.shape(value) or arr.size == np.size(value), (key, arr.shape, np.shape(value))
            node[key] = np.asarray(value, np.float32).reshape(arr.shape)
        else:
            arr[i] = np.asarray(value, np.float32).reshape(arr[i].shape)

    p["embedding"]["embedding"] = take()
    b = p["stack"]["layers"]["block"]
    sa, ha = b["self_attn"], b["hadamard_mlp"]
    for i in range(cfg.dec_layers):
        put(b["ZCRMSNorm_0"], "scale", i, take())
        for n in ("q_proj", "k_proj", "v_proj"):
            put(sa[n], "kernel", i, take().T)
        for n in ("q_taps", "k_taps", "v_taps"):
            put(sa, n, i, take())
        put(sa["q_norm"], "scale", i, take())
        put(sa["k_norm"], "scale", i, take())
        put(sa["gate_proj"], "kernel", i, take().T)
        put(sa["out_proj"], "kernel", i, take().T)
        put(b["post_attn_norm"], "scale", i, take())
        put(b, "attn_gate", i, take())
        put(b["pre_hada_norm"], "scale", i, take())
        for k in HADAMARD:
            put(ha, k, i, take())

    def mhc(node):
        for n in ("mhc_a_pre", "mhc_a_post", "mhc_a_res", "mhc_b_pre", "mhc_b_post", "mhc_b_res"):
            put(node, n, None, take())
        for n in ("mhc_phi_pre", "mhc_phi_post", "mhc_phi_res"):
            L, nC, lanes = node[n].shape
            node[n] = take().reshape(L, lanes, nC).transpose(0, 2, 1).copy()

    mhc(p["stack"])
    take(), take()  # hada_p1, hada_p2: computed, not parameters
    for s in range(len(cfg.sites)):
        eg = p[f"engrams_{s}"]
        put(eg, "embedding", None, take())
        eg["key_proj"]["kernel"] = take().T.copy()
        eg["value_proj"]["kernel"] = take().T.copy()
        put(eg, "taps", None, take())
    put(p["stack"]["final_norm"], "scale", None, take())

    manifest = take()
    assert manifest[0] == 3246.0, manifest
    ca = b["cross_attn"]
    for i in range(cfg.dec_layers):
        put(b["cross_norm"], "scale", i, take())
        for n in PROJ:
            put(ca[n], "kernel", i, take().T)
        put(ca["q_norm"], "scale", i, take())
        put(ca["k_norm"], "scale", i, take())
        put(b["post_cross_norm"], "scale", i, take())
        put(b, "cross_gate", i, take())
    put(p, "pe_gate", None, take())

    e = p["encoder"]["layers"]["block"]
    for i in range(cfg.enc_layers):
        for n in ("pre_hada_norm_0", "ZCRMSNorm_0", "post_attn_norm", "conv_norm", "conv_out_norm", "pre_hada_norm"):
            put(e[n], "scale", i, take())
        for n in PROJ:
            put(e["self_attn"][n], "kernel", i, take().T)
        put(e["self_attn"]["q_norm"], "scale", i, take())
        put(e["self_attn"]["k_norm"], "scale", i, take())
        put(e, "attn_gate", i, take())
        put(e["pw1"], "kernel", i, take().T)
        put(e["pw2"], "kernel", i, take().T)
        put(e, "dw", i, take())
        for mlp in ("hadamard_mlp_0", "hadamard_mlp"):
            for k in HADAMARD:
                put(e[mlp], k, i, take())
    mhc(p["encoder"])
    put(p["encoder"]["final_norm"], "scale", None, take())

    st = p["stem"]
    put(st, "w", None, take())
    for i in range(1, cfg.stem_stages):
        put(st, f"dw_{i}", None, take())
        st[f"pw_{i}"]["kernel"] = take().T.copy()
    st["out"]["kernel"] = take().T.copy()
    take()  # mel
    assert len(ts) == 1 and isinstance(ts[0], bytes), len(ts)
    return jax.tree_util.tree_map(jnp.asarray, p)


def rows(path, x):
    with open(path, "w") as f:
        f.write(f"{x.shape[0]} {x.shape[1]}\n")
        for r in x:
            f.write(" ".join(f"{v:.6f}" for v in r) + "\n")


cfg = WhistleConfig(remat=False)
meta, ts = read_export(weights)
quantize.configure_deploy(act_bits=8, kv_bits=meta["kv_bits"] or 8)
model = Whistle(cfg)
wav = samples_of(os.path.join(clip, "clip16.wav"))
x, n = jnp.asarray(wav)[None], jnp.asarray([len(wav)])
init = model.init(jax.random.PRNGKey(0), x[:, :16000], jnp.asarray([16000]), jnp.zeros((1, 4), jnp.int32))
params = rebuild(init["params"], ts, cfg)

(enc, frames), inter = model.apply({"params": params}, x, n, True, method=Whistle.encode,
                                   capture_intermediates=True)
t = int(frames[0])
stem = inter["intermediates"]["stem"]["__call__"][0][0]
rows(os.path.join(clip, "stem.txt"), np.asarray(stem[0, :t]))
rows(os.path.join(clip, "encoder.txt"), np.asarray(enc[0, :t]))
import dataclasses
for k in range(1, cfg.enc_layers + 1):
    cut = dataclasses.replace(cfg, enc_layers=k)
    sliced = dict(params)
    sliced["encoder"] = jax.tree_util.tree_map(lambda a: a, params["encoder"])
    for name in ("mhc_phi_pre", "mhc_phi_post", "mhc_phi_res", "mhc_a_pre", "mhc_a_post", "mhc_a_res",
                 "mhc_b_pre", "mhc_b_post", "mhc_b_res"):
        sliced["encoder"][name] = params["encoder"][name][:k]
    sliced["encoder"]["layers"] = jax.tree_util.tree_map(lambda a: a[:k], params["encoder"]["layers"])
    early, _ = Whistle(cut).apply({"params": sliced}, x, n, True, method=Whistle.encode)
    rows(os.path.join(clip, f"encoder{k}.txt"), np.asarray(early[0, :t]))

step = jax.jit(lambda tokens: model.apply({"params": params}, tokens, enc, frames, True, method=Whistle.logits))
tokens = np.full((1, cfg.max_tokens), cfg.pad, np.int32)
tokens[0, 0] = cfg.bos
tags = np.arange(cfg.vocab) >= cfg.text
for pos in range(cfg.max_tokens - 1):
    size = min(cfg.max_tokens, (pos // 64 + 1) * 64)
    logits = np.array(step(tokens[:, :size])[0, pos])
    logits[tags != (pos == 0)] = -np.inf
    tokens[0, pos + 1] = logits.argmax()
    if tokens[0, pos + 1] == cfg.eos:
        break
dec = model.apply({"params": params}, jnp.asarray(tokens[:, :pos + 1]), enc, frames, True, method=Whistle.decode)
rows(os.path.join(clip, "decoder.txt"), np.asarray(dec[0]))
ids = tokens[0, 1:pos + 1].tolist()
text = RefTokenizer.from_cact(weights).decode(ids[1:])
with open(os.path.join(clip, "greedy.txt"), "w") as f:
    f.write(" ".join(str(i) for i in ids) + "\n" + text + "\n")
print(f"{clip}: {t} encoder rows; greedy: {text}")
