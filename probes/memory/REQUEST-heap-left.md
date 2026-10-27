# Feature request: how much of its heap a program has left, so a kernel can refuse work before the heap runs out

Status: asked, not yet on L0's roadmap
Project: L0S, a microkernel in L0 for QEMU's virt boards and the
Raspberry Pi 5

L0S's kernel keeps a record of every page it gives a process, in its own
heap. When processes take enough pages, the kernel's heap runs out before
the frames do, and the kernel stops with `heap exhausted`, taking every
process with it. Its rule is that nothing a process does can crash it, and
this is the one case it cannot check for: L0 tells a program how many
frames are left (`frame_free_count`), but not how much of its own heap.

## What could not be written

A kernel that refuses a process another page while its heap could not
record it, as it refuses one when `frame_free_count` is 0.

Reproduced on QEMU's aarch64 board with L0S's board test
`test_frames_run_out`, which has four processes take 2,112 MB of the
pool's 1,839.5 MB:

| Kernel heap (`--heap-mb`) | What happens |
| --- | --- |
| 192 MB | frames run out first; the last process is ended for want of one, and the test passes |
| 96 MB | `l0: runtime error: heap exhausted`: the kernel dies, and the board with it |

On a Raspberry Pi 5 it is the same: the kernel's heap is sized when it is
built (`PI5_RAM_GB`, 2 GB by default, gets 208 MB), and on a board of 4,
8 or 16 GB processes can take more pages than that heap can record.

## Why L0S cannot do it alone

The heap's size is fixed at link time (`--heap-mb`, spec 10.3), but
nothing gives it to the program, and what is left of it depends on the
allocator, which only the runtime sees. A kernel could estimate: each
page given costs it about 285 bytes of records. But that misses everything
else that grows the heap (messages queued, the initramfs's copy, maps of
processes and ports), and an estimate that is wrong crashes the board,
which is the thing to avoid.

## Smallest change that would help

- `(heap_left)`: how many bytes the program's heap can still give, not
  less than 0, or -3 where the host's heap is the operating system's
  (under one there is no fixed heap to run out of, short of the
  machine's memory). Memory is reclaimed by reference counting, so a
  value freed is counted again at once.

If the allocator can be fragmented so that free bytes overstate what one
allocation can get, the largest block it could give would do as well, or
both: L0S's kernel allocates in small pieces, so either works for it.

## How L0S would use it

`map_frame` in `kernel/process.l0` is where every page a process gets
comes from. Before `frame_new` it would check `(heap_left)` against a
reserve, a few MB, enough to finish the call it is handling and to end
the process, and answer as if no frame were left: a fault ends the
process, a `shm_alloc` or `dma_alloc` is refused. Spawning and port
messages could check the same reserve. The board test above would pass
with a 96 MB heap, the last process refused rather than the kernel
stopped, and `test_frames_run_out` gains a case at that heap.

## Left out, on purpose

- **Recovering from `heap exhausted`.** A runtime error ends the program
  by design; this asks only for a way never to reach it.
- **The stack.** The kernel's stack is sized generously and its depth
  does not grow with what processes do.

## Which deliberate restriction this breaks

None. It reads a number the runtime already has, as `frame_free_count`
does.

## Alternatives considered

- **An estimate in L0S.** The Makefile would write the heap's size into
  an L0 file the kernel is built with, and the kernel would cap the pages
  it gives at what about 285 bytes a page allows. It needs nothing from
  L0, but is a guess, and covers only the page records.
- **A heap sized for the most RAM a board can have.** The Pi 5's was
  768 MB, enough for 16 GB, which left a 2 GB board 1.3 GB for
  processes; L0S moved away from it for that reason.
