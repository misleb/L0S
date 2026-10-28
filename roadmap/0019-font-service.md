# 0019: A font service that caches rasterized glyphs

Track: Toolkit · Status: done · Needs: – · Spec: toolkit.md, programs.md, demo.md, syscalls.md

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

- [x] The fonts and the reader as a library: Source Sans 3's
  `SourceSans3-Regular.ttf` and `-Bold.ttf` from `adobe-fonts/source-sans`'
  release into `fonts/`, with `SourceSans3-LICENSE.txt` and where they
  came from. `tools/mkfont/ttf.l0` moves to `user/lib/format/ttf.l0`
  (`TTF`, with its tests, in `DOC_SRCS` and a `l0_test` line), which
  mkfont links from there. Tests that Source Sans 3 reads: its cmap
  finds every ASCII code, its advances differ (`i` narrower than `m`),
  and a composite glyph's outline is whole.
- [x] A strike as bytes, pure (`user/lib/format/strike.l0`): one face at
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
- [x] The service: `user/sbin/font`, registered as `font`, started in
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
- [x] The toolkit asks for its text: `ui_face_load` asks `font` for
  Source Code Pro's regular and bold at the heights its scale paints,
  and draws from the shared pages in place, with no copy; with no
  `font`, it draws no text and says so once, as it does now with no
  face. `/etc/face` keeps only the pointers, and mkfont makes only
  those. `vt` asks the same way. Every screen test passes unchanged;
  `ps`'s memory and the time to a window's first paint, before and
  after, go in the Log.
- [x] Read-only sharing: `shm_share` gains a read-only form (a new call,
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
- 2026-10-27: step 1. Source Sans 3 3.052R's Regular and Bold TTFs,
  unmodified, from the release's `TTF-source-sans-3.052R.zip`, with
  its LICENSE.md, in `fonts/` (`SourceSans3-LICENSE.txt` says where
  from, and the zip's SHA-256). `ttf.l0` is `user/lib/format/ttf.l0`
  (`TTF`); its forms the undocumented list named by the old path are
  documented rather than relisted. It reads Source Sans 3 as it is:
  1000 units per em, every ASCII code mapped, `i` (a composite, stem
  and dot) narrower than `m`.
- 2026-10-27: step 2. `strike.l0`: magic `L0ST`, a 24-byte header,
  95 entries of 24 bytes, coverage from 2304 in u64 words, so a reader
  over shared pages reads a word with one aligned 64-bit access. The
  baseline is kept in 1/64 pixel; "the face's advance" is its `M`'s
  (600 for Source Code Pro), as the header needs one number. A glyph
  is rasterized in a grid its advance wide and H tall with a margin of
  H/4 all round, then cut to its ink, so no face loses ink at a cell's
  edge; the placement is mkfont's numbers scaled by 1000/upm, which
  for a face of 1000 units gives the same floats exactly. Source Code
  Pro's strikes cover `/etc/face`'s cells pixel for pixel at 16 and 32,
  regular and bold, and no glyph's ink leaves its cell, so drawing
  from a strike unclipped draws what today's cells do. On the host
  (x86-64, one core) a strike takes 11 ms at 16, 28 ms at 32 and
  47 ms at 64 (Source Code Pro), 9 and 20 ms for Source Sans 3 at 16
  and 32; it is 9.2 KB at 16, 15.3 KB at 32 and 49.7 KB at 64, against
  `/etc/face`'s 431 KB for all six tables.
- 2026-10-27: step 3. `font` reads the four faces as it starts (1.1 MB
  of TTF in its heap, kept: a strike needs its outlines) and
  answers `faces`, `strike FACE H` (`VA N`) and `stats`. A strike is
  made into `shm_region` pages, written once with `device_write_bytes`,
  its region closed at once so the cache never holds one of the 64; it
  is shared with a pid once, and asked again by the same pid answers
  where that pid already sees it. "How many have it" counts the
  processes it was given to, the dead too: nothing tells the service a
  client exited, and a count is all `stats` promises. Heights are 8 to
  128. On QEMU (TCG, one CPU) the build logged at debug: Source Code
  Pro 305 ms at 16, 578 ms at 32, 1225 ms at 64; its bold 207 and
  433 ms at 16 and 32; Source Sans 3 217 and 702 ms. So the four the
  desktop paints at scale 1 (regular and bold at 16 and 32, about
  1.5 s) are made before `font` registers, and `wm`, which waits for
  the name, never waits for a build in its first paint. At scale 2,
  64 is made on the first ask. `font` starts after `sh`, before `wm`:
  pid 16, and `wm`, the vts, procmon and the window's shell move up
  one (`spec/demo.md`, and `tests/vt.sh`'s one base, 16 to 17).
  `tests/e2e/fonts` asks Source Sans 3 at 32 from two processes and
  sees `strikes built` go from 4 to 5. The e2e harness's `font` file
  now also stages `/etc/fonts`.
- 2026-10-27: step 4. `ui_face_load` asks `font` (waiting up to 20 s for
  it) for `code` and `code-bold` at 16·s and 32·s, opens each with
  `dma_open` and draws from it in place (`UiStrike`, a glyph's entry
  read with `device_read32`, its rows a word at a time with
  `device_read64`), four of a process's 64 regions. vt needed no change:
  it calls `ui_face_load`. `strike.l0` split: the layout and readers
  stay (in `UI_CORE`), the making moved to `gfx/glyphs.l0`, so no
  window's program links the rasterizer. mkfont makes only the
  pointers, and only `wm` reads them (`ui_face_pointers`), only at
  scale 2, where it draws them; window programs read no `/etc/face`
  at all. Every boot that starts `wm` starts `font` first (the screen
  tests' etcs, the draw and virtio-gpu cases); `procmon.sh` counts one
  process more, so it runs five naps, not six, for its thirteen rows.
  Every screen test passes with its pixels unchanged.

  Measured on QEMU (TCG, one CPU), a boot of the drivers, `rtc clock`,
  `wm`, a vt and the gallery, three or four runs each; "today" is this
  branch at step 2, before any `font`:

  | | today | after |
  |---|---|---|
  | `wm`'s own pages (4 KB) | 243 | 34 |
  | `vt`'s own pages | 241 | 31 |
  | widgets' own pages | 250 | 38 |
  | `font`'s own / shared pages | – | 35 / 89 |
  | vt's first damage, from boot | 0.549–0.596 s | 0.540–0.584 s |
  | widgets' first damage, from boot | 0.631–0.650 s | 0.619–0.622 s |
  | `ui_face_load` in `wm` | 17 ms | 10 ms |

  The design call that got there: step 3's strikes made as `font`
  started put 0.7 s of rasterizing on every boot's path to the first
  paint (vt's first damage at 1.33–1.39 s). So the desktop's strikes,
  `code` and `code-bold` at 16, 32 and 64, are made at the build by
  `tools/mkstrike`, with the same `glyphs.l0`, and staged in
  `/etc/fonts` as `FACE-H.strike`; `font` keeps them as it starts and
  makes any other on request, reading a face's TTF only then, which
  took its own pages from 357 to 35. A missing stored strike is made
  on its first ask, so nothing depends on them but the time. That made
  asking the display for its scale unneeded, and it was dropped.
- 2026-10-27: step 5, and done. A new call rather than a flag:
  `shm_share_read`, 299, the same arguments and answers as
  `shm_share`, decoded to its own `CShmShareRead`, handled by
  `do_shm_share` with a perm, which reaches `space_map` as 0, read
  only, where `shm_share` passes 1 (`process.l0`'s `share_ro` and
  `share_rw`). A write there is a permission fault the kernel has no
  page to map for, so it ends the writer, status 139, as any bad
  access does; the owner's mapping is its own and untouched. `font`
  shares every strike so. `kernel_virt_test.l0` tests it to itself,
  its refusals (no such pid, pages not the caller's, none), a reader
  seeing the owner's 7, a writer ended with 139, and the owner reading
  its 7 after. Two of `syscall_test.l0`'s checks used 299 as the first
  unknown call; they use 300. `make check`, `make test`, `make e2e`
  and `make test-virt` pass. Left: Source Sans 3 in the interface is
  0020's (its Log says what 0019 gives it); strikes never freed,
  holders counted dead or alive, four regions a window program, and
  one request at a time are idea 0026.
