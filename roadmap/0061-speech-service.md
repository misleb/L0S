# 0061: The speech service: what is said to the board, said to the agent

Track: Agent · Status: active · Needs: 0058 (met), 0059 (met), 0060 · Spec: agent.md, speech.md, desktop.md, programs.md, demo.md, testing.md

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

Decided with the user: a key to talk, and nothing that hears all the
time; the key held is heard until let go, a tap until quiet; a phrase
heard while a turn runs is held and said once the turn is done; Whistle
runs in `speech` itself, reading the model once; nothing is said aloud
(that is 0062's). Whistle hears a clip whole, so a phrase is made text
after it ends, not as it is spoken.

- [x] Endpointing (`sbin/speech/endpoint.l0`): each piece's mean square
  against the quietest so far, speech begun at 16 times its power and
  ended after 0.8 s under 4 times, with leasts; 5 s with no speech, and
  30 s, end a tap. Host-tested on pieces made of a loudness.
- [x] A key for a client: `wm`'s `grab CODE PORT`, the key sent to PORT
  as the keyboard sent it, before the launcher, the menu and the window
  in front, let go when the client exits (`compositor_grab`).
- [x] `speech` and its protocol (`proto/speech.l0`): the model read
  once, F12 grabbed, `mic` heard while it is held or after a tap until
  quiet, the phrase heard by `whistle_transcribe` and said as `say
  speech`, held and said again each second while `agentd` is busy;
  `listen`, `stop`, `hear PATH`, `mute`, `open` and `close`, and its
  notices; `speech REQUEST` as its own client. Started after `agentd`
  by `/etc/system`, on the demo and the Pi 5.
- [x] The Agent app opens `speech` if it serves, and shows a line over
  its entry of what it is doing and heard.
- [x] The `speech` e2e case: `speech hear` of the Yeti's 4 s, said to
  `agentd`, the stand-in checking the source line and the text
  (`whistle` in e2e.sh, the model added to the case's etc; skipped with
  no model).
- [ ] On a Pi 5, with the Yeti Nano: F12 held and a question asked
  aloud, answered; a tap then quiet; a phrase held while a turn runs and
  said after; and how long from the key's release to the turn.

## Spec changes

- speech.md (the service, its protocol and its limits are in): the Pi
  5's run, and the limit that says no board has heard it through its
  key.
- testing.md (the e2e case is in): the run on a Pi 5.

## Log

- 2026-10-31: split from 0060, as the user asked for Whistle on the Pi.
- 2026-11-03: the user chose a key to talk only, ended by its release
  or, after a tap, by quiet, and a phrase held while the agent is busy.
  Steps written, and 1 to 5 done: the endpointer, `wm`'s `grab`,
  `speech`, the Agent app's line, and the e2e case, in which QEMU's one
  CPU reads the model in 40 s and the clip's text reaches the stand-in
  model with its source line. transcribe.l0's `window_look` and
  `window_frame` became `cut_look` and `cut_frame`, as `proto/wm.l0`
  has a `window_frame` and `speech` links both. The key's path, `wm` to
  `speech` to `mic`, is tested on the host only: QEMU has no
  microphone. Hearing as it is spoken, a caption while the key is held,
  went to 0067.
