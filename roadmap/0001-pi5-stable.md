# 0001: The Pi 5 boots reliably

Track: Pi 5 · Status: done · Needs: – · Spec: pi5.md, kernel.md

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
- [x] Cold boots: power-cycled by hand, ten in a row, each to the
  compositor. Only these can show the power loss, never yet seen in a
  warm boot. Ten did, with no power lost (log, 2026-10-26).
- [x] Once L0 gives `heap_left` (the request this goal needs): before
  `frame_new`, `map_frame` (`kernel/process.l0`) checks it against a
  reserve and answers as if no frame were left. `test_heap_runs_low`
  runs `test_frames_run_out`'s processes on a 96 MB heap (`make
  test-virt-heap`, part of `make test-virt`), where the kernel died
  with `heap exhausted`, and now refuses them instead.

## Spec changes

- pi5.md: the "not yet stable" limit goes, or shrinks to what remains.

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
- 2026-10-26: L0 gave `heap_left` (its roadmap 0124, 5617f17), and
  `map_frame` refuses a page while it is under `heap_reserve`. 8 MB and
  32 MB were too little: on a 96 MB heap the kernel still stopped with
  `heap exhausted`, once with 38 MB free, since `heap_left` counts free
  bytes, and a heap of page records leaves them in pieces too small for
  what ending a 600 MB process makes. 40 MB survived; the reserve is
  64 MB. Moved into the spec: kernel.md's refusal and its cost to the
  192 MB heap, pi5.md's "Nothing yet stops processes taking more".
- 2026-10-26: ten cold boots in a row, the board's power cut and
  restored by hand each time (the bootloader said `power-on-reset 1`),
  of 0da88be served over the network: each reached `l0s>`, the
  compositor at 3840x2160 and a DHCP lease, all four CPUs running, with
  nothing faulting, corrupted or lost. Moved into the spec: pi5.md's
  "not yet stable" limit goes, and kernel.md says the Pi 5 runs
  processes on its CPUs. Done.
