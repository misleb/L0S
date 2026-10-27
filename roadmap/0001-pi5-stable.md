# 0001: The Pi 5 boots reliably

Track: Pi 5 · Status: idea · Needs: – · Spec: pi5.md, kernel.md

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

To be written: first, find the cause of the corrupted boots.

## Spec changes

- pi5.md: the "not yet stable" limit goes, or shrinks to what remains.

## Log

- 2026-10-26: written from pi5.md's Limits.
