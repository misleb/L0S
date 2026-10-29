# 0006: A paced, pipelined display queue

Track: Display · Status: active · Needs: 0005 · Spec: display.md, desktop.md, toolkit.md

## Why

A client paints into the buffer the screen shows, so a frame can be shown
half painted ([desktop.md, Limits](../spec/desktop.md#limits)), and
nothing tells it when to paint next. The toolkit's former "Later" list,
item 2: an interrupt-driven, pipelined virtio queue, with frame and
buffer-release callbacks, so clients can pace themselves and double-buffer.

Today `virtio-gpu` makes one request at a time and spins on the used
ring until it is answered (`virtq_wait`), and every display request is
answered only once its commands are; `wm` waits on each in turn, and a
toolkit client paints its next change whenever its last `damage` is
answered, not when the screen showed it.

The notices are the display protocol's, which `hvs` serves too, so they
are not virtio-gpu's alone: on the Pi 5 a frame is shown when the HVS
ends it, and `hvs` can tell that only from its end-of-frame interrupts,
goal [0005](0005-hvs-frame-interrupts.md). The pipelined queue is
virtio-gpu's own; `hvs` has none, its `damage` only a cache clean.

## Done when

- `virtio-gpu` takes its queue's interrupts and keeps more than one
  request in flight.
- A client can ask to be told when a frame is shown, and when a buffer is
  released, as `wl_surface.frame` and `wl_buffer.release` do, from
  `virtio-gpu` and from `hvs` alike, `hvs` telling them at the end of
  the frame that showed them.
- A toolkit window paints into a buffer the screen does not show, and
  paints at most once a frame: the "shown half painted" limit goes.
- A screen test shows a window's frames told and its buffers swapped,
  and a drag of Disks's edge is no slower than today's 7 ms a size and
  9 ms a restack on QEMU; `make e2e` passes.

## Steps

Steps 1 to 4 are QEMU's alone; step 5 is the one that needs 0005.

- [x] `virtio-gpu` waits by its interrupt: it binds the virtio-mmio
  transport's interrupt (`irq_bind`, its `dev` line already there) to a
  port of its own and receives on it in place of spinning in
  `virtq_wait`, acknowledging the device's interrupt status. One
  request in flight still; the same answers, timed against today's
  restack.
- [x] Requests in flight: commands go into the control queue as they
  come, up to the ring's room, each display request's reply sent once
  its last command is answered, while the driver goes on taking
  requests; the cursor queue likewise. Replies keep their requests'
  order. Pure bookkeeping of what is in flight and what each reply
  awaits, tested on the host.
- [x] Frame notices in the display protocol: `frames PORT` asks the
  driver to tell PORT `frame N` after each frame that showed a change,
  N counting from 1; virtio-gpu tells it when a `RESOURCE_FLUSH` (2D)
  or the flush after a `SUBMIT_3D` (3D) is answered. `display.l0` reads
  the notice. `wm` asks for them, and its wm protocol gains `frame ID`:
  a client asks once per change, and `wm` sends it a frame notice when
  the display's next frame after that window's damage is told, as
  `wl_surface.frame`'s done does.
- [x] Paced, double-buffered toolkit windows: `ui_present` asks `frame`
  with each change, and paints no more until it is told, keeping what
  changed meanwhile for the next. A window has two buffers, as
  `UiSwap` already makes during a resize; it paints into the one not
  shown, gives it to `wm` (`attach ID VA N S`, the wm protocol's, a
  new request), and paints the other only once the display's
  `release` notice says it is no longer read: in 2D mode once its
  transfer is answered, in 3D mode once its texture has it. The pixels
  changed since the other was shown are copied over first, so only
  what changed is painted, as now. `widgets`, `procmon`, Files and
  Disks need no code.
- [ ] `hvs` tells frames and releases (needs 0005): `frame N` at the
  end of each frame 0005's bookkeeping says showed a change, and
  `release` once a list that no longer names a buffer is taken, since
  the HVS reads every pixel of a buffer it shows every frame.
- [x] The screen test: a window's frames told and its buffers swapped,
  `run windows` saying which buffer each window shows; the Disks drag
  timed against today's; the limit goes from desktop.md, and
  toolkit.md says how `ui_present` paces itself.

## Spec changes

- display.md: the Pi 5's "Frames and releases", written with step 5's
  code, says what a board showed of them, in place of "not yet run on
  a board".

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
- 2026-10-27: the notices are the protocol's, so `hvs` sends them too,
  from the end-of-frame interrupts of 0005, which it now needs.
- 2026-10-27: steps written, QEMU's first and `hvs`'s fifth, the only
  one that needs 0005.
- 2026-10-29: active. Measured first, on this host's QEMU (4 CPUs, 2D,
  1280×800), with temporary timing lines in `wm` and the toolkit and a
  script dragging Disks's right edge 240 pixels in and out twice, 6 at a
  step 30 ms apart, then its header bar: a size's step in Disks, from
  its start to its painting's end, median 12.6 ms; the restack after a
  size, `wm`'s `layers` asked and answered, 12.1 ms; a move drag's
  restack 20.9 ms. The goal's 7 and 9 ms were measured on another
  machine; these are the ones each step is held to here.
- 2026-10-29: step 1. `virtio-gpu` binds its transport's interrupt and
  receives on it in `gpu_wait`, for the control queue and the cursor
  queue alike, in place of `virtq_wait`'s yields and sleeps; one
  request in flight still. Timed again: a size 12.5 ms, its restack
  11.5, a move's restack 20.0, so no slower.
- 2026-10-29: step 2. `flight.l0` keeps what is in flight, pure and
  tested on the host: each command's chain from a ring of the 64
  descriptors, its request in a ring over the 62 request pages, its
  response in a 64-byte slot by its first descriptor; commands retired
  in the order made, whatever order they are used in; replies waiting,
  each for the last command made before it on both queues. The device is
  told once a request is handled, so a damage of five boxes is ten
  commands and one notify. The driver waits on `display` and its
  interrupt port as a set. What could not stay asynchronous: the
  startup's commands, whose answers decide what it does (`send_now`); a
  new cursor image, which the cursor queue's update must not overtake;
  and giving up the wallpaper's pages, which waits for every command.
  Timed: a size 12.6 ms, its restack 11.4, a move's restack 18.3. `wm`
  still waits for each reply, so the gain is within a request. The
  first `make e2e` caught the first frame never shown: its commands
  were made before any request, so nothing told the device of them;
  the driver now tells it as it starts serving.
- 2026-10-29: step 3. The notices are binary, as every other notice
  is: `frame N` is `frm` and N, `release ID` is `rel` and ID, each a
  u32 (`l0s.l0`'s `shown_notice` and `release_notice`, so `wm` sends a
  client the same `frm` as a window notice); `frames PORT` and `frame
  ID` are text requests, as the protocols' others are. `virtio-gpu`
  counts a frame for every `damage` and `layers`, not only those that
  flushed something: a damage under another window shows nothing, and
  a client waiting for its frame would wait for someone else's change.
  `release` came with this step rather than the next, as it is a
  notice of the same request: a buffer is released once the `layers`
  that left it out is answered. A client asks `frame` before its
  `damage`, as Wayland's frame comes before its commit: asked after,
  the frame `wm` tells may already have gone by. Both notices go
  before the reply, so `wm`, which waits on the reply, finds them next.
- 2026-10-29: step 4, with three changes to its design. `attach ID VA
  N S` does not show the buffer at once: it is shown at the next
  `damage`, which commits it, as Wayland's attach waits for a commit,
  since in 3D mode the buffer's texture must take what changed before
  it is composed. A window's content has a bank of its own, which a
  commit flips, apart from the chrome's, which only a resize flips with
  it; the buffer given up keeps its id, so the next attach gives the
  display nothing new unless the size changed. And a window with a
  drawing area, `vt`'s, stays in one buffer, unpaced: its program
  paints the area between presents, into the canvas it is given, and
  tells `wm` itself; goal 0039 takes that on, so the "shown half
  painted" limit is gone for every other window, not for `vt`'s
  terminal. `wm` tells a client a release as `rel` and 0. A window
  waits no longer than 100 ms for a frame or a release. Timed: a size
  13.2 ms (12.6 before 0006), its restack 11.4 (12.1), a move's restack
  19.5 (20.9). The size is half a millisecond slower: the copy over of
  what the buffer painted lacks, 0.58 ms median, measured; reading the
  box's rows in one span instead was slower, 1.8 ms. And a drag shows
  fewer sizes, 133 where 159 were shown in the same scripted drag, as
  the window paints the next only once the restack released the other
  buffer; a third buffer would overlap them again (0039).
- 2026-10-29: step 6. `run windows` ends each window's line with
  `buffer B frames F`, the display's id of the content it shows and the
  frames `wm` has told its client, and `tests/widgets.sh` checks that
  each of two Tabs shows the gallery from its other buffer (6, 4, 6)
  and tells a frame (3, 4, 5). The test is in `widgets.sh`, not a
  script of its own, as the gallery's Tabs are one change each. The
  Disks drag was timed by a script kept out of the tree, as a timing
  that varies with the host makes a poor pass or fail: the numbers are
  in step 4's line above. The limit went from desktop.md, and
  toolkit.md says how `ui_present` paces itself, with step 4. `launch.sh`
  and `files.sh` (which the first `make e2e` caught reading the pid as
  the line's last word), the `virtio-gpu` e2e case and the MCP server's
  `parse_windows` read the longer lines.
- 2026-10-29: step 5's code, not run on a board, so the step stays
  open. `hvs` answers `frames PORT`; `shown.l0` notes with each list
  switched the buffers it leaves out (`changes_releasing`), and at each
  end of frame says what it showed (`changes_shown`): the frame's
  number among those that showed a change, and the buffers released,
  which `frames.l0`'s `frames_taken` tells, releases first. Polling,
  with no end of frame, it tells at once. `layers_left` moved to
  `display_server.l0`, shared with `virtio-gpu`. Host-tested
  (`shown_test.l0`, `frames_test.l0`). To check on the board: with
  the desktop up, open Widgets and move the pointer over its buttons:
  each hover shows at once, not 100 ms late, and `run windows` shows
  the gallery's `buffer` flipping between its two ids and `frames`
  growing with each change; `dmesg` shows no `refused:` from `hvs` and
  the every-600th-frame line still `0 pending`; and a drag of a
  window's edge shows no torn window.
