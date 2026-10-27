# 0001: The Pi 5 boots reliably

Track: Pi 5 · Status: blocked · Needs: [probes/memory/REQUEST-heap-left.md](../probes/memory/REQUEST-heap-left.md) · Spec: pi5.md, kernel.md

## Why

The Pi 5 has booted to a shell and the compositor, but some boots corrupt
memory or lose power, and nothing stops processes from taking more RAM than
the kernel's heap was sized for ([pi5.md, Limits](../spec/pi5.md#limits)).
Every other Pi 5 goal waits on this one.

## Done when

- Repeated boots with `tools/pi5-boot` reach `l0s>` and the desktop with
  no memory corruption and no power loss.
- On a board with more RAM than `PI5_RAM_GB`, the kernel refuses pages
  past what its heap can record, and doesn't run out of heap.

## Steps

- [x] Warm boots: `tools/pi5-boot --reboot`, again and again, each to the
  compositor and an address from DHCP, with `ps` answering after.
  Seventeen did, on the four-CPU kernel, the last ten in a row once
  `inet` waited for the link (log, 2026-10-26).
- [ ] Cold boots: power-cycled by hand, ten in a row, each to the
  compositor. Only these can show the power loss, never yet seen in a
  warm boot.
- [ ] Once L0 gives `heap_left` (the request this goal needs): before
  `frame_new`, `map_frame` (`kernel/process.l0`) checks it against a
  reserve and answers as if no frame were left. `test_frames_run_out`
  gains a case on a 96 MB heap, where the kernel now dies with `heap
  exhausted`, and the last process is refused instead.

## Spec changes

- pi5.md: the "not yet stable" limit goes, or shrinks to what remains;
  "Nothing yet stops processes taking more" goes.
- kernel.md: a page is refused once the kernel's heap is nearly full, as
  once the frames are gone.

## Log

- 2026-10-26: written from pi5.md's Limits.
- 2026-10-26: the user has seen no corrupted memory lately. Seven warm
  reboots in a row reached the compositor, all four CPUs running
  processes, `ps` answering after each. The eighth try stopped the loop
  only because `inet` got no DHCP answer: it sends five DISCOVERs 2 s
  apart from when it starts, and the link can come up partway through.
  The kernel's heap running out is not the Pi's alone: on QEMU,
  `test_frames_run_out` on a 96 MB kernel heap ends with `heap
  exhausted`, the kernel and every process with it. L0 gives no way to
  see the heap's room, so L0S asked for one
  ([REQUEST-heap-left.md](../probes/memory/REQUEST-heap-left.md)).
- 2026-10-26: the nic protocol gained `link` and the `lnk up` / `lnk
  down` notices, and `inet` counts its DHCP tries only while the link is
  up, starting again when it comes up. Ten more reboots in a row each
  took an address right after `gem: link up`.
