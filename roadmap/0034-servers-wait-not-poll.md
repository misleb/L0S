# 0034: Servers that wait for their time and their ports, not poll

Track: Kernel · Status: done · Needs: – · Spec: programs.md, network.md, storage.md, boot.md, pi5.md, demo.md

## Why

0031 gave a process a set of ports to wait on (`port_set`,
`port_receive_set`), and the kernel already sends an alarm to a port at a
time (`alarm_at`, call 297). With both, no server needs to look at its
port, nap and look again, nor a process of its own to hold a second
name. Looking through the servers for 0031's last step found these
still doing one or the other (0031's Log has the survey):

- **`inet`, while a TCP connection is open,** takes a message if there
  is one and otherwise naps 1 ms (`tcp_poll_ns`) and looks at its
  timers: a thousand wakes a second for as long as any connection
  lasts, idle or not. An alarm at the soonest timer's due time, set
  again as timers change, would wake it only when one is due, as
  `usb-hid` now times a held key's repeats.
- **`inet`'s lease** (`lease.l0`'s `lease_wait`) naps 10 ms between
  looks while it waits for a DHCP answer.
- **`gem`** naps `poll_ns` between looks at the Ethernet link on the Pi
  5; an alarm a second, or the PHY's interrupt if RP1 routes one, would
  do.
- **`xhci`** polls, 1 ms naps, while a controller has no interrupt
  bound; with interrupts (QEMU's MSI, the Pi 5's RP1 vectors) it waits.
  Worth keeping only if a board without them is ever met.
- **`fs ram`** is a second `fs` process, registered as `tmpfs`, beside
  the disks' `fs`: one `fs` could serve both names, on a port each,
  waiting on both with a set, as `usb-hid` serves `keyboard` and
  `pointer`. Its loop (0024's `serve`, `drained`) would then take what
  waits with `port_try_receive_set` and wait with `port_receive_set`,
  and turns.l0's order, by pid, would cover both ports as it is.
- **System Monitor** (`procmon`) refreshes by `port_try_receive` and
  naps; its loop is the toolkit's to change, with 0033's.
- **`wm`** takes every client's request, the keyboard's and pointer's
  notices and the display's on one port, and uses `port_try_receive` to
  put pointer moves together; a port for input apart from requests
  would let it favour input. 0021 is changing `wm`'s notices, so this
  waits for it.

## Done when

- No server of the demo's or the Pi 5's naps between looks at its port
  when it has an interrupt: each waits on its port, or its set, and on
  the kernel's alarm for anything it must do at a time. A nap is left
  only where a driver has no interrupt to wait for, and the spec says
  so.
- `inet` sets the alarm for its TCP timers' soonest deadline, and none
  for an idle connection; its lease waits for the alarm at the end of
  each wait for a DHCP answer. Host tests pin the deadline it picks;
  the e2e cases `http`, `net_echo`, `net`, `dhcp` and `dns` pass.
- One `fs`, started `fs ram`, serves the RAM file system as `tmpfs` and
  the disks as `fs`, on a port each, waited on as a set; the Pi 5's
  inittab starts one `fs`. Host tests show both served side by side and
  what is refused of `tmp`; the e2e cases `tmpfs`, `bigdir`,
  `rootboot_tmpfs`, and the disk cases, pass.
- Every server of the survey has its step, changed or kept with the
  reason written here.

## Steps

- [x] 1. `inet`'s TCP timers: the alarm at the soonest deadline
  (`tcp_due`), set again only when that changes (`alarm_wanted`), in
  place of the 1 ms nap.
- [x] 2. `inet`'s lease: the alarm at the end of each wait
  (`asking_when`), in place of the 10 ms nap.
- [x] 3. `gem`: kept. It already waits on the GEM's interrupt and on the
  alarm for the link (since RP1's MSI-X came); it naps only when it
  cannot have its interrupt, as a fallback. The spec, which still said
  it polled, corrected.
- [x] 4. `xhci`: kept. It polls only a controller with no interrupt
  bound, which no board L0S runs on now has.
- [x] 5. `fs ram`: one `fs` serves `tmp` as `tmpfs` and the disks as
  `fs`, a port each, waited on as a set; the Pi 5's inittab starts one.
- [x] 6. System Monitor: done by 0033, whose toolkit loop gives it the
  window's alarm (`ui_win_alarm`); nothing to change.
- [x] 7. `wm`'s input port: judged a design of its own, written up as
  [0051](0051-wm-input-port.md), not done here.
- [x] 8. `rtc clock`, found on the way, polled every quarter of a
  second for requests and the minute: now it waits, and the alarm rings
  at the next minute.

## Spec changes

All moved into spec/ (network.md, storage.md, boot.md, pi5.md,
programs.md, and demo.md's `ps` sample: `rtc clock` waits for a
message now, and `fs` on a set of one port).

## Log

- 2026-10-28: written from 0031's last step, its survey of the servers.
- 2026-10-29: Done when and steps written, and every step done in one
  change. The design calls:
  - **inet's alarm on its own port.** The alarm comes to `inet`'s one
    port from pid 0 (`is_alarm_notice`), among frames and requests, so
    no set is needed. `serve` keeps when the alarm is set for (`armed`)
    and sets it only when the soonest deadline differs; an alarm that
    rings for a timer since stopped or put off looks at the timers for
    nothing, which `tcp_ticked` makes harmless. Timers are now looked at
    in turn with the messages, where before they waited for the port to
    be empty. A lease's last alarm, ringing after `inet` has registered,
    is taken as a look at the timers.
  - **rtc clock** reads the board's clock in whole seconds, so the
    alarm for the next minute is set the seconds between them on, at
    least one: it rings within a second after the minute begins, where
    the poll was within a quarter of one; one that rings before the
    board's clock has reached the minute is set again a second on.
  - **One fs, two ports.** `fs ram` makes the RAM store first, mounts
    `tmp` from a port of its own and registers it `tmpfs` at once, so
    boot's `root=tmpfs` finds it as before; then it waits for `disk0`
    as `fs` alone does (`name_wait`, 5 s), loads the disks and
    registers `fs` though there be none, so that a disk that comes
    later (the Pi 5's card) is attached. Until then `tmp`'s requests
    wait: on a board with no disk, the first 5 seconds (boot.md). The
    tmpfs port lives in the RAM store (`StoreRam`'s third field,
    `store_port`), where `unmount` finds it. The RAM store is store 0,
    the disks after it, and disk work passes it over: `disks_loaded`
    and `mkfs_from` skip it, `rescan` keeps its volume first
    (`ram_vols`), and `partition`, `erase` and `attach` of the disk
    `tmp` and `relabel` of its volume are refused -5 (`ram_asked`),
    where before `fs ram` refused every disk request whatever it named.
    Which port a request came on is not looked at: a request names its
    volume or disk itself. `fs` alone now waits with a set of one port.
  - **wm** is 0051: two ports in a set change no order, since a set
    gives the oldest first; favouring input means input passing
    requests that came before it, which a `top` or a new window makes
    matter to where a key goes.
  Tests: `inet_test.l0`'s `test_tcp_due`, `test_tcp_due_data`,
  `test_soonest_deadline`, `test_alarm_wanted`; `rtc_test.l0`'s
  `test_minute_alarm`; `fs_test.l0`'s RAM tests rewritten
  (`test_ram_refuses_tables`, `test_ram_refuses_relabel`,
  `test_ram_passed_over`) and `test_ram_and_disk`,
  `test_ram_and_disk_files`, `test_store_port`. The demo's inittab
  never started `fs ram`, so its pids are as they were.
  **On the Pi 5, for the user to check** (`tools/pi5-boot`), with and
  without an SD card: `ps` shows one `fs`, "waiting for a message on 2
  ports"; `/Volumes/tmp` is mounted, and with a card its volumes too,
  and `root=` boots from the card as before; `inet dhcp` gets its lease
  and `run http` fetches a page; the top bar's clock turns over at the
  minute.
