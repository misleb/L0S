# 0052: A node's ops cut to the node when painted

Track: Toolkit · Status: idea · Needs: – · Spec: toolkit.md

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

To be written: at least, painting cuts every op to a rectangle its node
gives (as `gtk_snapshot_push_clip`), text and images at the pixel; the
grid's own cutting (`ui_cut_across`, `ui_text_cut_onto`) goes; a host
test paints a grid scrolled across by a few pixels and finds an icon
and a character cut at the edge; `tests/files.sh` passes.

## Log

- 2026-10-29: written from 0014's limit, the grid's cutting of its own
  ops when scrolled across.
