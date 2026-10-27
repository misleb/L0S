# Feature request: the BCM2712's SD host controller, sdio1, and its interrupt, on the Raspberry Pi 5, so L0S can read and write the microSD card

Status: landed (L0 roadmap 0125, commit bd48a24): `sdio1` as asked,
0x1000FFF000 for 0x600 bytes, and its interrupt, 305; not `gio_aon`.
L0 has not run it on a board.
Project: L0S, a microkernel in L0, booting on a Raspberry Pi 5 (2 GB,
serial 1b08af2e, EEPROM 2026/05/26) by TFTP

L0S has no disk on the Pi 5: it boots over the network and keeps its
files in a volume in memory (`fs ram`), lost at every power cut. Its
SD card driver, `sdhci` (`user/sbin/sdhci/`), already brings cards up
and moves their blocks on QEMU, through `sdhci-pci`'s standard SDHCI
registers, by polling or by its interrupt. The Pi 5's microSD slot is
behind a standard SDHCI too, the BCM2712's own `sdio1`, but no region
reaches it. This asks for one.

## What could not be written

`sdhci pi5`: the same driver, opening `sdio1` at its fixed address in
place of a BAR that `pcie` found, and serving its card as a disk that
`fs` mounts (L0S's roadmap 0004). Every register it uses is SDHCI's
own, which `sdhci` already drives. What no region reaches is the
controller: `open_device` refuses it, since section 10.3 lists none.

`want.l0` beside this file opens the region asked for and reads the
controller's version, capabilities and present state, and the cfg
block's first word; `l0 check` accepts it, and on a Pi 5 today its
`open_device` gives `DeviceFailed`.

## The workaround, and why it is not enough

There is none. Polling would serve, as `sdhci` polls every card while
bringing it up, but polling still reads the controller's registers.
The firmware reads the card itself, to boot from it, but offers no
block reads to the OS over the mailbox. RP1's two SDHCIs (`rp1_mmc0`
and `rp1_mmc1`, at RP1's 0x180000 and 0x184000, inside the RP1 region
L0 gives) are `status = "disabled"` in this board's device tree; the
microSD slot is `sdio1`'s (its alias `mmc0`).

## Smallest change that would help

**`sdio1`'s registers as one region on the Pi 5, and its interrupt.**
From the device tree the firmware gives this board
(`bcm2712-rpi-5-b.dtb` from raspberrypi/firmware's `stable`,
decompiled), node `sdio1: mmc@fff000` under `soc@107c000000`, whose
`ranges` map 0 to 0x10_0000_0000:

```
sdio1: mmc@fff000 {
	compatible = "brcm,bcm2712-sdhci", "brcm,sdhci-brcmstb";
	reg = <0xfff000 0x260 0xfff400 0x200>;
	reg-names = "host", "cfg";
	interrupts = <0x00 0x111 0x04>;     /* GIC_SPI 273, level high */
	clocks = <&clk_emmc2>;              /* fixed, 200000000 Hz */
	bus-width = <0x04>;
	vqmmc-supply = <&sd_io_1v8_reg>;    /* gio_aon 3, SD_IOVDD_SEL */
	vmmc-supply = <&sd_vcc_reg>;        /* gio_aon 4, SD_PWR_ON */
	cd-gpios = <&gio_aon 5 GPIO_ACTIVE_LOW>;
	...
```

| Base | Bytes | What | Interrupt |
| --- | --- | --- | --- |
| 0x1000FFF000 | 0x600 | `sdio1`: SDHCI's registers (`host`, 0x260 bytes), then the brcmstb `cfg` block at 0x400 (0x200 bytes) | SPI 273, the GIC's ID 305, level |

Both blocks are in one page, which nothing else shares, so one region
over 0x600 bytes covers them. The `cfg` block is what Linux's
`sdhci-brcmstb.c` sets for the BCM2712 before using the host: how the
card is detected and the controller's speed straps. `sdhci` would read
it first and write it only as that driver does.

The interrupt is SDHCI's: a status bit set in Normal or Error
Interrupt Status (0x30) while its bit in Signal Enable (0x38) is set,
ended by writing the status bit back before `interrupt_done`. `sdhci`
already turns signals on only while it waits, so the line falls each
time. Polling would serve at first, as it does for a controller with
no interrupt; the table in section 10.3 would gain a row, `305 |
sdio1's | 305`.

The firmware's own state is what `sdhci` would need from it: the
card's power on (`sd_vcc_reg` is `regulator-boot-on`), its signalling
at 3.3 V (`sd_io_1v8_reg`'s `SD_IOVDD_SEL` low), and `aon_gpio5` muxed
to the controller's card detect (`emmc_aon_cd_pins`, function
`sd_card_g`), as it leaves them having looked at the card to boot. Its
log on this board says `uSD voltage 3.3V` on a network boot. If the
card turns out to be unpowered after a boot that did not use it, a
second, smaller ask would follow: `gio_aon` at 0x107D517C00, 0x40
bytes, for its pins 3 to 5 alone. That block also holds `RP1_RUN` and
the PMIC's lines, so it is left out of this one.

## How L0S would use them

`sdhci pi5` would do what `sdhci pci` does (spec, storage.md, "The SD
card"), with these differences:

1. The region opened at 0x1000FFF000 in place of BAR 0, and the cfg
   block read and said on the serial line.
2. The base clock taken as 200 MHz, the device tree's `clk_emmc2`,
   should the capabilities' field (bits 15 to 8 of 0x40) not say it:
   the card's 400 kHz while it is brought up, then 25 MHz.
3. A reset of all (0x2F), power on at 3.3 V (0x29), CMD0, CMD8,
   ACMD41, CMD2, CMD3, CMD9, CMD7, and blocks moved through the buffer
   (0x20) a word at a time, so no DMA and no `dma_sync`.
4. The interrupt bound, 305, as `sdhci pci` binds its MSI or INTx.

`sdhci probe` would read the registers first, writing none, as `hvs
probe` read the HVS's before anything was written.

## Which deliberate restriction this breaks

None that we can see. An SDHCI with its DMA unused (Transfer Mode's
DMA Enable clear, as `sdhci` leaves it) reads and writes only the card;
its SDMA and ADMA2 could write memory, but so can `dma40` and the HVS,
which L0 gives already, and only a program the kernel trusts with
devices opens a region (L0S's `dev` lines).

## Alternatives considered

- **The firmware**: it reads the card to boot, but the Pi 5's mailbox
  has no block-device property for the OS.
- **RP1's SDHCIs**: reachable today, but disabled on this board and not
  the slot's.
- **A USB card reader** behind RP1's xHCI: needs USB mass storage and
  bulk endpoints, which L0S's `xhci` has not, and is not the board's
  own slot.
- **The network**: `tftp` reads files from a server, but that is not
  a disk the board keeps.
