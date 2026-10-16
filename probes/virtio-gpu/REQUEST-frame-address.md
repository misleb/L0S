# Feature request: a frame's physical address, so a kernel can drive DMA devices

Status: landed, as newlang commit a7316ba (roadmap 0084)
Project: L0S, a microkernel in L0 for QEMU's virt board

> **Since landing:** L0 now has `frame_address` (spec 6.13), section 6.12's
> `barrier` now orders loads as well as stores, `space_read` and
> `space_write` included, and `l0 boot`, `l0 run --target virt`, and
> `l0 test --target virt` start QEMU with modern transports and add
> `L0_QEMU_ARGS` to its command line. The probe has since dropped
> `frame_address_guess` and `run.sh`, so the line numbers and commands
> below describe it as it was when this was written. It now runs as:
>
> ```bash
> L0_QEMU_ARGS="-device virtio-gpu-device" l0 run --target virt gpu.l0 main.l0 < /dev/null
> ```
>
> and `l0 test --target virt gpu.l0 gpu_virt_test.l0` tests `frame_address`
> on the board. Cache maintenance and runs of contiguous frames remain open,
> as below.

A kernel written in L0 can find, configure, and receive interrupts from
every virtio device on the virt board, but it cannot give any of them
memory to work in. Every virtio device does its work in memory that it
reads and writes itself (DMA): its virtqueues, the commands sent to it,
and its replies. To set that up, the driver writes the memory's physical
address into the device's registers. No builtin gives the address of
anything, so a virtio-gpu, and with it any display, cannot be written
within the spec.

This document asks for one builtin, `frame_address`. The rest is
evidence that it is enough.

## What could not be written

Setting up a virtqueue means writing the physical address of its memory to
`QueueDesc`, `QueueDriver`, and `QueueDevice` (virtio 1.2, section 4.2.2).
The memory a kernel has for a device is a frame:

```
(def queue_address ((d IoDevice) (t int)) int
  (let q (frame_new)
    (device_write32 d (add (mul t 512) 128) (frame_address q))))
```

```
want.l0:3:45: error: unknown function frame_address
```

None of the other ways in work:

- `region_open` over RAM gives -3. Section 6.12 gives regions only over
  devices, "never over memory the program or the runtime uses". The probe
  below confirms it at 0x40000000 and over the frame pool at 0x98000000.
- `space_map_device` gives -3 for the same ranges, since it follows
  section 6.12.
- A frame is "an `int` naming it" (6.13), and nothing says how that
  number relates to where the frame is.
- No bytes, array, or other value has an address, by design (6.12, 6.13,
  section 8).

What this blocks on the virt board:

- **Blocked:** all 32 virtio-mmio transports (GPU, input, block, network,
  entropy, console), and ramfb, which is set up through `fw_cfg`'s DMA
  interface with a framebuffer address in RAM.
- **Still works:** the PL011, the PL031, the PL061, and `fw_cfg`'s
  register interface.

## The workaround actually used

The workaround guesses each frame's address from the frame's number:
`probes/virtio-gpu/gpu.l0`, lines 25 to 29.

```
; The physical address of frame f. NOT something L0 gives: host-virt.ll hands
; frames out in order from __frames_start, 0x98000000, and its page tables
; from the other end of the pool, but section 6.13 promises none of that.
(def frame_address_guess ((f int)) int
  (add 2550136832 (mul f 4096)))                      ; 0x98000000
```

The guess comes from the shipped host, not the spec. In
`lib/l0/virt/host.bc` (read with `llvm-dis`), `l0_host_frame_new` returns
frame `f` at `__frames_start + f * 4096`, and page tables come from
`__frames_end` downward. `virt.ld` sets `__frames_start = 0x98000000`.

Using the guess, the rest of the probe (lines 116 to 167) does what a
virtio-gpu driver does:

- maps three frames into a space that no thread runs in, so that
  `space_write` and `space_read` can reach them
- writes two descriptors, the `VIRTIO_GPU_CMD_GET_DISPLAY_INFO` command,
  and the available ring with `space_write`
- writes the guessed addresses into `QueueDesc`, `QueueDriver`, and
  `QueueDevice`, then `barrier` and `QueueNotify`
- polls the used ring with `space_read` until the device has answered

`run.sh` boots it with `-device virtio-gpu-device` on a modern transport:

```
region_open over RAM at 0x40000000: -3
region_open over the frame pool at 0x98000000: -3
virtio-gpu on transport 31, version 2
features accepted; scanouts 1
control queue holds at most 64
frames 0 1 2, guessed at 0x98000000
response type 0x1101, scanout 0 1280x800, enabled 1
```

`0x1101` is `VIRTIO_GPU_RESP_OK_DISPLAY_INFO`, which the device wrote by DMA
into frame 2. So the only thing missing is the address. Everything else a
virtio driver needs is already in L0:

- regions for the transport's registers
- interrupts 48 to 79 (10.3)
- frames, `space_write`, and `space_read` for the memory itself
- `barrier`

To reproduce, with the toolchain installed on 2026-10-14 (`l0 version`
prints no number) and QEMU 11.1.2:

```bash
cd probes/virtio-gpu && l0 test gpu.l0 gpu_test.l0 && ./run.sh
```

## What the workaround costs

**It loses a correctness property.** The address is a guess about the
host's private allocator, and nothing checks it. When the guess is wrong,
the device reads and writes some other page, silently. The pool holds the
host's page tables too, so the page it hits may be one of those. The
guess goes wrong if:

- frames are ever freed and reused. Section 6.13 says "Nothing frees
  either yet", so freeing looks planned.
- the pool moves, as it would with another `-m`, a change to `virt.ld`,
  or a host for another board or real hardware.
- the allocator changes in any other way, such as handing frames out from
  the top, or interleaving them with page tables.

Within the spec, the program cannot be written.

## Smallest change that would help

One builtin, in section 6.13 beside `frame_new`:

> `(frame_address f)` returns the address at which a device reaches the
> 4096 bytes of frame `f`, a multiple of 4096 not less than 0, or -3 if
> the host gives devices no access to frames. The address is the same for
> as long as the frame lasts. It is a runtime error, `not a frame`, if
> `f` is not a frame the program has been given.

On `host-virt.ll` this is `__frames_start + f * 4096`, which it already
computes, behind a new `l0_host_frame_address`. Other hosts:

- `host-libc.ll` and `host-proc.ll` give -3, as they do for
  `frame_new`.
- A board where devices see memory at another address than the CPU does,
  or through an IOMMU, gives the device's address. That is why the
  wording says "at which a device reaches" and not "physical address".

Section 8's guarantee still stands:

- The result is an `int`, as region reads are.
- Frames are not the program's memory (6.13).
- What a device writes into a frame reaches the program only through
  `space_read`'s copy, exactly as a thread's writes to that frame do now.

The probe needed nothing beyond this builtin. In particular, it does not
need frames that are contiguous in memory:

- A modern virtqueue is three separately addressed areas. With 256 entries
  or fewer, each fits in one page.
- virtio-gpu's `RESOURCE_ATTACH_BACKING` takes a list of pages, so a
  framebuffer can be spread across frames.

### Left out, on purpose

These are not needed on QEMU, and each would be a request of its own:

- **Cache maintenance, for real hardware.** Frames are mapped write-back
  cacheable (10.3). QEMU's devices see memory the way the CPU does, but
  many real display controllers do not. They would need a frame mapped
  without caching, or builtins to clean and invalidate a frame. This is
  the next blocker after this one for driving a display on real hardware.
- **Contiguous runs of frames.** Only legacy virtio-mmio transports need
  one, for their whole ring at `QueuePFN`. A ring of a few entries fits in
  one page there too.

### A clarification to section 6.12, also wanted

The probe relies on `barrier` ordering `space_write` and `space_read`
against region accesses, in both directions:

- writing descriptors, then `barrier`, then the `QueueNotify` write
- reading the used ring after the device has answered

Section 6.12 says the barrier completes "every region access and every
store to memory made before it" before "any made after it begins". That
plausibly covers `space_write`. It is less clear that it covers
`space_read`, a load, made after it. `dsb sy` covers both, so this is
wording only. With `frame_address`, this ordering becomes part of what a
driver depends on, so it should be stated.

## Which deliberate restriction this breaks

None. It adds no types, inference, patterns, or function values. It also
gives the program no way to reach its own memory, since a frame is never
the program's.

## Alternatives considered

- **A host-side protocol on the byte channel.** On the virt board there is
  no host beneath the program to relay through. The display is a device on
  the board, and the device reads memory, not a byte stream.
- **An ordinary function or a prelude addition.** `frame_address_guess` is
  exactly that, and it is the problem. It hard-codes the pool's base
  address and the allocator's order, both of which are the host's private
  business. The prelude is shared by every host and cannot know them
  either. Only the host interface can.
- **`region_open` or `space_map_device` over RAM.** Both are ruled out by
  section 6.12. They would also map the memory as device memory
  (Device-nGnRnE) rather than as frames, and still yield no address to
  give a device.
- **A reserved range of RAM for DMA, at an address the spec fixes.** This
  is a new kind of memory with its own builtins, for what frames already
  are.

## Also found: running device tests

`l0 boot`, `l0 run --target virt`, and `l0 test --target virt` start QEMU
with no devices beyond the board's own, and give no way to add one. QEMU's
virtio-mmio transports are also legacy (version 1) unless
`-global virtio-mmio.force-legacy=false` is given, so a virtio driver
cannot be tested through `l0 test --target virt` as shipped.

`L0_QEMU` works as an escape hatch. A wrapper script that runs
`qemu-system-aarch64 -global virtio-mmio.force-legacy=false -device
virtio-gpu-device "$@"` boots the probe with `l0 boot` and gives the
output above. A documented way to pass QEMU extra devices, or a sentence
in section 9.2 or `l0 --help` pointing at `L0_QEMU` for this, would help.
