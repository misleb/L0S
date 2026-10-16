# Feature request: freeing frames and spaces, so a kernel can run processes for ever

Status: landed, as newlang commit 73a9a95 (roadmap 0086)
Project: L0S, a microkernel in L0 for QEMU's virt board

> **Since landing:** L0 now has `space_free` and `frame_free` as asked,
> with `frame still mapped` as asked, and `space_unmap` besides, with its
> own error, `user page not mapped` (spec 6.13). L0S frees a process's
> space and its frames when it ends, and keeps a count only of shared
> frames' mappings. Husks, the kernel's free list, and zeroing on reuse
> are gone, so `space_for` and `zero_pages`, and the line numbers below,
> describe the kernel as it was when this was written. `want.l0` now
> checks. `free_virt_test.l0` became `test_spaces_given_back` in
> `kernel/kernel_virt_test.l0`: 300 processes that each share a page now
> run in a row, the last as pid 303. L0S also uses `space_unmap` now, for
> two calls, `shm_unmap` and `shm_revoke`, so shared memory can be given
> up and taken back, and a closed window's buffers are freed. Giving a
> process's freed heap pages back while it runs remains open, as below:
> L0's runtime has no way to tell its kernel which pages those are.

A kernel written in L0 can make address spaces and frames, but it can
never give one back. Section 6.13 says so: "Nothing frees either yet, so
a space or frame lasts until the program ends." For a kernel whose
processes come and go, that means every process that ends leaves its
memory behind. L0S works around it by keeping what it can reuse. The
workaround covers ordinary programs, but not a process that shared memory
or drove a device. The board's 255 spaces then run out, though only one
process is alive.

This document asks for two builtins, `space_free` and `frame_free`. The
rest is evidence that they are needed, and that they are enough.

## What could not be written

When a process ends, the kernel wants to give back its space and every
frame no other process maps (`probes/free/want.l0`):

```
(def release ((s int) (fs (list int))) int
  (let r (space_free s)
    (free_all fs)))

(def free_all ((fs (list int))) int
  (if (is_empty fs) 0 (let r (frame_free (head fs)) (free_all (tail fs)))))
```

```
want.l0:6:10: error: unknown function space_free
want.l0:10:30: error: unknown function frame_free
```

None of the other ways in work:

- **No unmapping.** Nothing removes a mapping, and mapping a page that is
  mapped already is the runtime error `user page already mapped` (6.13).
  So a space cannot be cleared and given to another process: whatever it
  mapped, it keeps.
- **No reuse of a space's number.** `space_new` gives a new one each time,
  and section 10.3 gives "spaces up to 255 at once" on the virt board. Since
  none is ever freed, that is 255 over the program's life.
- **The new runtime's freeing doesn't reach spaces or frames.** Commit
  9000112 (roadmap 0085) gives freed heap blocks back to the host a chunk
  at a time. That is the program's own heap. A frame is "never the
  program's memory" (6.13), so it is untouched.

## The workaround actually used

L0S keeps what each ended process leaves, and gives it out again before
asking the host for more. The workaround is `Mem` in `kernel/memory.l0`
(lines 101 to 218), used from `kernel/process.l0` (`proc_create`,
`space_for`, `zero_pages`, `map_frame`, lines 161 to 239):

- **Husks.** A space whose process mapped nothing above `0xE8000000` (no
  device registers, no DMA or shared pages) is kept whole with every frame
  still mapped in it. The next new process takes the husk with the fewest
  pages, zeroes every page with `space_write`, and adopts them as its own,
  as if it had touched them. This is the only way to reuse a space: its
  mappings can't be cleared, so they must be kept and made harmless.
- **A free list of frames.** Any other space is given up for good. Its
  private frames go on a list, and are zeroed and mapped where a process
  next needs a page. They are still mapped in the space given up, which
  never runs again. A shared frame goes on the list once no live process
  maps it, the kernel counting each mapping.
- **Breaking husks.** When `frame_new` gives -5, the husk with the most
  pages is given up and its frames put on the list.

With that, ordinary programs run indefinitely. `kernel/kernel_virt_test.l0`
runs seven 64 MB processes in a row, 114,688 frames against the board's
98,304, and 300 processes in a row through the 255-slot table.

A space whose process mapped device or shared pages can't be a husk,
though: the next process in it would reach the old process's device
registers, or memory another process still uses. So it is given up, and
the board never gives it back. `probes/free/free_virt_test.l0` shows the
ceiling. Pid 1 runs children one at a time, each mapping one shared page
with `shm_alloc` and then exiting:

```
ok 1 - test_spaces_254_children       254th spawn gives pid 255
ok 2 - test_spaces_255th_refused      255th spawn gives -5, err_fault
```

At the 255th spawn only pid 1 is alive. Its space and the 254 given up
are all 255. In L0S such processes are the drivers, the window manager,
and the `vt` behind each terminal window, which shares the window's
pixels: each one that ends, a window closed, say, uses up a space for
good.

To reproduce, with the toolchain installed on 2026-10-15 (newlang commit
9000112) and QEMU 11.1.2, from the top of L0S:

```bash
cd probes/free && l0 check want.l0
```

```bash
l0 test --target virt common/abi.l0 common/initramfs.l0 common/queue.l0 kernel/memory.l0 kernel/ipc.l0 kernel/inittab.l0 kernel/sched.l0 kernel/pids.l0 kernel/syscall.l0 kernel/process.l0 kernel/kernel.l0 kernel/asm.l0 kernel/kernel_virt_test.l0 probes/free/free_virt_test.l0 --match spaces
```

## What the workaround costs

- **A ceiling the kernel can't lift.** At most 255 processes that ever
  mapped device or shared pages, over the kernel's life, as above.
- **Page tables, lost with each space given up.** They come from the same
  pool as frames ("98,304 of them less those the host's page tables take",
  10.3), so every space given up holds a few pages of it for good.
- **Whole husks, however little is needed.** A process given a husk gets
  every page of it, zeroed. After a 64 MB process ends, the next one,
  however small, takes 16,384 pages and is zeroed one `space_write` at a
  time before it runs, and holds them until it ends.
- **Code that exists only to cope.** Husks, picking and breaking them,
  zeroing on reuse, and a free list kept beside the host's own: most of
  `memory.l0`'s recycling section, and `space_for` and `zero_pages` in
  `process.l0`, with their tests. Only the count of each shared frame's
  mappings would stay.

## Smallest change that would help

Two builtins, in section 6.13 beside `space_new` and `frame_new`:

> `(space_free s)` removes every mapping of space `s`, of frames and of
> device memory alike, gives back the tables they took, and returns 0.
> `s` is then not a space, and a later `space_new` may give the same
> number. The frames `s` mapped are not freed: each lasts until
> `frame_free`, and stays mapped in any other space that maps it.

> `(frame_free f)` gives frame `f` back to the host and returns 0. `f` is
> then not a frame, and a later `frame_new` may give the same number, its
> bytes all 0 again, and the same `frame_address`.

And one runtime error, in 6.13's list, after `not a frame`:

> - `f` is mapped in some space, for `frame_free`: `frame still mapped`

So `frame_free` never takes away a page a thread could still reach. A
kernel unmaps first with `space_free`, or keeps the frame. The check needs
the host to count each frame's mappings. If that costs too much, freeing a
mapped frame could be left undefined instead, but a runtime error is
safer, and matches `user page already mapped`.

On `host-virt.ll` this would need:

- a free list of frames beside the bump allocator, and zeroing on reuse,
  which `frame_new` does already for fresh ones;
- `space_free` to free the space's table pages and invalidate its ASID's
  TLB entries (`tlbi aside1is`) before the ASID is given again;
- a mapping count per frame, for `frame still mapped`.

On `host-libc.ll` and `host-proc.ll`, which make no spaces or frames,
both are runtime errors, `not a space` and `not a frame`, as every other
6.13 builtin is there.

Section 8's guarantee still stands:

- Spaces and frames are not the program's memory (6.13). Freeing one
  frees nothing the program holds, and no value can point into one.
- Numbers given again are like handles reopened: a kernel that keeps a
  freed number and uses it reaches whatever has it now, or gets `not a
  space` or `not a frame`. That is the kernel's bookkeeping, as with
  handles.

### What L0S would do with them

When a process ends, `space_free` its space, then `frame_free` each frame
only it mapped, and each shared frame once the last process mapping it
has ended. A driver's DMA frames would still be kept: the device may still
write to them after its driver ends, so that remains the kernel's
decision. Husks, breaking them, zeroing on reuse, and the free list would
go. Every process would start in a fresh, empty space, and the ceiling
above would go with them.

### Left out, on purpose

These would help too, but each is a request of its own:

- **Unmapping one page, `(space_unmap s va)`.** It would let a kernel take
  back shared memory (L0S's `shm_share` can't be revoked) and drop pages a
  process no longer needs. Freeing whole spaces is enough for processes
  that end, which is the problem here.
- **Pages a process gives back.** Since commit 9000112, a process's
  runtime gives freed chunks back to its own heap, in `freestanding.ll`.
  Those pages stay mapped in the process, because no system call in
  section 10.3 tells the kernel. With `space_unmap`, a call for that would
  let a kernel take them back while the process runs.
- **More spaces at once.** 16-bit ASIDs would raise 255 to 65,535 on cores
  that have them. That only postpones the ceiling, and page tables would
  still be lost.

## Which deliberate restriction this breaks

None. It adds no types, inference, patterns, or function values, and gives
the program no way to reach its own memory: spaces and frames stay apart
from it, as they are now.

## Alternatives considered

- **What L0S does now.** Keeping and reusing what it can (above) handles
  processes that share nothing. It can't handle the rest, since a space
  can't be cleared.
- **A fixed pool of spaces, made at boot and handed round.** These are
  husks under another name, with the same problem: a space that ever
  mapped a device or shared page can't be handed to anyone else.
- **Mapping over a dead space's pages.** `user page already mapped` is a
  runtime error, so a kernel can't overwrite an old mapping either.
- **An ordinary function or a prelude addition.** Only the host knows its
  page tables and ASIDs, so only the host interface can free them.
