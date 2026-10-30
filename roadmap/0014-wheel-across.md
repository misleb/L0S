# 0014: Scrolling by the wheel across

Track: Toolkit · Status: done · Needs: – · Spec: toolkit.md, testing.md

## Why

The driver reports the wheel across, but it scrolls nothing yet
([toolkit.md, Limits](../spec/toolkit.md#limits)). A grid whose columns
are wider than it is cuts them off at its right edge, with no way to
see the rest, and Files' preview of a text file cuts every long line
short with `...`.

## Done when

- A scroller that is wider than it shows scrolls across by the wheel:
  the grid, when its columns add up to more than its width, scrolls
  across by the wheel's steps across, `ui_wheel_across` pixels a step,
  over its rows or its header, with an overlay scrollbar along its
  bottom whose slider says where, and drags, as the one down its right
  does.
- Files' preview of a file is as wide as its longest line, so a long
  line is scrolled to rather than cut short.
- `grid_test`, `widget_test` and `window_test` cover the layout, the
  actions and the routing, the wheel across included, on the host;
  `tests/files.sh` shows a preview of a long line with the scrollbar
  across and drags its slider across. QEMU's tablet sends no wheel
  across, so no screen test can turn it.
- `make check` and `make test` pass, and the screen tests of the grid
  (`files.sh`, `widgets.sh`, `procmon.sh`, `resize.sh`).

## Steps

- [x] The toolkit: a scroller's area across, `NAME.across.LEFT.MOST`,
  and its strip along the bottom, `NAME.acrossbar.LEFT.MOST.SPAN.SLIDER`,
  which `ui_route` reads for the wheel across and for a drag of the
  slider, setting off `NAME.acrossto.N`; the grid keeps how far across
  it is scrolled in `UiGridState`, lays its header and cells out that
  far to the left, cut to its edges, and draws the slider when its
  columns are wider than it. Host tests.
- [x] Files' preview is as wide as its longest line, and a grid asks
  its box for only 40 a column across, so the preview is laid out at
  the pane's width and scrolls; `tests/files.sh` drags the slider
  across over a preview of a long line.

## Spec changes

All moved into the spec.

## Log

- 2026-10-26: written from toolkit.md's Limits.
- 2026-10-29: steps written; the grid is the scroller that can be wider
  than it shows, and Files' preview the place it matters.
- 2026-10-29: step 1 landed: `UiGridState` has a fifth field, how far
  across; the grid cuts its ops to its edges itself (`ui_cut_across`),
  since a node's ops are not cut to the node when painted, so a text
  at the edge is cut by whole characters and an icon or level bar
  shows only whole (toolkit.md, Limits).
- 2026-10-29: step 2 landed. On the board the preview first laid out
  as wide as its column, 898, since a grid asked its columns' widths
  of the box it is in; it now asks 40 a column, as GTK's scrolled
  window does. QEMU 11.1's virtio tablet sends nothing for QMP's
  `wheel-left` and `wheel-right` (seen at `virtio-input`), so
  `files.sh` drags the slider instead. Done.
