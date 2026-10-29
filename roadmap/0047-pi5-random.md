# 0047: Randomness on the Pi 5

Track: Pi 5 · Status: idea · Needs: – · Spec: devices.md, pi5.md

## Why

`random` is served only by `virtio-rng`, so on a Pi 5 there is none
([pi5.md](../spec/pi5.md): "no virtio, so no `random`"), and `inet`
keys its TCP connections from the clock. TLS (0048) needs good
randomness for every connection's keys, so the board must have it. The
BCM2712 has a hardware random number generator; a driver for it serves
the same random protocol.

## Done when

- A driver for the BCM2712's generator registers `random` on a Pi 5 and
  serves `bytes N` as `virtio-rng` does, and `run random 32` writes
  bytes that differ every boot.
- `inet` then keys its connections from it on the Pi 5.

## Steps

To be written: find the generator's address, registers and interrupt,
if any, from the board's device tree, and read them through a region
as section 10.3's tables do.

## Spec changes

- devices.md: the Pi 5's driver.
- pi5.md: `random` on the board.

## Log

- 2026-10-29: written, with 0041 to 0046, 0048 and 0049; 0048 needs it.
