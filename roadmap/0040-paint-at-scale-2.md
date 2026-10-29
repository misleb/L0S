# 0040: Painting at scale 2 as fast as at scale 1

Track: Toolkit · Status: idea · Needs: – · Spec: toolkit.md

## Why

At scale 2 every window has four times the pixels, and the toolkit
paints each of them. Seen in roadmap 0006's board run on a Pi 5 at
3840×2160: Files painted 5 to 36 ms a step, once 181 ms, and Widgets
once 149 ms, where at 1920×1080 the same steps paint in a few ms. The
desktop felt sluggish with five windows open, alongside 0038's stalls.

## Done when

To be written: at least, a step's paint at scale 2 within a frame for
the apps' usual changes, timed on the Pi 5 by the `slow step` lines.

## Steps

To be written. First: which of a step's paint is fills, text and
icons at scale 2, from the `slow step` lines and a timing of each.

## Spec changes

- toolkit.md: how a window paints at scale 2.

## Log

- 2026-10-29: written from 0006's board run at 4K.
- 2026-10-29: after 0038's step 3 took out the 1.2 s stall, the user
  at 4K: moving windows and widgets responsive, resizing and scrolling
  large views still a little choppy.
