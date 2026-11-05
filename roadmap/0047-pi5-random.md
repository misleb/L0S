# 0047: Randomness on the Pi 5

Track: Pi 5 · Status: active · Needs: probes/driver/REQUEST-pi5-rng.md (met) · Spec: devices.md, pi5.md

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

- [x] **The generator found**: the BCM2712's RNG200,
  `brcm,bcm2711-rng200` at 0x7d208000 in `bcm2712.dtsi`, 0x107D208000
  to the CPU, 0x28 bytes, no interrupt; its registers and how Linux
  turns it on and reads it from `iproc-rng200.c`'s bcm2711 functions.
- [x] **`rng200`**, `user/sbin/rng200`: the generator turned on if it
  is off, as Linux does; for `bytes N`, warmed up, the FIFO's words
  taken as they come, least significant byte first, a failed health
  test restarting it once; `random` served as `virtio-rng` serves it.
  With no region it can open, it says so and exits 0. Started before
  `inet` in `pi5/etc/system`, flagged `dev` in `pi5/etc/inittab`.
  `inet` needs no change: it asks `random` for its secret at its first
  connection.
- [x] **The region asked of L0**:
  [probes/driver/REQUEST-pi5-rng.md](../probes/driver/REQUEST-pi5-rng.md),
  0x107D208000, 0x28 bytes.
- [ ] **On a Pi 5**, now that L0 gives the region: the log's `rng200: an
  RNG200 at 0x107d208000, serving random`, `run random 32` different
  every run and every boot, and `run http https://example.com/` over
  TLS (0048's last step).

## Spec changes

- devices.md: the Pi 5's driver.
- pi5.md: `random` on the board.

## Log

- 2026-10-29: written, with 0041 to 0046, 0048 and 0049; 0048 needs it.
- 2026-11-05: steps written and the first three done. The generator
  is no region of L0's yet, so `rng200` is written and tested on the
  host but has not touched the device; on QEMU it says there is no
  RNG200 and exits 0. Blocked on the region, asked of L0 in
  REQUEST-pi5-rng.md.
- 2026-11-05: the region landed in L0 (its roadmap 0151, commit
  d47d7cd, 0x107D208000, 0x28 bytes, no interrupt) and the toolchain
  was installed; the request is marked landed. What is left is the run
  on a Pi 5: `make pi5-netboot` (or a card), then in the log
  `rng200: an RNG200 at 0x107d208000, serving random`, `run random 32`
  twice and after a reboot, and `run http https://example.com/`.
