# 0026: The font service lets strikes go, and knows who holds them

Track: Toolkit · Status: done · Needs: – · Spec: programs.md, toolkit.md, testing.md, demo.md

## Why

Goal [0019](0019-font-service.md) left `font` simple, and these are its
limits ([programs.md](../spec/programs.md), `font`'s row):

- A strike is kept for as long as `font` runs, never freed, so a
  program that asks for many heights grows `font` for good, up to its
  device pages; heights are bounded (8 to 128), faces are four, so the
  worst is 484 strikes, some 9 MB.
- `stats` counts the processes a strike was given to, the dead too:
  nothing tells `font` a client exited, and the kernel takes the
  mappings back by itself.
- Every program with a window holds four of its 64 regions open for the
  strikes it draws from, `wm` among them, which also opens two per
  window.
- `font` is one process answering one request at a time: a strike it
  must make (0.2 to 1.2 s on QEMU) holds up every other client's ask
  behind it, even for one already made.

## Done when

The three questions, decided:

- **One region for all of a program's strikes.** `font` keeps its
  strikes in *arenas*: runs of 128 pages (512 KB) it allocates with
  `shm_alloc`, each strike in a run of an arena's pages, first fit. An
  arena is shared with a process once, read only, the whole of it, the
  first time it is given a strike there; the answer to `strike FACE H`
  is where the arena is in the asker, its pages, the strike's offset in
  it and its own pages, and the strike's name: `VA N OFF M FACE H`. The
  toolkit opens one region over an arena and reads every strike in it
  there, so a program holds one region for all its strikes (two once
  more than an arena's worth were made, as Fonts with every face opened
  may), where it held eight, and Fonts 32. The desktop's twelve stored
  strikes are 80 pages, so they and the first others share arena 0.
- **How `font` learns a holder exited**: `proc_watch`, the first time
  it gives a process anything, as `fs` watches its clients; the exit
  notice drops the pid from every strike and arena it was given.
  `stats` counts live holders only.
- **When a strike is let go**: at once, when its last holder exits, or
  when it was made for askers that were all gone by then, unless it is
  one of the stored ones, which are kept for good. Its pages go back to
  their arena for the next strike. An arena left with no strike, not
  arena 0, is unmapped from `font` (`shm_unmap`); its frames are freed
  once the processes it was shared with have exited too. So `font`
  holds the stored strikes and those live programs draw with, rounded
  up to arenas, and no more.
- **The fourth limit, one request at a time**: a strike `font` must make
  is made a glyph at a time, between messages: while one is being made
  `font` takes each message waiting (`port_try_receive`) and answers it
  first, a strike already made at once, so an ask is held up by at most
  one glyph's rasterizing, not a whole strike's (0.2 to 1.2 s on QEMU).
  Another asker of a strike being made waits for the same making. So
  answers no longer come in the order asked, which is why each names
  its strike, a refusal too (`error: FACE H: WHY`), and the toolkit
  matches an answer to its ask by that name.

Checked by:

- Host tests of the arenas' bookkeeping (placing, freeing, sharing,
  an exit), of the protocol's replies read back, and of the toolkit
  opening one region for two strikes of one arena.
- The e2e case `fonts`: a strike asked by a process that then exits is
  gone from `stats`, the stored ones show no holders, and `fonts strike
  sans 100 code 16`, two asks at once, prints `code 16` first, answered
  while `sans 100` was made.
- `fontview.sh` and the screen tests that draw text pass unchanged, and
  `fontview.sh` sees the strikes made for Fonts held by it alone;
  Fonts' regions, before and after, in the Log.
- `make check` and `make test` pass, and the e2e cases and screen tests
  that start `font`.

## Steps

- [x] Arenas: `user/sbin/font/store.l0`, pure, the strikes kept by face
  and height in arenas, each strike its arena, first page and pages,
  its bytes, its holders and whether it is stored; each arena its pages
  used and where each process it was shared with sees it; placing
  first fit, giving to a pid, `stats`. `font` keeps its strikes so,
  each written into its arena through a region opened for the write
  and closed after, the stored ones as it starts; the answer `VA N OFF
  M FACE H`, a refusal `error: FACE H: WHY` (`proto/font.l0`'s
  `FontStrike` of four numbers, `font_reply_key`). The toolkit's
  `UiStrikeIn` is a region, the arena's place and the strike's offset;
  a strike in an arena already open reuses its region, and
  `ui_face_regions` counts arenas. `fonts strike` says the strike's
  pages as before.
- [x] Holders that exit: `font` watches each pid it gives an arena to,
  and an exit notice takes it out of every strike's holders and every
  arena's sharers; `stats` counts the live. A strike left with no
  holder, not stored, is let go, its pages free in its arena; an arena
  left empty, not arena 0, unmapped. `stats`' first line says the
  pages used of the arenas'. The e2e case `fonts` shows a strike gone
  once its asker exited.
- [x] Making between messages: a strike to make is a job, made a glyph
  a turn while no message waits, its askers answered when it is
  whole; an asker that exits first is dropped, and a job none waits for
  any more is dropped too. The toolkit matches an answer by the
  strike it names (`ui_face_answered`), the oldest ask only for an
  answer that names none. `fonts strike FACE H ...` asks several at
  once and prints each as it comes; the e2e case `fonts` shows a made
  strike answered before one being made.
- [x] Fonts' regions and the screen: Fonts' regions with every face
  opened counted before and after (the Log), `fontview.sh` and the
  screen tests that draw text pass; spec and the `l0s-ui` skill say
  what changed.

## Spec changes

- programs.md: `font`'s row (arenas, holders watched, strikes let go,
  made between messages, the answer `VA N OFF M FACE H`), `fonts`' row
  (several strikes at once), `proto/font.l0`'s row.
- toolkit.md: `face.l0`'s row and **Text**: one region an arena, not a
  strike; `uiapp.l0`'s count of regions; **Replies, not waits**: a
  strike's answer matched by its name, not by order.
- testing.md: the `fonts` case and `fontview.sh`'s check of holders.
- demo.md: `font`'s row, strikes let go as their askers exit.

All moved into spec/ with the change that did the steps.

## Log

- 2026-10-27: written from 0019's limits.
- 2026-10-28: since 0020 every window holds eight regions for its
  strikes, both faces' regular and bold at 16 and 32 times its scale,
  not four, and a program that shows text at heights of its own
  (`UiFontAt`, as Fonts does) one more for each face and height it has
  shown, kept for the window's life: Fonts, every face opened, holds 32.
  One region for all of a program's strikes would matter more now.
- 2026-10-29: written out and done, the four steps in one change. The
  decisions: arenas of 128 pages shared whole, so one region an arena;
  `proc_watch` on first giving; a strike let go at once when its last
  holder exits, but the stored; strikes made a glyph a turn between
  messages, answers naming their strike. Measured on QEMU: the stored
  strikes take 80 of arena 0's 128 pages. `fontview.sh` with Source
  Sans 3's and Source Code Pro's pages opened: 8 strikes built (12, 24
  and 48 of those two, and the bold faces' 48 for their cards), 127 of 128
  pages used, so Fonts reads all its strikes, the desktop's and its own,
  through one region where it held 16 (8 of the desktop's and one for
  each of its own 8); with all four faces opened, 2, where the Log of
  2026-10-28 counted 32. Every other window program goes from 8 regions
  to 1. The `fonts` case: `sans 24` asked twice by one process, made
  once, gone once it exited; `fonts strike sans 100 code 16` prints
  `code 16` first; `sans 100` (25 pages) let go too. Left as they are,
  and said in programs.md: a strike is given back only by its holder's
  exit (there is no request to let one go), and an arena unmapped from
  `font` keeps its frames until every process it was shared with has
  exited. `make check` and `make test` pass (3159 tests, 182 files),
  the e2e cases that start `font` (`apps`, `draw`, `draw_4k`, `fonts`,
  `virtio-gpu`), and all 19 screen tests (`tests/screens.sh`); the full
  `make e2e` is left to the merge.
