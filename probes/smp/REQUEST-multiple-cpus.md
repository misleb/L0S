# Feature request: running user threads on the other CPUs, so a kernel in L0 uses every core

Status: asked, not yet on L0's roadmap
Project: L0S, a microkernel in L0 for QEMU's virt boards and the
Raspberry Pi 5

L0S runs every process on one CPU. A Raspberry Pi 5 has four Cortex-A76
cores, and three of them never run anything: section 10.3 says that BL31
"holds the other three CPUs". QEMU's virt boards could have as many as
the host gives them, but `l0 boot` starts QEMU with one. Nothing in L0
lets a kernel start another CPU or run anything on it.

This asks for the smallest thing that would put the other cores to work
without changing what L0 is on the one it runs on. The program, the
kernel, keeps running on CPU 0 alone, so its heap, its collector and its
records stay a single CPU's. The other CPUs run **user threads only**,
which the kernel hands them, and hand their traps back. Both directions
go through **lock-free rings in memory**, polled, with no
inter-processor interrupt.

## What could not be written

`want.l0` beside this file is L0S's loop as it would be. CPU 0 drains
every trap the other CPUs have posted, gives each to the handler that
`user_run`'s traps already go to, posts each thread that may go on, and
fills the CPUs that have room from the ready queue. `l0 check` rejects
it: none of `cpu_count`, `cpu_run`, `cpu_trapped` or `cpu_wait` exists.

Section 6.13 and section 10.3 say why nothing else can stand in for them:

- **No CPU can be started.** Starting one is PSCI's `CPU_ON` on the
  aarch64 boards (function 0xC4000003, an `smc` to BL31 on the Pi 5,
  whatever conduit QEMU's virt board gives), and SBI's HSM `hart_start`
  on the riscv64 board. L0's runtime already makes PSCI calls of its own
  (`runtime/bare/psci.ll`, `SYSTEM_OFF` and `SYSTEM_RESET`), but no
  builtin makes a firmware call. A thread at EL0 or in U-mode cannot make
  one either.
- **`user_run` is synchronous.** It runs a thread on the CPU that calls
  it and returns when the thread traps. Only one thread runs at a time,
  however many CPUs the board has.
- **A started CPU would have nothing to run.** L0 code needs the
  runtime's heap and collector, which serve one CPU, and L0 has no atomic
  to share anything else with. So "start a second instance of the
  program" isn't something to ask for. A CPU that runs only user threads
  and the runtime's own trap path needs neither.

## The workaround actually used

None. L0S runs on one CPU, with round-robin scheduling and 10 ms slices
(README, "Limits"). A system of a compositor, a terminal, a shell, drivers
for the GPU, the disk, USB and the network, and the file system shares
that one core. Another core waits on the Pi 5, and QEMU isn't given one.

## Smallest change that would help

Four builtins, which run on CPU 0, numbered as the host numbers its CPUs,
the program's own being 0. The names and encodings are L0's to choose;
`want.l0` uses these.

| Builtin | Arity | Types | Meaning |
| --- | --- | --- | --- |
| `cpu_count` | 0 | -> int | how many CPUs the host runs threads on, the program's included |
| `cpu_run` | 5 | int, int, (array int), int, int -> int | queue a thread on another CPU, and return at once |
| `cpu_trapped` | 0 | -> (array int) | the next thread another CPU has finished with, or none |
| `cpu_wait` | 0 | -> int | wait for an interrupt, as `interrupt_wait` does, or for another CPU's trap |

**`(cpu_count)`** is 1 under an operating system, on a host that cannot
start its other CPUs, and on a board run with one. A kernel that sees 1
does what it does today.

**`(cpu_run c s ctx deadline tag)`** puts the thread whose context is
`ctx`, in space `s`, on CPU `c`'s run ring and returns 0. That CPU runs
the threads on its ring in order. Each one runs until it traps or until
`clock_ns` reaches `deadline` (a negative deadline means none) on that
CPU's own timer. `tag` is the kernel's, given back with the trap, so that
it knows whose thread it is (L0S would use the pid). The answer is -5
when the ring is full, as -5 means "none left" elsewhere, and -3 on a
host with no user mode. A `c` out of range, or a context not of the
host's length, is a runtime error, as `user_run`'s `not a context` is
one.

**`(cpu_trapped)`** looks at every CPU's trap ring and gives the oldest
entry of the first ring that has one, or an empty array when none does.
The array is the thread's context, the same 104 words `user_run` gives
back, so `trap_of`, `call_number`, `call_arg` and `call_result` read it
as they read `user_run`'s. Two more words follow it: the CPU and the tag.
It never waits, so a kernel drains every ring in one pass and handles
the traps as a batch. (A library reader, `cpu_trap_of`, could give these
as a data type, as `trap_of` does the trap.)

**`(cpu_wait)`** is `interrupt_wait` that also returns, with -1, once any
CPU has posted to its trap ring. It must not need an interrupt from that
CPU. On aarch64, a CPU that posts would `sev`, and CPU 0 would `wfe`,
which an interrupt pending at the GIC also ends. On riscv64, which has no
event register, it would poll the rings between `wfi`s, the timer
pacing it. How is L0's to choose; what matters is that no SGI or IPI is
spent on a trap.

Each ring is single-producer, single-consumer: a run ring has CPU 0 as
its producer and CPU `c` as its consumer, and a trap ring the other way
round. So each needs only ordered loads and stores and a barrier, no
compare-and-swap. They live in memory the runtime owns, below the user
range, out of every space's reach. Their depth is the host's, at least 2,
so that a CPU whose thread trapped can start the next one at once,
without waiting for CPU 0.

### What the other builtins promise once threads run elsewhere

- **Interrupts.** Every device's interrupt still goes to CPU 0, as now.
  Another CPU takes only its own timer. A thread's deadline ending there
  comes back as an interrupt trap, `TrapInterrupt 0`, in its context,
  already ended on that CPU, so CPU 0 does not `interrupt_done` it. A
  device's interrupt never ends another CPU's thread.
- **Spaces.** `space_map` into a space whose thread is queued or running
  elsewhere is allowed: a new mapping needs no TLB to be invalidated.
  `space_unmap` invalidates the page on every CPU before it returns
  (`tlbi vae1is` and `dsb ish` on aarch64, SBI's remote `sfence.vma` on
  riscv64). `space_free` of a space whose thread is queued or running on
  any CPU is a runtime error, `space still running`, as `frame_free` of a
  mapped frame is `frame still mapped`. A kernel knows which spaces it
  has handed out and can avoid it. ASIDs, if the host uses them, are the
  host's to keep apart across CPUs.
- **`space_read` and `space_write`** of a space whose thread runs
  elsewhere copy what memory holds at that moment. That is the same as
  two processes sharing a page, which they already can.
- **Registers.** A thread's floating-point and SIMD registers are saved
  and restored as `user_run` saves them, on whichever CPU runs it. A
  thread may run on a different CPU each time it is queued.
- **Memory.** The cores are coherent with each other on every board L0
  has. `frame_sync` is unchanged: it is about devices, not CPUs.
- **Boards.** `l0 boot`, `l0 run` and `l0 test --target virt` start QEMU
  with more than one CPU when asked, by an option or `L0_SMP=N`, and with
  one by default, so that nothing that runs today changes. The Pi 5
  starts its three others by `CPU_ON`. Section 10.3's tables say how
  many each board has.

## How L0S would use it

The kernel's loop today is `schedule`, then `run_proc` (`user_run`),
then `on_trap`, then `step`, one process at a time
(`kernel/kernel.l0`). With more than one CPU, CPU 0 would run no thread
of its own. It would be the kernel and the poller:

1. Drain `cpu_trapped` until it is empty. Each trap goes to `on_trap`
   unchanged, with the process and the context that came back.
2. A process that may go on (`Resume`) is queued again on the same CPU,
   for its caches, if that CPU's ring has room, and otherwise goes back
   on the ready queue. One whose slice ended goes back on the ready
   queue too. One that waits is parked, as now.
3. Wake the sleepers whose time has come, and fill every CPU's ring, two
   threads deep, from the ready queue.
4. If nothing came back, `cpu_wait`, with the timer set for the soonest
   sleeper. A device's interrupt is a notice to its driver, as now.

There is one ready queue for every CPU, so processes move to whichever
CPU has room. A process moves between traps, never in the middle of a
slice, and one already queued behind another on a busy CPU's ring stays
there until its turn, at most one slice later.

A process on another CPU keeps its slot in the kernel's table, marked as
running there, so that other processes' calls still find it. A share
maps into its space while it runs. A revoke unmaps, which the promise
above makes safe. A kill marks it, and it ends when its trap comes back,
within one slice. The pure parts, the table of which pid runs or waits
on which CPU and the choice of a CPU, are a new `kernel/cpus.l0`, tested
on the host. With one CPU, the loop stays exactly as it is.

L0S's system calls, every message between processes among them, would
reach CPU 0 through the trap rings. A later step could let processes
post messages into rings of their own in shared memory, with no trap at
all, but nothing here depends on that.

## Left out, on purpose

- **A kernel on every CPU.** That needs a heap and a collector several
  CPUs can use at once, and atomics in the language. It is a far larger
  change, and a microkernel's calls are short enough that one CPU can
  serve them for a while.
- **Inter-processor interrupts.** Nothing here sends one. A thread runs
  until it traps or its deadline passes, so a kernel that wants a CPU
  back waits at most one slice.
- **Stopping a thread on another CPU early.** For the same reason. If a
  kill within a slice is ever too slow, it could be a later request.
- **Affinity, idle states, and per-CPU interrupts for devices.** A
  kernel can keep a process on one CPU by queuing it there, and nothing
  more is needed yet.

## Which deliberate restriction this breaks

None that a program can see. The program still runs on one CPU, and
nothing it computes is shared with another thread of L0 code. What runs
elsewhere is user threads, which already run with no access to the
program's memory. The rings are the runtime's, out of every space's
reach, as the tables `space_map` writes are.

## Alternatives considered

- **Several instances of the program, one per CPU, each with its own
  heap** (a multikernel). It needs no change to the collector, but every
  port, process and page would need a protocol between kernels, and a
  process could never move between CPUs. L0 would still have to start
  the CPUs and give each instance its own heap and memory.
- **IPIs instead of rings.** A CPU whose thread trapped would raise an
  SGI on CPU 0, which would take it as an interrupt. It is simpler on
  the GIC, but every system call would cost an interrupt on both sides,
  and CPU 0 would handle traps one at a time rather than in batches.
- **A synchronous `user_run` on another CPU.** It would block CPU 0
  until the thread traps, so only one thread would run at a time, as
  today.
