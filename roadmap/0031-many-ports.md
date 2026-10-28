# 0031: A process waits on several ports, and lets a name go

Track: Kernel · Status: active · Needs: – · Spec: syscalls.md, kernel.md, programs.md, devices.md, demo.md, testing.md

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
- [ ] Terminal without relays: `vt` waits on its window's port and a
  port per tab, registers `vtN` on the tab's port, and unregisters it
  as the tab closes; `vt tab` goes. `spec/demo.md`'s pids and `ps`
  sample, `tests/vt.sh`'s arithmetic, and 0025's design in
  `programs.md` follow.
- [x] One `usb-hid`: it claims every boot keyboard and boot mouse, waits
  on their endpoints' ports and on `keyboard`'s and `pointer`'s, and
  serves both. The inittabs start one; `devices.md`'s USB section,
  `programs.md`'s row and `demo.md`'s pids follow. Checked on QEMU by
  the keyboard and pointer screen tests, and on the Pi 5 with a USB
  keyboard and mouse, written in the Log. (On QEMU; the Pi 5's check is
  still to be made, as the Log says.)
- [ ] More of it: look through the servers for others that hold a name
  by a process of their own, poll with `port_try_receive`, or would
  serve better from one process waiting on several ports (`fs`' names
  per volume, `xhci`'s two controllers on RP1, `inet`, `wm`'s clients),
  and either change them here or write each up as a goal of its own.
  The findings go in the Log, each with what was done about it.

## Spec changes

- programs.md: `vt`'s row without relays.
- demo.md: a Terminal's pids without its relays, and the `ps` sample's
  if it shows one.

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
