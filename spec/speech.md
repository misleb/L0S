# Speech

L0S has Whistle's path from samples to text, written in L0: its
container, tokenizer, front end, stem, audio encoder and decoder; and
`speech`, a service that hears the microphone while a key is held and
says the text to the agent ([The speech service](#the-speech-service)). Whistle is Cactus Compute's open speech recognition model, whose weights are
one file, `whistle.cact` (16.9 MB, Apache-2.0,
[Hugging Face](https://huggingface.co/Cactus-Compute/whistle)), and
whose reference is `cactus-needle`
([source](https://github.com/cactus-compute/needle), Apache-2.0).
Neither is in the project: `probes/whistle` says how they are fetched
and run on the host, and what L0S's parts are checked against.

L0S also speaks: a Piper voice's path from text to samples, written in
L0, and `speak`, which says text on the monitor's speakers or writes
it to a file ([Speaking](#speaking)).

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
text, the front end, stem, encoder and decoder in turn. A clip over 30
s, one pass of the decoder, is heard in windows (`transcribe_windows`):
each 30 s or less, cut at the middle of the quietest 100 ms of its last
5 s, where a word is least likely, the next window from the cut, a last
piece under 0.1 s left out; each window is heard on its own, its front
end normalized over it alone, and their texts are joined by a space.
The engine cuts long audio its own way, which is not published, so
L0S's windows are checked against the rebuilt reference instead:
`probes/whistle/windows.py` cuts a clip where L0S does and has
`rebuild.py` hear each window. `wav_speech` reads a WAV file's samples,
refusing one not 16 kHz, one channel of 16 bits, 0.1 s to 5 minutes,
and saying why.

`listen FILE.wav...` ([programs.md](programs.md)) prints each file's
text, a line each, by the model at `/Volumes/data/speech/whistle.cact`,
where the installer puts it from the release ([Installing from the
proxy](boot.md#installing-from-the-proxy)), or `-m MODEL`,
loaded once; `-t` says on standard error how long the load and each
file took. `tests/listen.sh` boots it on QEMU as the kernel's one
program, the model (`-m /etc/whistle.cact`) and the recordings in the
initramfs (`WHISTLE` names the model, which is not in the project, or
else `build/fetch/whistle.cact`, which `make release` fetched), and
compares each line with
the reference's: on all four recordings it is the same, ALSA's "Front
center" and "Rear left", 4 s of the Yeti Nano's speech recorded
through QEMU ("Testing, testing, testing, testing."), and 39 s of the
three over again with a second of silence between, heard in two
windows, cut at 26.05 s. There, on one emulated CPU, the model loads in
37 s and 1.4 s of speech is heard in 6.8 s, 1.3 s in 5.6 s, 4 s in
16.3 s, 39 s in 201 s.

## The speech service

`speech` ([programs.md](programs.md), `/sbin/speech`, after `agentd` in
`/etc/system`) says what is said to the board to the agent. It reads
the model once, as `listen` does, from
`/Volumes/data/speech/whistle.cact` or `-m MODEL`, waiting up to 10 s
for the volume to be mounted; with none it says so in the log and exits
0. It then grabs its key of the compositor (`wm`'s `grab`,
[desktop.md](desktop.md)), F12 or `-k CODE`, so the key comes to it
whatever window is in front, registers `speech`, and says in the log
how long the model took and its key, or why it has none (no `wm`, as on
a board with no screen).

How a phrase begins and ends:

| | begins | ends |
|---|---|---|
| the key held | at its press | at its release |
| the key tapped, let go within 0.3 s | at its press | once the speaker is quiet, or at the key's next press |
| `listen`, asked | at once | as a tap's |

Either way a phrase is at most 30 s, what Whistle hears in one pass, and
is ended there. As it begins, `speech` asks `mic` for `listen 16000`
([sound.md](sound.md#microphones)), one channel of 16 bits at 16 kHz,
and gathers its `pcm` notices; as it ends, it asks `stop`, joins them,
and has `whistle_transcribe` hear them, all at once: Whistle hears a
clip whole, so its text comes after the phrase, in about the time it
took to say on a Pi 5.

Quiet is heard by loudness (`endpoint.l0`): each piece of samples, a
`pcm` notice's 10 ms or so, is weighed by its mean square against the
quietest piece heard so far, the room's floor. Speech has begun once a
piece has 16 times the floor's power, and at least a loudness of 250 in
32768; it has ended once 0.8 s of pieces under 4 times the floor, and at
least 150, follow it. A tap with no speech in 5 s is dropped, as is a
phrase under 0.1 s.

The text, its spaces trimmed, is said to `agentd` as `say speech`, so
the model is told `[from speech, sent by /sbin/speech]` before it
([agent.md](agent.md#where-a-prompt-came-from)). While a turn runs,
`agentd` answers `error: busy`: the text is held, and said again each
second, by the kernel's alarm, until it is taken; a newer phrase takes
its place. Nothing heard, only spaces, is said to no one.

It serves `speech` ([proto/speech.l0](../user/lib/proto/speech.l0)), each
a request, its answer to its reply port:

| Request | Answer |
|---|---|
| `listen` | `ok`: a phrase begun, as a tap begins one; `error: muted`, or `error: busy` while one is heard |
| `stop` | `ok`: the phrase ended, as a release ends it |
| `hear PATH` | `ok` once the WAV file at PATH, 16 kHz, one channel of 16 bits, is heard as a phrase and its text said; or `error: WHY` |
| `mute on\|off` | `ok`: the key and `listen` heard or not; muting drops a phrase being heard |
| `open NPORT` | `ok`: where speech stands told to NPORT, and its notices to NPORT from then |
| `close NPORT` | `ok`: NPORT told no more |

Its notices, to each NPORT open, are `speech idle`, `speech muted`,
`speech listening`, `speech hearing` (Whistle at work), `speech held`
(the agent busy), `speech said`, and, after a newline, `speech heard`
and the text, and `speech error` and why (no microphone, no agent).
The Agent app ([agent.md](agent.md#agent-the-app)) shows them as a line
over its entry. `speech listen`, `stop`, `hear PATH` and `mute on|off`,
given as arguments, ask the service running, waiting a minute for it to
register, as it reads the model first.

The `speech` e2e case boots it with the model in the initramfs
(`-m /etc/whistle.cact`), `agentd` and the host's stand-in model:
`run speech hear /etc/clip.wav`, the Yeti Nano's 4 s, comes to the
model as `[from speech, sent by /sbin/speech]` and "Testing, testing,
testing, testing.", and the conversation `agentd` keeps holds both and
the model's answer. On one emulated CPU the model is read in 40 s.

## Speaking

The voice is Piper's `en_US-ljspeech-medium`
([piper-voices](https://huggingface.co/rhasspy/piper-voices), trained
on LJSpeech, which is in the public domain): a VITS model of 15.65
million weights, all binary32, in one ONNX file of 63.5 MB, and its
JSON config, at 22,050 Hz. Words are looked up in CMUdict
(`cmudict.dict`, 3.6 MB, BSD 2-clause). Neither is in the project: the
Makefile pins both, at a commit and a SHA-256 (`make piper-fetch`),
`make release` puts them in the release's `speech/`, and the installer
on the data volume beside Whistle's model. Each part is written from
Piper's own source (its `train/vits`) and checked against Piper itself,
run on the host by `probes/piper` with its noise at 0
([testing.md](testing.md)).

**The voice's file** ([format/onnx.l0](../user/lib/format/onnx.l0)):
the ONNX protobuf read in place, its graph's 350 initializers by name
and their numbers left in the file's bytes. 35 are anonymous, the
flow's WaveNet weights whose weight norm the export folded
(`onnx::Conv_8959`) and the embedding (`sid`): each is also found as
the node that reads it and which input it is,
`/flow/flows.6/enc/in_layers.0/Conv#1`. Only FLOAT and INT64 are read;
any other type, data outside the file, or numbers held a field each is
refused, named. The config ([speech/voice.l0](../user/lib/speech/voice.l0))
gives the rate, the scales (noise 0.667, length 1, the durations' noise
0.333) and the 157 phonemes' IDs. Every initializer reads as the onnx
package reads it, bit for bit.

**The phonemes** ([speech/phonemes.l0](../user/lib/speech/phonemes.l0))
are those espeak-ng's en-us gives Piper. The config names espeak-ng's
`en`, which is British, but the speaker is American and CMUdict is, so
L0S and its reference both use en-us. The text is split into words and
marks: numbers with commas, decimals ("point five zero"), times ("three
forty five", "oh five", "o'clock"), years from 1100 to 1999 in pairs,
ordinals, percentages and dollars and cents are said in words, a few
symbols too, and 44 abbreviations before a full stop in full,
that stop not ending the sentence. Each word is found in CMUdict by
halves over its lines, in place, its first pronunciation taken, and its
ARPAbet written in espeak-ng's IPA: the stress mark before the stressed
vowel, a secondary right after the primary unmarked, an unstressed AH a
word's ɐ when first and else ə, ER0 ɚ, ER ɜː (an ɹ after it only before
a vowel), IY0 i, ᵻ in -ed and -es after T, D or a sibilant, and T a flap
ɾ after a vowel or a vowel's R and before an unstressed vowel. A word
not in CMUdict is spelled by letter-to-sound rules in the manner of the
Naval Research Laboratory's, 315 of them, its first vowel stressed.
69 function words have espeak-ng's weak forms between other words (the
ðə, of ʌv, to tə), and a word's final t flaps before a word starting
with a vowel (ɪɾ ɪz). Sentences end at . ! and ?; a mark follows its
word, and , ; and : a space, as Piper writes them; the IDs are the
start, each codepoint and the pad after it, then the end, a codepoint
the voice has no ID for left out. Of 2000 of CMUdict's words, sampled
evenly, 949 are espeak-ng's alike, most misses names espeak-ng's own
rules say otherwise; the rules alone, as for a word CMUdict lacks, say
547 alike. Of the four test sentences two are Piper's to the byte; the
other two differ only in CMUdict's vowel of "dog" and "costs".

**The model** ([speech/piper.l0](../user/lib/speech/piper.l0), its
arithmetic [speech/vits.l0](../user/lib/speech/vits.l0)) keeps every
tensor channel-last, its time steps' channels contiguous binary32s in
bytes, so that a convolution's output is one `bytes_dot_f32` over its
taps' rows, or one a tap when dilated; each convolution's weights are
laid out so once, at load (0.12 s on the host). Its parts, as the
medium voices have them:

- the text encoder: the IDs' embeddings times √192, 6 layers of
  self-attention of 2 heads of 96 with relative keys and values within
  4 positions, each with a residual and a layer norm and an FFN of two
  convolutions of 3 (768 wide, ReLU), then a projection to the prior's
  192 means and 192 log deviations, a phoneme a row;
- the stochastic duration predictor in reverse: a DDSConv (depthwise
  convolutions of 3 dilated 1, 3, 9, layer norms, GELU) over the
  encoder's rows conditions three ConvFlows, each inverting a
  rational-quadratic spline of 10 bins on −5 to 5, flips between, then
  an elementwise affine, from noise (zeros with `-0`) to each phoneme's
  log duration; its frames are e to that times the length scale, up;
- the flow in reverse: the prior's means repeated for each phoneme's
  frames (plus, with noise, its deviations times noise times 0.667),
  then 4 mean-only residual couplings, a flip before each, each a
  WaveNet of 4 layers (convolutions of 5, a tanh-sigmoid gate, residual
  and skip convolutions);
- HiFi-GAN: a convolution of 7 to 256 channels, then three times leaky
  ReLU, a transposed convolution (×8, ×8, ×4, to 128, 64, 32 channels)
  and the mean of three ResBlock2s (kernels 3, 5, 7, dilated (1, 2), (2,
  6), (3, 12)); leaky ReLU, a convolution of 7 to one channel, and tanh:
  256 samples a frame.

Noise, when not 0, is Gaussian from a xorshift seeded the same each run
(`piper_noise`), so a sentence sounds the same each time. Against Piper
with its noise at 0, on four sentences, every stage's rows have a
cosine of 0.999999 or more with the reference's, the durations are the
same frame for frame, and the samples' correlation is 0.999999 or more.
On the host, one CPU, a second of speech takes about 0.65 s: the
encoder and the durations 0.06 s, the flow 0.16 s, the vocoder 0.43 s.

**`speak`** ([programs.md](programs.md)) says text on `audio`: the
voice and CMUdict loaded, from `/Volumes/data/speech/` or `-v` and
`-d`, then each sentence made, normalized so its loudest sample is full
scale as Piper's are, doubled to 44,100 Hz ([sound.md](sound.md)) and
played, the next made once it has; or with `-o` all of them written as
one WAV at 22,050 Hz. A program calls the library as `speak` does:
`piper_of` and `phon_new` once, then `phon_sentences`, `phon_ids` and
`piper_say_ids` a sentence. On QEMU, `tests/speak.sh` gives the
oracle's samples on the two sentences whose phonemes are Piper's, each
WAV's correlation with the oracle's 0.999999 or more (on the other two,
L0S's own phonemes, a vowel apart, make other samples); there, on one
emulated CPU, the voice loads from a FAT32 volume in 68 s, and 0.92 s
of speech is made in 19 s, 4.5 s in 91 s.

## Limits

- The model is not in the project, nor in any initramfs: `make
  release` fetches it from Hugging Face, at a pinned commit and
  SHA-256, into the host's release, and the board has it only once the
  installer has fetched that onto the data volume.
- `speech` has heard a microphone through its key on no board yet: the
  e2e case hears a WAV file by `hear`, with no `wm` and no microphone,
  QEMU's `usb-audio` being a speaker only.
- `speech` registers only once the model is read, 14.6 s on a Pi 5 and
  40 s on QEMU; until then its key goes to it unheard, and the Agent
  app, which looks for it only as it opens and on Retry, shows no line.
- A phrase is heard only after it ends, and while it is made text,
  `speech` hears nothing else: its key and requests wait.
- The key is one, F12 unless `-k` says another, and the Agent app's
  line names F12 whatever it is. There is no wake word, and nothing
  hears all the time.
- Quiet is weighed by loudness against fixed factors, not by a model of
  speech: a loud room may keep a tap going to its 30 s.
- One text is held while the agent is busy; a newer phrase replaces it.
- The model's matrices are dequantized whole when it is loaded, about
  140 MB of binary32s (the encoder's 6.5 MB a block, the decoder's 8 MB
  a layer, the embedding's 17 MB), a row at a time in scalar code: a
  second on the host, 36 s on QEMU, 14.6 s on a Pi 5. Its dot products
  are its only vector arithmetic. On a Pi 5, on one CPU, 5 s of speech,
  the Yeti Nano's recorded by `rec FILE 5 16000`, was heard in 5.5 s,
  and rightly: about as long as it was spoken.
- The decoder reads a model whose self-attention has taps (27 tensors a
  layer) and whose geometry is Whistle's: 512 wide, 8 heads of 48 and
  64, 2 key and value heads.
- A clip is decoded in one pass, its whole memory attended: nothing
  windows a clip longer than 30 s.
- The model is on no board: it is fetched on the host, and read there
  by the probes.
- A decoding that is not UTF-8 is kept as its bytes, where the
  reference puts U+FFFD.
- The voice is one, English, of one speaker; a config of several
  speakers is refused. It and CMUdict are not in the project, nor in
  any initramfs (the voice is past an initramfs's 48 MB): the board has
  them once the installer has put them on the data volume.
- `speak` makes a sentence, then plays it: nothing is made while one
  plays, so sentences come with a pause between them as long as the
  next takes to make, and nothing is heard until the first is made.
  It has been heard on no board, and on one emulated CPU it is about 20
  times slower than speech; on a Pi 5 it is not yet timed.
- The voice's every convolution is run on one CPU.
- The phonemes are CMUdict's, not espeak-ng's: about half the words of
  a sample are said as Piper would say them, and the rest differ, most
  in a vowel or a stress. The weak forms are fixed, whatever a word's
  place in its sentence; a word CMUdict lacks is spelled by rules that
  agree on about a quarter of words; capitals mean nothing (an acronym
  is said as a word); only ASCII letters are read, any other letter
  being a space; numbers past the trillions are said digit by digit.
- CMUdict is searched by halves, but two pairs of its lines are out of
  order (sepulveda and sepultura, stilton and stilted), so a word near
  them may not be found and be spelled by rules.
- The front end works on a clip whole, at 16 kHz only, and resamples
  nothing: a microphone's 48 kHz is brought down by `usb-audio` when
  asked for 16 kHz ([sound.md](sound.md#microphones)), as `rec FILE S
  16000` asks.
