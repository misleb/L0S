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
- [ ] Requests in flight: commands go into the control queue as they
  come, up to the ring's room, each display request's reply sent once
  its last command is answered, while the driver goes on taking
  requests; the cursor queue likewise. Replies keep their requests'
  order. Pure bookkeeping of what is in flight and what each reply
  awaits, tested on the host.
- [ ] Frame notices in the display protocol: `frames PORT` asks the
  driver to tell PORT `frame N` after each frame that showed a change,
  N counting from 1; virtio-gpu tells it when a `RESOURCE_FLUSH` (2D)
  or the flush after a `SUBMIT_3D` (3D) is answered. `display.l0` reads
  the notice. `wm` asks for them, and its wm protocol gains `frame ID`:
  a client asks once per change, and `wm` sends it a frame notice when
  the display's next frame after that window's damage is told, as
  `wl_surface.frame`'s done does.
- [ ] Paced, double-buffered toolkit windows: `ui_present` asks `frame`
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
- [ ] The screen test: a window's frames told and its buffers swapped,
  `run windows` saying which buffer each window shows; the Disks drag
  timed against today's; the limit goes from desktop.md, and
  toolkit.md says how `ui_present` paces itself.

## Spec changes

- display.md: the display protocol's `frames` and its `frame N` and
  `release` notices; virtio-gpu's queue in flight; and in the Pi 5's
  section, when `hvs` sends them.
- desktop.md: the wm protocol's `frame ID` and `attach`; the "shown half
  painted" limit goes.
- toolkit.md: how `ui_present` paces itself, and a window's two
  buffers.

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
