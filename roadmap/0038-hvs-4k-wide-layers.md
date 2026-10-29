# 0038: `hvs` at 4K: wide windows, a pointer that keeps moving, and no stalls

Track: Display · Status: idea · Needs: – · Spec: display.md

## Why

Seen on a Pi 5 at 3840×2160, scale 2, during 0005's step 5, which went
clean at 1920×1080:

- **Every list refused once the layers are too wide.** System Monitor
  widened to 1516×520 (3032 pixels) beside overlapping windows: `hvs:
  refused: the screen's layers are too wide for the HVS's line memory`,
  3,152 times. Every list after it was refused too, the pointer's moves
  among them, so the pointer drawn stayed put while `wm`'s moved on: a
  detached cursor until the window was closed (`kill`). The refusal is
  from `screen_planes` (`pieces.l0`'s UPM budget, since the 4K mode,
  `c074150`).
- **The channel seems to stall while windows are resized.** 0005's gap
  lines: `no end of frame taken for 1087 ms, frames 19224 to 19267`,
  `714 ms, frames 19310 to 19311`, and more, all during resizes. In the
  714 ms STATUS's frame count moved one frame where 60 Hz is about 43,
  so the HVS itself made no frames, not the driver missing them; more
  than 63 frames in one gap also leaves `hvs`'s count short, by 64 in an
  earlier run.

## Done when

To be written: at least, a list too wide for the line memory never
stops the pointer, and a resize at 4K brings no gap over a frame or
two, said by 0005's gap line.

## Steps

To be written. First: log `STATUS`, `DL` and `HANDLE_ERROR` at a gap,
to tell a stalled channel from one the driver left; and find what of a
resize (a buffer of about 10 MB mapped and the old unmapped, a list of
large planes) it follows.

## Spec changes

- display.md: what `hvs` does with layers too wide for the line memory,
  and the stall gone from its Limits.

## Log

- 2026-10-29: written from 0005's step 5 board run.
- 2026-10-29: seen again in 0006's board run at 3840×2160, scale 2,
  with `hvs` answering restacks at once: smooth at first, then sluggish
  as Files, Fonts, Disks, System Monitor and Terminal were opened and
  moved, never a glitch. 41 gaps of 100 to 156 ms between ends of frame
  in nine minutes, from about four minutes in. In 30, STATUS's count
  moved 2 or 3 frames in about 117 ms where 7 were due, so the HVS
  itself made no frames; they came at multiples of about 1.2 s
  (352.75 and 353.96 s, 446.31 and 447.53 s), a rhythm worth matching
  against what runs each second (System Monitor's refresh, the clock).
  In the other 11 the count moved as it should, so the driver was late,
  likely mapping a resized window's buffer.
