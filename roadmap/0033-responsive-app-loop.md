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

- [x] Find out: time each stage of Fonts' step with `clock_ns` (the
  `l0s-testing` skill's timing on the board), with the page open and the
  pointer moving over the back button, and count the messages waiting
  on its port. Write the cause and the numbers in the Log, and fix what
  is Fonts' own, so the rest of the goal is measured against an app that
  is not slow by itself.
- [x] The slow step said: the loop times its stages and says a step
  over 16 ms once at the debug level (and again only after one under
  it), in the toolkit, so every app has it. Host tests of the line.
- [x] Putting together: before a step, the loop takes what else waits
  on the port (`port_try_receive`), keeps the last pointer move and
  size notice and the wheel's sum, and handles every press, release, key
  and request in order. Host tests with a queue of mixed events.
- [x] Keyed layout: a widget keyed by a value keeps the layout and the
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
- 2026-10-28: step 1, measured. Fonts' loop was timed with `clock_ns`
  on QEMU (four CPUs), Source Sans 3's page open, and 39 pointer moves
  sent 5 ms apart across the header bar onto the back button: each
  stage printed (route, update and view, `ui_present`; inside it the
  layout, the strikes wanted, `ui_changed`, the paint and the damage),
  and the messages waiting on the port counted by taking them all
  (`port_try_receive`) before each step. Every move was a step of 366
  ms: route 0.0, update and view 0.1 to 0.2, layout 53, strikes 0 (none
  asked: `font` is not it, as the Log said), `ui_changed` 312, paint and
  damage 0 (nothing differed: a hover of the header bar's ground lights
  nothing). The queue held 32, the port's most, at the second step, so
  the moves after were dropped and the 32 waiting were 12 seconds of
  steps; a hover of a second or two is a few moves' worth. The cause is
  the toolkit's measuring of text, not Fonts': `ui_changed` keys each
  text op by what it shows (`ui_op_key`, its `ui_ellipsized`), old and
  new, so the page's twelve lines, eleven of them wider than the window,
  were ellipsized 24 times a step, and `ui_fitting_before` measured the
  whole start again for each character it added, the square of 95
  characters a line; and each character's measure looked its face up by
  `ui_font_metric`, which made the list `split_spaces "code code-bold
  sans sans-bold"` and searched it, twice a character (advance and
  kerning). The layout's 53 ms was the same measure, by `ui_measure`,
  of every text, at each box above it. On the host the page's
  `ui_changed` took 27 ms and its layout 4.4.
  Fixed in the toolkit (`paint.l0`), so every app has it: the face is
  found from the font itself (`ui_font_metric` matches `UiMono`,
  `UiSans`, or a `UiFontAt`'s name against each literal), once a string
  (`ui_units_m`, `ui_char_units_m`, `ui_prefix_units_m`, `ui_metric_adv`,
  `ui_metric_kern`), and the fitting adds each character's advance and
  kerning once (`ui_fit_walk`), its result the same as measuring each
  start whole (`paint_test.l0`'s `test_fitting_agrees`, 300 seeded
  strings, faces and widths, and `test_fitting_codes`). After: a move's
  step is 6.5 ms on QEMU (layout 2.5, `ui_changed` 3.5), the queue at
  most 5, and the button lit in the first screendump taken after the
  burst; on the host the page's layout and diff are 0.1 and 0.2 ms.
  Nothing was Fonts' own: its view is small and asks nothing. What is
  left for the later steps is the layout and diff done again for every
  move (step 4) and the moves not put together (step 3).
- 2026-10-28: step 2, the slow step said, in a new library,
  `user/lib/ui/uiloop.l0` (`UI_WINDOW`), which steps 3 and 5 grow into
  the loop itself. The design calls:
  - **Timed where the toolkit already is.** An app's step is its own
    code between the toolkit's calls, so the toolkit times what it
    sees: `ui_route` keeps its start and end in the window (a new last
    field of `UiWin`, its `UiLoop`, whose `UiTimes` are the step's), and
    `ui_present` times the layout, the strikes asked of `font` (the
    wait), the paint (`ui_repaint` gives when its painting ended, as
    `ui_swapped` does) and the present, and adds the route and the
    update and view, the time from the route's end to the present's
    start. The update and the view are one stage: the view is an
    argument of `ui_present`, made before it is called, so nothing of
    the toolkit's runs between them. No app changed.
  - **Once, then again after one under.** A step over 16 ms
    (`ui_frame_ns`) is said if none was since the last step under it
    (`ui_slow_due`), so a drag that is slow every step says so once.
  - **At the debug level, in the program's name**, `debug_as` with the
    file name of `proc_path`, asked only when it says: `dmesg` shows
    it, the serial line does not, as every per-event line is kept.
  Host tests (`uiloop_test.l0`): the line, its milliseconds, when it is
  due, the stages from the times, a route timed, and the said flag
  after a slow step and after a quick one. On QEMU, Fonts opened and a
  face's page with it, `dmesg` said, of Fonts' first present and of the
  page's: `fontview: slow step: 1440.3 ms: route 0.0, update and view
  0.0, layout 8.6, wait 1391.5, paint 36.4, present 3.9` and `slow step:
  330.1 ms: route 2.3, update and view 14.8, layout 8.0, wait 231.5,
  paint 72.1, present 1.5`: the wait on `font` for the cards' and the
  page's strikes, which step 5 takes out of the step; the moves over
  the page said nothing, each under a frame.
- 2026-10-28: step 3, putting together. The design calls:
  - **Messages, not events.** What waits is put together as it came,
    before any of it is made an event, since an event needs the
    buttons the window held before it (`ui_pointer_event`), which each
    step before it may change. A pointer notice is a move if its
    buttons are its window's before it: the window's own as the toolkit
    last knew them (`UiWin`'s held, for every window of a `UiApp`) for
    its first in the queue, else the last pointer notice's before it.
    So a press or release is never dropped, and the first notice of a
    window the toolkit does not know is kept.
  - **Runs, one window at a time.** A window's run is its moves and
    wheel turns with nothing else of that window between them; a key,
    a press, a release, a leave, a focus or a size ends it. Of a run,
    the last move is kept, and one wheel turn at the last turn's place
    with the run's steps summed (`ui_wheel_summed`, made as a notice
    again: the tablet sends a turn then a pointer notice for each
    report, so turns are never next to each other, and runs must span
    moves). Another window's messages, and anything not the
    compositor's, end no run, as the order between windows does not
    matter. Of a window's size notices only the last is kept (`wm` has
    one size ask out at a time, so this is for safety).
  - **Where.** The queue is the loop's, `UiLoop`'s second field: a
    `UiApp`'s for its windows (`UiApp`'s new last field), a window's
    own for a program of one (`ui_win_next`, the same loop in its
    `UiWin`). `ui_loop_take` takes what waits on the port (up to 64,
    so a sender that keeps the port full still waits for steps) after
    what the queue holds, puts the whole together, and hands out the
    first; with nothing waiting it waits for one, and takes what came
    with it. `ui_app_next` now gives the app back too (`UiAppNext`),
    as its loop changed; Files' `fl_loop` takes it. Fonts, Disks, About
    and the gallery take `ui_win_next` in place of `port_receive` and
    `ui_event_of`; `ui_event_lost` says the port is gone. System Monitor
    polls with `port_try_receive` and `vt` waits on a set of its own:
    step 6's to bring under the conventions.
  Host tests (`uiloop_test.l0`): moves, a press and a release ending
  runs, a release the window's held buttons make, a window not known,
  wheel turns summed across moves, turns cancelling and a key ending a
  run, a key between moves, two windows, sizes, others, and a property
  test: 100 seeded queues of two windows' moves, presses, turns and
  keys, whose keys, presses and releases come out the same and in
  order. On QEMU, Fonts' page open: 39 moves sent through QMP with no
  gap between them were 8 steps (a debug line a step, since taken
  out), where each was one before; sent 5 ms apart, 34, as a step of
  6.5 ms leaves little to put together. `tests/fontview.sh` passes.
- 2026-10-28: step 4, keyed layout. The design calls:
  - **`UiKeyed KEY CHILD`, a widget**, the key text the program gives,
    as GTK's widgets are kept across frames and only what is queued
    for layout is laid out again. What is kept is found from the last
    layout itself, the nodes the window keeps, so nothing new is kept
    beside them: each part is laid after a mark, a node of no place and
    no ops (nothing hits it, nothing paints it, no focus), whose action
    `ui.kept.N.X.Y.W.H.SIG.KEY` says how many nodes follow, where they
    were laid out and against what (`ui_kept_mark`, `ui_kept_of`). The
    window gives them to the layout in the state, its new last field
    (`ui_st_keeping`), as the state is what every layout function
    already takes; the window keeps its own state without them.
  - **When a part is kept**: its key, its place and its signature are
    the same. The signature (`ui_key_sig`) hashes the ground, the
    backdrop, the style, and the actions under the pointer, pressed and
    focused, each only if it is one of the part's own nodes', so the
    pointer moving anywhere else keeps it and over one of its own
    buttons lays it out again. A part laid where x or y is below 0 is
    laid out again each time (its place is written as whole numbers
    from 0), which only scrolled parts are.
  - **Keyed by what it shows.** `ui_keyed_self NAME W` keys W by its own
    hash, cheaper than laying it out (no text is measured), which
    `ui_grid_page` does for its grid, so System Monitor's and the
    gallery's; Files keys its tiles or rows by their folder, names,
    kinds and sizes and its views' state (`fl_items_key`), not by the
    tiles, whose images a hash would read whole; Fonts keys its page by
    the face. A part's paint is kept too, as `ui_changed` finds its ops
    the same.
  Host tests: `widget_test.l0`'s keyed parts (found again by key, a
  mark not hit, a hover elsewhere keeping the page, one over its own
  button laying it out again, moved or another key laid out again, the
  backdrop, keys with dots), told apart from a fresh layout by kept
  nodes of an action of their own; `files_test.l0`'s key;
  `uiloop_test.l0`'s `test_parts_same`.
  - **Kept parts out of the diff.** Measured on QEMU (every step's line
    said for the run, since put back): keying Fonts' page alone took a
    hover's step from 6.5 ms to 5.6, its layout 1.5 ms but the paint
    stage, `ui_changed` keying all the page's ops again, 4.2. So
    `ui_presented` leaves out of `ui_changed`, on both sides, the parts
    whose marks old and new share (`ui_parts_same`, `ui_parts_out`):
    their nodes are the same. Leaving them out can only paint more,
    never less, as a fill they hold no longer covers another's change.
    A hover's step over Fonts' page is then 2.0 to 2.4 ms: route 0.0,
    update and view 0.1, layout 1.5 (the page still measured, as a box
    measures each child, and the marks read), paint 0.3.
