# 0004: USB and the SD card on the Pi 5

Track: Pi 5 · Status: done · Needs: – · Spec: devices.md, storage.md, pi5.md

## Why

USB and the SD card have run on QEMU only
([devices.md, Limits](../spec/devices.md#limits),
[storage.md, Limits](../spec/storage.md#limits)), and the Pi 5 has no
disk ([pi5.md, Limits](../spec/pi5.md#limits)).

## Done when

- A USB keyboard and mouse work on a Pi 5.
- `sdhci` reads and writes the Pi 5's card, and `fs` mounts its volumes.

## Steps

- [x] USB keyboard and mouse on the Pi 5, through RP1's xHCI controllers.
  They work, by interrupt, since 02918ae (log, 2026-10-26).
- [x] `sdhci` on the Pi 5's card, once L0 gives the BCM2712's `sdio1`
  (the request this goal needs): `sdhci pi5` opens it at 0x1000FFF000
  in place of a BAR, takes its base clock as 200 MHz if the
  capabilities do not say, binds interrupt 305, and serves the card as
  a disk; `pi5/etc/inittab` starts it. It read and wrote a 64 GB
  card, a sector at a time and eight in one request (log, 2026-10-27).
- [x] `fs` mounts a volume of the card, and Files shows it. A Raspberry
  Pi OS card's `bootfs` did, on an MBR (log, 2026-10-27).

## Spec changes

- storage.md: "has run on QEMU only" names the Pi 5.

## Log

- 2026-10-26: written from devices.md, storage.md and pi5.md's Limits.
- 2026-10-26: the first step had landed already, in 02918ae: `xhci`
  takes RP1's MSI-X vectors 31 and 36 (interrupts 191 and 196), not
  polling, and the user has used a USB keyboard and mouse on the board,
  the keys reaching the shell and the windows and the pointer following
  the mouse. Each of 0001's ten cold boots found both, by interrupt.
  Moved into the spec: devices.md's limit names the Pi 5, and its "first
  run should check" became what was seen.
- 2026-10-26: the card waits on L0. The Pi 5's microSD slot is behind
  the BCM2712's own SDHCI, `sdio1` (`brcm,bcm2712-sdhci`, host and cfg
  at 0x1000FFF000 and 0x1000FFF400, SPI 273, a fixed 200 MHz clock),
  not RP1's, whose two SDHCIs the board's device tree disables. L0's
  Pi 5 host gives no region there, so L0S asked for one
  ([REQUEST-pi5-sdio.md](../probes/storage/REQUEST-pi5-sdio.md)), with
  `want.l0` beside it. The card's power and card detect stay the
  firmware's, on `gio_aon` pins 4 and 5; a second ask follows only if
  a network boot leaves it unpowered.
- 2026-10-27: L0 gave `sdio1` (its roadmap 0125, bd48a24). `sdhci pi5`
  opens it, points its card detect at the slot (cfg's pin select, as
  Linux's sdhci-brcmstb does), and brought a 64 GB Raspberry Pi OS card
  up as `disk0`, on interrupt 305; its capabilities say the 200 MHz
  base clock themselves. Its sectors read back right. `fs` mounted
  nothing at first: the Pi's inittab started only `fs ram`, which is
  `tmpfs`, so `sdhci`'s `attach` reached no one; a disk `fs` beside it
  mounts `bootfs`, FAT32 on the MBR. Files then hung opening it: it
  counted each folder by listing it, and `overlays/`'s 368 entries made
  a `list` reply of more than a message, which `fs` could not send and
  the client waited for. `list` now takes FROM and answers a message of
  entries at a time, `fs_list` gathers them, `fs` says a reply too big
  to send, and Files no longer lists the folders in a place
  (`tests/e2e/bigdir`). Files opens and goes through `bootfs`. Moved
  into the spec: pi5.md's "has no disk". Writes are not yet tried on
  the board.
- 2026-10-27: writes, in the gap before the card's first partition,
  sectors 2048 to 2055, read as zeros first: `disk write` of one sector
  at 2048 and at 2055 (CMD24) read back right, then `disk zero 2048 8`,
  new, eight sectors in one request (CMD25 and Auto CMD12), read back as
  zeros, the gap as it was. The MBR and `bootfs`'s `cmdline.txt` read
  back unchanged. Moved into the spec: storage.md's SD card names the
  Pi 5 and `sdio1`. Done.
