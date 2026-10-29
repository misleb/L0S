# 0034: Servers that wait for their time and their ports, not poll

Track: Kernel · Status: idea · Needs: – · Spec: programs.md, network.md, storage.md, demo.md

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

## Log

- 2026-10-28: written from 0031's last step, its survey of the servers.
