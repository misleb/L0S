# 0003: All four of the Pi 5's CPUs

Track: Pi 5 · Status: blocked · Needs: 0001, 0002 · Spec: pi5.md, kernel.md

## Why

Several CPUs have run only on QEMU's aarch64 board. The Pi 5 has four, but
L0S does not boot reliably there yet
([kernel.md, Limits](../spec/kernel.md#limits)).

## Done when

- L0S boots on the Pi 5 with processes on the other three CPUs, and its
  shell and desktop work as on one.

## Steps

To be written once 0001 is done.

## Spec changes

- kernel.md: the sentence "Several CPUs have run on QEMU's aarch64 board
  only" names the Pi 5 too.

## Log

- 2026-10-26: written from kernel.md's Limits.
- 2026-10-26: the Pi 5 already runs the four-CPU kernel, as `cpu_count`
  says four: seven warm reboots for 0001 each logged `l0s: 4 CPUs: the
  kernel on CPU 0, processes on CPUs 1 to 3`, reached the compositor and
  answered `ps`. So the Pi 5's Limit in kernel.md no longer holds as
  written, and this goal may be mostly done once 0001 is.
