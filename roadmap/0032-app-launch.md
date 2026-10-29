# 0032: Apps launched one way: a running app is asked, not started again

Track: Desktop · Status: done · Needs: 0021 · Spec: desktop.md, toolkit.md, programs.md, testing.md

## Why

A click on an app in the launcher starts its program, every time
([desktop.md](../spec/desktop.md), the launcher): a second click on
Files is a second Files process, a second click on Disks a second Disks
over the same disks, and a Terminal or System Monitor that `/etc/system`
started is started again beside itself. Nothing an app does decides
this, and no running app is told it was asked for. A program started
from the shell with `run` is another path again, with no arguments an
app could take as a file to open.

GNOME does it one way: an app is a `GApplication` that owns its name on
the session bus, and launching it, from the dash, a file manager or the
command line, activates the one already running, which opens a window,
opens the files it is given, or does nothing but come forward, as fits
the app. Goal [0021](0021-many-windows.md) gives an app many windows in
one process; this goal makes every launch go through the app that is
running, if one is.

## Done when

- Every app registers a name for itself, `app.EXEC`, `EXEC` its
  manifest's `exec`, on the port its windows use (0021's `UiApp`), and
  answers an `open` request with its arguments: file paths, URLs, or
  none. What it does is its own: Files opens a window (at the folder a
  path names, or its usual place); Terminal opens a window; Disks,
  System Monitor, Fonts, About and the gallery open nothing. It answers
  with the window to bring forward, 0 for its front one.
- `wm` launches an app one way: it looks up the app's name first, and
  if the app is running sends it `open` with the arguments, and if not
  starts its program with them. Either way the app's window is brought
  to the front and given the focus. A launch while the app is starting
  but has not registered yet waits for it and is sent then, so two
  quick clicks start one process. An app that does not answer within 2
  seconds still has its front window brought forward, and `wm` says so
  once.
- The launcher launches this way, and so does a new shell command,
  `open APP [ARG ...]`, which asks `wm` (the compositor protocol's
  `launch`); `run` stays the plain start of a program.
- Tests: the open request and its answer, and `wm`'s choice, start or
  ask or wait, on the host; a screen test in which two clicks on Files
  give one Files with two windows, two on Disks one Disks with one
  window, brought to the front and focused from behind another, and
  `open files /Volumes` a Files window there. `make check`, `make test`
  and `make e2e` pass.

## Steps

- [x] The open request, pure (`user/lib/proto/app.l0`, beside the
  manifest's reading): `open` and its arguments as bytes, each
  argument length-prefixed so a path may hold spaces; the answer,
  `shown ID`; the name of an app's port, `app.` and its `exec`. Read
  and written in place, with host tests, refusals included.
- [x] The toolkit's side: a `UiApp` (0021) registers `app.EXEC` on its
  port, and gives the app an `open` as the action `app.open` with its
  arguments, through `ui_app_event` as any other. An app that does not
  take it answers `shown 0`, so every app comes forward and none opens
  more, until it says otherwise. Host tests.
- [x] `wm`'s launch: a launch looks up the app's name; found, it sends
  `open` and waits on the answer, on its alarm, 2 seconds at most;
  not, it starts the program with the arguments and keeps the app as
  starting until the name is registered, holding any launch meanwhile
  and sending it once it is. Then the window the answer names, or the
  app's front window, comes to the front with the focus, as a press on
  it would bring it. The launcher calls it. The choice is a pure
  function of what `wm` knows, tested in `wm_test.l0`.
- [x] `open APP [ARG ...]`: the compositor protocol's `launch NAME ARG
  ...` and a shell command, `user/bin/open`, that sends it, `APP` an
  app's name as the launcher shows it or its `exec`. desktop.md's
  protocol table, programs.md's row.
- [x] The apps: Files takes `app.open` as a new window, at the folder
  its first argument names, if it is one; the others come forward
  only. Each app's choice in programs.md.
- [x] Terminal's answer: `app.open` as a new window, in the process the
  first started. `vt` keeps its tabs: a new window is a window of its
  own, with one tab. It follows 0031's rewrite of `vt` (its relays
  gone), once both have merged.
- [x] The screen test (`tests/launch.sh`, in `SCREEN_TESTS`): Files
  clicked twice in the launcher, `run windows` showing two windows of
  one client; Disks clicked twice, one window, then a Terminal over it
  and Disks clicked again, Disks in front with the focus; `open files
  /Volumes`, a Files window there. testing.md says what it checks.

## Spec changes

- desktop.md: the launcher launching through a running app; the
  compositor's `launch`; an app's name, `app.EXEC`, and its `open`.
- toolkit.md: `UiApp`'s name and the `app.open` action.
- programs.md: `open`; each app's answer to `open`.
- testing.md: `tests/launch.sh`.

## Log

- 2026-10-28: written, at the user's direction: one way to launch an
  app, through `wm`, which asks a running app first by its named port
  and starts it only if none is, the app deciding what an open does,
  from a new window to nothing, and `wm` always bringing it to the
  front with the focus; an open may carry arguments, a path or a URL.
  It needs 0021's many windows on one port. 0031's wait on several
  ports is not needed, as the app's name can be registered on the port
  its windows use, but would let an app serve its name apart.
- 2026-10-28: step 1, in `user/lib/proto/appopen.l0`, not `app.l0`:
  app.l0 reads manifests and bundles through `PATHS` (`fs.l0`,
  `paths.l0`), which the toolkit's apps do not all link (Disks links
  `fs.l0` itself, so `PATHS` beside it would define its names twice),
  and the toolkit needs the request. `appopen.l0` is pure and needs only
  `ULIB` (`APPOPEN`). The name is `app.` and the program's file name
  (`app_port_name`, of a path or a bare exec). The request is `REPLY
  open` then each argument as a u16 length, least significant byte
  first, and its bytes (`app_open_request`, refused past 65535 bytes an
  argument or one message, 4096); `app_open_of` reads a message in
  place, an `AppOpen`: `AppOpenAsked REPLY ARGS`, `AppOpenBad REPLY
  WHY` for one whose lengths run past its end, or `NotAppOpen`. The
  arguments are made a list each, once, as they are text (paths). The
  answer is `shown ID` (`app_shown`, `app_shown_of`), text, as wm's
  protocol is.
- 2026-10-28: step 2. `ui_app_start` registers `app.EXEC` on the app's
  port, EXEC the file name of `proc_path (l0s_pid)`, so every toolkit
  program, `ui_open`'s too, has its name with no code of its own; a
  second of a program, from `run`, finds it taken and goes without. The
  open is a new event, `UiOpen REPLY ARGS`, read by one
  `ui_message_event` (exit, open, or `UiOther`) that `ui_event_of` and
  `ui_app_event` share, so it comes the same way from the compositor,
  which sends it, or from anyone. The default is GApplication's: routing
  it sets off `app.open` and answers `shown 0` at once, in
  `ui_app_route` (id -1) and in `ui_route` for a program of one window,
  so About, Disks, Fonts, System Monitor and the gallery need nothing.
  `UiApp` gained a last field, whether the app answers its opens itself
  (`ui_app_opening`), then with `ui_app_shown`; the default needs no
  state held across a step, unlike the close's, as the answer is sent as
  the open is routed. Every answer is a `port_tell`, so 0033's loop can
  send it without waiting. Terminal (`vt`) registers `app.vt` through
  `ui_open_csd`, but its own loop drops a notice from the compositor
  that names no window of its (`from_wm`), so it never answers an open:
  see step 5.
- 2026-10-28: steps 3 and 4, in one change, as the compositor's
  `launch` is `wm`'s launch asked by another. The pure part is
  `user/sbin/wm/launching.l0` and its tests, not `wm.l0` and
  `wm_test.l0`, to keep it apart from 0031's changes to `wm.l0`
  (`wm_test.l0` tests the window a launch brings forward,
  `launch_window`, and `port_client`). `launch_choice` takes the
  launches waited on, the exec and the name's lookup: `LaunchAsk PORT`
  if it is registered, `LaunchHold` if the app is starting, else
  `LaunchStart`. A `Launch` is `LaunchAsked EXEC PID PORT DUE` or
  `LaunchStarting EXEC PID DUE HELD`, kept in `Bar`'s new last field,
  not `Wm`'s, which every function of `wm` matches. The open's answer
  comes to `wm`'s own port, so `received`, which 0031 changes, is not
  touched: `replied` takes `shown ID` first (`app_shown_of`; a
  request's first four bytes are its reply port, and "show" read as one
  is no port), and matches it to the open asked of its sender, or else
  the oldest asked of an app with no window known. The alarm is the one
  wm has: `close_alarm` sets it for the soonest close or launch, and
  `closes_due` gives up the launches due too (`launches_late`). An
  answer brings forward the window named, if it is the sender's, else
  its front window, with `raised_by`, as a press does. "Registered" is
  seen as the app's first window: the toolkit registers before it opens
  one, so `window`'s and `csd`'s reply (`window_came`) ends the start
  and launches each held one again, which then asks it; a program that
  never registers is started again for them, as before. A start has 10
  seconds (`launch_start_ns`), as an app loads its face and icons
  first; past it, held launches go to the app if its name is there by
  then, or are dropped, never started again, and `wm` says so. An exit
  ends whatever was waited on of the process (`gone`). The L0S menu's
  About L0S launches the same way. `launch NAME ARG ...` is words, as
  every request of `wm`'s is: `requested` reads them split at spaces,
  and the shell splits `open`'s arguments at spaces already, so no
  argument from it holds one; the open sent on is length-prefixed, so
  another client could pass one. NAME is the app's name, its bundle's
  or its exec (`launch_named`); `ok` comes once launched, not once the
  window is up. `open` is `user/bin/open` (`run open files /Volumes`);
  `/bin/open` joined the `fs` and `shell` e2e cases' listings.
- 2026-10-28: step 5, every app but Terminal; the step is split in two,
  Terminal's answer its own step, which follows 0031's rewrite of `vt`
  once both branches have merged (another agent owns `user/apps/vt`
  meanwhile). Files says `ui_app_opening` and answers an open with a
  window more, in front, at the folder its first argument names
  (`fl_open_at`: an absolute path made normal, that `fv_list` lists),
  else at `/`, keeping the view and sidebar of a window it has, as New
  Window does, and answers with its id; with no room for a window, 0.
  Started with an argument, as `wm` starts it for `open files
  /Volumes` when it is not running, its first window is there
  (`fl_placed`). Disks, System Monitor, Fonts, About and the gallery
  route every message through `ui_route`, so the toolkit's `shown 0`
  answers for them with no change. Until Terminal's step: Terminal is
  started through `ui_open_csd`, so it registers `app.vt` and `wm`
  asks it, but its loop drops the open (`vt`'s `from_wm` passes on
  only notices naming its window), so a launch of Terminal while one
  runs waits `wm`'s 2 seconds, then brings its front window forward and
  `wm` says `vt did not answer its open within 2 seconds`; no second
  Terminal is started. A Terminal's tabs are its new terminals until
  then.
- 2026-10-28: step 6. `tests/launch.sh` boots the disks' initramfs, on
  a fresh disk, as `files.sh` does, since Files lists `/Volumes` only
  with `fs` running; it waits for `wm`'s `serving compositor` before its
  first click, as the shell's prompt comes first. Every check reads `run
  windows`: windows by title, their clients by the pid it gives last,
  never a fixed pid, so 0031's shift of the demo's pids does not touch
  it. Disks is checked to be the same pid after it is clicked from
  behind Terminal; `/Volumes` by the third window's sidebar, its
  Volumes row selected. A limit seen: an app's name is its exec's, so
  two bundles of one program, as `launcher-install.sh`'s copy of
  Terminal would be with the same file name, share one name, and the
  second launched is asked of the first. `/bin/open` is one file more
  in the `install`, `install_boot` and `rootboot_tmpfs` cases' counts,
  which this step's run of `make e2e` found. `make check`, `make test` and
  `make e2e` pass; the goal is done but for Terminal's answer.
- 2026-10-28: Terminal's answer, and the goal done. The design calls:
  - **`vt` is a `UiApp`.** `windowed` starts the app (`ui_app_start`,
    which registers `app.vt`) and opens its first window with
    `ui_app_open_csd`; a `Vts` holds the app, each window's `Vt` by its
    id (a `Map`), the ports of closed tabs, the set last waited on, and
    the cells new windows are opened at (the arguments'). A `Vt` is one
    window and its tabs as before; its loop's code is unchanged but for
    the top: `serve` takes a message on the app's port or a tab's and
    `vts_received` finds its window, by the notice's id (the
    compositor's), by the tab whose port it came on, or by the tab whose
    shell exited (`vts_holding`), and asks it (`Ask`: `AskWm`, `AskTab`,
    `AskExit`, `vt_asked`). An open (`ui_message_event`'s `UiOpen`),
    which comes from `wm`'s pid but names no window, opens a window
    more with one tab (`vts_opened`) and answers with its id
    (`ui_open_answer`), or 0 with why on stderr.
  - **Lent, not shared.** A step of one window may take or give back
    closed tabs' ports, and must know how many tabs the other windows
    have, as the set is the app's: so the app lends the window its free
    ports and that count for the step (`Lent`, `vt_lent`) and takes the
    ports back after (`vts_kept`), rather than every function of a
    window taking the app. A window closing (`Step`'s `Stop V STATUS`)
    gives its tabs' ports back too (`closed_all` lets each tab's name go
    and frees its port; its shells' exits, told later, find no tab).
  - **One set, made by the app.** `vt_waiting` went from inside a
    window's step to the loop: after every message `vts_waiting` makes
    the set again only if its ports (`vts_ports`: the app's port, then
    every window's tabs') are not those it waits on. Terminal's windows
    have at most 31 tabs between them (`tabs_room`), as a set holds 32
    ports (desktop.md's Limits).
  - **One face.** A window is painted with the app's face for its step
    and its face, with any strike it asked for, is the app's after
    (`ui_app_put_faced`), as `ui_app_present` does; a closed window goes
    with `ui_app_close`, which the window's own step no longer calls.
  `vt` ends with its last window, with the status of the shell whose
  exit closed it, or 0 for a close button. `tests/launch.sh` gained a
  fifth check: Terminal launched again is a second window of the same
  pid, in front, titled with its own tab's name, and `wm` never said an
  app did not answer its open. Host tests: `test_tabs_room`,
  `test_lent`, `test_term_win`, `tabs_test.l0`'s `test_first_port`.
  `tests/launch.sh` and `tests/vt.sh` pass, four CPUs.
