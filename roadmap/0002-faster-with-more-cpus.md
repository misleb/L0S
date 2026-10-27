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
