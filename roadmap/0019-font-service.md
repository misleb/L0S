# 0019: A font service that caches rasterized glyphs

Track: Toolkit · Status: ready · Needs: – · Spec: toolkit.md, programs.md, demo.md, syscalls.md

## Why

Text is one face, Source Code Pro, rasterized at the build by
`tools/mkfont` into `/etc/face` at three heights, 16, 32 and 64, and
nothing else ([toolkit.md, Limits](../spec/toolkit.md#limits): "One
monospaced face"). Every program with a window reads all of that file,
431 KB, into its own heap with `ui_face_load`, and parses it into a `Map`
of arrays, before it can draw: `wm`, each `vt`, Files, Disks, Monitor and
the gallery each hold a copy. A second face, the proportional one of goal
[0020](0020-proportional-text.md), would double that, and a new size
means a new build.

A service that owns the fonts, rasterizes a face at a height on the first
ask and keeps it, and shares those pages with every client that asks
next, makes a face cost its pages once, makes any height a request
rather than a build, and gives 0020 a second face for nothing more than
its file.

The face that goes with Source Code Pro is **Source Sans 3**: Adobe's,
by the same designer, made as its proportional companion (Source Code Pro
was drawn from it), under the same SIL Open Font License 1.1, with
nearly the same x-height, and released as TrueType outlines, which
`ttf.l0` reads. GNOME's own UI face, Adwaita Sans, was the other choice,
and was set aside because it does not match the monospace already used.

## Done when

- `fonts/` holds Source Sans 3's Regular and Bold beside Source Code
  Pro's, with their license and source, and `/etc/fonts` has all four.
- `font`, a service in `/sbin`, answers `strike FACE H`: the face's
  glyphs at line height H, rasterized on the first ask and cached, in
  pages it shares with the asker read-only; a second ask of any client
  rasterizes nothing.
- The toolkit's text comes from it: no program reads `/etc/face`'s
  glyphs, and text is drawn pixel for pixel as today, so every screen
  test passes unchanged.
- A window's program starts with less heap than today, by the face it
  no longer parses, and its first paint is no slower; both are measured
  and kept in the Log.
- `make check`, `make test`, `make e2e` and `make test-virt` pass.

## Steps

- [ ] The fonts and the reader as a library: Source Sans 3's
  `SourceSans3-Regular.ttf` and `-Bold.ttf` from `adobe-fonts/source-sans`'
  release into `fonts/`, with `SourceSans3-LICENSE.txt` and where they
  came from. `tools/mkfont/ttf.l0` moves to `user/lib/format/ttf.l0`
  (`TTF`, with its tests, in `DOC_SRCS` and a `l0_test` line), which
  mkfont links from there. Tests that Source Sans 3 reads: its cmap
  finds every ASCII code, its advances differ (`i` narrower than `m`),
  and a composite glyph's outline is whole.
- [ ] A strike as bytes, pure (`user/lib/format/strike.l0`): one face at
  line height H, codes 32 to 126, written once and read in place. A
  header (magic, H, the baseline, the face's advance in font units and
  its units per em), then each code's advance in 1/64 pixel, its box
  (left bearing, top, width, height) and where its coverage starts, then
  the coverage, 4 bits a pixel as the face's tables are now, each glyph
  only as wide as its ink. Built from a `Ttf` with `raster.l0` at the
  em today's cell implies (Source Code Pro's 600 units 8 pixels wide at
  H 16), so Source Code Pro's strikes cover the same pixels as
  `/etc/face`'s glyphs, which a test compares glyph by glyph at 16 and
  32. Timed on the host per strike, to know what the first ask costs.
- [ ] The service: `user/sbin/font`, registered as `font`, started in
  `demo/etc/system` before `wm`, reading `/etc/fonts/*.ttf` (the
  Makefile stages `fonts/`'s four there). `faces` names them
  (`code`, `code-bold`, `sans`, `sans-bold`); `strike FACE H`
  answers `VA N` once the strike is in pages shared with the asker,
  building it first if no one asked for it before; `stats` says each
  strike cached, its bytes, and how many have it. Kept in a `Map` by
  face and height, never freed while the service runs. If a strike
  takes long on QEMU (the step before's timing, at TCG's speed), the
  heights the desktop paints at (16 and 32) are built as the service
  starts, before it registers. The client side is
  `user/lib/proto/font.l0` (`FONTLIB`). A `fonts` command lists the
  faces and the cache; an e2e case asks a strike twice and sees one
  build. The start line shifts later pids: `spec/demo.md`'s table and
  `ps` sample, and `tests/vt.sh`'s arithmetic.
- [ ] The toolkit asks for its text: `ui_face_load` asks `font` for
  Source Code Pro's regular and bold at the heights its scale paints,
  and draws from the shared pages in place, with no copy; with no
  `font`, it draws no text and says so once, as it does now with no
  face. `/etc/face` keeps only the pointers, and mkfont makes only
  those. `vt` asks the same way. Every screen test passes unchanged;
  `ps`'s memory and the time to a window's first paint, before and
  after, go in the Log.
- [ ] Read-only sharing: `shm_share` gains a read-only form (a new call,
  by the system call checklist, or a flag in its arguments, whichever
  the kernel's `Call` takes more simply), which maps the pages into the
  receiver without write permission; a write there faults the writer,
  not the owner. `font` shares its strikes that way, so no client can
  change another's text. `kernel_virt_test.l0` tests the write fault
  and the refusals.

## Spec changes

- toolkit.md: `face.l0`'s row and **Text**: the glyphs come from `font`,
  read in place, shared by every program; `/etc/face` is the pointers
  only. The limit "One monospaced face" becomes two faces, still ASCII
  only, any height on request.
- programs.md: `font` and `fonts` in the programs table; `ttf.l0`,
  `strike.l0` and `proto/font.l0` in the libraries table.
- demo.md: `font`'s pid, and who asks it (every window's program).
- syscalls.md: the read-only share.

## Log

- 2026-10-27: written. Source Sans 3 chosen as Source Code Pro's
  companion face.
