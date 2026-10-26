# Feature request: a channel of the BCM2712's 40-bit DMA controller, and its interrupt, on the Raspberry Pi 5, so L0S can play sound on HDMI0

Status: asked, not yet on L0's roadmap
Project: L0S, a microkernel in L0, booting on a Raspberry Pi 5 (2 GB,
serial 1b08af2e, EEPROM 2026/05/26) by TFTP

L0S has no sound. On the Pi 5 the obvious first output is the monitor
on HDMI0, which L0S already drives: `hvs` (`user/sbin/hvs/`) sets its
mode itself through the regions L0 gives for HDMI0's controller, PHY,
pixel valve and DDC (roadmap 0120). Those regions already hold every
register HDMI audio needs but one thing: the samples have to reach the
HDMI audio FIFO, the MAI, at the rate the monitor plays them, and on the
BCM2712 that is a DMA controller's job. This asks for one channel of it.

## What could not be written

A driver, `hdmi-audio`, serving a sound protocol: a client's 16-bit PCM
turned into IEC958 subframes in DMA pages and played on HDMI0, as
Linux's `vc4_hdmi` does with `bcm2835-dma`. The MAI's registers are in
the HD block L0 gives (0x107C720000: `MAI_CTL` 0x10, `MAI_THR` 0x14,
`MAI_FMT` 0x18, `MAI_DATA` 0x1C, `MAI_SMP` 0x20), and the audio packet,
clock-regeneration and infoframe registers are in HDMI0's run
(0x107C700000: the core's `MAI_CHANNEL_MAP`, `MAI_CONFIG`,
`AUDIO_PACKET_CONFIG`, `CRP_CFG`, `CTS_0/1` at 0x1400 + 0xA4 to 0xD8,
the packet RAM at 0x3800, and the 108 MHz audio clock's gate in
`DVP_MISC_CONFIG`, bit 3). What no region reaches is anything that
writes `MAI_DATA` without the CPU: `open_device` refuses the DMA
controller, since section 10.3 lists none.

`want.l0` beside this file opens the channel asked for and reads its
registers; `l0 check` accepts it, and on a Pi 5 today its
`open_device` gives `DeviceFailed`.

## The workaround, and why it is not enough

The CPU could write `MAI_DATA` itself, polling `MAI_CTL`'s `FULL` (bit
11). Stereo at 48 kHz is 96,000 words a second, and the FIFO is small:
no source gives its depth, but Linux's thresholds for it are 6- and
7-bit fields set at 16 and 28 words, so it holds well under a
millisecond of sound. The MAI raises no interrupt of its own (the
`hdmi0` node lists only CEC's and hotplug's). So a driver would have to
run every few hundred microseconds, on the one CPU L0S has, with a
10 ms time slice: any other process running for a slice empties the
FIFO and the monitor clicks or mutes (`MAI_CTL`'s `DLATE`, bit 15). A
system-timer interrupt every 250 µs would make it run, at a cost of
some 4,000 wake-ups a second, and still underrun behind a slice. With
DMA the CPU fills a page of samples every 10 ms or so, and nothing else
in the system has to be fast.

## Smallest change that would help

**One channel of `dma40` as a region on the Pi 5, and its interrupt.**
From `bcm2712-ds.dtsi` (rpi-6.12.y), node `dma40: dma@10600` under
`axi`, whose `ranges` and `dma-ranges` are the identity above 64 GB:

```
dma40: dma@10600 {
	compatible = "brcm,bcm2712-dma";
	reg = <0x10 0x00010600 0 0x600>;
	interrupts = <GIC_SPI 86 IRQ_TYPE_LEVEL_HIGH>, /* dma4 6 */ ...
```

| Base | Bytes | What | Interrupt |
| --- | --- | --- | --- |
| 0x1000010600 | 0x100 | channel 6 of `dma40`, a 40-bit "DMA4" channel (`bcm2835-dma.c`'s `bcm2712_dma_cfg`, `chan_40bit_mask` bits 6 to 11) | SPI 86, the GIC's ID 118, level |

`bcm2712-rpi.dtsi` gives Linux channels 6 to 10 of it (`brcm,dma-channel-mask
= <0x07c0>`) and keeps channel 11 out: "The VPU firmware DMA channel 11
for VCHIQ". So channel 6 is not the firmware's. If a region per channel
is too fine, channels 6 to 10, 0x1000010600 for 0x500 bytes, with SPIs
86 to 90 (IDs 118 to 122), would do as well; channel 11, 0x1000010B00,
must stay out. The legacy `dma32` channels 0 to 5, at 0x1000010000, are
not needed.

The interrupt is the channel's end of a control block whose `TI` has
`INTEN`; a driver acknowledges it by writing `INT`, bit 2, to the
channel's `CS`, before `interrupt_done`. Polling would serve at first,
as `hvs` polls DDC0, but a driver that sleeps between periods is the
point: the table in section 10.3 would gain a row, `118 | dma40
channel 6's | 118`.

## How L0S would use them

`hdmi-audio` would play in Linux's order (`vc4_hdmi_audio_startup`,
`vc4_hdmi_audio_prepare`, then dmaengine's cyclic transfer):

1. M2MC on, as `hvs` makes sure of it, and the audio clock's gate
   opened; HDMI in HDMI mode, not DVI (`SCHEDULER_CONTROL`'s
   `MODE_HDMI`, and `HDMI_ACTIVE` read back).
2. The MAI reset (`MAI_CTL` 0x8207), its divider from 108 MHz to the
   sample rate (`MAI_SMP` 0x0008CA00 at 48 kHz), enabled for two
   channels (0x3028), its format PCM at 48 kHz (`MAI_FMT` 0x00020900),
   its thresholds as Linux sets them on the D0 this board's HVS is
   (`MAI_THR` 0x08080E1C), its config and channel map, the audio
   packets' config, N (`CRP_CFG` 0x01001800 at 48 kHz) and CTS, and
   the audio infoframe written into packet RAM's slot 4.
3. A ring of periods in pages from `dma_alloc`, a page each, 512 stereo
   frames as 1,024 subframe words, about 10.7 ms at 48 kHz, cleaned
   with `dma_sync` once written; and one control block per period, 8
   words, 32-byte aligned, in another DMA page: `TI` 0x00009404
   (`WAIT_RESP`, `PER_MAP` 10, HDMI0's DREQ, `D_DREQ`), with `INTEN`
   added, `SRC` the period's address and `SRCI` 0x5300 with its bits
   39 to 32 (`INC`, 128-bit reads, bursts of 4), `DEST` 0x7C72001C and
   `DESTI` 0x310 (`MAI_DATA`, bits 39 to 32 0x10), `LEN` a page, and
   `NEXT_CB` the next block's address over 32, the last pointing back
   to the first. A frame's address, from `frame_address` in the kernel
   and `dma_addresses` in the driver, is the DMA's, as the identity
   `dma-ranges` say.
4. The channel started: `CB` the first block's address over 32, then
   `CS` 0x00FA0301 (`ACTIVE`, `PROT`, `QOS` 10, `PANIC_QOS` 15).
5. On each interrupt, `INT` acknowledged, the period just played
   refilled from what clients queued, or with silence, and cleaned.
6. Stopped as `bcm2711_dma40_abort` stops it: `ACTIVE` cleared, waited
   for `TRANSACTIONS` (bit 25) to clear, `CS` `PROT`, and the channel
   reset by `DEBUG`'s `RESET` (bit 23); then the MAI reset and flushed.

`hdmi-audio probe` would read the channel's registers first, writing
none, as `hvs hdmi` read HDMI0's before anything was written.

## Which deliberate restriction this breaks

None that we can see. A DMA channel writes where its control blocks
say, so a program that can open one can write any memory, the
kernel's included; but so can the HVS through `iommu4`, which L0 gives
already, and on the Pi 5 only a program the kernel trusts with devices
opens a region (L0S's `dev` lines). The channel reads nothing the
program does not point it at.

## Alternatives considered

- **The CPU feeding the FIFO** (above): it runs, but underruns
  whenever any other process has the CPU.
- **The firmware.** The Pi 4's firmware played HDMI audio for Linux's
  `bcm2835-audio` over VCHIQ; the Pi 5's does not, and its HDMI audio
  is `vc4`'s alone.
- **RP1's I2S**, which L0 reaches through RP1's region, with RP1's own
  DMA: it needs a DAC on the GPIO header, and is not HDMI.
- **The `dma32` channels** at 0x1000010000: 32-bit addresses, so they
  could not reach `MAI_DATA` at 0x107C72001C, and Linux gives HDMI
  audio to `dma40`.
