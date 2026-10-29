# 0021: An app with many windows, its events told by window

Track: Desktop · Status: done · Needs: – · Spec: desktop.md, toolkit.md, programs.md, testing.md

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

- [x] Notices name their window: `wm` sends each window notice as the tag
  `win`, the window's id as a u32, then the notice as today
  (`l0s.l0`'s `win_notice`; `win_notice_of` reads the id and
  where the inner notice starts, in place, as bytes). The drivers'
  notices to `wm` stay as they are; `wm` wraps them as it forwards
  them, and wraps its own leave, focus and size notices. The toolkit's
  `ui_event_of` unwraps them and takes only its own window's; `vt`
  likewise. No app changes. Tests on both sides, and every screen test
  passes as it is.
- [x] Many windows on one port, in `wm`: what it already allows, a
  second `window` or `csd` from one client naming the port the first
  did, checked and tested (`wm_test.l0`: two windows of one client, a
  key to the front one told with its id, the pointer to the one under
  it), and written into desktop.md's protocol table. `windows` shows
  each window's client's pid, so a test can see two of one client.
- [x] Close asked, not forced: the close button sends the window's
  client a close notice (`win ID` then `clo`), as `xdg_toplevel.close`,
  and kills it only if the window is still open 2 seconds later, on
  wm's alarm, as today's `close_pressed` does at once. The toolkit
  gives an app the close as the action `win.close`; an app that does
  nothing with it is closed by the toolkit, its window first, then,
  as its last, the program, so every app behaves as today. `vt`
  closes on it as on its shell's exit.
- [x] The toolkit's many windows (`window.l0`, or `app.l0` in
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
- [x] Files' New Window: in its menu, beside New Folder..., a window at
  the same folder, each with its own place, selection, view and menus,
  kept in Files' state by window id; `win.close` closes that one, and
  the last ends Files. Files' launcher entry still starts a new Files.
- [x] The screen test and the spec: `tests/files.sh` opens a second
  window from the menu, sends a click to each and sees each change
  alone (`run windows`: two windows, one client), closes the first by
  its close button and sees the second stay; desktop.md's notices and
  close, toolkit.md's `UiApp`, programs.md's Files, testing.md's
  files.sh.

## Spec changes

All moved into the spec: desktop.md (the window notice, many windows
on one port, the close notice and the kill 2 seconds after, `end`,
`windows`' pid), toolkit.md (`UiApp`, `win.close`, `ui_open` as one
window of an app), programs.md (Files' New Window, `uiapp.l0`),
testing.md (`widgets.sh`'s close button, `files.sh`'s second window).

## Log

- 2026-10-27: written.
- 2026-10-28: step 1. The notice is `win_notice`, not `window_notice`:
  `common/abi.l0` already has `window_notice` (the kernel's notice of a
  client's file window to `fs`), and abi.l0 is in every program.
  `win_notice_of` gives a `WinNotice ID AT`, AT the payload's offset of
  the notice inside (7); each reader gained an `_at` form
  (`key_event_at`, `pointer_event_at`, `wheel_event_at`,
  `is_leave_notice_at`, `focus_notice_at`, `size_notice_at`, over
  `tagged_u32s_at`), and the old `X_of` is `X_at` at 0, so the notice
  is read where it is in the message and nothing is sliced to read it.
  `wm` passes a driver's key on with `port_forward_win`, the head and
  the key joined once as bytes; every other notice to a client goes
  through `win_tell` (`told_of`, tested in `wm_test.l0`). The toolkit
  gives a notice of another window, or a bare one, as `UiOther`.
- 2026-10-28: step 2. `wm` needed nothing to allow it: a window keeps
  the PORT its request named and nothing ties one window's port to
  another's, so the check is the tests, `wm_test.l0`'s `one_client`
  (`key_window`, split from `keyed`, and `pointer_target`, each told
  with `told_of`). wm cannot check that PORT is the client's own, since
  no call says who owns a port; a wrong one only loses that client's
  notices, as before. `windows` gives the client's pid last, after
  `front` or `-`, so the screen tests' `read`s gained a trailing `_`
  (`launcher.sh`, `launcher-install.sh`, `vt.sh`), the l0s MCP server's
  parser a `pid`, and the `virtio-gpu` e2e case its vt's pid, 8.
- 2026-10-28: step 3. `wm` keeps the closes it asked in `Wm`'s second
  field, a `Closing` (window, client, when) each, and sets its alarm for
  the soonest (`close_alarm`); at the alarm it kills the client of each
  due window still open and still that client's (`closes_due`,
  `still_open`). An app that does nothing with `win.close` cannot be
  ended by the toolkit from inside it: L0 has no exit but returning
  from `main`, and the kernel answers a process's kill of itself with
  no such process (its slot is out while it calls), and the kernel is
  not this goal's to change. So the toolkit keeps the window as asked to
  close (`UiWin`'s last field, `ui_win_close_asked`), and when the
  program presents it again, having done nothing with it, `ui_present`
  closes it and asks `wm` to `end` the program, a new request that
  kills its asker (`compositor_end`); every app closes at once, as it
  did. One that wants to keep its window calls `ui_win_close_kept`. The
  window's own close button (`UiCsdBar`'s) sets off the same and is
  kept the same, so the two buttons are one path. `vt` needed nothing:
  it already ended on `ui_close_action`. `widgets.sh` gained the title
  bar's close button: the gallery goes before wm's 2 seconds.
- 2026-10-28: step 4, in `user/lib/ui/uiapp.l0`, not `app.l0`, since
  `user/lib/proto/app.l0` has that stem and `make doc Q=` needs each
  library's unique. A `UiApp` is the compositor, the port, one face and
  the `UiWin`s by id (a `Map`). The face is the app's, not each
  window's: every strike is a region kept open (`ui_strike_open`'s
  `dma_open`), eight at load, so a face a window would have cost eight
  regions a window; `ui_app_present` paints a window with the app's face
  and keeps the face it comes back with, so a strike one window asks
  for is the others' too (`ui_app_put` keeps the app's face after a
  route, `ui_app_put_faced` takes the window's after a present). The
  regions: no call says how many a process has open, so `ui_app_regions`
  counts them, a window's buffer each, one for a resize's second buffer,
  and the face's strikes over pages (`ui_face_regions`), and
  `ui_regions_room` keeps 8 of the 64 for the program's own; 48 left
  after the eight strikes is 47 windows, which no app nears. `ui_open`
  is `ui_app_start` and one `ui_app_open_as` (`ui_win_open` makes the
  window, and now gives its buffer back if wm refuses it), so the apps
  of one window did not change. **Where the loop is**, for 0032 and
  0033: `uiapp.l0`'s section "the loop", `ui_app_next` (the receive)
  and `ui_app_event` (what a message is, of which window); 0032's
  `open` request comes in there as a message of no window, today
  `UiAppEvent -1 (UiOther ...)`, and 0033's putting together belongs in
  `ui_app_next`, before `ui_app_event`. An app's step stays its own
  (`fl_loop` in Files), as L0 has no function values to hand the
  toolkit an update with.
- 2026-10-28: step 5. Files is a `UiApp`; its loop (`fl_loop`,
  `fl_stepped`) keeps a `Files` state a window in a `Map` by id and
  hands each window's event to that state alone, the code that changes
  a state (`fl_acted`) as it was. New Window is the menu button's second
  item, after New Folder..., so the screen test's New Folder... stays
  where it was; it opens a window in front at the same place, its view
  kept but nothing selected, open or over it, and no Back (`fl_twin`,
  `fl_at`), as Nautilus's New Window does. `win.close` closes the
  window it came from, and Files returns 0 with its last. The full-color
  icons stay one set, in every window's state, loaded once.
- 2026-10-28: step 6, and done. `files.sh` takes the first window to
  0, 32 and the second to 400, 240, so the first's sidebar and close
  button show beside and above the second, whatever `cascade` gave
  it; a click on each sidebar changes that window alone, the second
  checked again once a press on its sidebar's empty foot brings it
  back; the first's close button leaves the second; the second's ends
  Files. `make check`, `make test` and `make e2e` pass. Left as they
  are, for 0033: a second window's strikes are the app's now, but each
  window still lays out and paints its whole step per message.
