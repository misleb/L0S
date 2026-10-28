# 0031: A process waits on several ports, and lets a name go

Track: Kernel · Status: ready · Needs: – · Spec: syscalls.md, kernel.md, programs.md, devices.md, demo.md, testing.md

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

- [ ] Waiting on several ports: the call, by the system call checklist
  (`l0s-dev`), the next free number (300 on), with its try form, its
  wrapper in `user/lib/sys/l0s.l0` returning the port with the message,
  and `ps`'s detail. The kernel's wait records the list, so a send to
  any of them wakes the process, and a port closed meanwhile is dropped
  from it. Board tests, refusals included.
- [ ] Unregistering a name: the call, its wrapper and its board tests.
  A name's owner exiting still frees it as now.
- [ ] Terminal without relays: `vt` waits on its window's port and a
  port per tab, registers `vtN` on the tab's port, and unregisters it
  as the tab closes; `vt tab` goes. `spec/demo.md`'s pids and `ps`
  sample, `tests/vt.sh`'s arithmetic, and 0025's design in
  `programs.md` follow.
- [ ] One `usb-hid`: it claims every boot keyboard and boot mouse, waits
  on their endpoints' ports and on `keyboard`'s and `pointer`'s, and
  serves both. The inittabs start one; `devices.md`'s USB section,
  `programs.md`'s row and `demo.md`'s pids follow. Checked on QEMU by
  the keyboard and pointer screen tests, and on the Pi 5 with a USB
  keyboard and mouse, written in the Log.
- [ ] More of it: look through the servers for others that hold a name
  by a process of their own, poll with `port_try_receive`, or would
  serve better from one process waiting on several ports (`fs`' names
  per volume, `xhci`'s two controllers on RP1, `inet`, `wm`'s clients),
  and either change them here or write each up as a goal of its own.
  The findings go in the Log, each with what was done about it.

## Spec changes

- syscalls.md: both calls' rows, and what a receive on several ports
  answers.
- kernel.md: a process waiting on several ports, and a name unregistered.
- programs.md: `vt`'s row without relays; `usb-hid`'s row, one process
  serving both.
- devices.md: USB's diagram and text, one `usb-hid`.
- demo.md: the pids and the `ps` sample.
- testing.md: the new board tests.

## Log

- 2026-10-28: written, after 0025's tabs needed a relay process each to
  hold and let go of a name. The user had already meant to make one
  `usb-hid` of the keyboard's and the mouse's. When it is taken up, look
  for more such places (the last step).
