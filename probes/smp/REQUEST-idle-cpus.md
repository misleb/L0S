# Feature request: idle CPUs that halt, so more CPUs are not slower on QEMU

Status: landed, as L0's roadmap 0123 ("Idle CPUs halt"); see "Since
landing" at the end
Project: L0S, a microkernel in L0 for QEMU's virt boards and the
Raspberry Pi 5

Roadmap 0121 gave L0S what [REQUEST-multiple-cpus.md](REQUEST-multiple-cpus.md)
asked for, and L0S's kernel now hands its processes to the other CPUs
(`many_schedule` in `kernel/kernel.l0`). Every board test passes on one
CPU and on four. On QEMU, though, four CPUs make L0S several times
slower, not faster, so L0S boots its demo and its tests with one.

## What could not be written

A demo and e2e tests that use the board's CPUs. The e2e case
`rootboot_tmpfs` installs the system onto a volume in memory and boots
it: the file server and `install` exchange thousands of messages, so
most of it is traps handed between CPUs. Timed on this machine (8 host
CPUs), with `tests/e2e.sh rootboot_tmpfs` and two more short cases:

| CPUs | Wall | Host user | Host system |
| --- | --- | --- | --- |
| 1 | 47 s | 46 s | 0.3 s |
| 2 | 113 s | | |
| 4 | 222 s | 292 s | 204 s |

Two hundred seconds in the host's kernel is QEMU's threads contending.
Three cases (`install`, `install_boot`, `rootboot_tmpfs`) pass their 60 s
limit with four CPUs, and pass on one.

## Why

Every CPU that waits does it with `wfe`: another CPU's idle loop in
`l0_bare_cpu_main` (`runtime/bare/board.ll`), when its ring is empty,
and CPU 0's `l0_host_cpu_wait`, between looking for a trap and an
interrupt, both through `l0_arch_idle`. On a real Cortex-A76 that is a
low-power wait that the other CPU's `sev` ends, which is what the
request asked for. QEMU's TCG, though, runs `wfe` as a yield: the vCPU
leaves its translated code, goes back through its main loop, which
takes QEMU's global lock, and runs again at once. So each idle vCPU
spins, taking that lock thousands of times a second, and the vCPU that
has work waits for the same lock whenever it touches a device or the
GIC. The more CPUs idle, the slower the one that works. A CPU in `wfi`
QEMU does halt, until an interrupt.

## Smallest change that would help

Let a CPU that has found nothing to do for a while halt, while the busy
path stays as it is, with no interrupt sent between CPUs:

- **Another CPU**, finding its ring empty, polls it for a short time (a
  few microseconds, or a number of tries), and then says in its ring that
  it sleeps and `wfi`s. `cpu_run`, handing a thread to a CPU that says it
  sleeps, sends it an SGI; to one that is polling, nothing. So a CPU busy
  with threads, or briefly between them, never costs an interrupt.
- **CPU 0 in `cpu_wait`** does the same: it polls for a short time, then
  says it sleeps and `wfi`s, and a CPU that gives a thread back to a
  sleeping CPU 0 sends it an SGI. Its devices' interrupts end its `wfi`
  as they do `interrupt_wait`'s.

The SGIs are the host's own, from its range of the GIC's 0 to 15, never
an interrupt a program enables, takes or ends, so nothing in spec 6.18
changes but the words "with no interrupt sent between the CPUs", which
would become "with no interrupt sent between CPUs that are busy".

## The workaround actually used

`CPUS` and `QEMU_CPUS` are 1 unless set, for `make demo`, `make boot`,
`make e2e` and the screen tests. `make test-virt` runs every board test
on one CPU and then on four (`VIRT_CPUS`), where each test is short, so
the several-CPU kernel stays tested.

## Left out, on purpose

- **Changing `cpu_wait`'s order.** It gives back a trap before it takes
  an interrupt, so a CPU 0 that always finds a trap takes devices' late.
  That is a separate matter, and no test has shown it yet.
- **The Pi 5.** There `wfe` is a real wait, and none of this costs
  anything; the change is for QEMU's sake, but harmless on the board.

## Which deliberate restriction this breaks

None that a program sees. The program still never sends or takes an
interrupt between CPUs; the host would, and only to wake a CPU that has
nothing to do.

## Alternatives considered

- **`wfi` with the CPU's own timer as the wake-up.** No SGI at all, but
  every hand-over to a sleeping CPU would wait for its next tick, which
  for a message passed between processes on different CPUs is the
  latency of every call.
- **QEMU's `-accel tcg,thread=single`.** One host thread for every vCPU,
  so no contention, but no parallelism either, which is the point.
- **Fewer CPUs in L0S's tests.** What L0S does now; it leaves the
  several-CPU kernel unexercised by everything that boots for real.

## Since landing

Roadmap 0123 does what this asked: an idle CPU polls its ring for
100 µs, then sleeps in `wfi`, and is woken by SGI 0 only if it sleeps.
`rootboot_tmpfs`, timed with L0S's kernel unchanged:

| CPUs | Before | After 0123 |
| --- | --- | --- |
| 1 | 47 s | 50 s |
| 2 | 113 s | 94–96 s |
| 4 | 222 s | 101–126 s |

What was left was L0S's own. A kernel that boots with four CPUs and never
hands them a thread took 57 s, so idle CPUs now cost little; 8000 round
trips to `echo` took 2.6 s on one, two or four; and keeping CPU 0 from
sleeping changed nothing. QEMU's exception log of the boot on one CPU
counted 2,064,544 data aborts against 59,960 system calls: the runtime
releases a freed block's pages (call 12), the kernel unmapped them, and
the next allocation faulted them in again, each fault a trip to CPU 0
and each unmap a TLB flush on every CPU. The kernel now acts on a
release only for a run of 16 MB or more, or with 128 MB of frames or
less left (`release_unmaps`, `kernel/memory.l0`), and the boot takes
25 s on one CPU, 26 s on two and 27–28 s on four.

Writing to a disk was the last case slower on four. A disk write is a
chain, `install` to `fs` to `virtio-blk` and back, each waiting on the
next, and the kernel handed each process to the idlest CPU, one that had
stopped polling and had to be woken: about 57 µs more a hand-off than on
CPU 0, 300,000 times. A kernel that used CPU 1 alone of four was as fast
as one CPU, and one that kept each process on its own CPU far slower.
`cpus_pick` now takes first a CPU active within 500 µs whose threads
each last ran 1 ms or less, so such a chain takes turns on one CPU, each
queued in its ring behind the last, and nothing waits behind a thread
that may be computing. With the case's disk in memory (the host syncing
`build/`'s varied the times by half or more):

| Case | 1 CPU | 4 CPUs before | 4 CPUs now | 4 CPUs, queued behind any |
| --- | --- | --- | --- | --- |
| `install` | 21–23 s | 32–33 s | 26–27 s | 25–26 s |
| `install_boot` | 36–40 s | 48–49 s | 47–48 s | 44–45 s |
| `rootboot_tmpfs` | 24–25 s | | 27 s | 26–27 s |

What is left is the hand-off itself: a thread handed to a CPU that has
stopped polling waits for the host to wake it, which on QEMU is a host
thread woken. Nothing L0S runs gains from more CPUs yet, so `CPUS` and
`QEMU_CPUS` stay 1 by default.
