# 0007: Source viewports and subsurfaces

Track: Display · Status: idea · Needs: – · Spec: display.md, desktop.md

## Why

The toolkit's former "Later" list, item 1 (`wp_viewporter`,
`wl_subsurface`). With them, a grid's body could scroll as a ring under a
header that stays still, and all title bars could share one atlas buffer,
easing the 64-region limit that caps `wm` at 60 windows
([desktop.md, Limits](../spec/desktop.md#limits)).

## Done when

- A layer can show a source rectangle of its buffer.
- A client can place a child surface within its window.
- The title bars share one buffer.

## Steps

To be written.

## Spec changes

- display.md: the new requests.
- desktop.md: the window limit, raised.

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
