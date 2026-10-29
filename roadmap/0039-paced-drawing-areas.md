# 0039: Drawing areas paced too, and a resize that overlaps the restack

Track: Toolkit · Status: idea · Needs: – · Spec: toolkit.md, desktop.md

## Why

Goal [0006](0006-paced-display-queue.md) paced toolkit windows and gave
them two buffers, with two limits it left
([toolkit.md, Limits](../spec/toolkit.md#limits)):

- A window whose program paints a drawing area itself, `vt`'s terminal,
  is painted in the buffer the screen shows, unpaced, so a frame can
  still show it half painted. Its program paints the area between
  presents, through `ui_win_canvas`, and tells `wm` with
  `ui_win_damaged`, and keeps a copy of the canvas to tell when it
  changes; with two buffers it would paint the one not shown, and the
  toolkit would copy the area over as it copies the rest.
- With two buffers a window paints the next size of a drag only once
  the restack that showed the last has released the other buffer, where
  with one it painted while `wm` restacked: a drag of Disks's edge
  showed 133 sizes where it had shown 159 in the same drag on QEMU.
  A third buffer, as Mesa's Wayland clients keep when they must, would
  let it paint while the restack runs.

## Log

- 2026-10-29: written from 0006's step 4.
