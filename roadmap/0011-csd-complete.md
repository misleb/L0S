# 0011: Client-side decorations: maximize and resize

Track: Desktop · Status: done · Needs: – · Spec: desktop.md, toolkit.md

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

- [x] Maximize and restore by a double click on the header bar.
- [x] A `resize` request from the client, started from inside its edge.
- [x] A double click on a title bar `wm` draws maximizes and restores
  that window too, by the same code as `maximize`.

## Spec changes

All moved into the spec.

## Log

- 2026-10-26: written from the toolkit README's "Still to do".
- 2026-10-26: `maximize ID` in the compositor protocol: `wm` keeps the
  place and size to restore in the window's `Sizing`, asks the client
  for the size by a size notice, and places it once it answers. The
  toolkit asks it on the second press of a double click on a `UiCsdBar`'s
  ground, the press told as the click since `wm` takes its release.
  `tests/files.sh` maximizes Files to 1280x768 at 0, 32 and restores it;
  its `dbl` now sends its four button events on one QMP connection,
  since four `nc -w 1` calls had stretched past 400 ms and its double
  click on a file had failed before this change too. Moved into the
  spec: desktop.md's `maximize`, and toolkit.md's double click. Found:
  `wm`'s own title bars do not maximize either (step 3).
- 2026-10-27: `edges ID E` in the compositor protocol, as
  `xdg_toplevel.resize`, named apart from `resize ID W H`, which is a
  client's answer to a size notice: `wm` checks what it checks for
  `move`, and that E is one side or two that meet, and starts the same
  `Resizing` drag a press on the border outside does. The toolkit asks
  it on a left press 3 deep inside a CSD window's edge (`ui_csd_edge`,
  as far in as a scrollbar's slider is, so none is under it), both edges
  within 20 of a corner, before whatever is under the press; `UiWin`
  now knows whether it is a CSD window. `tests/files.sh` drags Files's
  right side, its bottom left corner and its bottom from inside. Moved
  into the spec: desktop.md's `edges` and the inside edge, toolkit.md's
  window. Found: the pointer over the inside edge stays the arrow until
  the press, since a client cannot ask for a shape (goal 0008).
- 2026-10-27: a second press on a title bar `wm` draws, on the same
  window within the toolkit's `ui_double_ns`, maximizes or restores it
  through `maximize_toggled`, the code `maximize` runs, in place of a
  drag; `Ptr` keeps the last title press (`TitleClick`), forgotten once
  it makes a double so a third press drags again. `tests/resize.sh`
  maximizes the gallery to 1276 by 720 at 0, 32 and restores it. Moved
  into the spec: desktop.md's title bar press, and its limit on `wm`'s
  title bars folded into the one on windows that cannot be resized.
  Done.
