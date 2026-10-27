# 0005: The HVS's end-of-frame interrupts

Track: Display · Status: ready · Needs: – · Spec: display.md, pi5.md

## Why

`hvs` doesn't take the HVS's end-of-frame interrupts
([display.md](../spec/display.md#the-display-on-the-raspberry-pi-5),
"Not yet"), so it can't change the display list between frames or tell
clients when a frame has been shown, which the frame notices of goal
[0006](0006-paced-display-queue.md) need from it. Today a restack
writes the list the channel isn't fetching, points `LPTRS` at it and
polls `DL` for up to 50 ms to see it taken; after a `SET_TIMING` it
writes over the firmware's two lists, guessing from `DL` which one the
channel is on.

## Done when

- `hvs` takes channel 0's end-of-frame interrupt, and changes the
  display list only between frames, waiting on the interrupt rather
  than polling `DL`.
- `hvs` counts frames, and knows which frame first showed each change
  (a restack, a `damage`, a pointer move), as 0006's notices need.
- On a Pi 5 with a monitor on HDMI0 (`tools/pi5-boot`), the frame
  rate it counts matches the mode's (60 at 1920×1080 at 60 Hz), and the
  desktop shows steady with five windows, as it does today.
- `make check` and `make test` pass, with the interrupt's register
  words and the frame bookkeeping tested on the host.

## Steps

- [ ] Find the interrupt: which of the BCM2712's interrupts channel 0's
  end of frame raises, which SCALER6 register enables it and which
  clears it, from Linux's `vc4_hvs.c` (its `SCALER6_DISP_*` and
  `SCALER6_CONTROL` handling) and the bcm2712 device tree; and whether
  `irq_bind` may take it on the Pi 5. Written into the Pi 5 section of
  display.md as what is known. If L0 does not give that interrupt, an
  open `probes/display/REQUEST-pi5-hvs-irq.md` to L0, which this goal
  then needs.
- [ ] A stage `hvs eof`, beside `mode` and `hdmi`: does what `list`
  does, turns channel 0's end-of-frame interrupt on, binds it, counts
  the interrupts for two seconds, clearing each, and says the rate and
  `STATUS`'s frame count beside it. Run on the board; its register
  words built by pure functions, tested on the host.
- [ ] The full driver binds the interrupt to its own port and keeps a
  frame count. A restack writes the list not shown and points `LPTRS`
  at it as now, but the reply waits for the next end of frame, not a
  poll of `DL`; the firmware's-two-lists case writes the second list at
  the end of the frame that took the first, not on a guess. A frame
  with no interrupt within 50 ms is said once and falls back to today's
  poll, so a missing interrupt cannot hang the desktop.
- [ ] Which frame showed what: each change (a restack, a `damage`'s
  clean, a pointer move) is noted with the frame count it is pending
  for, and marked shown at the end of that frame; `hvs` keeps the
  latest shown, which 0006's notices read. Tested on the host as a pure
  record of pending and shown changes against frame numbers.
- [ ] A board run with five windows, a drag and a scroll at 1920×1080
  and at 3840×2160, the frame rate and any fallbacks in `dmesg`, kept
  in the Log; the Pi 5 section says how a frame is paced, and "Not yet"
  goes.

## Spec changes

- display.md: the "Not yet" line goes; the Pi 5 section says which
  interrupt ends a frame, that a list is changed only between frames,
  waited for by the interrupt with a 50 ms fallback, and that `hvs`
  counts frames and knows which showed each change.
- pi5.md: `hvs`'s row names its interrupt, as `uart`'s and `sdhci`'s do.

## Log

- 2026-10-26: written from display.md.
- 2026-10-27: 0006 now needs it, for `hvs`'s frame notices.
- 2026-10-27: steps written. Every step but the first runs on a Pi 5
  with a monitor on HDMI0, which no emulator stands in for; the first
  may find this goal needs L0 to give the interrupt.
