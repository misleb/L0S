# probes/piper -- Piper's reference on the host (roadmap 0062)

The voice is `en_US-ljspeech-medium` (LJSpeech, public domain; its
`MODEL_CARD` beside it), 22,050 Hz, 15.65 million weights, one ONNX
file of 63.5 MB and its JSON config. The pronouncing dictionary is
CMUdict (`cmudict.dict`, BSD 2-clause, its `LICENSE` beside it). The
Makefile pins all of them (`PIPER_VOICE_URL`, `CMUDICT_URL` and their
SHA-256s) and `make piper-fetch` fetches them into `build/fetch/`;
`PIPER_VOICE=FILE` and `CMUDICT=FILE` name files of your own instead.

## The reference

Piper itself (`piper-tts`, the OHF-Voice fork, 1.8.0 here) with
`onnx` and `onnxruntime`, in a venv outside the project:

```bash
python3 -m venv VENV
VENV/bin/pip install piper-tts onnx onnxruntime numpy
VENV/bin/python -I probes/piper/oracle.py build/fetch/en_US-ljspeech-medium.onnx build/piper-oracle \
  "Hello=Hello, world!" "Board=This is the board speaking." \
  "Fox=The quick brown fox jumps over the lazy dog." \
  "Numbers=It is 3:45, and the train costs 12 dollars."
VENV/bin/python -I probes/piper/words.py build/fetch/cmudict.dict 3000 > user/lib/speech/testdata/espeak-words.txt
```

`oracle.py` runs the voice with its noise at 0 and writes each stage's
output (its header lists them); `words.py` writes espeak-ng's phonemes
for a sample of CMUdict's words, the list `phonemes.l0`'s agreement is
counted on. `piper-tts` carries espeak-ng (its `espeakbridge` and
`espeak-ng-data`); nothing else is installed.

**en-us, not the config's "en".** The voice's config names espeak-ng's
voice `en`, which is British (non-rhotic, `əʊ`, `ɒ`), while LJSpeech's
speaker is American and L0S's phonemes come from CMUdict, which is
American. The reference is run with `en-us`, as Piper's other American
voices are; the model itself is the same either way, from its phoneme
IDs on.

## The model, as the file holds it

350 initializers, all binary32, named by PyTorch's module paths
(`enc_p.encoder.attn_layers.0.conv_q.weight`) but for 35: the flow's
WaveNet weights, whose weight norm the export folded, are
`onnx::Conv_N`, the embedding is `sid`, and the duration predictor's
first affine's `logs` is `onnx::Exp_N`. Each is named by the node that
reads it (`/flow/flows.6/enc/in_layers.0/Conv`, input 1), which is how
`onnx.l0` finds them. The parts, from the shapes and the convolutions'
attributes:

- text encoder: 256 symbols × 192, 6 layers, 2 heads of 96, relative
  keys and values over a window of 4, FFN 768 with kernel 3; the
  projection to 192 means and 192 log deviations.
- duration predictor (stochastic): `pre`, a DDSConv of 3 layers (kernel
  3, dilations 1, 3, 9, depthwise), `proj`; flows: an ElementwiseAffine
  and ConvFlows (10 bins, tail 5) with flips; reversed, the first
  ConvFlow (`flows.1`) is skipped, as VITS does, and is not in the file.
- flow: 4 residual coupling layers, mean only, a WaveNet of 4 layers,
  kernel 5, dilation 1, hidden 192, with flips.
- vocoder: HiFi-GAN, conv_pre 192 → 256 (kernel 7), upsampled ×8, ×8, ×4
  (kernels 16, 16, 8) to 128, 64, 32 channels, each with three
  ResBlock2s (kernels 3, 5, 7, dilations (1, 2), (2, 6), (3, 12)),
  conv_post 32 → 1 (kernel 7, no bias), tanh: 256 samples a frame.
