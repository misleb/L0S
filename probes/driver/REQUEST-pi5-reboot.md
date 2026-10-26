# Feature request: a way to reboot the Raspberry Pi 5, so L0S can restart itself

Status: landed (L0's `board_reset`, spec 6.12; L0S's call 298, sh's `reboot`)
Project: L0S, a microkernel in L0, booting on a Raspberry Pi 5 (2 GB,
serial 1b08af2e, EEPROM 2026/05/26) by TFTP

L0S is developed on the board: `tools/pi5-boot` builds a TFTP root, the
Pi network boots it, and the script reads the debug UART. Every test
boot, though, needs a person to pull the power and plug it back in.
L0S's shell can end the system (`exit`), but L0 then halts the board,
and nothing in L0 can restart it. This asks for a reboot.

## What could not be written

A `reboot` command for L0S's shell, typed at the UART console, which
would end the system and start the board again so the firmware fetches
the new build. There are two ways to reset a BCM2712, and L0 gives a
program neither:

- **PSCI's `SYSTEM_RESET`**, function 0x84000009, an `smc` to the
  firmware's BL31. L0 has no builtin that makes a firmware call. Its
  host makes exactly one: section 10.3 says an exit with a nonzero status
  "asks the firmware to power the board off by PSCI's `SYSTEM_OFF`, which
  halts it". An exit with status 0 halts it too.
- **The power manager's watchdog**, `watchdog@7d200000` in
  `bcm2712-ds.dtsi`, which Linux's `bcm2835_wdt.c` resets the board
  with. It is not one of section 10.3's regions, so `open_device` refuses
  it, as it does everything off that table.

The mailbox, which is a region, has no tag that resets anything. The
firmware's `NOTIFY_REBOOT` (0x00030048) and `SET_REBOOT_FLAGS`
(0x00038064) only tell the firmware a reboot is coming, and how; Linux
sends them and then resets by one of the two ways above.

## Why `SYSTEM_RESET` is the same as what the host already does

On the Pi 5 the two PSCI calls differ by one register write. Upstream
TF-A's Raspberry Pi platform (`plat/rpi/common/rpi_pm.c`, with
`plat/rpi/rpi5/include/rpi_hw.h` putting `RPI3_PM_BASE` at 0x107D200000)
has:

- `rpi3_system_off`: set `PM_RSTS` (0x20) to partition 63, `0x555` with
  the password `0x5A000000`, then `rpi3_watchdog_reset`.
- `rpi3_system_reset`: `rpi3_watchdog_reset` alone.
- `rpi3_watchdog_reset`: `PM_WDOG` (0x24) = password | 10 ticks, then
  `PM_RSTC` (0x1C) with its WRCFG bits (0x30) replaced by full reset
  (0x20), with the password, and wait.

So a "halt" on the Pi 5 is a watchdog reset that tells the bootloader to
stop, and that is what the board's own log shows after L0S exits: the
bootloader starts again and stops at `Halt: power_off: 0`, as partition
63 tells it to. `SYSTEM_RESET` leaves partition 0, and the bootloader
boots as at power-on, which for this board is over the network again.

## The workaround actually used

Pulling the power. The bootloader's halt is a low-power wait; the board's
power button may also start it again, but a person still has to be there
for every boot.

## Smallest change that would help

**A builtin that resets the board,** say `(board_reset)`, never
returning, for the bare targets:

- on `--target pi5`: drain the UART as an exit does, then PSCI
  `SYSTEM_RESET` by `smc`, as the host already calls `SYSTEM_OFF`;
- on `--target virt`: the same call by `hvc`, the conduit QEMU's virt
  board's PSCI uses, so that QEMU resets the board (or, run with
  `-no-reboot`, exits), which keeps a program's tests of it on QEMU;
- under an operating system, and for `--target proc`: nothing to reset;
  it could fail as `open_device` does, or not be allowed at all.

In L0S the kernel would take it as its own system call (pid 1 or the
console's shell may ask for it), flush its log, and reset; `sh` would get
`reboot` beside `exit`. `tools/pi5-boot` could then type `reboot` at the
console after one boot's lines are read and stay with the board for the
next, so a run of boots needs nobody there.

## Alternative: the power manager as a region

| Base | Bytes | Device |
| --- | --- | --- |
| 0x107D200000 | 0x308 | the power manager, `brcm,bcm2712-pm` (`watchdog@7d200000`): `PM_RSTC` at 0x1C, `PM_RSTS` at 0x20, `PM_WDOG` at 0x24 |

That is `bcm2712-ds.dtsi`'s `reg = <0x7d200000 0x308>`, under
`soc@107c000000`, whose `ranges` put bus 0 at CPU 0x10_0000_0000. With
it, L0S resets the board as `__bcm2835_restart` does (partition bits into
`PM_RSTS`, then `PM_WDOG` = password | 10, then `PM_RSTC` full reset),
and gets the watchdog too: a driver that rearms it every few seconds
makes a board that hangs reboot itself. The HVS hangs the board with no
fault if it is read unclocked, so that matters here.

The cost is that the block also holds the power domains
(`#power-domain-cells`), which a wrong write could switch off, and that
it would be a Pi-only path with nothing to test on QEMU. Both would be
welcome; the builtin alone is enough for a reboot.

## Which deliberate restriction this breaks

None that we can see. The host already calls PSCI at the end of every
program; this lets a program choose reset over power-off. A region would
be a device like the others.

## Alternatives considered

- **An exit status that means reset**, such as a reserved status in
  place of a new builtin. Smaller, but it mixes a program's answer with
  what the board does after, and section 10.3 already gives every nonzero
  status one meaning.
- **The mailbox.** No property tag resets the board (above).
