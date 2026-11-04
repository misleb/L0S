# 0067: Speech heard as it is spoken

Track: Agent · Status: idea · Needs: 0061 · Spec: speech.md, agent.md

## Why

`speech` (0061) makes a phrase text only once it ends: Whistle hears a
clip whole, its front end normalized over the utterance and its decoder
attending the whole encoding, so the text comes about as long after the
key's release as the phrase took to say on a Pi 5 (speech.md's Limits).
While it works, `speech` hears nothing else. And it registers only
once the model is read, so the Agent app, which looks for it only as it
opens, misses it when opened first.

## Done when

- The Agent app shows a caption of what is heard while the key is held,
  from the phrase so far heard again every second or two, and the final
  text once it ends; or the latency of the final text cut otherwise,
  measured on a Pi 5.
- Whistle's work does not hold `speech`'s ports: a key or request is
  answered while a phrase is made text (another CPU, or a server of its
  own).
- The Agent app finds `speech` whenever it comes, not only as it opens.

## Steps

To be written. Open: whether a partial pass is cheap enough beside the
microphone on one CPU, or wants 0060's last step's vector arithmetic
and the Pi 5's other CPUs; whether the caption is `speech`'s notice or
the app's own.

## Spec changes

- speech.md: captions, and the limits they lift.
- agent.md: the Agent app's caption.

## Log

- 2026-11-03: written as 0061 landed, after the user asked whether
  speech is made text as it is spoken or after.
