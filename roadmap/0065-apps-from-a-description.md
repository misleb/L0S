# 0065: Apps from a description: the toolkit's vocabulary, a preview, and a recipe

Track: Toolkit · Status: done · Needs: 0045 (met) · Spec: toolkit.md, programs.md, boot.md, testing.md, network.md, agent.md

## Why

0045 has a Claude Code session on the host write and build an app from
the board agent's prompt, told to copy the shape of Widgets. Three things
make every such app, and every app an agent writes here, harder than it
should be:

- Every app writes the same loop again (seven copies of Widgets' own),
  and the same pieces: a page with a title and a line under it, a heading
  row with buttons, a line along the foot, a Cancel button and a dialog
  that confirms, an entry's width, a tab bar's list. `ui_grid_page` says
  End Process whatever the grid holds. There is no switch, no check box,
  no slider, no spinner, and no list of rows: a to-do list or a settings
  page has nothing to be made of but a sidebar or a grid.
- Nothing shows a view before the board does. Layout and painting are
  pure and run on the host, the strikes and icons are built there, and
  `crc32`, `read_whole` and `write_whole` are there, but nothing joins
  them, so a session sees its app only by booting it.
- The guidance is the whole of four skills, with no path from a sentence
  ("a to-do list with a box to type in and a check on each item") to the
  widgets, actions and state it needs.

## Done when

- `ui_run` runs a program of one window from its state, view and update,
  and the apps of one window that need no loop of their own use it.
- `page.l0`'s composites are what the apps that rolled them use.
- `UiSwitch`, `UiCheck`, `UiScale`, `UiSpinner` and `UiList` are drawn
  as libadwaita draws them, take the pointer and the keys, and show in
  the Widgets gallery, whose screen test covers them.
- `make preview APP=NAME` renders an app's scenes, its `preview.l0`, to
  PNG files on the host in seconds, with the board's fonts and icons;
  `l0s-app-preview` does the same for a builder's app.
- `user/apps/todo`, To Do, is built of nothing else, with host tests,
  a preview and a screen test.
- `l0s-app-new` scaffolds an app in that shape, which checks, previews
  and builds as written (tested); the `l0s-ui` skill's `apps.md` takes a
  description to an app; the builder's session is told to scaffold,
  preview, then build.
- By hand: a builder session makes an app from one sentence, and the
  board runs it.

## Steps

- [x] PNG and the host preview: `format/png.l0`, `ui/preview.l0`
  (`UI_PREVIEW`), `make preview`, Widgets' `preview.l0`,
  `l0s-app-preview`.
- [x] The runner: `ui/run.l0`'s `ui_run`; About, Widgets, Monitor,
  Fonts, Installer and Agent on it.
- [x] Composites and test helpers: `ui/page.l0`, `ui/testing.l0`
  (`UI_TESTING`), the apps that rolled them using them.
- [x] Controls: `UiSwitch`, `UiCheck`, `UiScale`, `UiSpinner`
  (`ui/controls.l0`), the gallery's Controls tab, `tests/widgets.sh`.
- [x] The list: `UiList` (`ui/list.l0`), the gallery's Rows tab,
  `tests/widgets.sh`.
- [x] To Do: `user/apps/todo`, `tests/todo.sh`.
- [x] The scaffold, the recipe and the builder: `l0s-app-new`, the
  `l0s-ui` skill's `apps.md`, the builder's commands and prompt.
- [x] By hand: a builder session from one sentence, run on QEMU.

## Spec changes

- toolkit.md: the files `run.l0`, `page.l0`, `controls.l0`, `list.l0`,
  `preview.l0`, `testing.l0`; "How a program uses it" opens with
  `ui_run`; a section on previewing; the HIG's measures for the switch,
  check, scale, spinner and boxed list.
- programs.md: the libraries `png.l0`, `preview.l0`, `testing.l0`; To
  Do's row.
- boot.md: To Do in the Apps table.
- testing.md: the preview, `png_test`, the gallery's new cases,
  `tests/todo.sh`.
- network.md: `l0s-app-new` and `l0s-app-preview` among the session's
  commands, and its prompt's workflow.
- agent.md: `build_app`'s session previews before it builds.

## Log

- 2026-11-03: written, as the user asked for the toolkit made easy for
  agents to make apps from a person's description. The user chose: new
  widgets (switch, check, slider, spinner, boxed list) as well as
  composites; a preview of scenes written in L0 and rendered to PNG, not
  a second language for UI; and both gallery tabs and a To Do app
  checked in as the worked example, with a scaffold.
- 2026-11-03: step 1 done. `png.l0` writes stored-block PNGs, pinned
  against Python's zlib; `preview.l0` paints a scene with the build's
  strikes and icons; `make preview APP=widgets` takes about 4 s, almost
  all of it the build, and its selected row is the screen test's 36 56
  80. `l0s-app-preview` is among the builder session's commands, its
  prompt not yet changed (step 7).
- 2026-11-03: step 2 done. `ui_run` and `ui_run_csd` run About,
  Widgets, System Monitor, Fonts, Installer and Agent, each now a view
  and a step: `app.start` sets Monitor's first alarm and has Agent find
  `agentd`, and a close not kept ends the program. Fonts asks its faces
  before its window opens. Their screen tests pass (widgets, procmon,
  fontview, installer, launch, responsive, logo-menu).
- 2026-11-03: step 3 done. `page.l0`'s pages, heading rows, footers,
  toolbar page, split, Cancel and confirm, entry widths, toggles, and
  `ui_without` and `ui_key_after` over any list by a key, now what
  Disks, Files, About, Installer, Widgets and Terminal use; Widgets now
  selects the tab before the last one closed, as Terminal and GNOME do.
  `testing.l0` (`UI_TESTING`) is what the toolkit's, Disks', Monitor's
  and Widgets' tests lay views out with. Screen tests pass: widgets,
  procmon, disks, disks-create, partitions, files, vt, installer, fat.
- 2026-11-03: steps 4 and 5 done. `controls.l0`'s switch, check box,
  slider and spinner, and `list.l0`'s boxed list, a scroller of rows
  with widgets at their start and end; Adwaita's object-select,
  list-add and user-trash copied in. A slider's node names its range,
  not its value, so the focus stays on it as it changes; a press or a
  drag sets `NAME.set.N`, Left and Right `NAME.step.±1`. The gallery's
  tabs are pages now, Processes, Controls and Rows; their scenes were
  looked at with `make preview` before the board, which showed the
  switch and spinner centered in the properties' column, now at its
  start. `tests/widgets.sh`'s new cases passed on their first run.
- 2026-11-03: step 6 done. To Do, 150 lines of view and update over
  `ui_run`, `page.l0`, `list.l0` and `controls.l0`, with 12 host tests
  and three scenes; its preview showed its toolbar overflowing the
  window, an entry of 24 characters, before any boot, now 16.
  `tests/todo.sh` passed on its first run. `l0s-app-preview` now runs
  the session's preview under bubblewrap, read-only but `preview/`,
  since a preview is code the session wrote, run on the host.
- 2026-11-03: step 7 done. `tools/l0s-app-new` writes an app of one
  window that checks, passes its tests, previews and builds as
  written; the builder's sessions run it as `l0s-app-new`, and their
  prompt now sends them to `apps.md` first and to preview and look
  before they build. `apps.md`, the recipe, in the `l0s-ui` skill, the
  skill, the UI rule and `l0s-dev`'s checklist pointing to it.
- 2026-11-03: step 8 done, and the goal. By hand, the builder driven
  as the proxy drives it (Opus 5.5 at effort medium, the host's
  claude.ai login, no worktree, so it read this checkout and wrote only
  in its folder), from "A tip calculator: the bill typed in, a slider
  for the tip's percentage, and the tip and the total shown.": it read
  `apps.md`, ran `l0s-app-new`, read To Do, wrote 139 lines of app and
  43 of tests, previewed three scenes, read them, made the window 50
  shorter from what it saw, and built, in 143 s. Booted on QEMU with
  the screen tests' etc, `run tipcalc &` showed it as previewed, its
  entry focused. `make check`, `make test` (3962 passed) and `make e2e`
  (76 cases, 21 screen tests) pass. Done.
- 2026-11-03: the first apps built from a description merged into
  L0S, as the user asked: the builder's Calculator, `user/apps/calc`,
  in a release's system but not the initramfs (the Makefile's new
  `RELEASE_APPS`, staged by `make release-apps`, added by mkrelease's
  `APPS`), and its Installer, in place of L0S's, its button in the
  heading's row; their branches merged, the toolkit's filling, tinted
  and colored buttons, `ui_red_4`, and dark's raised toggle, with tests.
