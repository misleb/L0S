# 0025: Terminal keeps its scrollback, resizes, and has tabs

Track: Desktop · Status: active · Needs: – · Spec: programs.md, desktop.md, toolkit.md, demo.md, testing.md

## Why

`vt` draws what is written to it straight into its window's buffer and
keeps no copy of its text ([vt.l0](../user/apps/vt/vt.l0)). So:

- **No scrollback.** A line scrolled off the top is gone: `vt` scrolls
  by moving the buffer's top row (`OpScroll`), and the wheel's
  `WheelEvent`s that `wm` sends it are dropped.
- **No resizing.** It ignores `wm`'s size notice, since it has no text
  to lay out again ([desktop.md, Limits](../spec/desktop.md#limits)),
  so dragging an edge or double-clicking its title bar does nothing,
  and it is `vt [COLS ROWS]`, 80×24, for life.
- **One shell a window.** A second shell is a second Terminal. GNOME
  Console, whose look `vt` already takes, has tabs, each its own shell,
  in one window, with a new-tab button in its header bar.

`vt`'s window is decorated by `wm`, so it has no header bar of its own
to put a button in, and the toolkit has no tab bar.

## Done when

- `vt` keeps its screen and the last 10,000 lines scrolled off it as
  bytes, a row of cells each, bounded; the wheel scrolls back through
  them, three rows a step, with the toolkit's overlay scrollbar, and a
  key typed returns to the bottom; output while scrolled back leaves
  the view where it is.
- A drag of its edge, or maximizing it, resizes it to the cells that
  fit: lines wrapped at the old width are wrapped again at the new,
  the cursor's line kept in view.
- Its window is client-decorated, with a header bar and a new-tab
  button; a second tab shows the toolkit's tab bar under it. Each tab is
  a terminal of its own, registered under its own name, `vt1`, `vt2`
  and so on, with its own shell; keys go to the selected tab, output to
  a tab not shown is kept for when it is, the window's title is the
  selected tab's, and a tab's close button or its shell's exit closes
  it, the window with its last.
- `vt_test` covers the cells, the scrollback, wrapping again and the
  tabs' bookkeeping on the host; `tests/vt.sh` covers, by screendump:
  the wheel scrolling back, an edge dragged, a tab opened by its
  button, a command in each tab, switching between them, and closing
  one. `widgets` shows the tab bar, and `tests/widgets.sh` checks it.
- `make check`, `make test` and `make e2e` pass.

## Steps

- [x] The cells: `vt` keeps its screen as rows of bytes, a cell a byte,
  with a mark on each row that a wrap, not a newline, ended, and a ring
  of the 10,000 rows scrolled off; `render`'s ops change them as well
  as the buffer. Drawing at the bottom still scrolls by `top`, copying
  nothing. Host tests in `vt_test`; nothing on the screen changes.
- [x] Scrollback: the wheel moves the view back through the ring and
  forward to the bottom, the view drawn from the cells when it is not
  at the bottom, with `ui_scrollbar`'s overlay while there is more than
  fits; a key typed returns to the bottom; output while scrolled back
  goes into the cells and leaves the view. `tests/vt.sh` checks it.
- [ ] Resizing: `vt` answers the size notice with the cells that fit,
  keeping room in its buffer as a toolkit window does, wraps the screen
  and the ring again at the new width by their marks, and keeps the
  cursor's line in view; `wm`'s maximize then works on it too.
  desktop.md's limit on `vt` and `draw` keeps only `draw`.
  `tests/vt.sh` drags an edge.
- [ ] Client-side decorations: `vt`'s window is a `csd` one, its header
  bar the toolkit's, with its title and a new-tab button, the terminal
  under it painted by `vt` as now. If the toolkit cannot leave part of
  a window to a client to paint, this step adds that.
- [ ] The tab bar: a toolkit widget as libadwaita's `AdwTabBar` draws
  one, each tab its title and a close button, the selected one raised,
  shown only with two tabs or more; in `widgets`, and checked by
  `tests/widgets.sh`. toolkit.md's table gets it.
- [ ] Tabs: each tab a terminal of its own, its cells, its line
  editing and its shell, registered as the first `vtN` free; the button
  opens one, a click on a tab selects it, its close button kills its
  shell, a shell's exit closes its tab, and the last tab closes the
  window. `tests/vt.sh` opens a tab, runs a command in each, switches
  and closes one; demo.md's table says a Terminal's `vt` and each tab's
  shell.

## Spec changes

- programs.md: `vt`'s row: its cells and scrollback, its sizes, its
  header bar and tabs, a name and a shell for each.
- desktop.md: `vt` among the client-decorated windows that resize; its
  Limits line on `vt` gone, and what `vt` still lacks said there (no
  shortcuts, no copy or paste, no escape sequences, programs not told
  its size).
- toolkit.md: the tab bar.
- demo.md: the Terminal's processes, a tab's shell beside its `vt`.
- testing.md: what `tests/vt.sh` and `tests/widgets.sh` check now.

## Log

- 2026-10-27: written. Keyboard shortcuts, Shift-PgUp to scroll and
  Ctrl-Shift-T for a tab, are left for after 0012, since `KeyEvent` has
  no modifiers; the wheel and the buttons do it all meanwhile. Copy and
  paste wait on 0013's selection. A program is not told the terminal's
  size, as nothing L0S runs lays itself out by it; the tty protocol
  gains that when one does. Tabs are one window, so 0021's windows are
  not needed. A tab is a terminal registered as `vtN`, as a window is
  now, so `sh NAME` and `ps` work on it unchanged.
- 2026-10-27: the cells (`user/apps/vt/cells.l0`). The screen is an
  `(array bytes)` of rows, each `cols` bytes, a space for a blank, in
  slots that are a ring of their own, so a scroll moves no row; each
  slot's mark in an `(array int)`. The ring of rows scrolled off is
  `ring_max` (10,000) slots of bytes, each row as it scrolled off: its
  mark as its first byte, then its cells, all of them if a wrap ended
  it, else up to its last that is not a space. `render` marks a row's
  end with a new op, `OpEnd ROW WRAP`, which draws nothing; the ops
  are applied to the cells in order, as to the canvas. `cells_test`
  checks, over 200 random texts, that the lines joined at the marks
  are the lines written.
- 2026-10-27: scrollback. The view is `back` rows above the screen; the
  wheel moves it 3 rows a step, as far as the ring goes, and a view
  that is back is drawn whole from the cells. Its overlay scrollbar is
  grid.l0's `ui_scrollbar_on`, its node's ops painted by `vt` itself,
  shown only while the view is back, as GTK's overlay indicator shows
  only while scrolling; its slider is not dragged, as the goal asks
  only the wheel. Output while back moves `back` on by the rows it
  scrolled, so the view keeps its rows; a key with a character brings
  it back to the bottom and draws it whole. `tests/vt.sh` scrolls the
  window that has `cat` three times back a step and checks the slider,
  then Backspace and the cursor. Steps 1 and 2 are one commit, since
  they share `vt.l0`'s state.
