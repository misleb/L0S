# 0004: USB and the SD card on the Pi 5

Track: Pi 5 · Status: ready · Needs: – · Spec: devices.md, storage.md, pi5.md

## Why

USB and the SD card have run on QEMU only
([devices.md, Limits](../spec/devices.md#limits),
[storage.md, Limits](../spec/storage.md#limits)), and the Pi 5 has no
disk ([pi5.md, Limits](../spec/pi5.md#limits)).

## Done when

- A USB keyboard and mouse work on a Pi 5.
- `sdhci` reads and writes the Pi 5's card, and `fs` mounts its volumes.

## Steps

- [ ] USB keyboard and mouse on the Pi 5, through RP1's xHCI controllers.
  Check first whether "polls RP1's controllers" in devices.md's limit
  still holds, since RP1's interrupts now come as MSIs.
- [ ] `sdhci` on the Pi 5's card.
- [ ] `fs` mounts a volume of the card, and Files shows it.

## Spec changes

- devices.md and storage.md: "has run on QEMU only" names the Pi 5.
- pi5.md: "It has no disk" goes.

## Log

- 2026-10-26: written from devices.md, storage.md and pi5.md's Limits.
