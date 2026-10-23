# Feature request: the HVS and its IOMMU as regions on the Raspberry Pi 5, so L0S can show a screen

Status: open
Project: L0S, a microkernel in L0 for QEMU's virt board, heading for the
Raspberry Pi 5

L0S draws its desktop through a display protocol. On QEMU, virtio-gpu
serves it. On the Pi 5 the screen is the BCM2712's HVS (Hardware Video
Scaler, SCALER6), which the firmware leaves scanning HDMI0 at boot. L0S's
`hvs` driver (`user/sbin/hvs/`) would compose the screen with it as
virtio-gpu's 2D mode does on QEMU, copying no pixels:

- It writes display lists into the HVS's own list memory, one plane per
  layer, each fetched straight from a client's pages.
- The pages are scattered and a plane reads one run of addresses. So the
  driver maps each buffer's pages one after another in an aperture of the
  IOMMU in front of the HVS, `iommu4`.

L0's runtime gives none of these as a region. This asks for three, and
for one line of `config.txt`.

## What could not be written

Section 10.3 lists the Pi 5's regions: the debug UART, the system timer,
the VideoCore mailbox and RP1's peripherals. `probes/display/want.l0`
opens what the driver needs. On a Pi 5 each of them is refused, as it is
on the host:

```
regions: 0
version: -1
channel 0: -1
```

The driver is written and type checks, with its tests passing on the host.
Without the HVS it can't find HDMI0's mode, write a list, or point the
channel at one. Without the IOMMU it can't make a buffer of scattered
pages one run, and every buffer a client shares is scattered. With
neither, it says "no HVS on the board" and exits 0.

## The workaround actually used

None is possible. The mailbox, which is a region, can ask the firmware
for a framebuffer, but that framebuffer is in the firmware's own memory.
No `/memory` node describes it, and the boot map doesn't reach it, so no
L0 code can write a pixel there. A region over the firmware's memory
would be an alternative (below), but it means copying every pixel.

## Smallest change that would help

**Three regions on the Raspberry Pi 5.** Each is device memory,
Device-nGnRnE, like the others:

| Base | Bytes | Device |
| --- | --- | --- |
| 0x107C580000 | 0x1A000 | the HVS: its registers, and its display list memory from 0x4000 |
| 0x1000005200 | 0x80 | `iommu4`, the IOMMU in front of the HVS |
| 0x1000005B00 | 0x80 | `iommuc`, the cache the IOMMUs share |

These are the places in `bcm2712.dtsi` (`hvs@107c580000`) and
`bcm2712-ds.dtsi` (`iommu4`, `iommuc`). The two IOMMUs are smaller than a
page and share one with others (`iommu2` at 0x1000005100, `iommu5` at
0x1000005280). The mailbox already is such a region, so the host's rule,
"any range wholly within one of the board's devices", covers them.

**`hdmi_force_hotplug=1` in `l0 card`'s `config.txt`.** Then the firmware
brings HDMI0 up even when the monitor's hotplug line is late. The driver
takes the mode the firmware chose and never sets one.

## Later, for its own request

- `disp_intr` at 0x107C502000, 0x30 bytes, a Broadcom L2 interrupt
  controller cascaded to GIC SPI 97. Its bits 2, 9 and 16 are the three
  channels' end of frame. The driver polls the channel's list pointer
  instead, a millisecond apart, which is enough for a first screen.

## Which deliberate restriction this breaks

None. They are devices like the others, and the driver reaches memory
only through frames it was given (6.13). The IOMMU's tables are frames,
cleaned with `frame_sync` before the IOMMU reads them. The HVS reads the
frames the clients shared, cleaned the same way after each damage.

## Alternatives considered

- **A region over the firmware's framebuffer**, which the mailbox's
  allocate-buffer tag gives, or over the VideoCore's memory, which tag
  0x00010006 reports. Then only the mailbox would be needed. But the
  memory is RAM, not a device, and as Device-nGnRnE every pixel the
  driver copies there would be uncached and slow. It would also give up
  the HVS's planes, so every window and every scroll would be copied.
- **Physically contiguous frames for buffers**, in place of the IOMMU. A
  frame's number says nothing of where it is (6.13), and asking the pool
  for runs of pages is a new allocator. The IOMMU is how Linux's driver
  does it on this chip (`iommus = <&iommu4>` on the HVS).
