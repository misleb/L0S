# 0068: The first stage alone, wherever a card is made

Track: Pi 5 · Status: idea · Needs: – · Spec: pi5.md, boot.md, storage.md

## Why

The Pi 5's release boots from an initramfs of the first stage alone,
what mounts the system volume (`make pi5-stage1`), and starts the rest
from the volume ([pi5.md](../spec/pi5.md), "The release's initramfs is
the first stage alone"). Two ways of making a card still write the whole
system as `input.bin`, about 19.5 MB the card's System holds again:

- `install --boot VOLUME --root ROOT`, from a running system, writes an
  initramfs of every file of `/` ([pi5.md](../spec/pi5.md)'s Limits);
- `make pi5-card` with `PI5_ARGS=root=UUID`, the netboot's archive.

`usb-hid` is in the first stage though no disk needs it: started from
the system volume, the board's USB keyboard was dead though `usb-hid`
ran, which QEMU does not show (`usb-hid` started late there still
claims the keyboard and mouse). Why, from the board's `dmesg`, would let
it go back to the second stage.

And the first stage mounts only the card: `xhci` is in it so that a
system volume can be on USB storage, which L0S has no driver for yet
([storage.md](../spec/storage.md)).

## Done when

- `install --boot … --root ROOT` writes the first stage alone, the
  programs the initramfs's inittab starts and the shell, with
  `/etc/inittab`, `board`, `motd` and a rescue `/etc/system`, and a card
  so made boots to the desktop from ROOT.
- A USB mass storage driver serves a disk in the first stage, and a
  system volume on a USB drive boots with `root=`.

## Steps

(none yet)

## Spec changes

- pi5.md: `install --boot --root` writes the first stage alone; the
  limit goes.
- storage.md: USB mass storage disks.

## Log

- 2026-11-04: written when the release's initramfs became the first
  stage alone.
- 2026-11-04: usb-hid moved back to the first stage, the keyboard dead
  on the board when the system volume started it.
