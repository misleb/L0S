# 0051: `wm` takes input on a port of its own, ahead of requests

Track: Desktop · Status: idea · Needs: – · Spec: desktop.md, programs.md

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

To be written: at least, `wm` listens to `keyboard` and `pointer` on a
port of its own beside `compositor`'s and waits on both as a set; what
may pass what is written in `desktop.md`; `tests/vt.sh`,
`tests/responsive.sh` and `tests/usb.sh` pass.

## Log

- 2026-10-29: written from 0034's step 7, which judged it a design of
  its own rather than a change of a few lines, while 0008 changes `wm`.
