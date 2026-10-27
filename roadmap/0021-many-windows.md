# 0021: An app with many windows, its events told by window

Track: Desktop · Status: ready · Needs: – · Spec: desktop.md, toolkit.md, programs.md, testing.md

## Why

A program opens one window. `wm`'s protocol does let a client ask
`window` or `csd` more than once, each with a PORT its events go to, but
nothing a window is told says which window it is about: a key, a
pointer event, the wheel, a leave, a focus or a size notice is the
input driver's payload as it came, or wm's own, with no window in it
(`l0s.l0`'s `key_notice`, `pointer_notice`, `size_notice` and the rest).
So a client that wants two windows must give each its own port and wait
on each, which a program that waits with `port_receive` on one port
cannot. The toolkit is built on that: a `UiWin` is one window with its
own port, and an app's loop receives on it.

And the close button kills the window's client (`close_pressed`), which
with two windows would take both.

Wayland names the surface in every event (`wl_pointer.enter`'s surface,
`xdg_toplevel.configure` and `close` on the toplevel), and a GTK app
keeps many windows on one connection. This goal does the same: every
notice `wm` sends a client names the window, a client may have many on
one port, the close button asks the client to close that window, and
the toolkit lets an app open, route and close windows by id.

## Done when

- Every notice `wm` sends a client's window carries that window's id,
  and a client may give all its windows one port.
- The close button asks the client to close that window, as
  `xdg_toplevel.close`; a client that has not closed it within 2
  seconds is killed, as today.
- The toolkit opens any number of windows on one port, gives the app
  each event with the id of its window, presents and closes each by its
  id, and a single-window app needs no change.
- Files has New Window in its menu; each window browses on its own, and
  closing the last ends Files. `tests/files.sh` opens a second window,
  sends each a click that goes to it alone, and closes one, leaving the
  other. `make check`, `make test` and `make e2e` pass.

## Steps

- [ ] Notices name their window: `wm` sends each window notice as the tag
  `win`, the window's id as a u32, then the notice as today
  (`l0s.l0`'s `window_notice`; `window_notice_of` reads the id and
  where the inner notice starts, in place, as bytes). The drivers'
  notices to `wm` stay as they are; `wm` wraps them as it forwards
  them, and wraps its own leave, focus and size notices. The toolkit's
  `ui_event_of` unwraps them and takes only its own window's; `vt`
  likewise. No app changes. Tests on both sides, and every screen test
  passes as it is.
- [ ] Many windows on one port, in `wm`: what it already allows, a
  second `window` or `csd` from one client naming the port the first
  did, checked and tested (`wm_test.l0`: two windows of one client, a
  key to the front one told with its id, the pointer to the one under
  it), and written into desktop.md's protocol table. `windows` shows
  each window's client's pid, so a test can see two of one client.
- [ ] Close asked, not forced: the close button sends the window's
  client a close notice (`win ID` then `clo`), as `xdg_toplevel.close`,
  and kills it only if the window is still open 2 seconds later, on
  wm's alarm, as today's `close_pressed` does at once. The toolkit
  gives an app the close as the action `win.close`; an app that does
  nothing with it is closed by the toolkit, its window first, then,
  as its last, the program, so every app behaves as today. `vt`
  closes on it as on its shell's exit.
- [ ] The toolkit's many windows (`window.l0`, or `app.l0` in
  `user/lib/ui` beside it): a `UiApp`, the port and its `UiWin`s by
  id; `ui_app_open` and `ui_app_open_csd` open one more on the app's
  port; `ui_app_event` takes a message to `(UiAppEvent ID EVENT)`, the
  window's id and the event `ui_event_of` makes of it, and the routing
  and presenting stay `ui_route` and `ui_present` on that window, put
  back into the `UiApp` by id; `ui_app_close` closes one. `ui_open`
  stays, as a `UiApp` of one window underneath, so `widgets`,
  `procmon` and Disks need no change. Every region a window takes
  counts against the process's 64 (`l0s-dev`'s pitfalls): `ui_app_open`
  refuses a window past what is left, and says so. Tested on the host
  with two windows' events and their damage kept apart.
- [ ] Files' New Window: in its menu, beside New Folder..., a window at
  the same folder, each with its own place, selection, view and menus,
  kept in Files' state by window id; `win.close` closes that one, and
  the last ends Files. Files' launcher entry still starts a new Files.
- [ ] The screen test and the spec: `tests/files.sh` opens a second
  window from the menu, sends a click to each and sees each change
  alone (`run windows`: two windows, one client), closes the first by
  its close button and sees the second stay; desktop.md's notices and
  close, toolkit.md's `UiApp`, programs.md's Files, testing.md's
  files.sh.

## Spec changes

- desktop.md: the window notice, `win ID` before every notice to a
  client; many windows of one client on one port; the close button's
  close notice, and the kill 2 seconds after; `windows`' client pid.
- toolkit.md: `UiApp` and its calls, and the `win.close` action;
  `ui_open` as one window of them.
- programs.md: Files' New Window.
- testing.md: files.sh's second window.

## Log

- 2026-10-27: written.
