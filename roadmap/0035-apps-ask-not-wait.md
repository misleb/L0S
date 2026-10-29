# 0035: Disks and Files ask every server as a reply, not a wait

Track: Toolkit · Status: idea · Needs: 0033 · Spec: programs.md, toolkit.md

## Why

0033 gave the toolkit's loop replies (`ui_win_ask`, `ui_app_ask`,
`UiReply`) and idle work (`UiIdle`), and wrote the rule that a step
makes no request that waits on a server (`.claude/rules/l0s-ui.md`, the
`l0s-ui` skill's "A responsive app"). Looking through `user/apps` for
its step 6 left these still waiting in a step, each a request or a few,
which the user asked for, so none is a queue of steps, but each stops
the window for as long as its server takes:

- **Disks** reads a drive's partition table and volumes of its driver
  and `fs` when it is chosen in the sidebar, on Refresh, and after each
  change (`dk_read`, `dk_ios_more`), and makes, deletes, formats and
  labels with one request each, all in its step. A slow disk, or an SD
  card's driver busy with another's reads, stops its window.
- **Files** still asks in a step: `/Volumes`' sizes, a `df` of each
  volume (`fv_volume_sizes`), and the sidebar's frees the same; the
  listing again after a change (`fl_refreshed`), and the changes
  themselves (`fv_mkdir`, `fv_rename`, `fv_delete`); and a file's first
  64 KB shown (`fv_open`'s `FvShown`). Its idle work, a document
  stat'ed or an app's icon read a piece, waits on `fs` for that piece.
- **Terminal** (`vt`) waits on a set of its own, so it takes none of
  the toolkit's replies: a `UiFontAt` it showed would never be drawn.
  It shows none today. The toolkit's loop could take an app's own
  ports into its set, as 0031's Log foresaw, handing their messages
  out as events.

## Done when

- Disks reads a drive, refreshes and changes through `ui_win_ask`, its
  window showing the drive as it was, or a spinner, until the answers
  come.
- Files asks `df`, its refreshes, its changes and a file's text the
  same, and its idle pieces are asks too.
- The toolkit's loop takes ports an app adds to its set, and `vt` waits
  through it.
- Tests: host tests of each state waiting and answered; the screen
  tests of Disks and Files pass as they do.

## Steps

- [ ] Disks' reads and changes as asks.
- [ ] Files' sizes, refreshes, changes and previews as asks.
- [ ] An app's own ports in the loop's set; `vt` through it.

## Spec changes

- programs.md: Disks' and Files' rows, what they show while asking.
- toolkit.md: the loop's set taking an app's ports; Limits without
  `vt`'s.

## Log

- 2026-10-28: written from 0033's step 6, the apps checked against its
  conventions.
