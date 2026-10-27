# 0010: Output events for mode changes

Track: Display · Status: idea · Needs: – · Spec: display.md, desktop.md

## Why

The toolkit's former "Later" list, item 5. The screen's size and scale are
learned once, by `info`, so nothing follows a change of mode.

## Done when

- The display driver tells the compositor when the mode changes, and the
  compositor lays the desktop out again.

## Steps

To be written.

## Spec changes

- display.md: the notice.
- desktop.md: what `wm` does with it.

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
