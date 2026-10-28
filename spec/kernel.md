# The kernel

There is one event loop, `schedule` in `kernel/kernel.l0`. Each turn:

1. Wake any sleeper whose time has come.
2. Take the next ready process.
3. Arm the timer for a 10 ms slice, and `user_run` the process until it
   traps.
4. Handle the trap:
   - a system call is answered; a spawn's caller is given a fresh
     slice, since loading the child's image is the kernel's time, not
     the caller's;
   - a touch of an unmapped heap, stack or bss page gets a zeroed frame;
   - any other fault kills the process (status 139, with a line on stderr);
   - a timer interrupt preempts the process;
   - a device interrupt becomes a message to the port bound to it.

When nothing is ready, the kernel waits for an interrupt. If there is no
sleeper and no bound interrupt, nothing can ever wake anyone: it reports a
deadlock and exits with 124.

That is the loop on a board with one CPU. With more (spec §6.18; the
aarch64 virt board has as many as `-smp` gives it: `make demo CPUS=4`,
or `QEMU_CPUS=4` for `tools/qemu-boot.sh` and the tests), the kernel stays on CPU 0 and runs no process itself: it hands
processes to the others with `cpu_run`, and they hand each back when it
traps, through rings in memory, with no interrupt between CPUs. Each pass
of `many_schedule`:

1. Take back every process that has trapped (`cpu_trapped`), and handle
   each trap as above. One a call lets go on is handed again, with the
   rest of its slice, by the same choice as in step 3; a slice that ended
   on its CPU's own timer puts it back on the ready queue.
2. Wake any sleeper whose time has come.
3. Hand ready processes, each with a 10 ms slice, to the CPUs with room;
   each CPU holds at most two, one running and one to start the moment
   the first traps. A CPU handed a thread or giving one back within the
   last 500 µs, whose threads each last ran 1 ms or less, is chosen
   first, the latest of them: its thread is passing messages and traps
   soon, and the one queued behind it then starts at once, where an idle
   CPU has stopped polling and must be woken. Failing that, an idle CPU
   (`cpus_pick`). So processes that each wait on the next, as a file
   written goes from `install` to `fs` to `virtio-blk`, take turns on one
   CPU, and nothing waits behind a thread that has not run yet or last
   ran long, which may be computing. There is one ready queue, so a
   process runs on whichever CPU is chosen.
4. If nothing more can be handed out, wait (`cpu_wait`) for a CPU's trap,
   the timer for the soonest sleeper, or a device's interrupt, which all
   come to CPU 0.

A process out on another CPU stays in its slot, so other processes' calls
reach it: memory shared into it is mapped while it runs, `proc_info`
says it is running, and a kill marks it, to end it when it comes back,
within its slice. `kernel/cpus.l0` keeps which process each CPU holds.

**Nothing a process does can crash the kernel.** Every buffer, count,
address, path and interrupt number is checked against the kernel's own
records before it reaches a builtin that could raise a runtime error.
`kernel_virt_test.l0` fuzzes this with threads that make hundreds of calls
with random registers.

| File | What it holds |
|---|---|
| `common/abi.l0` | call numbers, error codes, limits, the address-space layout, little-endian helpers, argument encoding |
| `common/initramfs.l0` | the newc archive: parsing it, paths, entry kinds, and a writer for tests |
| `common/queue.l0` | a FIFO queue of any type, shared with user programs |
| `common/klog.l0` | the log's records, their levels, bytes and the lines `dmesg` prints, shared with user programs |
| `kernel/log.l0` | the ring of the kernel's log: stamping, dropping the oldest, and reading from a number |
| `kernel/inittab.l0` | `/etc/inittab`: parsing it, and checking it against the archive |
| `kernel/memory.l0` | what each address is for, by where a process's image lies; which pages to map before a copy, and which it may write; which heap pages a release names; where device regions and DMA pages go, from a pool of a process's device pages that takes back pages given up in any order; the code and rodata processes share, by their bytes' hash; which frames to free when a process ends |
| `kernel/elf.l0` | a program's ELF: its headers read and checked against spec §10.3, its segments, entry, and heap |
| `kernel/mounts.l0` | the mount table: the initramfs or the system volume at `/` and the volumes at `/Volumes/LABEL`, where a path's file is and the path its server is asked for, and where a rename goes |
| `kernel/ipc.l0` | ports, their message queues, names, and the mount table, whose volumes go with their ports |
| `kernel/sched.l0` | sleepers and the timer's deadline |
| `kernel/cpus.l0` | the other CPUs: which process each holds, with its slice's deadline, which CPU a process goes to next, a kill waiting for one to come back, and what `cpu_trapped` gives |
| `kernel/pids.l0` | which slot of the process table, and which pid, a new process gets |
| `kernel/syscall.l0` | a trapped context decoded into a `Call` |
| `kernel/process.l0` | creating a process from its ELF's segments, sharing its code and rodata with processes whose are the same, demand-paging, heap pages released, copying in and out of, mapping devices and DMA pages into, and the open files of a process |
| `kernel/kernel.l0` | the state, every call's handler, traps, the loop, and boot |

All of these except `process.l0` and `kernel.l0` are pure and tested on the
host. The kernel itself is tested on the board.

## The kernel's log

Every message the kernel and the drivers report is kept in a ring in the
kernel, as Linux keeps its own for `dmesg`, so that what booted can be
read again after the serial line has scrolled, or on a board with no
serial console, from the desktop's Terminal or the MCP's `dmesg` tool. A
message is a record: a number, from 0 in the order logged; the time in
nanoseconds since boot; the pid that logged it, 0 for the kernel; a level
(0 error, 1 warning, 2 info, 3 debug); and a line of at most 512 bytes of
text, which says who as `NAME: WHAT`. The ring holds 64 KiB of records
(`log_bytes`); a new one drops the oldest while it is over, so the first
number `dmesg` reads says how many were dropped.

Logging is call 294 (`log_write`) and reading call 295 (`log_read`); the
kernel's own messages go in by the same path, as `l0s: ...` with pid 0.
Every message but a debug one is also written to the kernel's standard
error as it is logged, which is the serial line, so the serial console
shows each as it happens, from the first line the kernel says: nothing is
held back for `uart`, and nothing is replayed when it starts. `dmesg` is
how to read the rest, and what was said before a program started.

The kernel says, as it boots (`banner_lines`): its CPU and boot
arguments; the pages of memory free; how many CPUs, as `l0s: 4 CPUs: the
kernel on CPU 0, processes on CPUs 1 to 3`; how a process's memory is
laid out, images and heaps, stacks, device and DMA pages; its limits; the
initramfs's size and entries. L0 has no builtin for the board's RAM,
timer or interrupt controller, so it says nothing of them. It logs
at the debug level each process it starts, and at info each volume
mounted or unmounted and `/` becoming a volume. Each driver says what it
found as it starts to serve, as `sdhci` does (see the `l0s-dev` skill's
"What a driver says").

## Processes and pids

The process table has 255 slots, so at most 255 processes are alive at
once, but any number may run over the kernel's life. A pid names a slot
in its low 8 bits, and in the bits above, how many times that slot was
given before: the first 255 pids are 1 to 255, and slot 2's second
process is pid 258. So a slot is reused but a pid never is, and a pid
kept after its process has gone, by a waiter, a typed `kill`, or a
queue, names nothing rather than whoever has its slot now: calls on it
give -1, as for a pid never used.

A process that exits keeps its slot, so that `proc_wait`, `proc_watch`
and `proc_info` can still report its status, until a new process needs
the slot. The kernel ([kernel/pids.l0](../kernel/pids.l0)) gives a new
process, searching on from the slot it last gave:
1. a slot never used;
2. otherwise one whose process exited, and whose status was given to
   someone, by a wait or an exit notice, or whose parent has gone, so no
   one will ask;
3. otherwise the oldest other exited one, whose status is then lost.

It gives none, and spawning fails with -5, only when all 255 are alive.

## A process's memory

The layout is fixed by spec §10.3. A program's image is an ELF, as
`l0 build --target proc` writes them, and
[kernel/elf.l0](../kernel/elf.l0) reads and checks its headers.

| Address | What | Mapped |
|---|---|---|
| `0xC0000000` | the image's segments, code, rodata, and data, ending below `0xD0000000` | at load, the pages holding the file's bytes, each with its segment's flags: code readable and executable, rodata readable, data readable and writable; code and rodata the same frames as another live process's, where its are the same bytes (see Sharing below) |
| the rest of a segment | its bss, zero | on first touch, with the segment's flags |
| from the page after the image to `0xD8000000` | heap | on first touch, RW; unmapped again, its frame freed, when the runtime releases it (call 12) in a run of 16 MB or more, or with 128 MB or less of frames left |
| to `0xE8000000` | stack, `sp` starting at the top | on first touch, RW |
| `0xE8000000` up | device regions, DMA pages, and shared pages | by the `region` and `dma_alloc` calls, for programs with a `dev` line only; by `shm_alloc` and `shm_share`, for any |

A process starts at its image's `e_entry`. The kernel starts only an ELF
of spec §10.3's for this CPU: static, `ET_EXEC`, at most three
page-aligned `PT_LOAD`s in order, none writable and executable, within
its file and the image's range; anything else, the raw images earlier
toolchains wrote among it, is "not a program", -6. A store to its code
or rodata faults, and the process is killed, as does a touch of a page
between its segments.

The kernel copies in and out of a process only through pages it mapped
itself. A buffer on a device's registers, or outside the user range, gets
-5, and so does one the kernel would write into the process's code or
rodata, which it may not write itself. DMA pages are ordinary memory the
kernel mapped, so a buffer there is accepted.

**DMA.** A device such as the virtio-gpu reads and writes memory itself,
at addresses it is given in its registers. `dma_alloc n` maps n fresh
frames at the caller's next device pages and returns the first one's
address. A process's device pages, the 384 MB above its stack, are
given out as a pool: its next ones are the first run of pages it gave
up that holds them, highest first, or else the pages above all it was
ever given. `dma_address va` gives where the device reaches the page
holding va, from L0's `frame_address`, and `dma_addresses va n` the same
of n pages from it in one call, as the display driver takes a buffer's
thousands of pages. The pages are consecutive in the process,
but not necessarily for the device, so a driver gives the device one
address per page, or merges the runs that happen to be consecutive.
A `region` call over DMA pages (`dma_open` in `l0s.l0`) returns the same
address, so the driver reads and writes them with `device_read32` and the
rest. The proc runtime keeps at most 64 regions open at once, which is
why the pages are mapped together rather than as one region each; one
closed (`close_device`, or `shm_region_free` for shared pages) frees its
place for another.

**Shared memory.** `shm_alloc n` is `dma_alloc` for any process: n zeroed
pages at its next device pages, with no `dev` line needed.
`shm_share va n pid` maps n of the caller's shared or DMA pages from va
into pid's next device pages as well. They are the same frames, so a
write by either is seen by both. It returns where pid sees them, for the
caller to tell pid. A `region` over one's own shared pages works without
a `dev` line too, so any process reads and writes them with `dma_open`.
`dma_address` stays for drivers alone: only they learn where a device
reaches memory.

**Taking it back.** Both are L0's `space_unmap` (spec §6.13).
`shm_unmap va n` gives up n of the caller's own shared or DMA pages from
va: they are unmapped, and each frame is freed once no process maps it.
Their addresses return to its pool of device pages, joined to any free
pages beside them, in whatever order they are given up, so a process
that shares and gives up in turn reuses its pages rather than running
out; pages taken back by `shm_revoke`, and those a call reserved but
could not map, return too. A driver may give up its own too: its doing so says its device is
done with them. `shm_revoke va n pid` takes back from pid every mapping
it has of the caller's n pages from va, so a process can withdraw what
it shared; never from a driver, whose device may have been given their
addresses, as a driver cannot be killed either. Either way, a process
that touches a page it no longer has is ended, as for any device page
with nothing mapped.

When a window closes, the display driver and `wm` both give up its two
buffers, the content's and the chrome's: the driver once the screen
no longer shows them, on `forget`, and `wm` after that. So a closed
window's memory is freed once its `vt` has ended too.

**File windows.** The first time a process opens a file on a volume
whose server is another live process, the kernel maps 16 fresh pages,
64 KB, into that server's device pages, the process's window to it
([kernel/memory.l0](../kernel/memory.l0)'s `Window`). It tells the
server first, by a `window_notice` from pid 0 on the server's port
(`wndw`, then the client's pid, the pages' address and their count,
u32s), which no process can send, so the server never takes a page it
was not given for one. The notice is queued before the open's request,
on the same port. A queue with no room for it has the window taken back
at once, and the open waits for room as any request does. Later opens
reuse the window, one a client per server. A server with no device
pages left, or a kernel out of frames or near its heap's reserve, has
the open refused -5. The server gives the window back with `shm_unmap`
once its client exits, which it watches: `fs` does. The kernel forgets
the window then, and when the server ends, its pages freed with its
other shared pages, so it never writes into a pid given again. It also
forgets a window once the server unmaps any page of it, or has one
taken back, so one it keeps is always mapped whole.

A file `write` of the process to that server copies up to 64 KB of its
buffer into the window (`space_write`) and sends `writew H N`, with no
bytes in the message; a `read` sends `readw H N`, and once the server
answers how many bytes it put at the window's start, copies those into
the process's buffer (`space_read`). A call of more is answered with
what one request moved, as before, and the runtime asks again. With no
window, as for a server that is the caller itself or gave its window
up, both go in messages as they did, 4 KB a request.

**Releasing.** While a process runs, its runtime names the whole heap
pages that its allocator has freed by call 12, `release` (spec §10.3).
The kernel unmaps each one it has mapped and frees its frame, and a later
touch of the page gets a zeroed frame again, as a first touch does. So a
process holds the heap it uses now, not the most it ever used. Its servers
run from boot to shutdown, so without this the frames they touched once
would never come back.

It does so for a run of 16 MB or more (`release_run_min`), or once the
board has 128 MB of frames or less left (`release_floor`); a shorter run
stays mapped. A runtime that frees a block mostly fills those pages again
soon, and each unmapped page costs a fault when it is touched again and a
TLB flush on every CPU when it is unmapped: `install`'s copy onto a RAM
volume, unmapping every release, took 2 million faults, 50 s on one CPU
and twice that on several, and keeping the short runs, 25 s on any. A
page kept is named again when it next comes free, and none can be taken
back later, as the runtime may have filled it since: so a process keeps
the small blocks it freed while memory is plenty, and gives them back
only as it frees them again once memory is low.

**Sharing.** Processes running the same program share its code and
rodata. Once a new process's image is loaded, each of its read-only
segments is compared with those the kernel already shares at the same
address, of the same length and flags, whose bytes hash alike: read out
of the new space and out of one that maps the other, the two compared
whole, so a hash alone never decides. If they are the same, the new
process maps the shared frames, and its fresh ones are freed; if none is,
its segment is shared from then on. It is the bytes that decide, not the
path, so a program started from the initramfs and the same one from a
volume share too. A segment over 8 MB is not shared, as comparing reads
it into the kernel's heap twice, and the data segment, which a process
writes, never is. So the shells and terminals of the desktop hold one
copy of `sh`'s and `vt`'s code between them.

**Freeing.** When a process ends, the kernel gives back its space with
`space_free`, which takes its page tables and every mapping with it, and
then, with `frame_free`, every frame of it that no other space maps
(spec §6.13; `kernel/memory.l0`'s `Mem` decides which):
- Its heap and stack frames, and its image's data, are its alone, so they
  are freed at once.
- A shared or DMA frame may be mapped by other processes too, and so may
  a frame of its image's code or rodata, so the kernel counts each such
  frame's mappings, and frees it once the last process mapping it has
  ended. Freeing one still mapped would be a runtime error, `frame still
  mapped`.
- A driver's DMA and shared frames are never freed: its device may still
  hold their addresses, as the device keeps going after its driver ends.

A frame the host gives again is zeroed, so a process sees only zeroed
memory, whatever ran before it. If the host runs out while a process is
being made, what was made for it is freed again.

The kernel's own heap holds a record of every page it gives, so it also
refuses a page once its heap is down to a reserve of 64 MB
(`heap_reserve` in `kernel/process.l0`, read with L0's `heap_left`), as
if no frame were left: a fault ends the process, a `shm_alloc` or
`dma_alloc` is refused, a spawn fails. The reserve finishes the call and
ends the process. It is large because `heap_left` counts free bytes, and
on a heap full of page records they lie in pieces that a new value of
another size cannot use: on a 96 MB heap the kernel stopped with `heap
exhausted` and 38 MB free behind a reserve of 32 MB.

## Limits

- **The kernel has a heap of 192 MB and a stack of 16 MB**, the Makefile's
  `KERNEL_HEAP_MB` and `KERNEL_STACK_MB`, which `l0 build` and `l0 test`
  give the board's layout; the RAM past them, below the user range, is
  the frame pool, about 1,840 MB at `-m 2G`. The heap keeps a record of
  every page given, about 128 MB with the whole pool given, and the
  kernel's copy of the initramfs; the demo's kernel peaked at 20.5 MB,
  12.3 MB of it that copy, and under 8 KB of stack. **An initramfs is at
  most 48 MB**, the heap less 144 MB, since the kernel keeps all of it:
  `mkinitramfs` refuses a larger one, and naming a larger
  `KERNEL_HEAP_MB` raises both. With the heap's 64 MB reserve kept back
  (see above), the 192 MB heap records fewer pages than the whole pool,
  so the last of the pool is refused for want of heap, never given; a
  smaller heap refuses more, and the kernel goes on. Ports and the messages queued on them,
  and the pages one shared region maps into many processes, are not yet
  bounded but by the heap, so a process that makes enough full ports, or
  shares one region with enough processes, can exhaust it.
- **The kernel's log keeps 64 KiB of records**, about 1,500 lines of the
  usual length, and a message is at most 512 bytes (see
  [The kernel's log](#the-kernels-log)); older messages are dropped as
  newer ones come, and `dmesg` says how many.
- **At most 255 processes alive at once**, the table's slots (see
  [Processes and pids](#processes-and-pids)), and a status no one asked
  for is lost once 255 newer processes have needed its slot.
- A process's image and stack pages stay mapped until it ends, and so do
  the heap pages its allocator keeps: the 4 chunks it holds back and the
  blocks on its free lists, which it cuts from next. Only the whole heap
  pages it frees are released, by call 12 (see
  [Releasing](#a-processs-memory)), and only shared and DMA pages are
  given up or taken back otherwise.
- **A process has 384 MB of device pages**, its shared, DMA and device
  memory mapped at once. Pages it gives up are given again, but a
  request's pages must lie together, so 384 MB in holes too small for it
  is still refused. `virtio-gpu` maps every window's buffers, four times
  as many pages at scale 2.
- Round-robin scheduling with 10 ms slices, from one ready queue. A
  process woken by a message runs once a CPU has room, which with every
  CPU busy is the end of a slice, not at once.
- **The kernel runs on CPU 0 alone**, as
  [probes/smp](../probes/smp/REQUEST-multiple-cpus.md) asked of L0: every
  system call, and so every message, is handled there, one after another,
  however many CPUs run processes. A process is one thread, so it uses
  one CPU at most. A kill of a process out on another CPU takes effect
  when it comes back, within its slice. L0's `cpu_wait` gives back a
  CPU's trap before a device's interrupt, so a kernel kept busy by traps
  takes interrupts late. Several CPUs have run on QEMU's aarch64 board
  and the Pi 5, whose four boot with processes on three; L0 starts no
  other CPU on the riscv64 board.
- **On QEMU, more CPUs are no faster, and some boots slower**, so the
  demo and the tests boot with one unless asked (`CPUS`, `QEMU_CPUS`).
  A boot that installs a system onto a RAM volume (`rootboot_tmpfs`) took
  47 s on one CPU and 3 min 42 s on four while L0's idle CPUs spun
  through QEMU's global lock; with idle CPUs halting (L0's roadmap 0123,
  [probes/smp](../probes/smp/REQUEST-idle-cpus.md)) 50 s and about 110 s;
  and with short releases kept (see Releasing), 25 s on one, two or four.
  Each hand-off to another CPU costs more than a call on CPU 0, and most
  of all to a CPU that has stopped polling, which made writing to a disk
  slower on four while a file's data went 4 KB a message. Through file
  windows, 64 KB a request (see File windows), it no longer is: the
  e2e case `install` takes about 3.3 s on one CPU and 2.9 s on four, and
  `install_boot` 2.9 s and 2.8 s, where they took 14.6 and 18.1 s, and
  25.4 and 32.2 s, before. Nothing L0S runs yet computes enough on its
  own to gain from more CPUs. With the disk in `build/`, as `make e2e` has
  it, the host's own disk syncing it varies these by half or more.
  `make test-virt` runs every board test on four too.
- Images are copied from the archive, or a volume's file, into fresh
  frames for every process that runs them, before its code and rodata
  are found to be another's and those frames freed again, so starting a
  program costs a copy and a compare whether or not it shares. Its data
  is never shared, nor a segment over 8 MB. Besides these, only pages
  made with `shm_alloc` or `dma_alloc` can be shared, and a share cannot
  be taken back from a driver.
- Interrupts the kernel enables stay enabled (L0 cannot disable one). If a
  driver exits while its device keeps the interrupt raised, the kernel ends
  each one as it comes.
- Only ELF images run: a raw one, as toolchains before L0's roadmap item
  0093 wrote them, is refused, so programs built by one must be built
  again.
- Nothing cleans the data cache or invalidates the instruction cache
  after an image is loaded: neither the kernel nor L0 has a way to.
  QEMU keeps the two coherent, so this is fine there, but a board that
  does not would run stale instructions.
- A failed receive reports no reason. `supervisor_receive` gives no bytes
  when the kernel's word is negative (spec §6.15), so `RecvFailed` stands
  for every failure, and for no message yet.
- An exit status is 32 bits, to `wait_pid` as in an exit notice: a
  status outside a signed 32-bit number is read back as its low 32 bits.
