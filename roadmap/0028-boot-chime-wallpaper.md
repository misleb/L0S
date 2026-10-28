# 0028: The chime as sound starts, the wallpaper as the screen does

Track: Desktop · Status: active · Needs: – · Spec: sound.md, display.md, desktop.md, demo.md, pi5.md, programs.md, testing.md

## Why

Until `wm` runs, nothing says the system is coming up. A display driver
shows nothing of its own, black on the Pi 5 (`hvs` sets the background
black) and whatever QEMU had on virtio-gpu, until `wm` draws its
wallpaper, `tools/mksplash`'s block letters (`/etc/splash.ppm`,
[demo.md](../spec/demo.md)). The sound driver plays only when a client
asks; `/etc/chime.wav` is heard only by typing `play /etc/chime.wav`
([sound.md](../spec/sound.md)).

`branding/wallpaper-dark.svg`, L0S's own wallpaper, is drawn nowhere.
`svg.l0` cannot draw it yet: the grid is a `<pattern>`, which it
refuses, and it draws only a square, n by n, not a 1920×1080 screen.

## Done when

- Every sound driver plays `/etc/chime.wav` once, as soon as it serves
  `audio`, because `audio_server.l0` does it, not each driver: a new
  driver gets the chime by linking the library. A missing or unplayable
  file is said once, on standard error, and the driver serves anyway. A
  client's `start` or `play` during the chime is answered as always, and
  it takes the ring from there.
- `hvs` and `virtio-gpu` each show `wallpaper-dark.svg`, drawn at the
  mode's size, as their first frame, before any client's buffer. `wm`
  then puts its own desktop over it, so nothing goes black between the
  two. The wallpaper is rendered at build time into the initramfs, as
  the icons are, not drawn by SVG on the board.
- `wm`'s wallpaper is the same image, in place of the splash.
- Tests: `svg_test` for `<pattern>` and for a document drawn W by H;
  `audio_server_test` for the chime's frames given to the ring before
  any client's; host tests of the drivers' first frame where the code
  is pure; the screen test `gpu-screen` reading the wallpaper's pixels
  before `wm` starts and after; on the Pi 5, the chime heard and the
  wallpaper seen before the desktop, written in the log.

## Steps

- [x] `svg.l0` draws a document W by H, not only n by n (its viewBox
  mapped whole and centered, as now), and `<pattern>` with
  `patternUnits` both ways and `patternTransform`, tiled under the
  shape it fills. Tests in `svg_test`.
- [x] A build step (`tools/mkicon --image`'s way, or a new
  `tools/mkwallpaper`) that renders `branding/wallpaper-dark.svg` to
  `/etc/wallpaper.ppm` at 1920×1080, plus `/etc/wallpaper2x.ppm` at
  3840×2160 for 4K modes, in the initramfs of every target. The
  Makefile staging (`stage_etc`) carries them. `mksplash` and the
  splash stay for `draw splash`, until nothing uses them.
- [x] `wm` takes the new wallpaper in place of the splash
  (`wallpaper`, `wallpaper_2x`, `load_wallpaper`). Screen tests' pinned
  wallpaper pixels and `demo.md`'s description change with it.
- [x] `virtio-gpu` shows the wallpaper as its first frame: read once,
  a layer of its own, shown under every client's layers and dropped
  from the stack once a client's buffer covers the screen. Scaled or
  centered on a mode that isn't 1080p or 4K. `gpu-screen` checks it
  before `wm` starts.
- [x] `hvs` the same, in a plane under the others, in place of the
  black background. It needs DMA pages for the frame (8 MB at 1080p)
  and must not get in the way of the 64-region limit. Seen on a Pi 5
  with a monitor on HDMI0. Written and host-tested; the board check
  (the Log's 2026-10-28 step 5 entry) is still to do.
- [x] `audio_server.l0` plays the chime: once a driver's ring runs, it
  reads `/etc/chime.wav` (`play`'s WAV parsing, moved into a library
  both use) and queues its frames as a client's would be, at the
  file's rate. `hdmi-audio` needs no code of its own beyond the
  library. Heard on a Pi 5, and `audio_server_test` pins the frames.
  Written and host-tested; the board check (the Log's 2026-10-28
  step 6 entry) is still to do.

## Spec changes

- sound.md: a sound driver plays `/etc/chime.wav` once as it starts
  serving; what a client's requests do meanwhile.
- display.md: the drivers' first frame is the wallpaper, and when it
  leaves the stack. Limits: the sizes it is rendered at.
- desktop.md, demo.md: the wallpaper is `branding/wallpaper-dark.svg`'s.
- pi5.md: what the board shows and plays as it boots.
- programs.md: `hvs`, `virtio-gpu`, `hdmi-audio`, `wm` rows; the
  `svg.l0` and `audio_server.l0` library rows; the new tool's row.
- testing.md: the new tests.

## Log

- 2026-10-28: written. Open: whether the chime waits for the screen to
  show the wallpaper (on the Pi 5 `hdmi-audio` already starts only
  after `hvs` serves), and whether a boot argument turns it off.
- 2026-10-28: the user decided the first open question: neither the
  chime nor the wallpaper waits for the other. Each driver acts as soon
  as its own hardware is ready: a sound driver plays the chime the
  moment its ring runs, a display driver shows the wallpaper the moment
  its mode is set, with no ordering or handshake between them. On the
  Pi 5 `hdmi-audio` still starts after `hvs` serves, since that is when
  HDMI's audio exists: the hardware being ready, not a wait for the
  chime.
- 2026-10-28: step 1. `svg_render_wh` and `svg_argb_wh` draw W by H;
  `svg_render` and `svg_argb` are them at n by n. A pattern is drawn
  as a painter, like a gradient: its tile once, in pixels of its own at
  the canvas's resolution there (the scale `patternTransform` and the
  shape's matrix give), then each pixel under the shape takes the tile's
  pixel its place maps back to, wrapped. So at the wallpaper's 1:1 and
  2:1 the grid is exact. With `patternUnits` objectBoundingBox (the
  default) the tile is a fraction of the shape's box, measured on the
  screen and mapped back, as gradients' boxes are. A pattern's `viewBox`
  and `patternContentUnits` objectBoundingBox are refused by name;
  `wallpaper-dark.svg` uses neither. Drawn at 1920 by 1080 the wallpaper
  takes 1.6 s on this host and differs from `rsvg-convert`'s by an RMS
  of 0.16%; at 3840 by 2160, 7 s.
- 2026-10-28: step 2, a new `tools/mkwallpaper`, and QOI, not PPM. As
  PPMs the two images would be 6.2 MB and 24.9 MB, 31 MB on an
  initramfs of 20.7 MB (21.6 on the Pi 5) whose limit is
  `INITRAMFS_MAX`, 48 MB: they do not fit, and raising the kernel's
  heap to make room would take pages from every process. As QOI
  (qoiformat.org, `user/lib/format/qoi.l0`), whose runs and small
  differences suit the wallpaper's gradients, they are 232 KB and 530
  KB, and read back in 110 ms and 470 ms on this host. So the files are
  `/etc/wallpaper.qoi` and `/etc/wallpaper2x.qoi`, in every target's
  initramfs through `stage_etc` (the Makefile's `WALLPAPERS`), and QOI
  is in `RENDER`, for whatever draws the wallpaper on the board.
- 2026-10-28: step 3. `render.l0`'s `load_background` reads a QOI as
  well as a PPM, by its magic, into a PPM's pixels once, so `wm`'s
  `Background`, `restore` and `draw splash` are unchanged. `wm` draws
  `/etc/wallpaper.qoi`, or `wallpaper2x.qoi` at scale 2, at 100%, not
  the splash's 70%: the drivers show it at full brightness, and the
  image is dark already, so nothing changes under the desktop as `wm`
  comes. On QEMU's 1280×800 it is the middle of the 1920×1080 image;
  at 4K and scale 1, the 1920×1080 image centered on its corner's
  color. The pinned pixels in `gpu-screen`, `hidpi`, `launcher` and
  `launcher-install` are the image's. `make demo SPLASH=` gave way to
  `WALLPAPER_SVG=`. Nothing on the board reads `/etc/splash.ppm` or
  `splash2x.ppm` any more; `mksplash` and the splash are left as they
  were, for a later change to remove with `SPLASH`.
- 2026-10-28: step 4. What every driver does alike is in
  `display_server.l0`: the wallpaper's buffer id, 1,000,001, past a
  client's (buffer now refuses ids outside 0 to 1,000,000 in 2D mode
  too, as 3D mode did), `wall_under` (the stack for a client's layers)
  and `layer_covers`. `render.l0`'s `wallpaper_load` picks the file by
  scale, for the drivers and `wm` alike. `virtio-gpu` draws the image
  into an `shm_region` of its own, closes the region at once (it holds
  none of the 64), and shows that buffer as the only layer; then every
  `layers` stacks it under the client's until a client's layer covers
  the screen square, when it leaves and its pages are unmapped. In 3D
  mode it is a texture, given up the same way. Not scaled: centered and
  cut, as `wm` draws it, so the change to `wm`'s desktop shows nothing.
  The driver registers `display` before it draws, since at 4K on QEMU
  decoding and painting took longer than `wm`'s 5 s wait for the name;
  `wm`'s first request waits on the port instead. `gpu-screen` boots
  first a copy of its initramfs with no `wm` and reads the driver's
  own frame.
- 2026-10-28: step 5, written with no board here. `hvs` registers
  `display` once the channel is on its own list and the IOMMU is on,
  then draws the wallpaper into an `shm_region` the screen's size (2,025
  pages at 1080p, 8,100 at 4K: one allocation each, as virtio-gpu's at
  4K on QEMU was), closes the region at once, so it keeps none of the
  64 open, and gives the pages to `mapped_for`, the path every client
  buffer takes: mapped in the aperture (512 MB, room enough) and
  cleaned out of the caches. The first list is that one plane. `layers`
  keeps it under the client's until one covers the screen square; the
  list without it is then shown, 40 ms (two frames at 50 Hz) waited,
  so the channel can be fetching none of it, and its PTEs cleared and
  pages unmapped (`unmapped`, as `forget` does). `buffer` refuses ids
  past 1,000,000 there too. Host tests: `screen_covered`, `wall_kept`,
  and the pieces of the first frame and of a window over it.
  **On a Pi 5 (`make pi5-netboot`, a monitor on HDMI0), look for:** the
  serial log's `hvs` lines up to `a screen of WxH on HDMI0 ...,
  serving display` with no `no wallpaper:` or `the wallpaper not
  shown:` warning (`dmesg` shows the debug lines `drawing the
  wallpaper` and `showing the wallpaper` too); on the monitor, black
  from the firmware's handover, then the L0S wallpaper (gold "L0S"
  over a dark blue-violet grid, the hub and six boxes), whole at
  1920×1080 or at 4K, its grid lines crisp; then `wm`'s top bar and
  desktop over the same image with no black frame and no flash
  between; no `HANDLE_ERROR` warning; and the board still answering
  at the shell afterwards (the pages given up without a hang). A hang
  right after `showing the wallpaper` would point at the wallpaper's
  plane, one past `drawing the wallpaper` at the region or the
  painting.
- 2026-10-28: step 6, written with no board here. `play`'s WAV parsing
  was already a library, `wav.l0`; `AUDIO_SERVER` now links it.
  `audio_server.l0` reads the chime (`audio_chime_load`) and says what
  to write as the ring has room (`audio_chime_feed`), and samples come
  from an `AudioSource`, a client's pages or a file's bytes, so the
  driver writes the chime's frames with the same `frames_put` as a
  client's. L0 has no function values, so the library cannot call the
  driver's hardware writes itself: `hdmi-audio`'s own part is a field
  in its `Drv` for the chime, `chime_started` as it serves (its rate
  set as a client's `start` would) and `chime_fed` after each period's
  interrupt, about twenty lines. A client's `start` or `play` ends the
  chime there. Decided, the second open question: **a boot argument,
  `chime=off`, turns the chime off**; anything else plays it. It costs
  one word, and on a board netbooted for work (`PI5_ARGS=chime=off`)
  silence wants no rebuild; a setting that lasts is the Settings app's
  (0029). `audio_server_test` pins the first feed's frames and
  samples, the ring after it with a client's place behind the chime's,
  the feed after a period ends, mono, refusals, and
  `pi5/etc/chime.wav` itself: 28,800 stereo frames at 48 kHz, 5,632 in
  the first feed.
  **On a Pi 5 (`make pi5-netboot`, a monitor with speakers on HDMI0),
  listen for:** the chime, 0.6 s, once, right after `hdmi-audio`'s
  `HDMI0 at 48000 Hz, ... serving audio` line, whatever is on the
  screen then; no `no chime:` warning; whole, with no click, gap or
  repeat (the ring refilled across about fifty periods); then `play
  /etc/chime.wav` at the shell still plays it again. Booted with
  `PI5_ARGS=chime=off`, nothing at boot.
- 2026-10-28: `make e2e` whole. Drawing the wallpaper first moves
  `virtio-gpu`'s and so `wm`'s lines a second or two later on QEMU's
  one CPU, after the shell's prompt, which three screen tests had
  counted on: `keyboard` and `usb` now wait for `wm`'s `serving
  compositor` before pressing keys, so its line is not among them;
  `fat` waits for its volume's `mounted` before `ls`; and `vt`'s
  `windows` reads a listing whose line a late prompt comes before.
  `paint_background` no longer fills the screen with the corner's color
  first when the image covers it, as the wallpaper does every screen up
  to its size.
- 2026-10-28: left over, for an idea goal of its own (not numbered
  here, since other goals were being written in parallel): nothing on
  the board reads `/etc/splash.ppm` or `splash2x.ppm` now, so
  `tools/mksplash`, the Makefile's `SPLASH`, `SPLASH2X` and their
  `stage_etc` lines, and `tools/l0s-mcp`'s copy of the splash can go,
  3.4 MB off every initramfs.
- 2026-10-28: they are gone, all of them. `/etc/face` stays: it holds
  the pointers, which `wm` reads (`ui_face_pointers`), until goal 0008's
  cursor set replaces them. `draw splash` keeps its name, and draws the
  wallpaper as it did.
- 2026-10-28: on a Pi 5 with an LG 4K monitor the chime was not heard
  at boot, though `play /etc/chime.wav` was after, and no `no chime:`
  was said. It played as soon as `hvs` served `display`, right after
  HDMI0's mode and scrambling were set, before the monitor had locked
  on and unmuted. The user decided on a lead-in: `hdmi-audio` holds the
  chime back 2 s (`chime_lead_ms`; `audio_chime_after` and
  `audio_chime_due` in the library, a held chime feeding nothing). This
  waits on the monitor, not on another driver, so the decision above
  stands. A sound driver now says `playing the chime, ...` at info as it
  starts, so the log shows it played. Still to hear on the board.
- 2026-10-28: with 2 s, heard on one boot of three, though each logged
  `playing the chime`. The lead-in is now 3 s. And the chime is the
  user's choice of a softer piano G major chord, G3, B3, D4 and G4
  rolled 30 ms apart, 2.5 s mono at 48 kHz, its loudest sample 8192
  where the old one's was 12436: `tools/mkchime` synthesizes it at the
  build, six stretched partials a note, each dying away faster the
  higher it is, so `pi5/etc/chime.wav` is gone from the tree.
