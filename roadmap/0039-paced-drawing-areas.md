# 0039: Drawing areas paced too, and a resize that overlaps the restack

Track: Toolkit · Status: done · Needs: – · Spec: toolkit.md, desktop.md

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

## Done when

- `vt`'s terminal is drawn in the buffer the screen does not show, at
  most once a frame, and the toolkit's limit of a drawing area "shown
  half painted" is gone from toolkit.md and desktop.md.
- A scripted drag of a window's edge on QEMU shows about as many sizes
  as one buffer did (0006's 159), more than two buffers' 133.
- `make check`, `make test` and `make e2e` pass, and the third buffer
  and `vt`'s pacing have run on the Pi 5 with nothing refused.

## Steps

- [x] The toolkit's drawing areas in the buffer painted next:
  `ui_win_drawing` gives the canvas a program draws on, that buffer
  brought up to what the screen shows, or says to draw later while the
  window waits; `ui_win_drew` keeps what was drawn for the next
  `ui_present` to damage; `ui_win_lost` counts the times what was drawn
  was lost. A window whose next buffer cannot be shared is painted in
  the buffer shown from then on (`ui_win_single`), where it stayed as
  the compositor showed it. `ui_win_damaged` goes.
- [x] `vt` draws through it: what output changed is due (`Due`, the
  rows scrolled and the rows changed, put together while the window
  waits), drawn at the next step the window may, and presented; what
  was last drawn whole is a `View` of the area, the window's losses,
  the tab and how far back, no longer the canvas.
- [x] A third buffer while resized: `wm` keeps up to two other buffers
  a window, each in a bank of its own, the third bank's ids from
  `third_id`, 200000; `detach ID VA` gives one up. The toolkit keeps
  its buffers not shown as a list, the oldest given up first, a release
  the oldest's; while resized it waits for no frame and makes a third
  rather than wait for a release, and gives a third up once released
  and not resized.
- [x] On the Pi 5 (to check on the board, `hvs`): with the desktop up,
  drag a window's edge, and type in Terminal and run something that
  prints a lot (`ls -l /bin`, a long `cat`): no torn or half-drawn
  terminal, `run windows` shows a window's `buffer` an id from 200000
  after a drag and back to its two after the next change, and `dmesg`
  shows no `refused:` from `hvs` or `wm`.

## Spec changes

All moved: toolkit.md's "Paced, in two buffers" and "Drawing areas,
paced too", its Limits, and the `window.l0` and `uiapp.l0` rows;
desktop.md's `attach` and `detach`, the buffer ids, the releases and
the resize paragraph; demo.md's `run windows` sample. The board's
results go in the Log.

## Log

- 2026-10-29: written from 0006's step 4.
- 2026-11-03: active; steps written, and steps 1 to 3. Measured on this
  host's QEMU (4 CPUs, 2D, 1280×800) with a script kept out of the
  tree: the gallery opened by `run widgets` in `screen.cpio`, its right
  edge dragged 240 pixels in and out twice, 6 at a step 30 ms apart,
  160 moves, and the frames `wm` told the window counted from `run
  windows` (one a size shown). `main` before: 133, 132 and 135 sizes in
  7.2 to 7.4 s. With the third buffer: 154, 155 and 153 in 7.0 s. The
  frame wait had to go too while resized, not only the release's: both
  come with the restack that shows the last size, so a third buffer
  alone would have waited as long. `vt`, now paced, asks its frames:
  the `virtio-gpu` e2e case's `run windows` says `frames 2` for its
  window where it said 0, the same on five runs. The first `make e2e`
  caught `resize.sh` and `files.sh` stuck after two sizes: a window's
  first buffer, made at open with no room, is given up at its first
  resize (`detach`), leaving `wm` none of its other buffers, which it
  took for a client of one buffer, giving up the content it had while
  the client waited for its release. `wm` now keeps it for a client
  that asked for its frame, as a paced one does before it resizes.
  Timed again after: 156, 156 and 149 sizes.
- 2026-11-04: the first board run (Pi 5, 3840×2160, scale 2, from `make
  release`): Terminal, once maximized, showed rows of its text
  incompletely drawn until output scrolled it whole. `ui_win_drawing`
  copied what the buffer lacked from the one shown and then lacked
  nothing, but damaged none of it, and on the Pi a damage is what `hvs`
  cleans from the caches, so the copied pixels were not seen; QEMU has
  no such caches. What it copies is now kept as drawn, for the present
  to damage. Steps that scrolled damaged all of the terminal, 3840×1920,
  as they did before. No `refused:`. Terminal's first launch opened no
  window in `wm`'s 10 seconds, at 14 s after boot as `speech` read
  Whistle from the card for 5 s, and the second opened; nothing in the
  log says why, and its window is asked before anything this goal
  changed runs. Run again with that: Files, System Monitor, Disks and
  Terminal moved and resized, only Terminal, grown, kept a trace of
  its old top right corner in its header bar until moved. Bringing its
  buffer up to date, `ui_win_drawing` copied all the buffer lacked,
  the header bar too, with the corner `hvs` cuts in the buffer shown by
  its pixels' alpha; a present copies only what it does not paint
  again. It now copies only within the areas the program names, the
  rest left for the present, as any window's.
- 2026-11-04: done. With both fixes and Terminal's review (`97d7055`)
  from `make release` on the card, the user moved and resized Files,
  System Monitor, Disks and Terminal and ran output in Terminal: no
  torn or half-drawn terminal, no corner left behind. `dmesg` had no
  `refused:`, though by then it held only the last of 90 minutes. A
  buffer id from 200000 in `run windows` after a drag was not caught:
  Terminal was closed by the time it was asked.
