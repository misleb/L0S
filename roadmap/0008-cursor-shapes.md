# 0008: A cursor set and cursor shapes

Track: Display · Status: idea · Needs: – · Spec: display.md, desktop.md, toolkit.md

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

To be written.

## Spec changes

- display.md and desktop.md: the cursor set, and the request for a shape.
- toolkit.md: the shape over an entry.

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
