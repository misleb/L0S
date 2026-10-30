# 0035: Disks and Files ask every server as a reply, not a wait

Track: Toolkit · Status: done · Needs: 0033 · Spec: programs.md, toolkit.md, storage.md

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

- [x] Disks' reads and changes as asks.
- [x] Files' sizes, refreshes, changes and previews as asks.
- [x] An app's own ports in the loop's set; `vt` through it.

## Spec changes

Moved into the spec as the steps landed: programs.md's Disks, Files,
`vt`, `proto/fs.l0` and `proto/disk.l0` rows; toolkit.md's "Replies,
not waits", a new "A program's own ports", `uiloop.l0`'s row and its
Limits; storage.md's volumes, a program sending the file requests
itself.

## Log

- 2026-10-28: written from 0033's step 6, the apps checked against its
  conventions.
- 2026-10-30: all three steps, in one change. The design calls:
  - **The protocol libraries carry the bodies and the readers.** An
    ask is a port and a body, and its answer a message, so what the
    `_on` wrappers wrapped in `fs_ask` is split out, pure: a body for
    every request (`fs_list_body`, `fs_open_body`, `fs_read_body`,
    `fs_df_body`, `fs_partition_body` and the rest, paths as the
    server knows them) and a reader for every reply (`fs_df_of`,
    `fs_relabel_of`, `fs_partition_of`, `fs_erase_of`, `fs_mkfs_of`;
    `fs_reply_msg` for a message, `fs_read_of` for a read's bytes in
    place, never through a list), which the `_on` wrappers now use
    too. `fs_close_told` closes a handle with no answer wanted, so a
    read's chain ends without a reply to take. `disk_read_body` and
    `disk_reply_why` are the same for a disk. The kernel's own file
    requests, `open`, `read`, `close`, `rename` and `remove`, were
    always served to any pid with its own handles: a program sends
    them itself, which is how Files reads a file's bytes and renames
    and deletes without a kernel call that blocks it.
  - **The toolkit's loop takes a program's own ports.** `UiWaits`
    keeps them (`ui_loop_own`), `ui_loop_set` puts them in the set
    with the window's and the two reply ports, made again when they
    change, and a message on one is handed out before the window's
    own, as replies are, as a new event, `UiPort PORT MESSAGE`
    (`ui_port_of`, `ui_win_ports`, `ui_app_ports`). A set the kernel
    refuses is said as a warning and the loop falls back to the
    window's port alone, as before.
  - **Terminal is an ordinary app of the loop.** Its tabs' ports are
    the app's own; `serve` takes `ui_app_next`'s events, a tab's
    message as `UiPort`, a window's key, wheel or anything else as the
    event the loop made of it (`from_event`, in place of reading the
    notice itself), an exit and an open as events of no window. Its
    own draining, putting together and set-making went (`vt_drained`,
    `vts_batch`, `vts_waiting`'s `port_set`). The app's and the
    toolkit's two reply ports take three of a set's 32, so its windows
    have 29 tabs between them, not 31. A strike that comes is now
    drawn, so `vt` could show `UiFontAt` text.
  - **Disks reads a drive as a chain, one request out.** `DkRead` is
    where the read is (the GPT's header, its entries with the header
    kept, the MBR, a partition's first sector with the parts left and
    the contents so far, a volume's `df` with the sector kept), and
    `dk_read_sectors` and `dk_read_space` go on from each reply to
    the next ask (`DkNext`), pure, tested with the demo's GPT written
    by `gpt_pieces` and a hand-made MBR. `DkWait` is what the window
    has out, with its chain's tag: a read, a change, or a rescan, a
    change's reply asking the rescan and the rescan's reply beginning
    the read, with what to say and select once it is read
    (`DkAfter`). A reply of an older tag changes nothing; a newer
    start replaces a read in flight, but a change or rescan locks the
    window against another drive or start until it is done
    (`dk_locked`). The view takes a busy line: what is waited for at
    the foot in place of the status, Refresh and the part's button
    insensitive, and a status page of the drive's name while it is
    not read yet, as at the start and on choosing a drive. A disk
    registered since the start is still opened at Refresh with an
    `info` ask in the step, once, small, and left so.
  - **Files has a queue of jobs a window.** `FlJobs` is the tag out
    and the jobs in order: a listing (a reply at a time, as before,
    now with what then, `FlShow` or `FlKeep` of the selection and a
    line), `/Volumes` with a `df` a volume, the sidebar's sizes, a
    change (`mkdir`, `rename`, `remove`, `relabel`), a file read
    (`open`, `read` a piece at a time up to the preview's 64 KB or an
    icon's 256 KB, then `close` told) for a preview, an `icon.face`
    or, failing that, an `icon.draw`, and a `stat`. `fl_job_ask`
    makes a job's next ask, or finishes one with nothing to ask;
    `fl_job_reply` takes a reply and says what jobs go on. A new job
    replaces the queue (`fl_jobbed`), except that a file being read
    finishes first so its handle is closed; the sidebar's sizes and
    the idle looks are queued after (`fl_queued`). Idle work now only
    starts a job, a stat or an icon read, and the app has idle work
    only while a window has things to look at and no job out, so the
    loop never spins. `FlListing` left `FlOver`, and `fsview.l0` lost
    its waits: `fv_list` lists the initramfs alone, and `fv_open`
    says a document is to be read (`FvRead`). Starting an app still
    reads its manifest in the step, a small read, left so.
  - Host tests: `fs_test.l0`'s bodies and readers, `disk_test.l0`'s
    body and why, `uiloop_test.l0`'s own port handed out and the set
    made again, `vt_test.l0`'s events and 29 tabs, `disks_test.l0`'s
    whole read of the demo's disk a reply at a time, the MBR, no
    table, a change then a rescan then the read, a stale reply, what
    each change asks, the busy view and the locked window;
    `files_test.l0`'s jobs: a listing's replies, more asked, stale and
    refused, `/Volumes`' sizes, the sidebar's, each change asked and
    answered and refused, a volume relabelled, a file read in pieces
    to a preview, reads refused, idle looks and a stat's reply.
    `make check`, `make test` and `make e2e` pass; the screen tests of
    Disks, Files, Terminal and the responsive hover pass as they did.
