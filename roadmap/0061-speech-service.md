# 0061: The speech service: what is said to the board, said to the agent

Track: Agent · Status: idea · Needs: 0058, 0059, 0060 · Spec: agent.md, speech.md, programs.md, testing.md

## Why

0058 gave each prompt a source so that speech could say its own; 0059
gives the board a microphone and 0060 Whistle, to hear it. What is left
is a service that listens, hears when someone speaks and stops, and
says the text to the agent, all on the board.

## Done when

- A service, `speech` (in `/sbin`), listens to `mic` (0059), hears when
  someone speaks and stops, by its loudness or by a key held, gives
  what was said to Whistle (0060), and says the text to `agentd` with
  `say speech`, the turn's line `[from speech, sent by /sbin/speech]`.
- It serves a little of its own, `speech`: `listen`, `mute`, and
  notices of what it heard, so the Agent app can show that it listens
  and what it heard before it is said, and hold it while a turn runs
  (`agentd` answers `error: busy`).
- Host tests of the endpointing; an e2e case with a WAV file in place
  of the microphone, the turn's source line checked against the
  stand-in; a run on a Pi 5 with a microphone, a spoken question
  answered.

## Steps

To be written. Open: whether it listens all the time or only after a
key or a wake word; whether a phrase heard while a turn runs is held,
said after, or dropped; whether Whistle runs in `speech` itself or in
a server of its own that other programs ask too; whether the agent
answers speech aloud, which would want text to speech, a goal of its
own (0062).

## Spec changes

- agent.md: speech's turns, and the Agent app's showing it listens.
- speech.md: `speech`, its protocol, and its limits.
- programs.md: `speech`.
- testing.md: the tests above.

## Log

- 2026-10-31: split from 0060, as the user asked for Whistle on the Pi.
