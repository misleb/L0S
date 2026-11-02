# Speech

L0S has Whistle's path from samples to text, written in L0: its
container, tokenizer, front end, stem, audio encoder and decoder. Whistle is Cactus Compute's open speech recognition model, whose weights are
one file, `whistle.cact` (16.9 MB, Apache-2.0,
[Hugging Face](https://huggingface.co/Cactus-Compute/whistle)), and
whose reference is `cactus-needle`
([source](https://github.com/cactus-compute/needle), Apache-2.0).
Neither is in the project: `probes/whistle` says how they are fetched
and run on the host, and what L0S's parts are checked against.

## The container

[format/cact.l0](../user/lib/format/cact.l0) reads a Needle 3 `.cact`
container in place, as `export.py` writes it:

| Part | Holds |
|---|---|
| header | 48 u32s and an f32: the tag 0x05E12A84 (a Needle 2 one, 0x05E12A83, is refused), the tensors, the codebooks' floats, the KV cache's window and bits, then the geometry (vocabulary, width, heads, layers, head sizes, the Hadamard size, lanes, engram sites), and rope theta |
| codebooks | f32s, Lloyd-Max levels on the unit sphere: 4 for 2 bits, 8 for 3, 16 for 4 |
| directory | a record of 44 bytes a tensor, in an order that is the contract, since none has a name: its type (FP16, FP32, CQ, RAW), dimensions, offset, size, group and bits |
| tensors | each at its offset, 64-byte aligned |

A CQ matrix is each row's indices, `bits` each, eight packed least
significant first, then each row's each group's FP16 norm; a group of
128 weights is its codebook's entries times its norm, rotated back by
the Walsh-Hadamard matrix over the square root of 128 (`cq_row`, by the
fast transform). `whistle.cact` has 681 tensors: 145 CQ matrices of 2
bits, 7 of 4 (the embedding among them), 524 FP16 and 4 FP32 ones (the
mel filters, the audio manifest, two Hadamard permutations), and its
tokenizer, RAW.

The tokenizer is a SentencePiece BPE vocabulary: 8192 pieces and 7
language tags, `<|en|>` to `<|pl|>`, 8192 to 8198. `pieces_decode`
spells token IDs as SentencePiece does: a byte piece `<0xAB>` its byte,
control and unknown pieces nothing, the meta space U+2581 a space, and
the first space dropped.

## The front end

[speech/mel.l0](../user/lib/speech/mel.l0) makes Whistle's features of
16 kHz samples, as `whistle.py`'s `features` does: frames of 400
samples under a symmetric Hann window, every 160, the signal padded
with 200 zeros each side, `n / 160` frames of `n` samples; each padded
to 512 and turned by a radix-2 FFT; each frame's power through 80 mel
filters (`mel_matrix`: triangles on a scale linear below 1 kHz and
logarithmic above, each of area 1), the natural logarithm of it plus
2^-24; and each filter normalized over the clip, its mean taken away
and divided by its standard deviation (over frames less 1) plus
0.00001. L0's library has no logarithm or exponential, so `mel.l0` has
its own (`float_ln`, `float_exp`), by powers of 2 and their series.

It works in 64 bits, the reference in 32: on ALSA's recordings "Front
center" and "Rear left" its features are within 0.000074 of the
reference's, and its filters the same as those `whistle.cact` holds to
within a millionth.

## The stem and the encoder

[speech/whistle.l0](../user/lib/speech/whistle.l0) finds a model's
audio tensors by position after its audio manifest (an FP32 tensor of
13 whose first is 3246), and runs its stem, as `whistle.py`'s `Stem`:
a 3x3 convolution of stride 2 from the features to 128 channels, then
twice SiLU, a depthwise 3x3 of stride 2 and a pointwise 128 by 128,
each padded by zeros; SiLU, each row's 128 channels of 10 columns,
channel first, quantized to int8 and back, times a matrix to 512. A row
every 8 frames, 80 ms.

[speech/encoder.l0](../user/lib/speech/encoder.l0) runs the encoder on
those rows: 8 blocks on 4 residual lanes, the lanes' mean then normed.
Before each block mHC unit-norms each row's lanes, 2048 wide, and takes
from them by three CQ matrices the block's input (the lanes weighted
by sigmoids), how its change is added to each lane (twice a sigmoid),
and a 4 by 4 mixing of the lanes (Sinkhorn, 20 rounds). A block is a
Hadamard MLP at half weight, self-attention (8 query heads of 48 over 2
key and value heads of 48 and 64, each head normed and turned by RoPE,
theta 100000, gated by a sigmoid of its own row), a convolution module
(a GLU, a depthwise kernel of 9 over the clip's rows, SiLU) and another
Hadamard MLP at half weight, each part after a zero-centred RMS norm.
A Hadamard MLP is three Kronecker products of 16 by 16 and 32 by 32
factors with diagonals between, a SiLU, two fixed permutations (the
container's two FP32 tensors) and a conditioning of rank 8.

As the engine does, every matrix's input row is quantized to int8 and
back, and each head's query, key and value row too.
[speech/nn.l0](../user/lib/speech/nn.l0) has the arithmetic: a CQ
matrix is dequantized once into binary32s held in bytes, and each
product of a row is a `bytes_dot_f32`, in binary32 as the reference;
the rest is in 64 bits.

The reference, `cactus-needle`'s JAX model, loaded with
`whistle.cact`'s own tensors (`probes/whistle/rebuild.py`), gives the
oracle. On "Front center" and "Rear left" every stem row has a cosine
of 0.999999 with the reference's, and the encoder's rows 0.9995 or
more but one, row 9 of "Rear left" after the last block, at 0.976: the
reference itself moves that row to 0.82 when its samples are changed by
one part in 10,000, as an int8 rounding there turns the other way. The
reference's decoder, given L0's encoder rows, makes the same tokens as
from its own on both.

## The decoder

[speech/decoder.l0](../user/lib/speech/decoder.l0) turns the encoder's
rows into token IDs, as `whistle.py`'s `decode` and Needle's blocks: 8
blocks on 4 residual lanes, mixed by mHC as the encoder's, run a token
at a time, every layer's keys and values kept (`decoder_step`). A block
is self-attention (8 query heads of 48 over 2 key and value heads of 48
and 64, each projection the sum of its last 3 rows under learned taps,
normed, turned by RoPE at the token's place), cross-attention (8 heads
over the memory: the encoder's rows plus sigmoid(pe_gate) times
sinusoids, quantized, its keys and values made once a clip by
`decoder_memory`), each gated by a sigmoid of its own and between
zero-centred RMS norms, then a Hadamard MLP. At layers 3 and 7 (the
header's engram sites) an engram adds first: the bigram and trigram
ending at the token, each hashed twice (FNV, from seeds 0x9E3779B9
apart), pick rows of 4 tables of 18432 by 128 (CQ, read a row as it is
needed); through a key and a value matrix, the value under 4 taps 3
tokens apart, added weighted by the sigmoid of the row's and the key's
unit dot product.

The first token is BOS; the logits are the lanes' mean, normed and
quantized, times the embedding. Greedy decoding (`decoder_run`) takes
the likeliest language tag first, then the likeliest text token, until
EOS or 320 tokens; `pieces_decode` spells the text, the tag left out.
Queries, keys and values are quantized a head's row at a time, as the
KV cache's 8 bits and the encoder's.

Over the reference encoder's rows, every row L0's decoder makes has a
cosine of 0.9998 or more with the reference's (`decoder.txt`), and its
tokens are the reference's; from the WAV file through L0's own front
end, stem and encoder, 0.9994 or more, and again the same tokens and
text: "Rear, left." and "FRENT. CENTER.", where the engine itself gives
"FRENT, CENTER.". On the host, the decoder decodes a token in about 15
ms.

## Listening

[speech/transcribe.l0](../user/lib/speech/transcribe.l0) is what a
program calls: `whistle_listener` reads the model once, every part of
it, and `whistle_transcribe` turns a clip's 16 kHz samples into its
text, the front end, stem, encoder and decoder in turn. `wav_speech`
reads a WAV file's samples, refusing one not 16 kHz, one channel of 16
bits, 0.1 to 30 s, and saying why.

`listen FILE.wav...` ([programs.md](programs.md)) prints each file's
text, a line each, by the model at `/etc/whistle.cact` or `-m MODEL`,
loaded once; `-t` says on standard error how long the load and each
file took. `tests/listen.sh` boots it on QEMU as the kernel's one
program, the model and the recordings in the initramfs (`WHISTLE` names
the model, which is not in the project), and compares each line with
the reference's: on both recordings it is the same. There, on one
emulated CPU, the model loads in 36 s and 1.4 s of speech is heard in
6.7 s, 1.3 s in 5.5 s.

## Limits

- The model is not on the board unless put there: `tests/listen.sh`
  adds it to an initramfs of its own; the demo's initramfs and the
  system volume have no `/etc/whistle.cact`, and nothing hears a
  microphone yet.
- The model's matrices are dequantized whole when it is loaded, about
  140 MB of binary32s (the encoder's 6.5 MB a block, the decoder's 8 MB
  a layer, the embedding's 17 MB), a row at a time in scalar code: a
  second on the host, 36 s on QEMU. Its dot products are its only
  vector arithmetic: how long a clip takes on a Pi 5 is not known.
- The decoder reads a model whose self-attention has taps (27 tensors a
  layer) and whose geometry is Whistle's: 512 wide, 8 heads of 48 and
  64, 2 key and value heads.
- A clip is decoded in one pass, its whole memory attended: nothing
  windows a clip longer than 30 s.
- The model is on no board: it is fetched on the host, and read there
  by the probes.
- A decoding that is not UTF-8 is kept as its bytes, where the
  reference puts U+FFFD.
- The front end works on a clip whole, at 16 kHz only, and resamples
  nothing: a microphone's 48 kHz is brought down by `usb-audio` when
  asked for 16 kHz ([sound.md](sound.md#microphones)), as `rec FILE S
  16000` asks.
