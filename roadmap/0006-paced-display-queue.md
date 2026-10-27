# 0006: A paced, pipelined display queue

Track: Display · Status: idea · Needs: – · Spec: display.md, toolkit.md

## Why

A client paints into the buffer the screen shows, so a frame can be shown
half painted ([desktop.md, Limits](../spec/desktop.md#limits)), and
nothing tells it when to paint next. The toolkit's former "Later" list,
item 2: an interrupt-driven, pipelined virtio queue, with frame and
buffer-release callbacks, so clients can pace themselves and double-buffer.

## Done when

- `virtio-gpu` takes its queue's interrupts and keeps more than one
  request in flight.
- A client can ask to be told when a frame is shown, and when a buffer is
  released, as `wl_surface.frame` and `wl_buffer.release` do.

## Steps

To be written.

## Spec changes

- display.md: the display protocol's frame and release notices.
- toolkit.md: how `ui_present` paces itself.
- desktop.md: the "shown half painted" limit goes.

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
