# 0033: An app's loop that keeps its window answering

Track: Toolkit · Status: active · Needs: 0021, 0031, 0032 · Spec: toolkit.md, desktop.md, programs.md, testing.md

## Why

In Fonts, with a face's page open, the header bar's back button takes a
second or two to light under the pointer, and to take a click, though
the page is drawn already. Nothing says why: whether the app is
computing, or waiting on `font` for something more.

Whatever the cause, nothing in the toolkit keeps it from happening in
the next app. An app is one thread, and its loop does all of a step at
once, for each message, as it comes: take the event, update the model,
build the view, lay it out (`ui_layout_window`), find what changed, ask
`font` for any strike it lacks, paint, and present (`ui_present`). Each
pointer move is a message of its own, none is put together with the
next, and the port holds 32, so a step slower than the pointer leaves a
queue that the window works through long after the pointer stopped. A
request that blocks, to `font` or `fs`, stops the window for as long as
the server takes. Two guesses fit what was seen, and the first step is
to find out, not to guess: the face page laid out again, twelve lines
of kerned text at heights up to 64, some cut to fit with "...", for every
move of the pointer over a button; and its strikes asked of `font` on
the way, in the step.

GTK's main loop puts motion events together before a frame, does work
when idle, and talks to servers with replies that come back as events;
an app that does long work there is told by GNOME that it is not
responding. L0S has one thread an app, and cannot stop an app from
blocking itself. It can make the loop do the right thing by default,
make the slow path visible, and write down how an app stays answering.

## Done when

- Why Fonts' back button was slow is found, measured, and written in
  the Log, and Fonts' page answers the pointer within 50 ms on QEMU.
- The toolkit's loop (0021's `UiApp`, which 0032 gives its `open`)
  puts together what it can before it lays out: of pointer moves, the
  wheel's steps and size notices waiting on the port, only the last
  move and size and the wheel's sum are handled; presses, releases and
  keys never are dropped or reordered.
- A view is laid out again only where its model changed: a part of the
  view the app keys by what it shows (`ui_keyed`, or whatever the
  toolkit's widgets take most simply) keeps its layout and paint while
  its key is the same, so a hover over one button lays out that button.
- No request to a server blocks the window: the toolkit's own (strikes
  from `font`) go out and come back as events, on a port the loop waits
  on beside its windows' (0031), and text whose strike has not come
  yet is drawn when it does; an app's own requests can be made the same
  way (`UiReply`), with `fs` the first.
- Work too long for one step is done a piece at a time between events,
  as the toolkit's idle work, each piece bounded.
- A step that takes longer than a frame, 16 ms, is said once at the
  debug level, with how long each stage took (update, view, layout,
  paint, present, and any wait), so the next slow app says why.
- The `l0s-ui` skill gains "A responsive app", the conventions: what a
  step may do, what it must hand to idle work or a reply, how to key a
  view, how to read the debug line; and `.claude/rules/l0s-ui.md` the
  rule that a step does no blocking request. Every app in
  `user/apps` follows them.
- Tests: the putting together, the keyed layout and the replies on
  the host; a screen test that moves the pointer onto Fonts' back
  button and sees it lit in the next screendump, within 50 ms of the
  move; `make check`, `make test` and `make e2e` pass.

## Steps

- [ ] Find out: time each stage of Fonts' step with `clock_ns` (the
  `l0s-testing` skill's timing on the board), with the page open and the
  pointer moving over the back button, and count the messages waiting
  on its port. Write the cause and the numbers in the Log, and fix what
  is Fonts' own, so the rest of the goal is measured against an app that
  is not slow by itself.
- [ ] The slow step said: the loop times its stages and says a step
  over 16 ms once at the debug level (and again only after one under
  it), in the toolkit, so every app has it. Host tests of the line.
- [ ] Putting together: before a step, the loop takes what else waits
  on the port (`port_try_receive`), keeps the last pointer move and
  size notice and the wheel's sum, and handles every press, release, key
  and request in order. Host tests with a queue of mixed events.
- [ ] Keyed layout: a widget keyed by a value keeps the layout and the
  paint of the last view while its key and its place are the same;
  Fonts' page and the grids of Files and System Monitor keyed. Host tests
  that a hover lays out only what it lights.
- [ ] Replies, not waits: the toolkit asks `font` for a strike and goes
  on, the strike coming as a `UiReply` on its second port (0031), the
  text drawn once it is; `UiReply` for an app's own requests, Files'
  listing of a folder first. Idle work: a queue of bounded pieces the
  loop runs while no message waits.
- [ ] The conventions written: the `l0s-ui` skill's "A responsive app"
  and the rule in `.claude/rules/l0s-ui.md`; every app in `user/apps`
  checked against them and changed where it does not follow them.
- [ ] The screen test (`tests/responsive.sh`, in `SCREEN_TESTS`): Fonts'
  page open, the pointer moved onto the back button, the button lit in
  a screendump within 50 ms; the same over a Files window listing a
  large folder. testing.md says what it checks.

## Spec changes

- toolkit.md: the loop's steps and its putting together, keyed
  widgets, `UiReply` and idle work, the slow-step line; Limits: an app
  can still block itself, and what the toolkit does about it.
- desktop.md: that a client's window answers while its server is busy,
  as the toolkit's loop has it.
- programs.md: Fonts' and Files' rows where they change.
- testing.md: `tests/responsive.sh`.

## Log

- 2026-10-28: written, from Fonts' back button taking a second or two
  to light with a face's page open. The toolkit's loop does a whole
  step for every message and reads one message at a time, never
  `port_try_receive`, so a burst of pointer moves is a queue of whole
  steps; whether the step is slow from laying out the page's text or
  from waiting on `font` is the first step's to find. Needs 0021 (the
  `UiApp` loop this changes), 0031 (a second port to wait on for
  replies), and 0032 (the `open` request that loop answers too).
- 2026-10-28: `font` is likely not it. A window's `UiFace` keeps every
  strike it is given, in a map by name, read in place from the pages
  `font` shares, and a refused one as empty; `ui_present` asks
  (`ui_strikes_wanted`, `ui_strike_wanted`) only for those it lacks,
  so a face at a height is asked for once, the first time a window
  shows it, and Fonts' `fv_loop` keeps the window `ui_route` and
  `ui_present` give back, so the map lasts. Once the page is drawn, a
  hover asks `font` nothing: start the first step at the layout of the
  page's twelve kerned lines, done again for every move, and at the
  moves not put together. The map is a window's, not the process's: a
  second window of an app (0021) asks for its strikes again, which
  `font` answers from its cache, a round trip each; the replies step
  could keep them once for the app.
