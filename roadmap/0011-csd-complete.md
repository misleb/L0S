# 0011: Client-side decorations: maximize and resize

Track: Desktop · Status: ready · Needs: – · Spec: desktop.md, toolkit.md

## Why

A window that draws its own header bars, such as Files, can be moved by
them (`move ID`, as `xdg_toplevel.move`), but isn't maximized by a double
click on its header bar ([desktop.md, Limits](../spec/desktop.md#limits)),
and can't be resized from inside its own edge. These were the toolkit
README's "Still to do" for client-side decorations.

## Done when

- A double click on a `UiCsdBar`'s ground maximizes the window, and
  another restores it.
- A press inside a CSD window's edge resizes it, as `xdg_toplevel.resize`.
- `tests/files.sh` covers both.

## Steps

- [ ] Maximize and restore by a double click on the header bar.
- [ ] A `resize` request from the client, started from inside its edge.

## Spec changes

- desktop.md: the compositor protocol's new request, and the Files limit
  loses "is not maximized by a double click".
- toolkit.md: `UiCsdBar`'s double click and edge.

## Log

- 2026-10-26: written from the toolkit README's "Still to do".
