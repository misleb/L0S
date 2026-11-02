# 0062: Piper on the board: text to speech in L0

Track: Agent · Status: ready · Needs: – · Spec: speech.md, sound.md, programs.md, testing.md

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

- [ ] The voice and its reference: choose the voice, by its sound, its
  size and its licence (each voice's MODEL_CARD names its dataset's;
  LJSpeech's is in the public domain); `probes/piper` says how the
  voice and Piper are fetched and run on the host, and writes the
  oracle: phoneme strings and IDs, each stage's output and the samples,
  for a few sentences, noise at 0.
- [ ] Reading the voice (`format/onnx.l0`): the protobuf of an ONNX
  file, read in place, its initializers by name, and the config by
  `json.l0`.
- [ ] Text to phonemes (`speech/phonemes.l0`): normalization, CMUdict
  and its mapping to espeak-ng's IPA, letter-to-sound rules, and the
  phoneme IDs as Piper puts them (a start, each phoneme then a pad, an
  end); checked against espeak-ng on a word list.
- [ ] The text encoder and the duration predictor, checked against the
  oracle's durations.
- [ ] The flow and the HiFi-GAN vocoder, channel-last with the vector
  arithmetic, checked against the oracle's samples; their time on the
  host a second of speech.
- [ ] `speak`: text to a WAV file, or to `audio` a sentence at a time;
  the e2e case on QEMU.
- [ ] On a Pi 5: heard, and timed a second of speech; if slower than
  spoken, the vocoder's time steps split over the other CPUs.

Open: the voice, and whether its 16 or 22.05 kHz quality is natural
enough at the speed the Pi 5 makes it; where the voice and the
dictionary live, the initramfs or the data volume; whether noise at
Piper's own scales (0.667 and 0.8) wants a random source of L0S's, or
a fixed seed is enough; whether `speak` is a program or a server that
`speech` (0061) and the agent ask.

## Spec changes

- speech.md: Speaking: the voice's container, the phonemes, the
  model's parts and how they are checked, `speak`, and their limits.
- sound.md: a voice's rate doubled to one `hdmi-audio` plays.
- programs.md: `speak`, and the libraries' rows.
- testing.md: the host tests, the e2e case and the oracle.

## Log

- 2026-11-01: written, as the user asked, Piper chosen over Kitten TTS
  and Kokoro for its size, its voices and its record on the Pi.
