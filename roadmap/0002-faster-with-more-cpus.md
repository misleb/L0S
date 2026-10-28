# 0002: More CPUs make L0S faster

Track: Kernel · Status: active · Needs: – · Spec: kernel.md, demo.md, testing.md

## Why

Every system call, and so every message, is handled on CPU 0, and on QEMU
more CPUs are no faster: writing to a disk is slower on four than on one,
because handing a thread to another CPU costs more than a call on CPU 0
([kernel.md, Limits](../spec/kernel.md#limits)). So the demo and the tests
boot with one CPU unless asked.

## Done when

- `install` and `install_boot` (e2e) run no slower on four CPUs than on one.
- The demo's default `CPUS` can be more than 1.

## Steps

- [x] Measure, on one CPU and on four: `install` and `install_boot`,
  `rootboot_tmpfs`, a boot to the desktop, small messages between two
  processes, and a CPU-bound process beside one passing messages. Keep
  the cases that are not e2e's own, and a script that times them, in
  `tools/cputimes`.
- [x] CPU 0 runs a process that passes messages itself, as on one CPU,
  and hands only those that compute to the other CPUs; processes ready
  together, or new, still go to CPUs of their own. Host tests in
  `cpus_test.l0`; the board tests pass on one CPU and on four.
- [ ] The demo's `CPUS` is 4, and the tests' `QEMU_CPUS` follows it; e2e
  cases whose output depends on which program runs first pinned to one
  CPU.
- [ ] kernel.md's Limit says the default; demo.md and the README say
  the new default.

## Spec changes

- kernel.md: the Limit says the demo and the tests boot with four.
- demo.md: the default `CPUS`.

(Moved with steps 1 and 2: kernel.md's loop, CPU 0 running processes
itself and a kernel that stops taking its threads back, its banner line
and its Limit's timings; testing.md's `tools/cputimes`.)

## Log

- 2026-10-26: written from kernel.md's Limits.
- 2026-10-27: most of what this measures, writing to a disk, is file
  data in 4 KB messages, a round trip of hand-offs between CPUs each
  (caller, kernel, `fs`, the disk driver, and back). 0023 moves it in
  requests of 64 KB through shared pages, about a sixteenth as many
  hand-offs, and times `install` and `install_boot` on one CPU and on
  four before and after; its numbers will be logged here too. Measure
  again once it lands, before working on this.
- 2026-10-27: 0023 landed on QEMU. Before it, `install` took 14.6 s on
  one CPU and 18.1 s on four, `install_boot` 25.4 s and 32.2 s; after,
  3.3 s and 2.9 s, 2.9 s and 2.8 s (0023's log has the method). Writing
  to a disk is no longer slower on four CPUs. kernel.md's Limit, which
  says it is, should be measured again with something that is not
  file data before this goal is worked on, or it may be done.
- 2026-10-28: measured again, at 3c9c731, and four CPUs were slower
  after all. Method: the wall time of `tests/e2e.sh CASE` (mkinitramfs,
  QEMU's start and the typed lines' pauses included, the same either
  way) with `QEMU_CPUS` 1 and 4, interleaved, five runs each, medians;
  this machine has 8 CPUs, and other agents' QEMUs ran meanwhile, the
  load 0.6 to 2. Runs of one case spread by 0.1 to 0.2 s. Besides the
  e2e cases, four of `tools/cputimes.d`: `t-install` (install alone,
  no other commands), `t-boot` (`install --boot` three times, 14 MB a
  file), `t-ping` (9,000 requests from `ping` to `echo`, nothing else)
  and `t-spin` (300 pings beside three `spin`s, which never call):

  | case | 1 CPU | 4 CPUs |
  |---|---|---|
  | `install` | 2.76 s | 2.95 s |
  | `install_boot` | 3.16 s | 3.96 s |
  | `rootboot_tmpfs` | 3.97 s | 3.97 s |
  | `t-install` | 2.35 s | 2.85 s |
  | `t-boot` | 4.17 s | 5.48 s |
  | `t-ping` | 2.41 s | 2.92 s |
  | `t-spin` | 18.60 s | 17.34 s (10.5 to 23.5) |

  `rootboot_tmpfs` waits on its typed lines, with work to spare, so it
  says nothing either way. 0023's `install` numbers were taken on a
  quieter host, and before the font service and more programs were
  in the initramfs; the case is mostly its typing's pauses, and four
  CPUs' 0.2 s more is real. `t-ping` puts it plainly: a message passed
  on four CPUs costs 55 µs more than on one, every call a trip from
  its CPU to CPU 0 and back through the rings, which on QEMU costs more
  than the call. And `t-spin`, where more CPUs should win, hardly did:
  each ping waited in the ready queue, or queued on a CPU behind a
  spin's 10 ms slice, wherever `cpus_pick` put it.
- 2026-10-28: the change, step 2: CPU 0 runs a process itself when its
  last run was 2 ms or less (`cpus_keeps`), in turns of at most 4 ms,
  its own timer set to the turn's end, and with no other CPU holding a
  thread, runs it again after each call at once, as on one CPU, looking
  at nothing else. A process whose last run was longer, or that has not
  run yet, is handed out, unless it is the only one ready and no CPU
  holds one (`cpus_here`); and when CPU 0 picks a process to run, every
  other ready one goes to a CPU with room (`many_spread_rest`). Found on
  the way, each with its effect on `t-ping`'s 9,000 round trips:
  - Every small step on CPU 0's path costs on QEMU, far more than the
    same work on the host: a field read from the kernel's record or
    `Cpus` 0.2 to 0.3 µs, `map_put` into a map the record still holds
    a copy (the map is copied whole, as an array is), `timer_at` about
    1 µs, and it seemed to slow the next run of the thread by more;
    taking a pid off the ready queue and putting it back 8 µs. So the
    path between a CPU-0 thread's runs does nothing of these: no clock
    read, no record of the run, no timer set (once a turn, not once a
    run), no look at the rings while no CPU holds a thread, no look at
    the ready queue. Doing them all cost 0.5 s (2.8 s against 2.3 s);
    doing none, 0.1 s.
  - Worst of all is a value that still holds the kernel's record while
    `on_trap` rebuilds it: every change it makes then copies the
    record's arrays whole. Passing the CPUs' table, read from the
    record, beside `on_trap`'s step cost `t-ping` 0.3 s, 13 %; a count
    read before the trap costs nothing measurable.
  - Board tests boot the kernel again and again in one program, and a
    kernel that stopped with a thread out on another CPU (pid 1 exiting
    while a spinner ran) left it running into the next boot, which took
    it back as its own pid 2: `test_kill_sibling` freed its pid 2's
    space while the first boot's was still out, "space still running".
    The old scheduler met it by chance less often. The kernel now takes
    every thread out back before it stops (`many_halt`), at most a slice
    later, and `test_halt_takes_back` stops it so.
  - Two e2e cases list processes' ports, whose numbers depend on which
    driver makes its port first: `pcie` and `virtio-input_tablet` keep
    to one CPU (`cpus`), as `virtio-input` did.
  - Only a turn the timer ends records how long its process ran, the
    turn's runs together; a process that runs long on CPU 0 is handed
    out at its next pass, and one handed out comes back once a run on
    its CPU is brief, recorded there by `cpus_back` as before.
  - First the threshold was 1 ms and the turn 2 ms: `fs`, copying
    64 KB windows, runs 1 to 2 ms at a time, and was handed out and
    back 250 times in `t-boot`, about 5 % of its time. At 2 ms and
    4 ms, 5 times. A long process alone on CPU 0 with nothing else
    ready stays there too, as `fs` writing a large file is.
  - First every new process started on CPU 0, so a short program never
    woke another CPU. The desktop then reached the screen in 1.3 s, as
    on one CPU, where before this change it took 1.0 s on four: its
    programs start together and each draws at first. Starting a new
    process, and every one ready beside the one CPU 0 picks, on a CPU of
    its own brought it back to 1.0 to 1.1 s, at no cost to `install`
    beyond the noise. Marking a new process brief once it ran alone on
    CPU 0, so that it stayed there later, lost that again (1.1 to
    1.3 s), and was dropped.
  - Measured on the desktop: the demo's initramfs booted headless
    (`QEMU_INPUT=usb`, a fresh 1 MB disk), QEMU's monitor dumping the
    screen every 50 ms, the time from QEMU's start to the first dump
    whose Terminal shows its ground (30 30 30 at 60,300), the files'
    times: five or six boots of each, interleaved. One CPU 1.25 to
    1.34 s; four, before 0.96 to 1.05 s, after 1.00 to 1.09 s.

  After, the same method as before, five runs each, before and after in
  the same runs, the load 1 to 3 (other agents' tests), and before it
  0.6 to 2:

  | case | 1 CPU | 4 CPUs, before | 4 CPUs, after |
  |---|---|---|---|
  | `install` | 2.76 s | 3.55 s | 2.80 s |
  | `install_boot` | 3.26 s (3.17 to 3.47) | 4.40 s | 3.35 s (3.23 to 3.39) |
  | `rootboot_tmpfs` | 3.99 s | 3.98 s | 3.98 s |
  | `t-install` | 2.34 s | 2.94 s | 2.46 s |
  | `t-boot` | 4.50 s | 6.16 s | 4.60 s |
  | `t-ping` | 2.41 s | 3.35 s | 2.65 s (2.50 to 2.66) |
  | `t-spin` | 18.7 s | 2.9 s (2.9 to 23) | 0.53 s |

  On a quieter host (load about 1) an earlier version, the same but for
  the desktop's change, measured `install` 2.75 and 2.74 s, `install_boot`
  3.18 and 3.13 s, `t-install` 2.35 and 2.35 s, `t-ping` 2.32 and 2.41 s.
  So four CPUs are as fast as one at writing a disk, to within the
  noise, which a busy host widens against four; passing nothing but
  messages, 4 % slower on a quiet host and up to 10 % on a busy one,
  what the steps above that are left cost, about 2 µs a round trip;
  and thirty to forty times as fast with processes that compute beside
  one passing messages. The first "Done when" holds.
- For 0030 (CPU usage): processes now run on CPU 0 as well as on 1 to
  3, so "CPU 0's share small" holds only of a computing process, which
  is handed out; one passing messages runs on CPU 0. And clock reads
  and record updates are not as cheap there as 0030's Steps say: a
  read of the clock and an update of `Cpus` on every run cost `t-ping`
  0.1 to 0.2 s of 2.3 s. Count CPU 0's runs per turn, as `many_own`
  ends one, not per run, or keep the totals somewhere a run does not
  rebuild the kernel's record; and never hold the record, or a field
  read from it, across `on_trap` (above). `tools/cputimes`' `t-spin`
  is a ready case for seeing a busy process's % CPU on CPUs 1 to 3.
- For 0031 (several ports): a process woken while another runs on CPU
  0 waits, if it would be handed out, for that one to stop or its turn
  (4 ms) to end; one passing messages, as a server waiting on several
  ports is, runs on CPU 0 and is not delayed.
