# Bug report: the Pi 5's frame pool includes RAM the firmware still uses

Status: answered, no change. L0's roadmap 0118 read the firmware's patched
device tree on a Pi 5: with a monitor the firmware shrinks `/memory` to end
at 0x3F800000, so no frame lies in its framebuffer. The corruption has
another cause (hvs and the display IOMMU, or the mailbox).
Project: L0S, a microkernel in L0, booting on a Raspberry Pi 5 (2 GB,
serial 1b08af2e, EEPROM 2026/05/26) by TFTP

The runtime builds the frame pool from the device tree's `/memory` nodes
and ignores the firmware's reservations. On a Pi 5, though, the firmware
keeps memory above the image too. Its HDMI framebuffer seems to lie inside
the pool, under the pages the runtime takes for page tables. L0S has seen
memory corruption on the board ever since it started driving the display.
This is the most likely cause we can't fix from L0S. This asks the runtime
to leave out what the firmware reserves.

## What the runtime does

`runtime/bare/board.ll`, above `pool_init`:

> Firmware reservations are not read, since the firmware a board's host
> runs under keeps below the image.

and further down:

> Untouched pages of the pieces before the input's go to frames from the
> bottom and to the host's own page tables from the top, until the two
> meet

Spec 10.3 says the same: the pool is RAM from the `/memory` nodes, minus
the image and what lies below it, the heap, the stack, the device tree and
standard input.

## What the Pi 5's firmware keeps

The firmware's own log, on the debug UART as it starts the image, says
where its framebuffer is:

```
MESS:00:00:23.180870:0: Select resolution HDMI0/2 hotplug 1 max_mode 2
MESS:00:00:23.194670:0: FB0 disp 0 max-fb 1 1920x1080 stride 3840 base 0x3f800000
```

That is 1080 lines of 3840 bytes from 0x3F800000, up to 0x3FBF4800. The
HVS keeps scanning it out until a driver reprograms the HVS.

The pool reaches 0x3FC00000. At boot L0S's kernel prints `memory: 320879
pages free, 1.3 GB`. That count matches a first piece that ends at
0x3FC00000, where the VideoCore's own RAM starts. It doesn't match one
that ends at 0x3F800000, which would be 1024 pages fewer. So the
framebuffer lies inside the first piece, at its top, where page tables are
taken first.

The stock `bcm2712-rpi-5-b.dtb`, before the firmware patches it, has a
`/reserved-memory` with:

- `atf@0` (`no-map`, the first 512 KB), which the image's hole covers
  already
- `linux,cma` (`reusable`, so not a hole)
- `nvram@0` (`raspberrypi,bootloader-config`, `no-map`), whose `reg` is
  `<0 0 0 0>` until the firmware fills it in at boot

The framebuffer isn't in the stock tree. The firmware must describe it
when it patches the tree, either as a `/reserved-memory` child, as a
`/memreserve/` entry, or as a `simple-framebuffer` node under `/chosen`.
We haven't read the patched tree, since nothing gives a program the
device tree's bytes. Which of these the firmware uses is unconfirmed.

## What L0S saw

These were seen on the board over one evening, with L0S's `hvs` driver
running:

- The screen showed the firmware's 1080p mode with stripes and repeating
  colour patterns, not anything L0S drew. That is consistent with page
  tables and frames being scanned out as pixels.
- A driver's DMA page, which `dma_alloc` gives zeroed and which it had
  just written a firmware mailbox request into, read back as AArch64
  code: `f9461fa9 91006008 eb09011f 54000089 52800300 94004af8 14000002
  f9061b68`.
- A process was killed with ESR's exception class 0 inside its own code
  (`fault at 0xc005d0e8, syndrome 0x2000000`): its code page had been
  overwritten.
- The kernel stopped with `esr = 0x96000004, elr = 0x83fc8, far =
  0x001000ae00400058`, a translation fault on a garbage pointer.
- Once, the firmware stopped answering the mailbox and the board then lost
  power entirely, with nothing from the runtime.

Other causes overlap with these, and we can't rule them out from here:

- L0S's `hvs` driver programs the HVS's IOMMU, which the firmware may also
  use.
- We changed the mailbox code the same evening.

The overlap with the pool is established. That it causes the corruption
is not; it's the cause that would explain all of it.

## What is asked

1. On every board, the pool leaves out the regions the firmware reserves,
   as Linux does:
   - each `/memreserve/` entry
   - each `/reserved-memory` child with a `reg`, unless it is
     `reusable` (as `linux,cma` is)
   - the `reg` of each `simple-framebuffer` under `/chosen`

   Each of these becomes a hole, as the image and the device tree are
   now.
2. Spec 10.3 says so, and the comment above `pool_init` drops "the
   firmware keeps below the image".
3. Ideally, some way to read the device tree as the firmware handed it
   over, or the reservations the runtime found, so a program can check
   what was left out. An item in the changelog with the patched tree's
   reservations, read on a board, would do as well.

## Done when

- on a Pi 5, no frame's `frame_address` lies in 0x3F800000 to 0x3FBF4800,
  or in any range the patched device tree reserves; a test allocates
  frames until `frame_free_count` is 0 and checks every address
- `frame_free_count` at boot drops by the reserved pages, and the
  changelog says by how many
- the virt boards are unchanged, since QEMU's trees reserve nothing in
  their RAM

## The workaround actually used

None. L0S can't keep the kernel's page tables or frames out of a range,
because the runtime picks them. L0S's `hvs` could reprogram the HVS before
anything is drawn so that the firmware's framebuffer is no longer scanned
out. That would hide the screen symptom, but not any writes the firmware
makes to that memory, and not whatever else the patched tree reserves.
