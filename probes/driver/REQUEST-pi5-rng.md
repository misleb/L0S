# Feature request: the Raspberry Pi 5's random number generator as a region

Status: landed (L0 roadmap 0151, commit d47d7cd): the region, 0x107D208000,
0x28 bytes, no interrupt; not yet seen on a Pi 5
Project: L0S, a microkernel in L0, running on QEMU's virt board and on a
Raspberry Pi 5 (L0S roadmap 0047, which 0048's last step needs)

L0S now has a TLS 1.3 client (L0S roadmap 0048): `http https://…` and
its agent's own internet access work on QEMU, keyed by `random`, which
`virtio-rng` serves from the host's `/dev/urandom`. A Pi 5 has no
virtio, so it has no `random`. TLS there refuses to connect, since it
has nothing to make its X25519 key and ClientHello random from.
`inet`'s TCP sequence numbers also go unkeyed. The BCM2712 has a
hardware generator, but L0 gives no region over it.

This asks for one region and no interrupt.

## What could not be written

L0S's driver for the generator, `user/sbin/rng200`, is written and in
the Pi 5's `/etc/system`, before `inet`. It sets the generator up and
reads it as Linux does the same model:

- `bcm2712.dtsi` (raspberrypi/linux, rpi-6.12.y): `random:
  rng@7d208000`, `compatible = "brcm,bcm2711-rng200"`, `reg =
  <0x7d208000 0x28>`, no `interrupts`. It is in `soc@107c000000`, whose
  `ranges = <0x00000000 0x10 0x00000000 0x80000000>` put it at
  0x107D208000 to the CPU, beside the debug UART at 0x107D001000, which
  is already a region.
- `drivers/char/hw_random/iproc-rng200.c`, `bcm2711_rng200_init` and
  `bcm2711_rng200_read`: `RNG_CTRL` at 0x00 (RBGEN, bits 0 to 12, and
  the divider from bit 13); `RNG_TOTAL_BIT_COUNT` at 0x0C and its
  threshold at 0x10; `RNG_INT_STATUS` at 0x18; `RNG_FIFO_DATA` at 0x20;
  `RNG_FIFO_COUNT` at 0x24. If RBGEN is clear, init writes 0x40000 to
  the threshold, `2 << 8` to the FIFO count, and `0x3 << 13 | 0x1FFF` to
  `CTRL`. A read waits for the bit count to pass 16, then takes words
  from `FIFO_DATA` while `FIFO_COUNT & 0xFF` says there are any.
  `iproc_rng200_restart` resets it through `RNG_SOFT_RESET` (0x04) and
  `RBG_SOFT_RESET` (0x08) after a failed health test.

Every register is inside the 0x28 bytes. `rng200` opens
`(open_region 70818758656 40)`. On QEMU's board that fails, and it says
so and exits 0:

```
rng200: no RNG200 on the board: no device there
```

On a Pi 5 it says the same today, since the region is not in section
10.3's table.

## The workaround actually used

None that is good enough. Without `random`, `inet` keys TCP from the
clock alone, and TLS refuses to connect on a Pi 5. The other sources a
program can reach on the board (the system timer's low bits, the
mailbox's answers) are not secret enough to key TLS with. The firmware
puts a seed in the device tree's `/chosen/rng-seed`, but L0 does not
pass the device tree to a program.

## Smallest change that would help

**One region on the Raspberry Pi 5:**

| Base | Bytes | Device |
| --- | --- | --- |
| 0x107D208000 | 0x28 | the BCM2712's random number generator, an RNG200, `brcm,bcm2711-rng200`: its control, status, bit count and FIFO |

The host sets nothing up: `rng200` turns the generator on if the
firmware left it off, as Linux does.

## Which deliberate restriction this breaks

None. It is a device's registers. A driver reaches no memory through
them, and the device has no DMA.

## Alternatives considered

- **A builtin for randomness** (`(random_bytes n)`, from the host's
  `getrandom` under an OS, a board's generator on a board). That would
  serve every program and board at once, QEMU's without virtio-rng
  included. But it is a larger change than a region, and L0S already has
  a protocol and drivers for it.
- **The device tree's `rng-seed`**, given to the program as bytes. It is
  64 bytes once a boot, enough to seed a generator in user space. But
  that seeding is what a hardware generator makes unnecessary.

## How it will be checked

On a Pi 5 (2 GB, D0 silicon): the boot's log says `rng200: an RNG200 at
0x107d208000, serving random`; `run random 32` writes 32 bytes that
differ every boot and every run; `run http https://example.com/` fetches
the page over TLS 1.3. Then L0S's roadmap 0047 is done, and 0048's last
step, the Pi 5, can run.
