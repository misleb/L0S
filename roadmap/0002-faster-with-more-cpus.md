# 0002: More CPUs make L0S faster

Track: Kernel · Status: idea · Needs: – · Spec: kernel.md

## Why

Every system call, and so every message, is handled on CPU 0, and on QEMU
more CPUs are no faster: writing to a disk is slower on four than on one,
because handing a thread to another CPU costs more than a call on CPU 0
([kernel.md, Limits](../spec/kernel.md#limits)). So the demo and the tests
boot with one CPU unless asked.

## Done when

- `install` and `install_boot` (e2e) run no slower on four CPUs than on one.
- The demo's default `CPUS` can be more than 1.

## Steps

To be written. The limit's own measurements are the starting point.

## Spec changes

- kernel.md: the "more CPUs are no faster" limit is revised to the new
  timings.
- demo.md: the default `CPUS`, if it changes.

## Log

- 2026-10-26: written from kernel.md's Limits.
- 2026-10-27: most of what this measures, writing to a disk, is file
  data in 4 KB messages, a round trip of hand-offs between CPUs each
  (caller, kernel, `fs`, the disk driver, and back). 0023 moves it in
  requests of 64 KB through shared pages, about a sixteenth as many
  hand-offs, and times `install` and `install_boot` on one CPU and on
  four before and after; its numbers will be logged here too. Measure
  again once it lands, before working on this.
