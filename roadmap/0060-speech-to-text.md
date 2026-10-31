# 0060: Whistle on the board: speech to text in L0

Track: Agent · Status: active · Needs: – · Spec: speech.md, programs.md, testing.md

## Why

What is said to the board should reach the agent as text (0061), and
the board should hear it itself, with no host to send it to: the Pi 5
alone, as a Pi on a desk is. [Whistle](https://cactuscompute.com/blog/whistle),
Cactus Compute's open speech recognition model (Apache-2.0, its
[weights](https://huggingface.co/Cactus-Compute/whistle) one 16.9 MB
file, `whistle.cact`), runs on a CPU alone, from 16 kHz mono audio, in
seven languages, English first. Its engine, Needle, is C++, and L0S
runs only L0: the engine is written again in L0, as a library, from
its reference in Python (`cactus-needle`,
[source](https://github.com/cactus-compute/needle), Apache-2.0) and the
[porting guide](https://cactuscompute.com/blog/porting-needle).

## Done when

- A library reads a `.cact` container in place, as bytes: its header,
  its directory of tensors by order (no names), each tensor's dtype,
  shape, offset, group and bits, refusing a tag or a count it does not
  know; and its SentencePiece BPE vocabulary, stored at its end.
- Its weights used as they are stored: CQ2 and CQ4 (2.125 and 4.125
  bits a weight; groups of 128 along the reduction axis, each an FP16
  norm and a direction snapped to a shared Lloyd-Max codebook of 4, 8
  or 16 unit-sphere centroids, rotated by the Walsh-Hadamard matrix),
  and FP16; activations and the KV cache in int8, as the engine has
  them.
- Whistle's path from samples to text: its log-mel front end (an FFT
  of L0's own), its convolutional stem and audio encoder (a row per 80
  ms), and its Needle-shaped decoder reading the encoder through gated
  cross attention at every layer, at the depth asked (`--audio-depth`),
  decoding greedily to token IDs and then text; a clip up to 30 s in
  one pass, longer ones in windows.
- `listen FILE.wav` on the board prints a WAV file's text, and a
  program can call the library (`whistle_transcribe`).
- Tested against the reference: a host tool runs `cactus-needle` in
  float32 with quantisation simulated, the oracle, on a few clips, and
  the library's token IDs are the same byte for byte, its front end's
  and encoder's rows within a cosine of 0.999; on the Pi 5, a 10 s clip
  transcribed in a time this goal measures and states.

## Steps

Whistle, as `cactus-needle`'s `needle/model/whistle.py` and the
container's audio manifest give it: 16 kHz mono; 80 log-mel bins of a
512-point FFT of 400-sample Hann windows every 160 samples, normalized
over the utterance; a stem of three 3x3 convolutions of stride 2 (1 to
128 channels, then depthwise and pointwise twice, SiLU), its 1280
features a frame projected to 512; an encoder of 8 blocks on 4 residual
lanes (mHC, mixed by Sinkhorn); a decoder of 8 Needle blocks
(self-attention with causal conv taps, gated cross-attention, a
Hadamard MLP, engram memories at layers 3 and 7) on 4 lanes; logits on
the embedding, 8192 text tokens and 7 language tags.

- [x] The container: `format/cact.l0` reads the header, the codebooks,
  the directory, FP16 and FP32 tensors, and CQ rows of 2 and 4 bits
  through the fast Walsh-Hadamard transform; tested on a container
  built in its tests, and on `whistle.cact` itself against a decoder
  in Python written from the format alone (`probes/whistle`), the same
  to every digit printed.
- [x] The tokenizer: the RAW SentencePiece BPE record read, token IDs
  to text (`pieces_decode`); the reference's decodings of two
  recordings' tokens the same.
- [x] The front end (`speech/mel.l0`): the FFT, the window, the mel
  matrix (computed, and the same as the file's), the logarithm and the
  normalization, from 16 kHz samples; within 0.000074 of the
  reference's features on two recordings, and of a chirp, a fixture,
  within 0.001 in `mel_test.l0`.
- [x] The stem (`speech/whistle.l0`, its arithmetic `speech/nn.l0`):
  every row within a cosine of 0.999999 of the reference's on two
  recordings (`probes/whistle/stemcheck`).
- [x] The encoder (`speech/encoder.l0`): ZC-RMSNorm, the Hadamard MLP,
  self-attention with RoPE, the conv module (GLU, a depthwise kernel of
  9), the lanes, and activations fake-quantized to int8 where the
  engine does. Every row at 0.9995 or more after each block but one
  the reference itself is unstable on (`probes/whistle/enccheck`); the
  reference's decoder makes the same tokens from L0's rows.
- [x] The decoder (`speech/decoder.l0`): self-attention with its taps
  and an int8 KV cache, cross-attention over the encoder's rows plus
  gated sinusoids, the engrams, the lanes, greedy decoding from a
  language tag to EOS. The reference's tokens on both recordings, from
  its encoder's rows and from L0's own, every row at 0.9994 or more
  (`probes/whistle/deccheck`).
- [ ] The oracle and `listen`: `cactus-needle` run on the host on a
  few clips (`probes/whistle/oracle.py`: features, the engine's text,
  tokens; `rebuild.py`: its JAX model loaded from the `.cact`, the
  stem's and encoder's rows and its greedy tokens); `listen FILE.wav`
  on QEMU giving the engine's text.
- [ ] On a Pi 5: a 10 s clip's time, scalar and, once L0 has it,
  with vector arithmetic over bytes
  ([REQUEST-vector-arithmetic.md](../probes/vector/REQUEST-vector-arithmetic.md):
  L0 is 55 times slower than vectorized C at an int8 dot product
  today), and whether it then wants the Pi 5's four CPUs.

Open: where the 16.9 MB model lives, in the initramfs or on the data
volume, and how it is read, whole or in pieces; whether its licence's
NOTICE goes beside it, as the icons' licences do; how well it hears,
as its page has it behind Whisper's base on some test sets (TED-LIUM,
AMI).

## Spec changes

- speech.md (the container, the tokenizer, the front end, the stem,
  the encoder, the decoder and listening on QEMU are in): the Pi 5's
  timing, and the limits it changes.
- programs.md: in (`listen`'s row, and the container's, the front
  end's, `nn.l0`'s, `whistle.l0`'s, `encoder.l0`'s, `decoder.l0`'s and
  `transcribe.l0`'s).
- testing.md: more clips, the run on the Pi 5 (the fixtures, probes
  and `tests/listen.sh` are in).

## Log

- 2026-10-31: written, as the user asked, after 0058's prompt sources.
  Read "Whistle" as Whisper, speech to text.
- 2026-10-31: the user chose Whisper's small free model, run on the
  host: no API.
- 2026-10-31: the user meant Whistle, Cactus Compute's model, not
  Whisper: Whistle on the host, by `cactus-needle`.
- 2026-10-31: the user wants it on the Pi: Whistle written in L0, on
  the board, no host. The service that listens and says what it hears
  to the agent split off as 0061.
- 2026-10-31: needs vector arithmetic over bytes from L0, asked in
  probes/vector/REQUEST-vector-arithmetic.md, with a measurement
  (`probes/vector/dot.l0`): an int8 multiply-add 1930 ps in L0, 274 ps
  in scalar C, 35 ps in vectorized C.
- 2026-10-31: the user had `whistle.cact` (16,919,407 bytes, Hugging
  Face) and `cactus-needle`'s source (GitHub) fetched, kept outside the
  project and read, not run. Steps written from them; step 1 done, the
  container read in L0 and checked on the model itself. The vector
  request is no longer a Need to start: the port goes on in scalar
  arithmetic, and the last step measures it.
- 2026-10-31: the user had `cactus-needle[train]` installed, in a venv
  of the scratchpad's, and run with NEEDLE_TELEMETRY=0 (its first run,
  before that was set, sent its anonymous usage counts). Its engine
  hears ALSA's "Front center" as "FRENT, CENTER." and "Rear left" as
  "Rear, left.". Steps 2 and 3 done against it. Its JAX model loads
  only a training checkpoint, not the `.cact`, so the encoder's rows
  have no oracle yet: either Cactus's checkpoint is fetched, or the
  `.cact`'s tensors are put back into its parameters, export.py's
  order in reverse.
- 2026-10-31: the user chose to rebuild the reference from the `.cact`
  rather than fetch a checkpoint: `probes/whistle/rebuild.py` puts
  `whistle.cact`'s tensors back into the JAX model's parameters,
  export.py's steps undone; it hears "Rear left" as the engine does,
  and "Front center" as "FRENT. CENTER." (the engine "FRENT,
  CENTER."), its quantisation simulated. Steps 4 and 5 done against
  it, in scalar code but for `bytes_dot_f32`, L0's vector arithmetic,
  which has landed (L0's 0148 to 0150): `enccheck`, the model read and
  the encoder run nine times over 1.4 s of speech, takes 1.9 s on the
  host.
- 2026-10-31: step 6 done, as the user asked: the decoder, a token at a
  time with its keys and values kept, no array copied. `rebuild.py`
  also writes the decoder's rows. `deccheck` gives the reference's
  tokens and text on both recordings, from its encoder's rows and from
  L0's own; on the host the model loads in 1.1 s (every matrix
  dequantized, about 140 MB), the front end, stem and encoder of 1.4 s
  of speech take 1 s with the encoder's loading, and the decoder about
  15 ms a token. The Hadamard MLP and mHC are shared with the
  encoder (`hmlp_rows` takes the permutations, `mhc_of`).
- 2026-10-31: step 7 begun, as the user asked ("try the qemu test"):
  `speech/transcribe.l0` (`whistle_listener`, `whistle_transcribe`,
  `wav_speech`), `listen [-t] [-m MODEL] FILE.wav...`, and
  `tests/listen.sh`, which boots it on QEMU with the model and the two
  recordings in the initramfs: both give the reference's text. On one
  emulated CPU the model loads in 36 s (its CQ rows dequantized in
  scalar code) and each 1.3 to 1.4 s clip is heard in 5.5 to 6.7 s.
  Left of the step: more clips than the two, and the engine's text
  where it differs from the reference's ("FRENT, CENTER." against
  "FRENT. CENTER.").
- 2026-10-31: `tools/qemu-boot.sh` boots a Cortex-A76, as L0's `virt`
  target now assumes (its vector work): on the A72 it had, the kernel
  faulted on an `LDAPR`, and every case booted through it failed.
