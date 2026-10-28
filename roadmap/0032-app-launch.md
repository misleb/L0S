# 0032: Apps launched one way: a running app is asked, not started again

Track: Desktop · Status: blocked · Needs: 0021 · Spec: desktop.md, toolkit.md, programs.md, testing.md

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

- [ ] The open request, pure (`user/lib/proto/app.l0`, beside the
  manifest's reading): `open` and its arguments as bytes, each
  argument length-prefixed so a path may hold spaces; the answer,
  `shown ID`; the name of an app's port, `app.` and its `exec`. Read
  and written in place, with host tests, refusals included.
- [ ] The toolkit's side: a `UiApp` (0021) registers `app.EXEC` on its
  port, and gives the app an `open` as the action `app.open` with its
  arguments, through `ui_app_event` as any other. An app that does not
  take it answers `shown 0`, so every app comes forward and none opens
  more, until it says otherwise. Host tests.
- [ ] `wm`'s launch: a launch looks up the app's name; found, it sends
  `open` and waits on the answer, on its alarm, 2 seconds at most;
  not, it starts the program with the arguments and keeps the app as
  starting until the name is registered, holding any launch meanwhile
  and sending it once it is. Then the window the answer names, or the
  app's front window, comes to the front with the focus, as a press on
  it would bring it. The launcher calls it. The choice is a pure
  function of what `wm` knows, tested in `wm_test.l0`.
- [ ] `open APP [ARG ...]`: the compositor protocol's `launch NAME ARG
  ...` and a shell command, `user/bin/open`, that sends it, `APP` an
  app's name as the launcher shows it or its `exec`. desktop.md's
  protocol table, programs.md's row.
- [ ] The apps: Files takes `app.open` as a new window, at the folder
  its first argument names, if it is one; Terminal as a new window, in
  the process the first started; the others come forward only. Each
  app's choice in programs.md. `vt` keeps its tabs: a new window is a
  window of its own, with one tab.
- [ ] The screen test (`tests/launch.sh`, in `SCREEN_TESTS`): Files
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
