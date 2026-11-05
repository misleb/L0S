# 0052: A node's ops cut to the node when painted

Track: Toolkit · Status: done · Needs: – · Spec: toolkit.md

## Why

Since [0014](0014-wheel-across.md) the grid scrolls across, and since a
node's ops are not cut to the node when painted, the grid cuts its own
to its edges ([toolkit.md, Limits](../spec/toolkit.md#limits)): a fill
to its part inside, a text to its characters wholly inside, and an
icon, image, level bar or status dot only if all of it is inside. So a
cell's text at the edge loses a character at a time and its icon or bar
goes whole, where GTK's scrolled window cuts them at the pixel. Any
other widget that scrolls across, or draws past its bounds, would need
cutting of its own as well.

## Done when

- Painting cuts every node's ops to the node's rectangle, as
  `gtk_snapshot_push_clip` cuts a widget's, text and images at the
  pixel (`ui_paint_nodes`).
- No widget paints past its node: a host test helper finds any op that
  reaches past its node (`ui_ops_past`), and the slider's focus ring,
  which did, is in its node.
- The grid's own cutting (`ui_cut_across`, `ui_text_cut_onto`) goes.
- Damage is diffed from the ops as cut, so a grid scrolled across still
  moves its rows when scrolled down, rather than damaging the cells at
  its edges.
- A host test paints a grid scrolled across by a few pixels and finds
  an icon and a character cut at the edge.
- `make check` and `make test` pass, and `tests/files.sh` and
  `tests/widgets.sh`.

## Steps

- [x] 1. `ui_paint_nodes` paints each node's ops cut to the node and the
  damage; the slider's node holds its ring (`ui_scale_ring`).
- [x] 2. The grid lays its cells out uncut, and `ui_cut_across` and the
  rest go.
- [x] 3. Damage and scrolling compare each op with what of it is in its
  node (`UiCutOp`); `ui_op_rect` moves to `paint.l0`.
- [x] 4. Host tests: the grid's icon and character cut at its edges
  (`paint_test`), a grid scrolled across and down (`window_test`), the
  slider's ring (`controls_test`).

## Spec changes

All moved into the spec.

## Log

- 2026-10-29: written from 0014's limit, the grid's cutting of its own
  ops when scrolled across.
- 2026-11-05: done. Every app's preview scenes were swept for ops past
  their node: none, but the slider's focus ring, 2 past its node when
  the knob is at an end and focused (no preview focuses). Its node is
  now the slider and the ring, so `widgets_test` pins it 2 larger each
  way; the slider itself is where it was. The boxed list still shows
  whole rows only, since it scrolls by rows.
