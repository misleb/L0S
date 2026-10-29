# Feature request: the HVS's end-of-frame interrupt on the Raspberry Pi 5, its controller as a region and its interrupt given

Status: landed (L0 roadmap 0127, commit 955ebbb): the region and interrupt 129, not the
pixel valve's; seen on a Pi 5, `hvs eof` counting 59.9 Hz
Project: L0S, a microkernel in L0, running on QEMU's virt board and on a
Raspberry Pi 5 (L0S roadmap 0005, which 0006 needs)

L0S's `hvs` driver (`user/sbin/hvs/`) shows the desktop on a Pi 5
through the BCM2712's HVS, on the regions L0 roadmap 0105 gave. It
can't tell when a frame ends. A restack writes the display list the
channel isn't fetching, points the channel at it, and polls the
channel's `DL` register for up to 50 ms to see it taken. So it can't
change a list only between frames, or tell a client which frame showed
its change. L0S's paced display queue (its roadmap 0006) needs both.

This asks for one region and one interrupt.

## What could not be written

On the BCM2712 the HVS raises a channel's end of frame not by a register
of its own but through the display's interrupt controller, `disp_intr`:

- `bcm2712.dtsi`: `disp_intr: interrupt-controller@7c502000`,
  `reg = <0x7c502000 0x30>`, `brcm,bcm2711-l2-intc`, `interrupts =
  <GIC_SPI 97 IRQ_TYPE_LEVEL_HIGH>`.
- The `hvs` node has `interrupt-parent = <&disp_intr>`, `interrupts =
  <2>, <9>, <16>` and `interrupt-names = "ch0-eof", "ch1-eof",
  "ch2-eof"`.
- `vc4_hvs.c` on SCALER6 (`VC4_GEN_6_C`, `VC4_GEN_6_D`) enables and
  disables the line at that controller (`enable_irq` and
  `disable_irq_nosync`), and writes no HVS register to do so.
- `irq-brcmstb-l2.c` handles a `bcm2711-l2-intc` as level-triggered: the
  lines raised at 0x00, a write of 1s clearing them at 0x08, the mask at
  0x0C, masking at 0x10, unmasking at 0x14.

So a driver unmasks line 2, waits for GIC SPI 97, and clears line 2 at
0x08 before it ends the interrupt. L0 gives neither the controller nor
the interrupt. `hvs eof`, a stage that asks for both and touches nothing
else, said on a Pi 5 (2 GB, D0 silicon, a 3840×2160 monitor on HDMI0)
with the desktop running:

```
hvs: eof: the display's interrupt controller, 0x107c502000, is not given: no device there
hvs: eof: cannot bind interrupt 129: the board has no such interrupt
```

The second line is L0S's kernel reporting `interrupt_enable 129` as -3.
Section 10.3's table of the Pi 5's interrupts lists 0, 96 to 99, 118,
153, 160 to 223 and 305.

## The workaround actually used

Polling. After pointing `LPTRS` at a new list, the driver reads the
channel's `DL` a millisecond apart, for at most 50 ms, until its active
list is the new one. It works, but it ties up the driver for most of a
frame on every restack. It can't tell a frame that showed a `damage`
from one that didn't, and STATUS's frame count is 6 bits and is only
read when polled.

## Smallest change that would help

**One region and one interrupt on the Raspberry Pi 5:**

| Base | Bytes | Device |
| --- | --- | --- |
| 0x107C502000 | 0x30 | `disp_intr`, the display's interrupt controller, `brcm,bcm2711-l2-intc`, through which the HVS raises its channels' ends of frame |

| Number | Interrupt | The GIC's ID |
| --- | --- | --- |
| 129 | `disp_intr`'s, the HVS's end of frame among its lines | 129 (GIC_SPI 97), level |

The controller is on a page of its own (`mop` at 0x7c500000 and `moplet`
at 0x7c501000 are on the pages before it). It is a device like the
HVS. Its clock is the display's, which is on whenever the HVS answers,
so the host's rule for the HVS covers it: read it only on a board that
booted with a monitor.

As with the others, the host sets nothing up. The driver masks every
line but channel 0's, and clears each line it takes before
`interrupt_done`.

## Which deliberate restriction this breaks

None. It is a device's registers and its interrupt. A driver reaches no
memory through them.

## Alternatives considered

- **A pixel valve's interrupt.** Pixel valve 0 (`pixelvalve@7c410000`,
  already a region) has its own, GIC SPI 101, which `vc4_crtc.c` takes
  for the vblank of the CRTC it feeds. But it marks HDMI0's vertical
  blank, not the HVS taking a list. Linux's SCALER6 driver uses the HVS's
  own end of frame to swap and sweep lists, and the pixel valve's for
  vblank events. Either would serve a frame count. If L0 would rather
  give one interrupt, 133 (SPI 101) with no new region would do for
  pacing, and the controller could come later. `hvs` would then set
  `PV_INT_VFP_START` (bit 7) in the valve's `PV_INTEN` (0x24) and clear
  it in `PV_INTSTAT` (0x28), both inside the valve's region.
- **The 6-bit frame count in STATUS, polled.** It wraps every second at
  60 Hz, and polling it is the cost this asks to remove.
