# 0005: The HVS's end-of-frame interrupts

Track: Display · Status: done · Needs: probes/display/REQUEST-pi5-hvs-eof.md · Spec: display.md, pi5.md

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

- [x] Find the interrupt: which of the BCM2712's interrupts channel 0's
  end of frame raises, which SCALER6 register enables it and which
  clears it, from Linux's `vc4_hvs.c` (its `SCALER6_DISP_*` and
  `SCALER6_CONTROL` handling) and the bcm2712 device tree; and whether
  `irq_bind` may take it on the Pi 5. Written into the Pi 5 section of
  display.md as what is known. If L0 does not give that interrupt, an
  open `probes/display/REQUEST-pi5-hvs-eof.md` to L0, which this goal
  then needs.
- [x] A stage `hvs eof`, beside `mode` and `hdmi`: does what `list`
  does, turns channel 0's end-of-frame interrupt on, binds it, counts
  the interrupts for two seconds, clearing each, and says the rate and
  `STATUS`'s frame count beside it. Run on the board; its register
  words built by pure functions, tested on the host. Done without
  `list`'s part, beside the serving driver (Log).
- [x] The full driver binds the interrupt to its own port and keeps a
  frame count. A restack writes the list not shown and points `LPTRS`
  at it as now, but the reply waits for the next end of frame, not a
  poll of `DL`; the firmware's-two-lists case writes the second list at
  the end of the frame that took the first, not on a guess. A frame
  with no interrupt within 50 ms is said once and falls back to today's
  poll, so a missing interrupt cannot hang the desktop.
- [x] Which frame showed what: each change (a restack, a `damage`'s
  clean, a pointer move) is noted with the frame count it is pending
  for, and marked shown at the end of that frame; `hvs` keeps the
  latest shown, which 0006's notices read. Tested on the host as a pure
  record of pending and shown changes against frame numbers.
- [x] A board run with five windows, a drag and a scroll at 1920×1080
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
- 2026-10-28: step 1 done, and it does. On SCALER6 the end of frame has
  no HVS register: it is line 2 (channel 0; 9 and 16 the others) of the
  display's interrupt controller `disp_intr`, a `bcm2711-l2-intc` at
  0x107C502000, 0x30 bytes, level, cleared at 0x08 and unmasked at 0x14,
  which raises GIC SPI 97, the host's 129 (`bcm2712.dtsi`, `vc4_hvs.c`,
  `irq-brcmstb-l2.c`, rpi-6.12.y; in display.md and `regs.l0`). The
  first part of step 2's stage, `hvs eof`, asks for both and touches
  nothing else, so it runs beside the serving driver. Run with `run hvs
  eof` on the Pi 5 (3840×2160, desktop up, over the network boot and
  the UART with no one at the board): `the display's interrupt
  controller, 0x107c502000, is not given: no device there` and `cannot
  bind interrupt 129: the board has no such interrupt`. Asked of L0 in
  probes/display/REQUEST-pi5-hvs-eof.md, which this goal now needs. The
  request names pixel valve 0's own interrupt, SPI 101 (133), whose
  registers are already a region, as a smaller alternative for pacing
  alone. Steps 2 to 5 wait for it.
- 2026-10-29: L0 roadmap 0127 gave both (the region and 129, level; not
  the pixel valve's), installed the same day. Step 2 done: `hvs eof`
  does not do `list`'s part, since a channel already scanning shows its
  ends of frame without being moved, and leaving the HVS alone lets it
  run beside the serving driver, over the UART, with no one at the
  board. Its words (the mask's restore, the rate) are pure and tested.
  On the Pi 5 at 3840×2160 at 60 Hz with the desktop up: the
  controller's mask 0 as the firmware leaves it, 121 interrupts in 2000
  ms, 120 with line 2 raised, 59.9 Hz; STATUS's frame count 14 to 6, so
  120 frames on (134 mod 64). One interrupt came without line 2,
  likely another line latched before the stage cleared them all.
- 2026-10-29: the board hung within moments of that run: the shell's
  prompt came back, then nothing, and `reboot` was never echoed. The
  stage had put the mask back as the firmware left it, every line
  unmasked, and exited. 129 stays enabled once enabled, as L0 disables
  none, and the kernel ended an interrupt bound to nobody at once, so
  with a line raised and no one to clear it 129 came again for ever and
  CPU 0 ran nothing else. Two fixes: the stage leaves every line masked
  and cleared; and the kernel holds an interrupt its driver let go
  taken, not ended, until the next driver binds it, which ends it
  (syscalls.md; a board test binds one again after its driver exits).
  The board needs a power-cycle by hand before step 3 can be run.
- 2026-10-29: step 3 written, not yet run on the board: `frames.l0`
  binds 129 to a port of the driver's own as it starts serving, masks
  every line but channel 0's, and waits on its display port and that one
  as one set, counting each end of frame (clear, then `irq_ack`). A
  restack, and the firmware's-lists case, wait for the end of frame
  after which `DL` names the new list, polling 2 ms more after each, as
  the list may be taken just after it; no frame in 50 ms is said once
  and polled once more. With no controller or interrupt it polls as
  before. While the driver is in a step the interrupt is taken and not
  acked, so frames pass uncounted: the count is of frames the driver
  saw, which step 4 must allow for (STATUS's 6-bit count may fill it).
- 2026-10-29: the Pi 5 was power-cycled and booted step 3's driver on
  the kernel before the fix, then was rebooted from the UART onto the
  fixed kernel. On both, at 3840×2160: `ends of frame by interrupt
  129`, the wallpaper shown, Files and Fonts opened and stacked (`run
  windows`), and no `no end of frame in 50 ms` in `dmesg`, so every
  switch was taken by an end of frame. `hvs eof` beside it now says 129
  is bound and touches nothing. Step 3 done. Not seen: the firmware's-
  two-lists case, which needs an `hdmi=` without HDMI0's regions; the
  50 ms fallback; and a restack's time against the poll, which step 5's
  run measures.
- 2026-10-29: step 4 done, as `shown.l0`, pure and tested on the host
  (the 6-bit carry against counting one by one over 300 seeded cases;
  changes shown in turn, late, out of order). The count is carried on
  by STATUS's frame count at each end of frame, which settles step 3's
  frames passing uncounted while the interrupt is taken. A switched
  list is shown by the end of the frame after the count it was taken
  at, a `damage`'s clean a frame later; a pointer move is a switched
  list. On the Pi 5 at 3840×2160, Files, Fonts and Terminal opened:
  `frame 600: changes shown to 188 of 188, 0 pending` at 12.66 s, 1200
  at 22.66 s, 1800 at 32.66 s, 600 frames each 10.000 s.
- 2026-10-29: step 5, on the Pi 5 with five windows (Files, Fonts,
  Terminal, Disks, System Monitor), the user dragging, scrolling and
  resizing at the board, `dmesg` read over the UART:
  - 3840×2160, scale 2: a drag and a scroll clean, a line every 10.000
    s for two minutes, 3863 changes all shown, none pending, no
    fallback. A first run had lost 64 frames, so `hvs` now says any gap
    over 100 ms between ends of frame taken. Resizing then showed gaps
    of up to 1087 ms in which STATUS's own count barely moved (one
    frame in 714 ms), the HVS seemingly stalled; and a window widened
    to 3032 pixels made every list refused, too wide for the line
    memory, so the pointer stopped moving on the screen until the
    window was closed. Both are 4K's alone and older than this goal's
    work: goal 0038.
  - 1920×1080, scale 1 (`hdmi=boot`): drag, scroll and resizes all
    clean, smoother at the board, frames 600 to 7200 each 10.000 s
    (one line 15 ms early, a frame's jitter), 3865 changes all shown,
    no gap, no refusal.
  Done: the rate counted is the mode's at both, and the desktop steady
  with five windows as before, but for 0038's resizes at 4K. A
  restack's time against the poll was not taken apart from the frames:
  0006's queue, now ready, is where it matters.
