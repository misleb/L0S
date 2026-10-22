# Feature request: PCIe and RP1 regions, and cache maintenance, so L0S can drive USB

Status: landed, as newlang roadmap 0101 (8650245), 0102 (95c5c11) and
0103 (cfef295)
Project: L0S, a microkernel in L0 for QEMU's virt board, heading for the
Raspberry Pi 5

> **Since landing:** `usb_virt_test.l0` passes 3/3 and `want.l0` checks.
> L0S offers `frame_sync` to drivers as `dma_sync`, call 293, and `xhci`
> cleans each page of a controller's memory as it writes it and cleans
> and invalidates it before reading it. On QEMU the stack runs: `pcie`
> sets the bus up, `xhci` brings up `qemu-xhci`, `usb-kbd` and
> `usb-mouse`, and `usb-hid` types and moves the pointer
> (`tests/e2e/usb`, `tests/usb.sh`). Nothing has run on a Pi 5 yet.
> Interrupts remain for a request of their own.

L0S needs a USB stack for the Pi 5, where USB is the only way to attach a
keyboard and a mouse. Both of the Pi's USB controllers are on RP1, the
southbridge behind PCIe. They are Synopsys DWC3s in host mode, so both are
xHCIs. QEMU has no Pi 5 machine, and its virt board has no xHCI on the
system bus, but it does have `qemu-xhci` on PCIe. One xHCI driver can serve
both boards. Only how the driver finds its controller differs. On QEMU it
uses the PCIe ECAM and a BAR in the MMIO window. On the Pi it uses RP1's
fixed addresses, which the firmware sets up.

L0's runtime gives neither. This document asks for three things. Each one
is the smallest change that unblocks one part of the stack, and they are
listed in the order L0S will need them:

1. on the virt aarch64 board, regions over the PCIe ECAM and the 32-bit
   MMIO window
2. on the Raspberry Pi 5, a region over RP1's peripherals, with the
   firmware told to leave RP1 set up
3. a builtin that cleans and invalidates a frame, for the Pi's DMA, which
   is not coherent

## What could not be written

**1. The virt board's PCIe windows.** `probes/usb/usb_virt_test.l0` opens
the first megabyte of the ECAM at QEMU's high ECAM, 0x4010000000, which
is bus 0's configuration space. It also opens the first and last pages
of the MMIO window, 0x10000000 up to 0x3EFF0000, where a driver puts a
device's BARs. On the board, all three get -3:

```
not ok 1 - test_ecam_bus_0
not ok 2 - test_mmio_window
not ok 3 - test_mmio_window_end
```

Section 10.3 says why: "Anything else … is no region, and so is any range
of the flash, the PCIe windows, or the gaps between devices"
(`runtime/board/virt-aarch64.ll`'s `@devices`). Without the ECAM, nothing
can find `qemu-xhci`, size its BAR, or turn on its memory space and bus
mastering. Without the window, nothing can reach its registers.

**2. RP1.** Section 10.3 says of the Pi 5: "whose RP1, behind PCIe, is
none". The Pi's two xHCIs are at 0x1F00200000 and 0x1F00300000 in the
CPU's map, in RP1's peripheral window, 0x1F00000000 to 0x1F00400000. That
window holds only while the firmware leaves RP1's PCIe link set up, which
it does only when `config.txt` says `pciex4_reset=0`. `l0 card`'s
`config.txt` doesn't say it.

**3. Non-coherent DMA.** An xHCI reads its rings and contexts from memory
and writes events into memory. A driver writes a TRB into a ring's frame,
then rings the doorbell. Later it reads an event the controller wrote
into the event ring's frame. Section 10.3 says that on the Pi 5 "a device
reading or writing it may see the cache's bytes or the memory's, until a
builtin that cleans and invalidates is added for a driver that needs it".
This is that driver. `probes/usb/want.l0` is what it would write:

```
(def offered ((ring int)) int
  (frame_sync ring (to_device)))

(def polled ((events int)) int
  (frame_sync events (from_device)))
```

```
want.l0:14:3: error: unknown function frame_sync
want.l0:17:3: error: unknown function frame_sync
```

## The workaround actually used

None is possible. A region the host refuses can't be reached any other
way, and no L0 code can clean a cache line. L0S has written everything
that needs no device. That covers the xHCI's rings, contexts and TRBs,
its enumeration as a pure state machine, USB descriptors, and the HID
boot protocol, all tested on the host with scripted completions. The
drivers that would run it are written and type check. They wait on this.

## Smallest change that would help

**1. virt aarch64: two more regions.** Both are device memory,
Device-nGnRnE, in the boot map, as the other devices are:

| Base | Bytes | Device |
| --- | --- | --- |
| 0x4010000000 | 0x10000000 | the PCIe ECAM, 256 buses, 1 MB each |
| 0x10000000 | 0x2EFF0000 | the PCIe 32-bit MMIO window, where BARs are put |

These are QEMU's places for them when the board has high memory. The
device tree's `pcie@10000000` node gives them as `reg` and as the `ranges`
entry of type 0x02000000. If the host reads the table from the device
tree, these follow, and so would any other board's. The PIO window and
the 64-bit MMIO window at 0x8000000000 aren't needed: a driver puts every
BAR in the 32-bit window.

**2. The Raspberry Pi 5: one more region and a line of `config.txt`.**

| Base | Bytes | Device |
| --- | --- | --- |
| 0x1F00000000 | 0x400000 | RP1's peripherals, through the firmware's outbound window |

`l0 card`'s `config.txt` also gets `pciex4_reset=0`, so the firmware
leaves the PCIe x4 link to RP1 as the bootloader set it up. A driver then
reaches RP1's devices with no PCIe set-up of its own. A device on RP1
reaches the Pi's memory at a bus address 0x10_0000_0000 above its CPU
address (bcm2712's `dma-ranges` for RP1). That is the driver's to add, so
`frame_address` stays the CPU's address.

**3. One builtin, in section 6.13 beside `frame_address`:**

> `(frame_sync f dir)` makes frame `f`'s bytes agree between the CPU's
> caches and memory, for a device, and returns 0. With `dir` 1 it cleans
> every line of the frame to the point of coherency, so a device about to
> read it sees what the CPU wrote. With 2 it invalidates them, so what
> the CPU reads next is what a device wrote. With 3 it does both. On a
> host whose devices reach memory through the CPU's caches it is a
> `barrier`.

It raises `not a frame` as `frame_address` does, and a new `sync
direction out of range` for any other `dir`. On the Pi's host it is `dc
cvac`, `dc ivac`, or `dc civac` over the host's map of the frame, a line
at a time, with the line size from `CTR_EL0`, then `dsb sy`. A process
maps the same frame at the same physical address with the same
attributes, and the A76's data caches are physically tagged. So
maintaining the host's map covers what a process wrote through its own.
The L0S kernel would offer it to drivers as a call of its own,
`dma_sync`.

## Left out, on purpose

- **Interrupts.** The virt board's INTx (GIC 35 to 38, level) and GICv2m
  MSIs (80 to 143), and RP1's, which reach the GIC through bcm2712's MIP.
  The driver polls its event ring every millisecond when idle, which is
  enough for keyboards and mice, since their endpoints report every 1 to
  10 ms. These will be a request of their own once the driver runs.
- **PCIe set-up on the Pi.** The external x1 connector's root complex is
  L0S's to bring up later, as a driver. Nothing here needs it.

## Which deliberate restriction this breaks

None. Regions stay device memory that no value points into (6.12), and
`frame_sync` moves no bytes a program holds. It only decides which copy
of a frame's bytes a device and the CPU see.

## Alternatives considered

- **Frames mapped non-cacheable.** A `frame_new` for DMA whose every
  mapping is Normal Non-cacheable would need no syncs. But the host's own
  map of the pool is cacheable, in 1 GB blocks, and mapping one page two
  ways is what the architecture warns against. Splitting the host's map
  around each such frame costs more than a cache operation.
- **Syncing by address from a process.** `dc cvac` at EL0 needs
  `SCTLR_EL1.UCI`, and a process's runtime can't name a frame. The host
  is the one place that knows both the frame and its map.
- **QEMU with `highmem=off`.** That puts the ECAM at 0x3F000000, below
  4 GB, but the request is the same: the host has to give a region there.
