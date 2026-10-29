# 0031: A process waits on several ports, and lets a name go

Track: Kernel · Status: done · Needs: – · Spec: syscalls.md, kernel.md, programs.md, devices.md, demo.md, testing.md

## Why

A process may own many ports (`port_new`) and register many names
(`name_register`, which checks only that the port is the caller's and
the name free, `kernel/ipc.l0`'s `ipc_register`). It cannot use them.
`port_receive` and `port_try_receive` take one port, so a process
blocked on one misses the rest, or polls them all with
`port_try_receive` and burns its CPU. Several names on one port cannot
be told apart, as a message carries only its sender's pid and payload.
And no call unregisters a name: it goes only when its owner exits.

So L0S spends processes to hold names:

- **Terminal's tabs.** Each tab's `vtN` is held by a relay, a `vt tab
  PORT PID` of its own, which forwards everything sent to it to the
  window's port (`port_forward`), so that the window's `vt` knows the
  tab by the relay's pid, and so that closing the tab, by ending the
  relay, lets the name go ([0025](0025-vt-scrollback-resize-tabs.md)'s
  Log). That is a process and a copy of every message a tab, and the pid
  arithmetic in `tests/vt.sh` and `spec/demo.md` that follows from it.
- **Input devices.** `usb-hid` is started once for each kind, `usb-hid
  keyboard` serving `keyboard` and `usb-hid mouse` serving `pointer`
  (`demo/etc/inittab`, `pi5/etc/inittab`), each its own process with its
  own claims on `usb`, though one class driver could serve both, and any
  other HID device, if it could wait on its endpoints' ports and its
  clients' together.

## Done when

- A system call waits for a message on any of several ports the caller
  owns, given as a list in its memory (up to a bound the kernel says),
  and answers with the port it came on and the message, as
  `port_receive` does. A try form returns at once. A busy port does not
  starve the others: the oldest message waiting across them is
  answered first. A port not the caller's, a list too long or out of
  its memory, is refused before anything waits.
- A system call unregisters a name the caller holds, on a port it owns:
  the name is free at once for `name_register` and `name_lookup` no
  longer finds it. A name not registered, or another's, is refused.
- `ps` and `proc_info` say a process waits on several ports (the count,
  or the first, as `state_receiving`'s detail says).
- Terminal's tabs have no relays: the window's `vt` registers each
  tab's `vtN` on a port of its own, waits on all of them and its
  window's, knows the tab by the port, and unregisters the name when
  the tab closes. A Terminal is one `vt` and a shell a tab.
- One `usb-hid`, with no argument, serves `keyboard` and `pointer`
  together, every boot keyboard and mouse it claims, each on its own
  port and its clients told apart by it. The inittabs start it once.
  Other HID devices it learns later join the same process.
- Board tests in `kernel_virt_test.l0` cover both calls, their refusals
  included; host tests cover the pure parts; `tests/vt.sh` and the e2e
  and screen cases that count pids are recomputed. `make check`, `make
  test`, `make e2e` and `make test-virt` pass.

## Steps

- [x] Waiting on several ports: the call, by the system call checklist
  (`l0s-dev`), the next free number (300 on), with its try form, its
  wrapper in `user/lib/sys/l0s.l0` returning the port with the message,
  and `ps`'s detail. The kernel's wait records the list, so a send to
  any of them wakes the process, and a port closed meanwhile is dropped
  from it. Board tests, refusals included.
- [x] Unregistering a name: the call, its wrapper and its board tests.
  A name's owner exiting still frees it as now.
- [x] Terminal without relays: `vt` waits on its window's port and a
  port per tab, registers `vtN` on the tab's port, and unregisters it
  as the tab closes; `vt tab` goes. `spec/demo.md`'s pids and `ps`
  sample, `tests/vt.sh`'s arithmetic, and 0025's design in
  `programs.md` follow.
- [x] One `usb-hid`: it claims every boot keyboard and boot mouse, waits
  on their endpoints' ports and on `keyboard`'s and `pointer`'s, and
  serves both. The inittabs start one; `devices.md`'s USB section,
  `programs.md`'s row and `demo.md`'s pids follow. Checked on QEMU by
  the keyboard and pointer screen tests; `wm` tells a key's notice from
  a pointer's by what it says, not by its sender's pid. The Pi 5's
  check, with a USB keyboard and mouse, is the user's, on a netboot, as
  the Log's last entry for this step writes it out: not yet done.
- [x] More of it: look through the servers for others that hold a name
  by a process of their own, poll with `port_try_receive`, or would
  serve better from one process waiting on several ports (`fs`' names
  per volume, `xhci`'s two controllers on RP1, `inet`, `wm`'s clients),
  and either change them here or write each up as a goal of its own.
  The findings go in the Log, each with what was done about it.

## Spec changes

All moved into the spec: programs.md (`vt`'s row without relays, at
most 31 tabs; `usb-hid`'s, one process), demo.md (a Terminal is a `vt`
and a shell a tab; the pids with one `usb-hid`, the `ps` sample, which
shows no Terminal), desktop.md (`wm` telling its input apart by what it
says; `vt`'s limit, a relay a tab, gone, its 31 tabs said), devices.md
and pi5.md (one `usb-hid`), testing.md (`vt.sh`'s pids, no relay).

## Log

- 2026-10-28: written, after 0025's tabs needed a relay process each to
  hold and let go of a name. The user had already meant to make one
  `usb-hid` of the keyboard's and the mouse's. When it is taken up, look
  for more such places (the last step).
- 2026-10-28: steps 1 and 2, calls 300 to 303 (310 and up are left for
  0030). The design calls:
  - **A set, not a list each call.** L0's `supervisor_receive` hands
    the kernel one range of bytes, which the kernel fills, and
    `supervisor_send` one it reads: no call can both give a list and
    take a message. So `port_set` (300, a send of the ports as u32s)
    names the caller's set, up to `port_set_limit`, 32, and is refused
    whole before anything changes (a port not the caller's -1; none,
    more than 32, or a part of a u32 -4; a bad buffer -5); then
    `port_receive_set` (301) waits on it and `port_try_receive_set`
    (302) does not. A set is kept until the next `port_set` or the
    process's exit, so a loop whose ports stay the same, as a server's
    do, pays for the list once, not once a message, as epoll's sets do;
    `port_receive_any ports` does both for a loop whose ports change.
    `Ipc` keeps the sets by pid (no change to `Proc`), and a port closed
    (`ipc_close`) leaves its owner's set, which goes with its process.
  - **The port after the message.** A receive on a set writes the
    sender, the payload and then the port, a u32; the wrapper reads the
    port from the end and gives `(SetMessage port m)`, `m` a `Message`
    as `port_receive` gives one, so every `msg_` reader works on it.
    That costs one copy of the message in the process (`bytes_slice`,
    at most 4 KB), where a port first would have cost the same and a
    second call to ask the port would have cost a trip to CPU 0; the
    kernel's word cannot be returned beside the bytes.
  - **Oldest first.** Every message queued on any port is numbered as it
    is queued (`QMsg`, the counter in `Ipc`), and the set's receive
    takes the lowest of the messages first in their queues, so a busy
    port starves none (`test_receive_set_oldest`, `test_oldest_across`).
  - **What `ps` says.** A process waiting on its set is `ReceivingSet`,
    `proc_info`'s new `state_receiving_set`, 10, its detail the set's
    count; `ps` says "waiting for a message on N ports", and System
    Monitor tones it as any wait.
  - **One set a process.** For 0033: the toolkit's loop sets its
    windows' port and its reply port once, and sets again only as a
    window opens or closes; an app that wants ports of its own beside
    them must go through the same set (kernel.md's Limits). Sets
    numbered by a handle could lift that if an app ever needs two.
  - **Letting a name go** is `name_unregister name` (303), a send of
    the name alone, as `name_lookup` is: the name's port must be the
    caller's (-6 otherwise), and a name not registered is -1. It is free
    at once; an owner's exit still frees its names
    (`test_name_freed_on_exit`).
  Tests: 20 board tests (sets: made, counted, the port given, oldest
  first, only the set's ports, woken by another's send, deadlock, try
  empty, no set, too little room with the message kept, not the
  caller's, sizes, faults, `proc_info`; names: let go, found no more,
  registered again, not registered, twice, bad names, another's, freed
  on exit), host tests of `ipc.l0`'s sets and names and of the
  wrappers' `_of`s. `make test-virt` 258 on one CPU and on four.
- 2026-10-28: step 4, one `usb-hid`, with no argument, in every
  inittab (the demo's, the Pi 5's, `tests/usb`'s and the `usb` e2e
  case's). The design calls:
  - **Three ports, not one an endpoint.** The usb server sends every
    endpoint's reports as notices to the one port that listened, each
    naming its device and endpoint, so "their endpoints' ports" is that
    one port: `usb-hid`'s own, where the server's answers and notices
    come. Beside it a port for `keyboard` and one for `pointer`, each
    registered on its own, and the three are its set; a listen is
    added to the keyboard's or the pointer's listeners by the port it
    came on. A device is a `Board` with its kind, so a device with a
    keyboard and a mouse interface is two boards, by endpoint, and both
    go when it is unplugged. Other HID kinds join as kinds of `Board`.
  - **An alarm for a held key, not a poll.** While a key was held the
    old loop took a message if there was one, else napped 2 ms
    (`poll_ns`) and looked again. Now the repeat sets the kernel's alarm
    (`alarm_at`, on its own port) for when it is due, as the repeat
    changes, and the alarm's notice repeats the key; an alarm a
    replaced repeat had set, ringing early, sets it again. Found in this
    goal's own files, so done here (step 5's kind of finding).
  - **Waiting for an answer** from the usb server receives on its own
    port alone (`port_receive`), so clients' listens wait on their
    ports meanwhile rather than being kept; the server's notices that
    come first are kept as before.
  The pids after it each move down one: the demo's `sh` is 14, `font`
  15, `wm` 16 (`spec/demo.md`'s table and `ps` sample), and
  `tests/vt.sh`'s `vt_base` is 16. No e2e case's expected output
  listed the demo's pids; the `usb` case's `contains` lists one
  `usb-hid`, "waiting for a message on 3 ports".
  **The Pi 5, still to check** on a netboot (`tools/pi5-boot`) with a
  USB keyboard and a USB mouse on RP1's ports: on the serial line (or
  `dmesg`), `xhci`'s lines for both controllers, a `device` line for
  each device, then `usb-hid`'s two lines, "device N, interface 0: a
  keyboard, serving keyboard" and "... a mouse, serving pointer", from
  one pid; `ps` at the serial shell shows one `usb-hid`, "waiting for a
  message on 3 ports"; keys typed reach the serial shell's `run keys`
  and the front window, a held key repeats (500 ms, then about 30 a
  second) and stops when let go; the mouse moves the pointer and
  clicks.
  Checked on QEMU, four CPUs: `tests/usb.sh` (the USB keyboard typing
  "hi! A", and now a z held 900 ms, typed 13 times: once, then every
  33 ms from 500 ms, by the alarm; the mouse clicking the launcher
  open), the `usb` e2e case, and the demo's inittab booted with USB
  input, whose `ps` is `spec/demo.md`'s sample. `make check`, `make
  test` 2875 passed.
- 2026-10-28: step 5, the servers looked through, for a name held by a
  process of its own, a poll with `port_try_receive` and a nap, or one
  that would serve better waiting on several ports:
  - `usb-hid`'s held key, polled every 2 ms: done in step 4, by the
    kernel's alarm.
  - `vt`'s tab relays, a process each to hold `vtN`: step 3's, which
    waits for 0021, below.
  - `fs`' names per volume: there are none. `fs` registers `fs` once,
    and each volume is a mount the kernel routes by path to `fs`' one
    port (`fs_mount`), so nothing is held by a process. But `fs ram` is
    a second `fs` process holding `tmpfs` beside it: written up in
    [0034](0034-servers-wait-not-poll.md).
  - The disk drivers register every disk, `diskN`, on one port, and
    tell the disks apart by a request's first word (`disk_asked`):
    nothing to change.
  - `xhci`'s two controllers on RP1 are one process, one port and both
    interrupts bound to it; it polls, napping 1 ms, only while no
    interrupt is bound. Nothing to change while every board it runs on
    gives interrupts; in 0034 should one not.
  - `inet` naps 1 ms between looks at TCP's timers for as long as a
    connection is open, and its lease 10 ms while it waits for DHCP;
    `gem` naps between looks at the link. An alarm at the next due time
    would do for each: 0034.
  - `wm` takes requests, input and the display's notices on one port,
    and `port_try_receive`s to put pointer moves together; System
    Monitor refreshes by a poll and a nap. Both are 0021's and 0033's
    to change (`wm`'s notices, the toolkit's loop), so 0034 names them
    and leaves them.
  The rest of the servers (`echo`, `font`, `pcie`, `rtc`, `uart`,
  `virtio-*`, `hvs`, `hdmi-audio`, `sdhci`) serve one name on one port
  and wait on it, their naps being for their devices' registers, not
  for messages.
- 2026-10-28: step 3, Terminal's tabs without relays, waits: another
  goal, 0021, is changing `vt` now. It follows once 0021 has merged,
  with the calls of steps 1 and 2 (`port_set`, `port_receive_set`,
  `name_unregister`) as they are. `tests/vt.sh`'s `vt_base` is 16 after
  step 4, and its arithmetic will change again as the relays go.
- 2026-10-28: step 4 taken back in part, and left unticked. With one
  `usb-hid`, `make e2e`'s `tests/vt.sh` failed at "the wheel scrolled
  vt1 back", every run, and passed with the old two drivers in its
  place. The cause is `wm`'s, not the driver's: `wm` listens to
  `keyboard` and `pointer` and tells their notices apart by the sender's
  pid (`received` and `motion_from` in `wm.l0` test `from` against the
  keyboard driver's pid first), so with one pid serving both, a mouse's
  motion that turns the wheel, which `wm` does not join with other
  moves, went to `keyed` and was forwarded to the front window as a
  key. Moves and clicks happened to take the other path. A debug line
  showed the driver sending the wheel's report rightly. Fixing it is a
  few lines in `wm` (test the payload, a key notice or a pointer's,
  before or beside the pid), but `wm` is 0021's while 0021 is in
  flight, so it was not changed here. What is in:
  - `usb-hid` serves both names from one process with no argument
    (sets of ports, a port a name, the alarm), and one kind, as before,
    with `keyboard` or `mouse`; the inittabs start the two as they did,
    so the pids are as they were (`spec/demo.md`, `tests/vt.sh`), and
    each `usb-hid` waits on its three ports ("waiting for a message on
    3 ports" in `ps`, and in the `usb` e2e case's `contains`).
  - The alarm for a held key, and `tests/usb.sh`'s held z, are in
    either way.
  What is left, once 0021 has merged: `wm` routes a notice from its
  input drivers by what it is (`key_event_of`, `pointer_motion_of`,
  `pointer_event_of`, `wheel_event_of`), not by which pid sent it;
  then the inittabs start one `usb-hid` with no argument, the later
  pids move down one (`spec/demo.md`'s table and `ps` sample, `sh` 14,
  `font` 15, `wm` 16, and `tests/vt.sh`'s `vt_base` 16: these were
  made and tested once, `tests/vt.sh` passing its pid checks before the
  wheel), the `usb` e2e case's `contains` lists one `usb-hid`, and
  `devices.md`, `programs.md` and `pi5.md` say one process.
  **On the Pi 5, to check now** on a netboot (`tools/pi5-boot`) with a
  USB keyboard and a USB mouse on RP1's ports: `usb-hid`'s two lines,
  "device N, interface 0: a keyboard, serving keyboard" and "... a
  mouse, serving pointer", each from its own `usb-hid`; `ps` at the
  serial shell shows both "waiting for a message on 3 ports"; keys
  typed reach `run keys` and the front window; a held key repeats
  (after 500 ms, then about 30 a second, now by the kernel's alarm)
  and stops when let go; the mouse moves the pointer, clicks, and its
  wheel scrolls a Terminal back. Once the inittab starts one
  `usb-hid`, the same again, with both lines from one pid.
- 2026-10-28: step 4 finished, after 0021's merge. `wm` routes its
  input by what a notice says: `input_kind` takes a message from either
  input driver (`from_input`: the keyboard's pid or the pointer's, 0
  until `wm` listens, so nothing from pid 0 or a client counts) and
  makes it a key if `key_event_of` reads one, else the pointer's
  (`pointer_received` then tells a place, a motion and a wheel's turn
  apart, as before); `motion_from`, which joins queued motions, takes a
  motion from either driver the same way. Everything else
  (`received_other`) is as it was. The design call: keep the pid test
  beside the payload, so a client cannot pass itself off as the
  keyboard by sending a `key` notice; and keep `wm`'s two pids, `kp`
  and `pp`, since a board may still have two drivers (virtio-input's
  keyboard and tablet). Host tests: `test_input_one_driver` (one pid's
  key, wheel and motion), `test_input_two_drivers` (another pid's, and
  the kernel's before `wm` listens, are no input).
  Then the inittabs start one `usb-hid` with no argument (the demo's,
  the Pi 5's, `tests/usb`'s and the `usb` e2e case's), and the pids move
  down one as the earlier entry said: `sh` 14, `font` 15, `wm` 16
  (`spec/demo.md`'s table and `ps` sample), `tests/vt.sh`'s `vt_base`
  16, the `usb` case's `contains` one `usb-hid`, and `devices.md`,
  `programs.md`, `pi5.md` and `desktop.md` say one process. `usb-hid
  keyboard` and `usb-hid mouse` still serve one kind alone, for trying
  one by hand. Checked on QEMU, four CPUs: `tests/usb.sh` and
  `tests/vt.sh`, whose wheel now scrolls vt1 back with one `usb-hid`.
  **The Pi 5, for the user to check** on a netboot (`tools/pi5-boot`)
  with a USB keyboard and a USB mouse on RP1's ports: `usb-hid`'s two
  lines, "device N, interface 0: a keyboard, serving keyboard" and "...
  a mouse, serving pointer", from one pid; `ps` at the serial shell
  shows one `usb-hid`, "waiting for a message on 3 ports", and `sh` at
  14; keys typed reach `run keys` and the front window; a held key
  repeats (after 500 ms, then about 30 a second) and stops when let go;
  the mouse moves the pointer and clicks; and its wheel scrolls a
  Terminal back, not typing into it, which is what `wm`'s change fixed.
- 2026-10-28: step 3, Terminal's tabs without relays, and the goal
  done. `vt tab` is gone: a Terminal is one `vt`, and each tab one more
  process, its shell. The design calls:
  - **A port a tab, named there by `vt` itself.** Opening a tab takes a
    port, registers the first `vtN` free on it (`vt_register`, as the
    relay did), starts `sh NAME` watched on the window's port, and adds
    the tab, all at once: no tab waits unnamed for a relay to say its
    name. A tab is known by its port (`Tab`'s first field, `tab_port`,
    `tabs_by_port`; the tab bar's keys are ports), the window's port
    still takes `wm`'s notices and the shells' exits.
  - **One set, made as the tabs change.** `vt` waits with
    `port_receive_set` on its window's port and every tab's
    (`vt_ports`); `vt_waiting` makes the set again after a tab opens or
    closes, not every message. A window therefore has at most 31 tabs
    (`tabs_most`, `port_set_limit` less the window's), and a 32nd is
    refused, said on stderr: desktop.md's Limits.
  - **A closed tab's port is kept, not leaked.** No call gives a port
    back, so the tab's port goes on `Vt`'s list of free ports and the
    next tab takes it, emptied first (`port_drained`) of what the old
    shell sent last. A tab's name is let go as it closes
    (`name_let_go`, `name_unregister`), so `vt3` closed is `vt3` free.
  - **Terminal's `open`** (0032: a new window in the first Terminal's
    process) goes in `from_window` in `vt.l0`, where everything that
    comes on the window's port is taken: an `open` request there would
    open a second window. `Vt` holds one `UiWin` and its tabs; for many
    windows it becomes a window's `Vt` per `UiApp` id, the tabs' ports
    joining one set across them (`vt_ports` over every window), within
    the same 32.
  Tests: `tabs_test.l0` keyed by port (`test_ports`, `test_not_found`,
  `test_pids` shells alone), `vt_test.l0`'s `test_tabs_most`;
  `tests/vt.sh` checks `ps` shows the windows' two `vt`s and no other
  (the pids as step 4 left them, `vt_base` 16). Checked on QEMU, four
  CPUs: `tests/vt.sh` and `tests/launcher.sh`.
