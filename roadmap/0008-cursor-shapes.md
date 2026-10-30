# 0008: A cursor set and cursor shapes

Track: Display · Status: done · Needs: – · Spec: display.md, desktop.md, toolkit.md

## Why

The toolkit's former "Later" list, item 3: a cursor set and
`wp_cursor_shape`, such as an I-beam over text, switched with one
`UPDATE_CURSOR`. Today the pointer's image is painted again and given to
the display whenever it changes between the arrow and a resize pointer
([desktop.md, Limits](../spec/desktop.md#limits)). And a client cannot
ask for one, so the inside of a client-decorated window's edge, which
resizes it, shows the arrow until it is pressed.

## Done when

- The cursors are made once, and switching costs one `UPDATE_CURSOR`.
- A client can ask for a shape by name, and an entry shows an I-beam.
- The inside of a CSD window's edge shows the resize pointer of its
  edges, as the border outside does.

## Steps

- [x] The display keeps a cursor set: `virtio-gpu` makes a cursor
  resource of a buffer the first time `cursor` names it and keeps it, so
  `cursor` of a buffer it has is one `UPDATE_CURSOR`; `forget` gives the
  resource up. (`hvs` already shows the pointer as a plane over the
  buffer, so a switch there is one list written.)
- [x] `wm` makes its pointers once, at start, in one region: the arrow,
  the four resize pointers, and an I-beam, `text`, new in the toolkit's
  art and `fonts/cursors.paths`; switching is one `cursor` request.
- [x] `cursor ID NAME` in the compositor protocol: the shape a client
  asks for its window, shown while the pointer is in its content.
- [x] The toolkit asks for the shape under the pointer as it moves: the
  I-beam over an entry, and the resize pointer of its edges inside a
  client-decorated window's edge; else the arrow.
- [x] A screen test shows the I-beam over an entry and the resize
  pointer inside a client-decorated window's edge.

## Spec changes

All moved into the spec.

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
- 2026-10-29: steps written and all done. `virtio-gpu` keeps a cursor
  set: `Cursor` maps each buffer `cursor` has named to a resource of
  its own, 4 to 15 (12 at most), made, backed and transferred the first
  time, so naming it again is one `UPDATE_CURSOR` and nothing on the
  control queue; `forget` detaches and unreferences it, in 2D and 3D
  mode, and `buffer` refuses to give such an id again until it is
  forgotten. `hvs` needed no change: its pointer is a plane over the
  buffer, so a switch was one list written already. `wm` paints its six
  pointers (`ui_cursor_names`: the arrow, the new I-beam `text`, the
  four resize pointers) once at start into one region, 64 rows each
  (`ui_paint_cursor_at`), and gives each as a buffer of its own 4 pages
  (`pointer_id`: 1, then 100001 on), keeping a region for windows;
  `pointer_shaped` only asks `cursor`. The I-beam is 1x art in
  `ui_cursor_art` and `cursor text` in `fonts/cursors.paths`, hot spot
  5, 10. `cursor ID NAME` in the compositor protocol keeps, in `Ptr`, the
  pointer each window's client asked for over its content, shown at
  once; `windows` names it. The toolkit's `ui_route` asks it on a
  motion when the pointer it wants differs from the one `UiWin` last
  asked (`ui_pointer_at`): the resize pointer inside a CSD window's edge
  (`ui_csd_edges`, `ui_edges_pointer`), the I-beam over an entry, else
  the arrow. `tests/files.sh` checks `ew-resize` inside Files's right
  edge, `nesw-resize` inside its bottom left corner, the arrow inside,
  and `text` over the New Folder dialog's entry. 3D mode's cursor set
  is the same code as 2D's but no screen test runs the GL device.
  Done.
