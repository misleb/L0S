# 0062: Piper on the board: text to speech in L0

Track: Agent · Status: active · Needs: – · Spec: speech.md, sound.md, programs.md, testing.md

## Why

The board hears (0060) but cannot speak: the agent's answers, and
anything else a program would say aloud, are text on a screen. The
Pi 5 has a speaker in the monitor, `hdmi-audio` ([sound.md](../spec/sound.md))
plays 16-bit PCM at 32, 44.1 or 48 kHz, and L0 has the vector
arithmetic a model needs (`bytes_dot_f32`, `bytes_axpy_f32`,
`bytes_dot_i8`), with which Whistle hears 5 s of speech in 5.5 s on one
CPU. What is missing is a voice that sounds natural, made on the board
about as fast as it is spoken.

[Piper](https://github.com/rhasspy/piper)'s voices are VITS models
made for the Raspberry Pi: a text encoder, a duration predictor, a
flow and a HiFi-GAN vocoder, from 5 to 30 million weights a voice, in
one ONNX file and a JSON config beside it, at 16 kHz (doubled to 32
kHz) or 22.05 kHz (doubled to 44.1 kHz), so `hdmi-audio` plays them with
no resampling. The model is written again in L0, as a library, as
Whistle's was, and checked against Piper's own synthesis on the host.
Larger models (Kokoro, 82 million) sound better, and are a later goal
once this one runs on all four CPUs; Kitten TTS is the alternative if
no Piper voice's licence fits.

## Done when

- A library reads a Piper voice in place, as bytes: the ONNX file's
  initializers by name, each tensor's type, shape and data, refusing
  a type it does not know; and its config, the sample rate, the
  phoneme map and the inference scales.
- Text to phonemes, in L0, for English: numbers, abbreviations and
  punctuation spelled out; each word looked up in a pronouncing
  dictionary (CMUdict) and spelled in the IPA espeak-ng gives Piper,
  stress and length marks included; words not in it spelled by
  letter-to-sound rules. Its phonemes agree with espeak-ng's on a list
  of words, as many as the list says, and the misses are named.
- The voice's path from phonemes to samples: the text encoder, the
  stochastic duration predictor run in reverse, the flow in reverse,
  and the HiFi-GAN vocoder, its convolutions laid out channel-last and
  computed with L0's vector arithmetic.
- `speak TEXT` on the board says it on `audio`, a sentence made while
  the one before plays; `speak -o FILE.wav TEXT` writes it instead;
  a program can call the library.
- Tested against the reference: a host tool runs Piper's own
  synthesis with its noise at 0 (so it is deterministic), the oracle,
  on a few sentences, and L0's phoneme IDs, durations, flow output and
  samples match it (the samples by correlation, as floats will
  differ); host tests of each part; an e2e case that boots `speak -o`
  on QEMU and compares its WAV with the oracle's.
- On a Pi 5: a sentence heard on the monitor's speakers, the first
  sound within a second of `speak` starting, and speech that plays
  without gaps, made at least as fast as it is spoken, on more CPUs if
  one is not enough.

## Steps

- [x] The voice and its reference: `en_US-ljspeech-medium` (LJSpeech,
  public domain; 15.65 million weights, 22,050 Hz), CMUdict, pinned in
  the Makefile (`make piper-fetch`); `probes/piper` (README, `dump.py`,
  `oracle.py`, `words.py`) says how they and Piper 1.8.0 are fetched and
  run on the host, and writes the oracle: four sentences' phonemes and
  IDs, each stage's rows and the samples, noise at 0, into
  `build/piper-oracle`.
- [x] Reading the voice (`format/onnx.l0`, `speech/voice.l0`): the
  protobuf read in place, its 350 initializers by name and the 35 the
  export left anonymous by the node reading them; every one as the onnx
  package reads it (`onnxdump.l0` against `dump.py`); the config by
  `json.l0`.
- [x] Text to phonemes (`speech/phonemes.l0`): normalization, CMUdict
  searched in place and its ARPAbet in espeak-ng's IPA, 315
  letter-to-sound rules, weak forms, a flap across words, and Piper's
  IDs. 949 of 2000 words espeak-ng's alike, 547 by the rules alone
  (`wordscheck.l0`, its misses listed); two of the four sentences
  Piper's to the byte, the others differing in CMUdict's vowels
  (`textcheck.l0`).
- [x] The text encoder and the duration predictor (`speech/piper.l0`,
  `speech/vits.l0`): every row at a cosine of 0.999999 or more, the
  durations the oracle's frame for frame on all four (`stagecheck.l0`).
- [x] The flow and the HiFi-GAN vocoder, channel-last, each output one
  `bytes_dot_f32`: the samples' correlation with the oracle's 0.999999
  or more; on the host a second of speech in about 0.65 s, the vocoder
  0.43 s of it.
- [x] `speak`: text to a WAV file, or to `audio` a sentence at a time
  (made, then played), at 44.1 kHz; `tests/speak.sh` on QEMU, the voice
  on a FAT32 volume, each WAV the oracle's on the two sentences whose
  phonemes are Piper's.
- [ ] On a Pi 5: heard, and timed a second of speech; if slower than
  spoken, the vocoder's time steps split over the other CPUs; and a
  sentence made while the one before plays, which a process playing
  beside the one making needs, the driver's ring holding 128 ms.

Settled: the voice and the dictionary live on the data volume, as
Whistle's model does, the release carrying them (the voice is past an
initramfs's limit); the noise is from a fixed seed. Open: whether the
voice's 22.05 kHz is natural enough at the speed the Pi 5 makes it;
whether `speak` is a program or a server that `speech` (0061) and the
agent ask.

## Spec changes

- speech.md (Speaking is in: the voice's container, the phonemes, the
  model's parts and their checks, `speak`, the limits): the Pi 5's
  timing, and the limits it changes.
- sound.md, programs.md and testing.md: in.

## Log

- 2026-11-01: written, as the user asked, Piper chosen over Kitten TTS
  and Kokoro for its size, its voices and its record on the Pi.
- 2026-11-04: steps 1 to 6 done, as the user asked ("do 0062", steps 1
  to 6, the Pi 5 left to them). The user chose `en_US-ljspeech-medium`
  and had it, its config and MODEL_CARD (rhasspy/piper-voices at
  e7229f7d), CMUdict (cmusphinx/cmudict at 74790861) and `piper-tts`
  1.8.0 with onnx and onnxruntime, in a venv of the scratchpad's,
  fetched. The config names espeak-ng's `en`, British; the oracle and
  L0S use en-us, as the speaker and CMUdict are American. The model
  matched the oracle at once, every stage at a cosine of 0.999999, the
  durations exactly, the samples at a correlation of 0.999999; on the
  host a second of speech is made in about 0.65 s, on one emulated CPU
  in about 20 s, and the voice loads from a FAT32 volume on QEMU in 68
  s. The driver's ring is 128 ms, so making a sentence while another
  plays needs a second process: moved to step 7, with the Pi 5.
