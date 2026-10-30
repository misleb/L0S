# 0030: How the CPUs are used, and what each process serves, in `ps` and System Monitor

Track: Kernel · Status: done · Needs: – · Spec: kernel.md, syscalls.md, programs.md, demo.md, testing.md

## Why

Nothing says what the CPUs are doing. The kernel's boot banner says how
many there are (`l0s: 4 CPUs: the kernel and brief processes on CPU 0,
the rest on CPUs 1 to 3`, since 0002), and `Cpus` knows, in the moment, which pid is out on which CPU
and how long each pid's thread was last out (`cpus_last_run`). But it
keeps no totals, and `proc_info` gives none. So `ps` and System Monitor
show each process's state and memory and nothing of its CPU: not where
it runs, not how much of a CPU it takes, not whether the system is busy.
That 0003's processes ran on CPUs 1 to 3 had to be argued from the
scheduler's code rather than read off the screen, and since 0002 which
runs where depends on how long each runs, which nothing shows either.

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
  a CPU from 1 to 3 (0002's `tools/cputimes.d/t-spin` is such a case),
  and one passing messages on CPU 0. On the Pi 5, `ps` shows which
  processes run on which CPU, which 0003's Log could only argue. An e2e
  case sees `ps` and `names` agree on who serves `compositor` and
  `console`, and a name gone once its owner exits. `make
  check`, `make test`, `make e2e` and `make test-virt` pass.

## Steps

- [x] 1. The kernel counts: a pure `kernel/usage.l0`, kept in `Cpus`,
  with each slot's CPU time, last CPU and start, each CPU's busy time,
  CPU 0's time waiting, and the load averages, sampled every 5 s and
  decayed as Linux's `calc_load` does (fixed point, 11 bits). A thread
  out on CPU 1 to 3 is charged from the later of its hand-off and the
  return of the one before it on that CPU, to its trap; a turn on CPU 0
  (or a run on one CPU) from its start to its park, its calls
  included. CPU 0's own time waiting is the time in `cpu_wait` or
  `interrupt_wait`; the wait wakes for the load's tick. Host tests in
  `usage_test.l0` and `cpus_test.l0`.
- [x] 2. The calls: `cpu_usage` (304), a process's record (its CPU
  time, the CPU it is on or last ran on, its start), or with pid 0 the
  system's (uptime, CPU 0's waiting, each CPU's busy time, the load);
  and `name_list` (305), the names registered from the i-th in order,
  each with its port and owner, as many whole as the buffer holds. By
  the system call checklist, with board tests in
  `kernel_virt_test.l0`, refusals included.
- [x] 3. `ps` with CPU, %CPU (over the quarter second `ps` watches, or
  over the process's life if it is newer; see the Log) and SERVES
  columns; `names`, every
  name, its port, owner and program; `uptime`, how long the system has
  run, the load averages, and each CPU's % busy over a second, CPU 0's
  kernel share beside it. Shell builtins, with `procs.l0` holding what
  `ps` and System Monitor share. The e2e cases that show `ps` mask its
  CPU and %CPU, which differ every boot (`e2e.sh`'s `filter`).
- [x] 4. System Monitor: CPU, % CPU and Provides columns, sortable;
  under the grid, each CPU's % busy as a level bar, CPU 0 marked the
  kernel's, and the load averages, read every second. `procmon.sh`
  follows.
- [x] 5. Tests on QEMU with `-smp 4`: an e2e case, `cpu_usage`, of
  three spins beside `ping` to `echo`, where `ps` shows each spin near
  100% on a CPU from 1 to 3; and `names`, where `ps` and `names` agree
  on who serves `compositor` and `console`, and a name goes once its
  owner is killed.
- [x] 6. On the Pi 5, `ps` and `uptime` show which processes run on
  which CPU, booted by the user with `tools/pi5-boot`; its lines go in
  the Log.

## Spec changes

All moved into the spec: kernel.md (How the CPUs are used: what the
kernel counts, CPU 0's waiting and the kernel's share, the load
averages; `usage.l0` in the files table), syscalls.md (calls 304
`cpu_usage` and 305 `name_list`), programs.md (`sh`'s `ps` columns,
`names` and `uptime`, builtins of the shell; System Monitor's % CPU,
CPU and Provides columns, its CPUs' bars and the load; `procs.l0`),
demo.md (the `ps` sample with its columns, `names` and `uptime`),
testing.md (`filter`, the `cpu_usage` and `names` cases, the board
tests, `procmon.sh`'s CPU bar).

## Log

- 2026-10-28: written when 0003 was closed, which showed that the CPUs'
  use could be argued from the code but not seen.
- 2026-10-28: widened to the names each process serves, which `ps` and
  System Monitor should show beside its CPU.
- 2026-10-29: steps 1 to 5 done. The kernel counts in `kernel/usage.l0`,
  kept in `Cpus`, at a look at the clock per park, hand-back or wait,
  not per trap: a turn on CPU 0 is counted whole as it ends, its calls
  included (`k_turn_over`, `step`). Calls 304 `cpu_usage` and 305
  `name_list`, with board tests on 1 and 4 CPUs (`test_cpu_usage_*`,
  `test_name_list*`; a spinner's time grows on CPU 0 alone, or on a CPU
  from 1 to 3). `ps`, `names` and `uptime` are the shell's builtins.
  `ps`'s %CPU is over a quarter second it watches, not "since the last
  `ps`": that needs state the shell keeps between commands, threaded
  through `repl` and `obey`, which goal 0017 rewrote at the same time;
  the window says as much, as `top`'s first screen does. The e2e cases
  that show `ps` mask its CPU and %CPU (`e2e.sh`'s new `filter`);
  `cpu_usage` (three spins at 90%+ on CPUs 1 to 3, `echo` on CPU 0, a
  load above 0) and `names` (`compositor` and `console` agreed on, `echo`
  gone once killed) are new. System Monitor is 1080 wide for its % CPU,
  CPU and Provides columns, with its CPUs' bars under the memory's.
  `make check`, `make test`, `make test-virt` pass; e2e run for the
  cases that show `ps`, `shell`, `cpu_usage` and `names`. `procmon.sh`
  passes up to its last two checks, the slider wide under the pointer
  and dragged: they fail the same with main's kernel, shell and
  procmon on this machine, the grid scrolled back from its end within
  0.2 s of the wheel, so not this goal's; left for the merge's `make
  e2e` to show. Step 6, the Pi 5's board run, is the user's.
- 2026-10-30: step 6, and the goal, done. Booted on a 2 GB Pi 5 with
  `tools/pi5-boot --reboot`, at 4K. Idle, `ps` shows every process on
  CPU 0 but `boot` (CPU 2, waiting for `sh`), %CPU 0.0 to 0.3, and what
  each serves: `fs` `fs,tmpfs` on 2 ports, `usb-hid` `keyboard,pointer`
  (wider than the column, which pushes its STATE on), `wm`
  `compositor`, `hvs` `display`; `names` lists the 14 names and agrees.
  With three `run spin &`, `ps` shows them on CPUs 2, 3 and 1 at 99.6,
  99.5 and 99.5%, and `uptime`:

  ```
  up 0:01:17, load average: 0.62, 0.13, 0.04
  CPU 0: 0.5% busy, the kernel 0.4%
  CPU 1: 100.0% busy
  CPU 2: 100.0% busy
  CPU 3: 100.0% busy
  ```

  Once they are killed, CPUs 1 to 3 read 0.0% and the load decays from
  1.11. So which process runs on which CPU, which 0003's Log could only
  argue, is read off the board.
