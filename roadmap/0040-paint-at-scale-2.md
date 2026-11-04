# 0040: Painting at scale 2 as fast as at scale 1

Track: Toolkit · Status: active · Needs: – · Spec: toolkit.md

## Why

At scale 2 every window has four times the pixels, and the toolkit
paints each of them. Seen in roadmap 0006's board run on a Pi 5 at
3840×2160: Files painted 5 to 36 ms a step, once 181 ms, and Widgets
once 149 ms, where at 1920×1080 the same steps paint in a few ms. The
desktop felt sluggish with five windows open, alongside 0038's stalls.

## Done when

- On the Pi 5 at 3840×2160, the paint of Files', Widgets' and Disks'
  steps for their usual changes (a hover, a selection, a page scrolled,
  a folder opened) is within a frame, 16.7 ms, by the `slow step`
  lines' paint, where 0006's run saw 5 to 36 ms.
- Nothing painted differs from before: the paint and render tests pass
  unchanged, and the screen tests' pixels are the same.

## Steps

- [x] Measure which of a paint is fills, text, icons, images and
  rounds at scales 1 and 2: a timing harness on the host, kept out of
  the tree, painting a page like Files' (fills, 30 lines of text, their
  icons, 24 full-color icons, a row of buttons) into an array canvas.
- [x] Fills over a buffer a copy a row: the row's pixels made once as
  bytes and copied into each row (`render.l0`'s `fill_rows`,
  `canvas_fill`), in place of a 64-bit write every two pixels.
- [x] Text, icons and images a row at a time: the row's place and its
  columns in the clip found once (`paint.l0`'s `UiPxRow`), each pixel
  put by its index, a word of coverage outside the clip skipped whole,
  an image's columns cut to the clip before its loop, and an edge mixed
  in one function (`ui_cov_mix`, tested against `ui_mix`).
- [ ] Timed on the Pi 5 at 3840×2160 (to check on the board): with
  Files, Widgets and Disks open, hover, select, scroll and open a
  folder, and read `dmesg`'s `slow step` lines; their paint against
  0006's 5 to 36 ms. The screen tests (`make e2e`) show the same
  pixels, as the region path of the fills runs only on the board and
  QEMU, never in the host's tests.
- [ ] Whatever step 4 finds still over a frame, from its numbers: what
  is left a pixel at a time is rounds' edges, and an image's opaque
  pixels, which could be copied a run at a time.

## Spec changes

- toolkit.md: how a window paints at scale 2 (moved with steps 2 and
  3; step 4's numbers go in its Log).

## Log

- 2026-10-29: written from 0006's board run at 4K.
- 2026-10-29: after 0038's step 3 took out the 1.2 s stall, the user
  at 4K: moving windows and widgets responsive, resizing and scrolling
  large views still a little choppy.
- 2026-11-03: active; steps written, and steps 1 to 3. Measured on
  this host into an array canvas, a page of 900×600 of the desktop's
  pixels, each op list painted five times, the mean, scale 1 then 2:
  the window's three big fills 1.6 and 6.5 ms, 30 row fills 0.86 and
  3.5, 30 lines of Source Sans 3 1.5 and 3.5, 30 symbolic icons 0.13
  and 0.42, 24 folder images 48 wide 0.98 and 3.3, 12 rounded buttons
  0.18 and 0.50. Text and images were most of what is not a fill, and
  in them the work of each pixel: a clip test, the pixel's place found
  from its row again, and `ui_mix`'s channels a call each, about 40%
  of text's time. After steps 2 and 3: text 0.74 and 1.75 ms, icons
  0.07 and 0.23, images 0.46 and 1.7; at scale 2 text is now 2.4 times
  scale 1's, less than its pixels' 4. Fills into an array are as they
  were, a cell at a time; into a buffer, which the host cannot have,
  a window's fill at 4K, 1800×1200 of its pixels, was about a million
  64-bit writes and is now 1,200 copies of a row, so the board's paint
  should drop most there, which step 4 is to see. A fill by index,
  `canvas_fill`, copies its color's bytes at most 4,096 pixels at a
  time (`fill_chunk`), as `wm` fills the whole screen with it, which
  at 4K would have made 33 MB of bytes at once.
