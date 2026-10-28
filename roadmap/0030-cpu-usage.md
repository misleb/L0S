# 0030: How the CPUs are used, and what each process serves, in `ps` and System Monitor

Track: Kernel · Status: idea · Needs: – · Spec: kernel.md, syscalls.md, programs.md, demo.md, testing.md

## Why

Nothing says what the CPUs are doing. The kernel's boot banner says how
many there are (`l0s: 4 CPUs: the kernel on CPU 0, processes on CPUs 1
to 3`), and `Cpus` knows, in the moment, which pid is out on which CPU
and how long each pid's thread was last out (`cpus_last_run`). But it
keeps no totals, and `proc_info` gives none. So `ps` and System Monitor
show each process's state and memory and nothing of its CPU: not where
it runs, not how much of a CPU it takes, not whether the system is busy.
That 0003's processes ran on CPUs 1 to 3 had to be argued from the
scheduler's code rather than read off the screen. Goal 0002, which makes
more CPUs faster, also needs a way to see the CPUs used.

Nor does anything say what a process serves. A server registers its
port under a name (`name_register`, `compositor`, `font`, `vt1`), and
clients find it with `name_lookup`. The kernel knows each name's port,
and each port's owner, but no call lists them. So `ps` shows `wm` and
not that it is `compositor`, and which `vt` is `vt2`, or which of two
`usb-hid` is `keyboard`, can only be guessed from the order things
started, as `tests/vt.sh` and `spec/demo.md` do with pids.

GNOME System Monitor shows each process's % CPU in its Processes tab,
and each CPU's use over time in its Resources tab. `top` and `uptime`
show the load averages.

## Done when

- The kernel keeps, for each process, the CPU time its thread has run,
  from each hand-off to its trap (or each `user_run` on one CPU), and
  the CPU it last ran on. For each CPU it keeps the time it held a
  thread, and for CPU 0 the time the kernel spent on calls and
  interrupts rather than waiting. It also keeps the load averages over
  1, 5 and 15 minutes: the ready and running threads, sampled on a
  tick, decayed exponentially as Unix does.
- A system call gives them: a process's CPU time and last CPU (in
  `ProcInfo`, or a call of its own), and the CPUs' busy times and the
  load. These are checked against the kernel's records, with board tests
  in `kernel_virt_test.l0`, refusals included.
- A system call lists the names registered, each with its port and the
  pid that owns it, or a process's own names given its pid. It is
  bounded as `proc_slot` is, a slot at a time or into a buffer the
  caller gives, and checked against the kernel's records.
- `ps` shows each process's CPU, its % of one CPU since the last `ps`
  (or over its life, the first time), and the names it serves, comma
  separated, `-` for none: `wm` shows `compositor`, each `usb-hid` its
  `keyboard` or `pointer`. A `names` command lists every name, its port
  and its owner. `uptime`, or a line of `ps`,
  shows the load averages and each CPU's % busy.
- System Monitor has CPU, % CPU and Provides columns in its process
  grid, sortable like the others, Provides being the names it serves. Under the grid, beside memory, each CPU's % busy is a
  bar, CPU 0 marked as the kernel's, and the load averages, read again
  every second.
- On QEMU with `-smp 4` a test sees a busy process's % CPU near 100 on
  a CPU from 1 to 3 and CPU 0's share small. On the Pi 5, `ps` shows
  processes on CPUs 1 to 3, which 0003's Log could only argue. An e2e
  case sees `ps` and `names` agree on who serves `compositor` and
  `console`, and a name gone once its owner exits. `make
  check`, `make test`, `make e2e` and `make test-virt` pass.

## Steps

To be written. Clock reads cost little on CPU 0, which the kernel
already does on every hand-off and trap (`cpus_place`, `cpus_back`), so
the totals should cost an add each.

## Spec changes

- kernel.md: what the kernel counts, and the load averages.
- syscalls.md: the CPU call, or `ProcInfo`'s new fields, and the call
  that lists names.
- programs.md: `ps`'s columns, `names`' row, `uptime`'s row if it is a
  program, System Monitor's CPU and Provides columns and its bars.
- demo.md: the `ps` sample with its new columns.
- testing.md: the tests that read them.

## Log

- 2026-10-28: written when 0003 was closed, which showed that the CPUs'
  use could be argued from the code but not seen.
- 2026-10-28: widened to the names each process serves, which `ps` and
  System Monitor should show beside its CPU.
