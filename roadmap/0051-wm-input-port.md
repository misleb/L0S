# 0051: `wm` takes input on a port of its own

Track: Desktop · Status: done · Needs: – · Spec: desktop.md, programs.md

## Why

Split from [0034](0034-servers-wait-not-poll.md), whose last step it
was. `wm` takes every client's request, the keyboard's and pointer's
notices, the clock's and the display's on one port, and puts pointer
moves together with `port_try_receive` (`took`, `gathered`). A port for
input apart from the requests, waited on with them as a set
(`port_receive_set`), was to let it favour input. It is not the small
change it looks:

- A set gives the oldest message across its ports first, so two ports
  alone change no order: input is favoured only if `wm` drains the input
  port before the set (a `port_try_receive` on it first, or a
  `port_try_receive_set` and a sort), and then input passes requests
  that came before it.
- Requests and input are not independent. A client's `top`, `close` or
  a new window changes where a key goes and what a click hits; a key
  typed after a window was raised, handled before the raise, goes to
  the old front window. Which of them may pass which needs deciding,
  window by window, and testing on the screen.
- Gathering moves (`gathered`) would read the input port alone, and a
  press or a wheel's turn would still have to stop it, as now.
- A port's queue holds 32 messages, so a flood of requests can today
  fill the one port and make the input drivers' notices `SendFull`;
  with a port of its own input is never crowded out. That much is a
  clear gain on its own.

So: measure first whether input waits behind requests at all (a pointer
move's time from `usb-hid` or `virtio-input` to the display's
`cursor`, with several busy clients), then decide.

## Done when

- How long a pointer move waits is measured, idle and with busy
  clients, and written here.
- `wm` listens to `keyboard` and `pointer` on a port of its own beside
  `compositor`'s, and waits on both as a set (`port_receive_set`),
  gathering moves from the set (`port_try_receive_set`) as before.
- Since the measurement shows no move waiting behind requests, input
  passes none: the set's order, the oldest first, is kept, and
  `desktop.md` says so, and why.
- `make check` and `make test` pass, and `tests/vt.sh`,
  `tests/responsive.sh` and `tests/usb.sh`.

## Steps

- [x] 1. Measure: a move's time from `usb-hid`'s notice to `wm`'s
  `display_move` done, idle and busy.
- [x] 2. `wm`'s input on a port of its own, the two a set; the clock's
  replies no longer skip input, which no longer comes on their port.
- [x] 3. `desktop.md` and `programs.md` say so.

## Spec changes

All moved into the spec.

## Log

- 2026-10-29: written from 0034's step 7, which judged it a design of
  its own rather than a change of a few lines, while 0008 changes `wm`.
- 2026-11-05: measured on QEMU with `tests/vt.sh`'s boot, on a USB
  mouse, 100 moves 10 ms apart in each phase, stamped (`clock_ns`, in
  the kernel's log, since removed) as `usb-hid` sent each notice and as
  `wm`'s `display_move` returned:

  | Phase | 1 CPU: p50, p90, max | 4 CPUs: p50, p90, max |
  |---|---|---|
  | No client busy | 3.3, 4.5, 14.7 ms | 3.5, 4.4, 23.7 ms |
  | A Terminal printing a font file | 3.7, 4.3, 5.4 ms | 3.4, 4.4, 4.6 ms |
  | Then System Monitor and Widgets too | 3.5, 4.3, 39.9 ms | 3.0, 4.5, 27.0 ms |

  Nearly all of it is the display's `move`, which `wm` waits for; the
  rare long one comes as often idle as busy. No move waits behind
  requests, so favouring input would buy nothing and cost the order
  of a key after a raise. Done as the set alone, which keeps the
  order and gives input room of its own. A first try sent the moves
  through `tools/qsock`, which reads all its input before sending any,
  so QEMU joined them into a few reports: a measurement of moves must
  send each as it is due. The title, "ahead of requests" until now,
  drops that.
