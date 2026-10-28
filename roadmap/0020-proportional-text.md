# 0020: Proportional text where GNOME's is

Track: Toolkit · Status: ready · Needs: 0019 · Spec: toolkit.md, desktop.md, programs.md, testing.md

## Why

Every word on the desktop is in Source Code Pro's 8-pixel cells
([toolkit.md, "The HIG, as encoded here"](../spec/toolkit.md#the-hig-as-encoded-here)): labels, buttons, header
bars, the sidebar, the grid, the title bars, the top bar and the
launcher, where GNOME sets them in a proportional face and keeps a
monospace for terminals and code. Text in cells is wider than it need
be and reads as a terminal's. Goal [0019](0019-font-service.md) gives
the toolkit Source Sans 3 from the font service; this goal measures and
draws text by its own advances, and moves the interface to it.

Today a width is `ui_text_w s bold scale`, the count of characters times
the cell, pure and with no face, which is what lets `ui_layout` and every
host test of a layout run without one. That must stay so.

## Done when

- The toolkit measures and draws text by each glyph's advance, in either
  face, and `ui_layout` still needs no face: the advances are a pure
  table in the toolkit, made from the fonts at the build.
- Labels, buttons, header bars, sidebars, alerts, the path bar,
  toggles, menus, status pages, entries and the grid's text are in
  Source Sans 3, and so are `wm`'s title bars, top bar, launcher and
  L0S menu; `vt` stays in Source Code Pro, as GNOME Console does, and so
  does whatever must line up in columns.
- Pairs such as `AV` and `To` are kerned, as the font's GPOS says.
- Fonts, an app as GNOME's Fonts is, previews every face `font` has, at
  heights from 12 to 64, and a screen test checks it.
- The screen tests pass with their coordinates recomputed, and one of
  them shows a proportional label's pixels; `make check`, `make test`
  and `make e2e` pass.

## Steps

- [x] The advances, pure: `tools/mkmetrics` writes
  `user/lib/ui/metrics.l0`, both faces' advances of codes 32 to 126 in
  font units and their units per em, as defs; it is checked in, and
  `make check` fails if it differs from what mkmetrics would write now.
  A `UiFont` (`UiMono`, `UiSans`) and `ui_text_w s font bold scale`:
  the sum of the advances, in font units, turned into desktop pixels
  once, rounded up, so a width never depends on where text starts.
  `ui_ellipsized` cuts by that width. Nothing calls it with `UiSans`
  yet, and every width is as today, which the tests pin.
- [x] Drawing by advance: `UiPText` carries its `UiFont`, and
  `ui_text_at` places each glyph at its sum of advances turned into the
  screen's pixels at the face's scale, offset by the strike's bearing,
  so text at scale 2 is placed in the screen's pixels, not doubled from
  scale 1's. Bold is the bold face's own advances, not a pixel wider.
  An entry's cursor and a press's place in it are found by the same
  sums (`ui_entry_keyed`, `NAME.place.N`). `ui_op_key` keeps the font,
  so a change of face is damage. Still all `UiMono`, so the screen is
  as today; host tests draw `UiSans` text onto an array canvas and pin
  its pixels.
- [x] Which digits line up: whether Source Sans 3's digits share one
  advance (its default figures, or `tnum`'s, which a glyph-substitution
  lookup would need). If they do not, the grid's number, size and level
  cells, Monitor's columns and the top bar's clock stay `UiMono`;
  written into toolkit.md either way.
- [ ] The interface in Source Sans 3: every widget's text is `UiSans`
  but what the step before kept mono, `vt` and `draw`'s `char`; `wm`'s
  title bars, top bar (`bar_apps_w` measured, not 120 by its cells),
  launcher names and menu; Files', Disks' and the gallery's own text.
  `wm_test.l0`'s pinned pixels and every screen test's coordinates
  recomputed, as `l0s-ui`'s rule 5 says: drawing, hit test and tests
  together. Widths a program reserved by counting cells, such as
  entries' and Disks' dialogs', checked against the new measure.
- [ ] Kerning: `ttf.l0` reads GPOS's pair adjustments (lookup type 2,
  formats 1 and 2, the `kern` feature of the default script) for the
  ASCII pairs, mkmetrics writes them into `metrics.l0` beside the
  advances, and the sums take each pair's adjustment, in measuring and
  in drawing alike. Tests pin `AV` and `To` narrower than their
  advances.
- [ ] Fonts, an app to preview them, as GNOME's Fonts
  (`gnome-font-viewer`) is: `user/apps/fontview`, `Fonts.app` in the
  launcher, its icon GNOME Fonts' own, as Disks' is GNOME Disks'. Its
  window shows every face `font` names (`faces`, so a font added to
  `/etc/fonts` shows with no change here) as a grid of cards, each its
  name and "Aa" in that face. A click on one opens it, with a back
  button in the header bar: its name, its file, and a pangram and then
  codes 32 to 126, at 12, 16, 24, 32, 48 and 64 tall, kerned as the
  step before has it. Those heights are not the toolkit's, so the
  toolkit gains text at a height its program names, the strike asked of
  `font` on first use and kept for the window's life (a height in
  `UiFont`, or an op of its own, whichever `UiPText` takes more simply).
  Host tests of its layout and of that op; `tests/fontview.sh`, in
  `SCREEN_TESTS`, opens it from the launcher, sees four cards, opens
  Source Sans 3 and reads an `i` narrower than an `m` at 64, then
  Source Code Pro and reads them the same width.
- [ ] A screen test: the gallery's labels, read back from a
  `screendump`, are proportional (an `i` narrower than an `m`), and
  `vt`'s cells are as before. toolkit.md's **Text** and Limits say
  which face is where, and `l0s-ui`'s text line follows.

## Spec changes

- toolkit.md: **Text** says the interface is Source Sans 3 and terminals
  and columns Source Code Pro, measured by advance and kerned; `UiFont`
  and `ui_text_w`'s font; `metrics.l0` in the table; text at a height
  a program names. The limit loses "monospaced".
- desktop.md: the title bars, top bar and launcher in Source Sans 3; the
  top bar's Applications measured.
- programs.md: `tools/mkmetrics`; `fontview`, Fonts, in the
  programs table.
- testing.md: the screen test that reads proportional text, and
  `tests/fontview.sh`.

## Log

- 2026-10-27: written, after 0019, which gives it the face.
- 2026-10-27: 0019 is done, and leaves this: the toolkit asks `font`
  only for `code` and `code-bold` (face.l0's `ui_text_names`); `sans`
  and `sans-bold` are there on request, made on the board, 0.2 to
  0.7 s each on QEMU, unless added to the strikes made at the build
  (font.l0's `stored`, the Makefile's `STRIKES`, `tools/mkstrike`),
  which the first step that draws them should do, or a window's first
  paint waits. A strike already holds each glyph's advance in 1/64
  pixel and its box's bearing (`format/strike.l0`), at the em Source
  Code Pro's cells imply, 5H/6. mkfont no longer reads TrueType at
  all (it makes the pointers only), so the first step's `--metrics`
  belongs in `tools/mkstrike` or a tool of its own, reading `ttf.l0`.
- 2026-10-28: a step added for Fonts, an app that previews the faces,
  after kerning so it shows text as the interface will. It is named
  `fontview` because `fonts`, the command that lists the cache, has
  the name already.
- 2026-10-28: step 1. mkfont reads no TrueType since 0019, so the
  metrics are a tool of their own, `tools/mkmetrics FACE=FONT.ttf...
  OUT`, reading `ttf.l0`, and the steps say so where they said mkfont.
  `make metrics` writes `metrics.l0`; `make check`'s `metrics.ok`
  writes it into `build/` and compares. Each advance is a def of a code,
  a tree of comparisons that is a single number where a range of codes
  shares one (Source Code Pro's is `600`), as L0 has no constant
  arrays a pure function could read without building. A width is the
  sum in font units turned into pixels once, at the em the strikes are
  made at, 5H/6 of the line, rounded up; Source Code Pro's 600 units
  are then 8 pixels exactly, so every width is as before, bold Source
  Code Pro still a pixel wider, as it was. `ui_text_font` names the
  face the interface's text is in, one def to change in step 4, and
  every width the toolkit and `wm` measure asks it.
- 2026-10-28: step 2. A strike is kept as `glyph.FACE.H`, FACE the
  font service's own name (`ui_font_face`), and a window asks for all
  four faces at 16 and 32 times its scale, eight regions where it had
  four; the build makes Source Sans 3's six strikes beside Source Code
  Pro's (`STRIKES`, font.l0's `stored`), so no window waits for one,
  and the `fonts` e2e case asks for Sans at 24, which is not stored,
  to still see one built once and shared. A pen is the sum of the
  advances before it at the strike's em, rounded to nearest, in the
  screen's pixels; a width stays rounded up, so the last glyph's ink
  never passes it. An entry finds a press's character from its node's
  first text op, so the window needs no copy of the entry's text.
  Bold Source Sans 3 is its own advances; bold Source Code Pro keeps
  its extra pixel until step 4, so that the screen is as it was.
- 2026-10-28: step 3. Source Sans 3's default figures are tabular:
  hmtx gives every digit 497 units, bold 528 (`paint_test.l0`'s
  `test_sans_digits_line_up` pins it, from `metrics.l0`). So nothing
  stays in Source Code Pro for its digits: the grid's number, size and
  level cells, Monitor's columns and the clock all move to Source Sans
  3 in step 4, and no `tnum` lookup is read. Written into toolkit.md's
  Text.
