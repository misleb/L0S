# The desktop

```
 sh ─tty─ vt1 ─┐ compositor protocol                display protocol
     procmon ──┼──────────────────▶ wm ─────────────────────────▶ virtio-gpu ──▶ QEMU
       draw ───┘ (shared buffers)   ▲ ▲                           (or another driver)
                                    │ └── pointer ◀──┐
                                    └──── keyboard ◀─┴ usb-hid ◀─usb─ xhci
                                             (or virtio-input tablet and keyboard)
```

Pixels never travel in messages. They move by sharing pages:

1. A client, such as `vt`, allocates its window's buffer with
   `shm_alloc`, shares it with `wm` with `shm_share`, and draws into it.
2. `wm` shares the same pages on to the display driver, then gives up
   all but the first page of its own mapping: it never reads a client's
   pixels, and the first page keeps the address that names the buffer in
   `attach` and `resize` (`wm.l0`'s `client_trimmed`).
3. The driver builds the screen from the buffers where they are.

What goes over IPC is only which buffers there are, where each goes, and
which rectangles changed.

The display protocol, and what virtio-gpu does for the compositor, are in [display.md](display.md).

**The compositor protocol** ([user/lib/proto/wm.l0](../user/lib/proto/wm.l0)) is what
`wm` serves, as `compositor`, to its clients:

| Request | Does |
|---|---|
| `hello` | `compositor scale S`, so the client learns `wm`'s pid, to share with, and the scale to make its buffer at: S times W×H. Every other number, a window's size, place and damage, its top row, and the pointer, is the desktop's pixels |
| `window W H VA PORT TITLE` | a window of W×H pixels, its buffer at VA in `wm`, shared there with `shm_share`. It opens in front, cascading from 40, 40. Keys typed while it is in front, the pointer in it, and the notices below go to PORT, each a window notice naming ID. A client may open any number of windows, `window` or `csd`, and give each the same PORT, as a GTK app keeps its windows on one connection: the notices tell them apart. The reply is `window ID` |
| `csd W H VA PORT TITLE` | a window as `window` makes one, but one its client decorates, as GNOME's own apps do: `wm` draws no title bar or frame for it, all of it is the client's content, its four corners rounded to 12, and the border round it, its top's too, resizes it. The reply is `window ID` |
| `move ID` | the window dragged with the pointer from where it is, held where the pointer holds it, until the button is up: what a client that draws its own header bar asks as it is pressed, xdg_toplevel's move. Only while the left button is down after a press in that window, and nothing else is dragged (`not pressed`); only the window's client may ask |
| `damage ID X Y W H ...` | each rectangle of the window changed, ID X Y W H again for each, given to the display in one `damage` and shown together |
| `top ID T` | the window's rows read from its buffer's row T on, as a ring: how a client scrolls |
| `attach ID VA N S` | the window's content from now on the buffer at VA in `wm`, N pages, shared there with `shm_share`, its rows S of its own pixels apart, at the window's size: shown in place of the one shown at the next `damage`, which commits it, as `wl_surface.attach` is shown at a commit. `wm` gives it the display under another bank's id than the content's once, and keeps it as one of the window's other buffers, at most two, the oldest given up first: attached again, it is given again only if the window's size has changed; a third new to `wm` takes the oldest's bank, which is given up. The buffer given up stays one of the window's other buffers, whose release `wm` tells the client (below), and which it may name in an `attach`, or in a `resize` as its new buffer. Only the window's client may ask |
| `detach ID VA` | the window's other buffer at VA in `wm`, not attached, which its client paints no more, given up: its id forgotten by the display and its pages by `wm`, as a client gives up the third it kept while the window was resized. Nothing if the window has none there. Only the window's client may ask |
| `frame ID` | the window's client told, by a frame notice (below), once the display shows the next frame: what a client asks once for a change, before the `damage` that shows it, as `wl_surface.frame` is asked before a commit. Only the window's client may ask |
| `resize ID W H [VA N S]` | the window's content is now W×H: in the buffer it has, which must have room for it, its rows where they were, or in a new one at VA, N pages, its rows S of its own pixels apart, shared as a window's is: a client's answer to a size notice (below), or its own choice. `wm` gives the display the content and a chrome to fit under new ids, in the pages they had when they fit, shows them at once and forgets the old ids; the reply comes as soon as the display has the content, so the client paints the next size while `wm` finishes. The client frees an old buffer once the reply is ok. Only the window's client may ask |
| `edges ID E` | the window resized by its edges E with the pointer, from where it is, until the button is up, as by the border outside it, as xdg_toplevel's `resize` asks: what a client asks when the inside of its own edge is pressed. E adds the edges' bits, left 1, right 2, top 4, bottom 8: one side, or two that meet. As `move`, only the window's client may ask, while the left button is down after a press in the window and nothing else is dragged |
| `maximize ID` | the window made to fill the screen under the top bar, from 0, 32, its place and size kept; or, if it is maximized, put back where it was, at its size: what a double click on a client's own header bar asks. `wm` asks the client for the size with a size notice, as a drag of its right and bottom edges does, and places the window once it answers. Only the window's client may ask |
| `cursor ID NAME` | the pointer shown while it is over the window's content, by name, as `wp_cursor_shape`'s `set_shape`: `default`, the arrow, `text`, the I-beam, or `ew-resize`, `ns-resize`, `nwse-resize`, `nesw-resize`. Kept until asked again or the window closes, and shown at once if the pointer is there. Only the window's client may ask. The toolkit asks it as the pointer moves (see [toolkit.md](toolkit.md)) |
| `title ID TEXT` | a new title |
| `close ID` | the window gone. A client's windows also go when it exits, since `wm` watches it |
| `end` | the client asking it killed, its windows closing with its exit: what the toolkit asks for a program that did nothing with the close of its last window, since a program cannot end itself but by returning from `main`. Refused for a driver |
| `desktop CMD ...` | a drawing command, as `draw` takes them, drawn on the desktop |
| `windows` | a line a window, front first, `ID TITLE X Y W H` then `front` or `-` and its client's pid, so two windows of one client show it, then `buffer B frames F`, the display's id of the content it shows and how many frames its client has been told; then `pointer X Y`, and the pointer's name if it is not the arrow (`ew-resize`, `ns-resize`, `nwse-resize`, `nesw-resize` over a window's edges, or what its client asked for over its content, such as `text`) |
| `launch NAME ARG ...` | the app NAME launched with the ARGs, as the launcher launches it (below), the launcher closed: NAME its name as the launcher shows it, its bundle's name, or its exec, the first app of one kind that matches, the apps read again if none does; the ARGs words, each an argument of the `open` sent on. `ok` once it is launched, or `error: no app NAME`; what `open` asks |
| `apps` | the apps in `/Applications` read again, if `/` is a volume and its bundles are not those known, and the launcher's page painted again: what opening the launcher does already |
| `place ID X Y W H` | the window's content made W×H at X, Y, below the top bar: its client asked for the size with a size notice, as `maximize` asks, and the window placed once it answers, or moved at once if it is that size; no longer maximized. W×H must fit the screen. Any client may ask, as the agent does ([agent.md](agent.md)) |
| `raise ID` | the window brought to the front with the keyboard's focus, as a press on it brings it. Any client may ask |
| `dismiss ID` | the window's client asked to close it, with the close notice, and the window closed by force if it is open 2 s later: what its close button does. Any client may ask |
| `grab CODE PORT` | the key of Linux code CODE (0 to 767), pressed, released and repeated, sent to PORT as the keyboard's driver sent it, before anything else sees it: whatever window is in front, and while the launcher, the status menu or a screenshot's area is shown. Its client keeps it until it exits, which `wm` watches; grabbing it again moves it to another PORT; refused while another client has it. What `speech`'s key to talk is ([speech.md](speech.md#the-speech-service)) |
| `paste X Y W H VA` | the buffer at VA in `wm`, shared there with `shm_share`, W×H of the desktop's pixels (S times each way in the screen's), ARGB words row after row, not premultiplied, drawn over the desktop at X, Y by each pixel's alpha (`ui_mix`, to a percent), what falls off the screen left out; the desktop damaged where it is, and the buffer given up. W×H must fit the screen |
| `capture X Y W H VA` | what the screen shows in X Y W H, the desktop's pixels, copied by the display ([display.md](display.md)) into the buffer at VA in `wm`, shared there with `shm_share`, W×H times the scale each way of the screen's pixels, a window's buffer's words row after row: the windows, the bar and the desktop as they show, without the pointer; the buffer given up after. Refused for a rectangle off the screen. What `snip` asks |

`wm`'s own buffers are the desktop (the wallpaper, and what `draw`
draws), buffer 0; the pointers, its cursor set, each made once at start
(`with_pointers`): Adwaita's arrow, 1, and from 100001 the I-beam
(`text`), the four resize pointers and the crosshair, in
`ui_cursor_names`'s order, all seven painted one under another in one
region and each given as a 64×64 buffer of its own 4 pages; the top
bar, 2; the launcher's page, 3; the status menu's card, one buffer
given as 100000 at its height with power closed and 99999 with it
open; a client's capture's buffer, 150000, while it is captured into;
the frozen screen while a screenshot's area is chosen, 150001; and each window's
chrome, its title bar with the frame under it, one buffer as big as the
window: window i's content and chrome being 4 + 4i + 2k and 5 + 4i + 2k,
k a bank, 0 or 1, the content's and the chrome's each its own, and the
content's third bank, 2, for a client's third buffer, 200000 + i. A
resize gives the display a window's buffers at their new size under
another bank's ids, the content's that of the other buffer it is in, if
it is in one, shows them, and only then forgets the old ones, since the
display refuses to forget a buffer that is on the screen; the content
of a client that has attached other buffers is kept, as one more,
under its id. A commit shows the attached buffer under its bank, which
becomes the content's. The layers it gives the driver are the desktop, then
each window from back to front, its chrome and then its content, then
the top bar over them all; while the launcher is open, the desktop, the
launcher under the bar, and the bar, the windows left out; while a
screenshot's area is chosen, the frozen screen alone.

The top bar is GNOME Shell's: 32 rows across the screen, black, with
**Applications** at its left, a button its
label's width in Source Sans 3 (`bar_apps_w`, measured as the toolkit
measures text) and 12 either side, then the name of the front window's app in
white, or its title if its client is no app, and the date and time,
bold, in its middle, as GNOME shows them by default (`Oct 15  22:42`,
on a 24-hour clock), and the **status menu**'s button at its right
end. All of the bar's text is in Source Sans 3, as are
the title bars', the launcher's names and the status menu's, as GNOME
Shell's are in its interface font; the clock's digits are tabular, so
it does not move as the minutes change. An app's name is its bundle's manifest's: `wm`
reads every manifest in `/Applications` as it starts, and again each
time the launcher opens if `/` is a volume and the bundles in
`/Applications` are not those it knows, and names a window by where its
client's program is, from `proc_info`; the manifest of a program it has
not scanned yet is read at that moment. `wm`
repaints the bar when the front window or its title changes, when the
launcher or the status menu opens or closes, when the volume changes,
and when the clock says a minute has begun.

**The status menu** ([user/sbin/wm/status.l0](../user/sbin/wm/status.l0))
is GNOME Shell's status area and its quick settings. Its button, at the
bar's right end, shows the default output's speaker, by its volume
(`audio-volume-muted` at 0, `-low` to 33, `-medium` to 66, `-high`
above), once the audio server has said it, and the power icon: 36 wide
with the power icon alone, 60 with both. A click on it, acting on its
release over it, lights it with a pill and drops a card, 360 wide, 4
in from the screen's right edge and 4 under the bar, in its own buffer
(a layer over the windows and under the bar, in the display's layers
only while it is shown), laid out with the toolkit's widgets and painted
by `wm`:

- a row of round buttons at its end: **screenshot**, which closes the
  card and starts choosing an area (below); **settings**, which does
  nothing yet; and **power**, which opens, under the row, a boxed list
  of **Restart**, which restarts the board as `reboot` does
  (`board_restart`), and **Shut Down**, which kills pid 1 (`proc_kill
  1`), so `boot` exits and the kernel halts. Neither tells anything
  first, a stand-in for a safer shutdown. The card is 104 high, 216
  with power open;
- the volume's row: the speaker's icon and a slider of the default
  output's volume, 0 to 100, which a press sets and a drag moves; or
  `No sound output` while the audio server has none, or has not
  answered.

Esc, a click outside the card or on the bar closes it. While it is open
no window is told of the pointer or the keys (`tests/status-menu.sh`).
`wm` is a client of the audio server ([sound.md](sound.md)), whose
answers come on a port of its own: it looks the server up as it starts,
and, until it is found, each minute and each time the card opens; asks
it to `watch`, then for its `devices`, the default output among them,
and that output's `volume`; asks the devices again when a device comes
or goes, and the volume again each time the card opens, since no notice
says another client changed it. The slider sets it with `volume ID PCT`,
one ask out at a time: a value moved to meanwhile is shown at once and
sent when the answer comes (`tests/screenshot.sh`).

**Screenshots** ([user/sbin/wm/snip.l0](../user/sbin/wm/snip.l0),
[user/bin/snip](../user/bin/snip/snip.l0)) are GNOME's area
screenshots. The status menu's screenshot button freezes the screen:
`wm` makes a buffer the screen's size, has the display `capture` the
whole screen into it ([display.md](display.md)), keeps its pixels, and
shows it alone over everything, the pointer a crosshair. A press starts
an area there and a drag grows it, either way, kept on the screen and
outlined 2 pixels thick in the accent color, `3584e4`, the pixels under
the old outline put back from those kept; Esc gives up. The release
gives up the frozen screen and starts `/bin/snip X Y W H` for the area,
which asks `wm` to `capture` it from the screen as it is now and saves
it as a PNG, its rows filtered and deflated
([user/lib/format/png.l0](../user/lib/format/png.l0),
[deflate.l0](../user/lib/format/deflate.l0)), at the screen's own
pixels, in `/Volumes/data/user/Screenshot-YYYY-MM-DD-HH-MM-SS.png`, the
clock's local time, making `user` if it is missing; it says `saved
PATH, W x H, N bytes` in the log. From a shell, `snip` takes the whole
screen, or `snip X Y W H`, and a FILE after either.

**The launcher** ([user/sbin/wm/launcher.l0](../user/sbin/wm/launcher.l0)) is GNOME
Shell's grid of apps. A click on Applications, acting on its release
over it, lights the button with a pill and shows a page under the bar,
`242424`, of each app's 48×48 icon with its name under it, in cells
136×104, in rows from 64 below the bar, in the middle of the screen, in
the archive's order, or, once `/` is a volume, the name order its file
server lists them in. A click on an app closes the page and launches
the app (below). Esc, a click on the page, or
Applications again closes it. While it is open no window is told of
the pointer, the wheel or the keys. Its page is one buffer, painted
when `wm` starts and again when opening it finds a changed set of
bundles: the apps of the initramfs never change, but an app copied into
`/Applications` on a system volume, a bundle `mkdir`, `cp`, `write` and
`append` make, is there the next time it opens (`tests/launcher-install.sh`).

**An app's name and its open** ([user/lib/proto/appopen.l0](../user/lib/proto/appopen.l0)),
as a `GApplication` owns its name on the session bus: an app's name is
`app.EXEC`, EXEC its manifest's `exec` (`app.files`, `app.vt`), and a
running app is launched again by the request `REPLY open ARG ...` to
the port registered as that name: its arguments, paths or URLs, or
none, each its length as a u16, least significant byte first, then its
bytes, so one may hold spaces, the whole within one message. The answer,
to REPLY, is `shown ID`: the window to bring to the front, 0 for the
app's front one. What an open does is the app's own.

**Launching** ([user/sbin/wm/launching.l0](../user/sbin/wm/launching.l0))
goes one way, whatever asks it: the launcher,
or the compositor's `launch`, which the command `open` asks. `wm` looks
the app's name up. Found, the
app is running: `wm` sends it `open` with the launch's arguments, its
answer to `wm`'s own port, and waits for it on its alarm, 2 seconds at
most; then the window the answer names, or the app's front window if it
names 0 or none of the app's, comes to the front with the focus, as a
press on it would bring it. An app that does not answer in time has its
front window brought forward all the same, and `wm` says so once
(`disks did not answer its open within 2 seconds`). Not found, `wm`
starts the app's program, with the arguments if there are any and
otherwise the inittab's for it, watching it as it does any client so
that its slot is free once it exits, and `wm`'s terminal, the serial
line, as its own; and keeps the app as starting until its first window
opens, which the toolkit opens only once the name is registered, 10
seconds at most. A launch while it is starting is held, and launched
again, so sent to the app, once that window has opened: two quick
clicks start one process. A program that never registers its name is
started again for a launch held meanwhile, as before there were names;
one that opens no window in its time has its held launches sent if its
name is registered by then, and dropped if not, and `wm` says so. An
exit gives up whatever `wm` waited on the process for.
The clock is
`rtc clock` ([user/sbin/rtc](../user/sbin/rtc/rtc.l0)), which serves `clock`
([user/lib/proto/clock.l0](../user/lib/proto/clock.l0)): `listen` replies `time S`, S
the board's count of seconds since 1970 in UTC, and sends `time S` again at the start of
every minute; `time` replies once; `set S` replies `ok`, and the clock
says S from then on, the board's count with what the set moved it by
added, and tells each listener `time S` at once, so the bar shows it
then, and sets its alarm for the minute after S (on the Pi 5 it also
writes S to the RTC, see [pi5.md](pi5.md)); `zone` replies `zone M U`,
the zone the time is shown in, M minutes east of UTC, in force until
the clock says U, when it next changes. `wm` waits a second for a clock as
it starts, after the keyboard and the pointer, on `compositor`'s port
before it registers it, so only the clock answers there, then asks its zone; with
none, the bar shows no time. The clock counts UTC everywhere: QEMU
starts the PL031 at this machine's time in UTC (`-rtc base=utc`, in
`tools/qemu-boot.sh`, the e2e cases' `l0 boot` and `make boot`), and
on a Pi 5 `ntp` sets it to UTC. The bar shows S in the zone, S plus M
minutes, and once a minute's `time S` reaches U, `wm` asks the zone
again and shows the time in the new one as its answer comes.

The zone is `rtc clock`'s alone
([user/sbin/rtc/zone.l0](../user/sbin/rtc/zone.l0)), so that every
client asks the one place: US Pacific time, PST, UTC−8 (`zone -480`),
and PDT, UTC−7 (`zone -420`) from 2:00 local time on the second Sunday
of March (10:00 UTC) to 2:00 local time on the first Sunday of
November (9:00 UTC), the US rule since 2007. `fs` dates FAT32's files
in it ([fat32.md](fat32.md)); UUIDs, `rtc`'s and `ntp`'s log lines
(which say `UTC`), and `inet`'s lease keep UTC.

Windows open below the bar, and a drag stops a window's top at the
bar's foot, so the bar never hides a title bar. A press on the bar does
nothing, and no window is told of the pointer while it is over the bar,
unless a press in its content holds it. Each title bar is an
Adwaita header bar, laid out and painted by the toolkit
([user/lib/ui](toolkit.md)), 46 rows, as wide as the window.

Under the content is the window's frame, a buffer of `wm`'s 4 pixels
wider than the content and 2 higher, the content 2 pixels in from its
left: the 2-pixel border down the content's sides and along its foot,
painted in the title bar's ground, `303030` in front and `242424` in the
backdrop, and repainted with it. The content covers the rest of the
frame, which is never painted. So a window W×H is W + 4 wide and
46 + H + 2 high; `windows` gives its top left and W and H, its
content's size, and the pointer goes to the client relative to the
content, as before. A press on the border brings the window to the
front and goes to no client. `wm` shapes the title bar's top corners
and the frame's bottom corners to Adwaita's 12-pixel radius, and the
content's bottom corners to 10, inside the frame's, and a press in a
cut corner falls through to what is beneath.

A window its client decorates (`csd`), as Files and Terminal (`vt`) are, has none of that:
no chrome, no buffer or layer of `wm`'s for it, so one fewer layer in
every restack and one fewer region of `wm`'s. It is its content alone,
W×H at its top left, `windows` giving that place; its four corners are
shaped to 12, and a press anywhere in it goes to its client. The client
paints its outline, as libadwaita outlines a window on dark: a line a
pixel wide just inside its edge and along its cut corners, 10% white
over the window's ground (`3a3a3a`), over everything else in it, a
terminal's drawing too, so its edge shows on a dark desktop or over a
dark window, as a frame's does. The client draws its own header bars, the toolkit's `UiCsdBar`, and a press on one's
ground asks `wm` to `move` the window, which `wm` then drags as by its
own title bar, and a second press there within 400 ms, a double click,
asks it to `maximize` the window, or to restore it; its close button is the client's, which closes the window
and exits. The 6-pixel border outside it, on all four sides, resizes it,
and so does the inside of its edge, 3 deep, within 20 of a corner both
the edges that meet there: a left press there asks `wm` to resize the
window by those `edges`, which `wm` then drags as by the border.

Input:

- **Every notice names its window.** Whatever `wm` sends a client about
  a window, a key, the pointer, the wheel, a leave, a focus or a size
  notice, goes as a window notice, as Wayland names the surface in each
  event: `win`, the window's id as a u32, then the notice as below
  (`win_notice` in [user/lib/sys/l0s.l0](../user/lib/sys/l0s.l0);
  `win_notice_of` reads the id and where the notice starts, in place,
  and `key_event_at` and the rest read the notice there). The drivers'
  notices to `wm` are as they were; `wm` puts the window before them as
  it passes them on. The toolkit's `ui_event_of` takes only its own
  window's, any other as `UiOther`; `vt` likewise.
- **What the drivers send** is told apart by what it says, a key's
  notice or the pointer's, not by which of them sent it: one process
  may serve `keyboard` and `pointer` both, as `usb-hid` does. Only a
  message from a driver `wm` listens to is taken as input.
- **Its two ports**: `wm` listens to `keyboard` and `pointer` on a port
  of their own, and takes everything else, the requests, the clock's
  time, the display's frames and releases, exits and its alarm, on
  `compositor`'s, waiting on both as a set. The set gives the oldest
  message of either first, so nothing passes anything: input is handled
  in the order it came with the requests, and a key typed after a
  window was raised, closed or opened goes where the request left the
  focus. A port's queue holds 32 messages, so a flood of requests that
  fills `compositor`'s leaves the drivers' notices room on theirs,
  which a full queue would refuse (`SendFull`, the notice lost). A
  mouse's moves waiting next are joined into one move
  (`gathered`), stopped by a change of the buttons held, a wheel's turn,
  or anything else that came before the next move, request or not.
  From `usb-hid`'s notice to the display's `move` done, a move takes
  3.5 ms or so on QEMU, 4.5 at the most for nine in ten, alike with no
  client and with a Terminal printing, System Monitor and Widgets.
- **Keys** go to the front window's client, as the `KeyEvent` notices
  the keyboard driver sends, their bytes passed on as they came after
  the window notice's id: `key` and four u32s, the Linux key code; 1
  pressed, 0 released, 2 repeated; the character it types (`keymap.l0`,
  with Shift, Caps Lock, and Ctrl with a letter as its control
  character); and the modifiers held as it went, not counting itself,
  Shift 1, Ctrl 2 and Alt 4 (`key_mod_shift` and the rest), either side
  of each the same. Both keyboards send them alike, `virtio-input`'s
  and `usb-hid`'s from its reports' modifier byte.
- **The pointer**'s place, 0 to 32767 on each axis from a tablet,
  `virtio-input`'s or QEMU's USB one through `usb-hid`, is
  scaled to the screen and sent to the driver as a `move`. A mouse's
  report, a `PointerMotion` from `usb-hid`, moves it instead from
  where it is, a pixel a count, kept on the screen; its wheel's turn is
  told first, where the pointer was (see [USB](devices.md#usb)).
- **A left press** on a window brings it to the front. On its title bar,
  or on a header bar its client draws, whose client then asks `move`,
  the press starts a drag: the window follows the pointer until the
  button is released. A second press on the same title bar within
  400 ms, a double click, instead maximizes the window, or restores it,
  as `maximize` does for a client's header bar. The screen is rebuilt for it once 20 ms have
  passed since the last rebuild ended, timed from its end and not its
  start: a rebuild can take longer than the pointer takes to move
  (about 9 ms with two windows), so the moves that come in while one runs
  only move the window, and the next rebuild shows the latest.
- **The pointer in a window's content** goes to its client as Wayland's
  does: every move and button change as a `PointerEvent` relative to the
  window. After a press in a window's content, everything goes to that
  window until every button is up (an implicit grab), even outside it,
  where x and y may be negative. When the pointer leaves a window, its
  client gets a leave notice (`leave_notice` in
  [user/lib/sys/l0s.l0](../user/lib/sys/l0s.l0)).
- **The scroll wheel** goes, as a `WheelEvent` relative to the window, to
  the window the pointer would go to: the one whose content it is over,
  or the one holding it since a press. It counts steps, down and right
  positive, three rows a step in the toolkit's grid.
- **The front window changing** is told to both clients with a focus
  notice (`focus_notice`), so a client can draw itself in the backdrop.
- **Resizing**: the frame's sides and foot, and a border 6 pixels wide
  outside the window's left, right, top and bottom, grab its edges; 20
  pixels along from a corner, the border, the frame and the corners the
  window's shape cuts away grab both edges that meet there. The pointer
  shows which: GNOME's `ew-resize`, `ns-resize`, `nwse-resize` and
  `nesw-resize` (`ui_paint_named_cursor`, smooth from the face at scale
  2); over a window's content, what its client asked for with `cursor`
  (the toolkit: the I-beam over an entry, and the resize pointer inside
  a client-decorated window's edge, as the border outside shows); the
  arrow elsewhere. Showing another is one `cursor` request to the
  display, of a buffer it already has: nothing is painted again. Dragging asks the window's client for the size
  that gives (`size_notice`, "siz" and two u32s, in
  [user/lib/sys/l0s.l0](../user/lib/sys/l0s.l0)): the opposite edge stays,
  at least 200×100, and no further than the screen or the top bar. It
  asks again only once the client has answered, so a slow client is
  asked for the latest size, not every one. A toolkit window
  (`ui_route`'s `UiResize`) keeps room in its buffer, a quarter more and
  64 each way, its rows as far apart as the buffer is wide, so most sizes
  fit the buffer it has and every pixel keeps its place as the window
  grows or shrinks in it. At its next `ui_present` it paints only what
  changed and what the window grew into, and answers with `resize`; only
  a size past that room makes a new buffer, painted whole. `wm`'s chrome
  keeps room the same way, so a resize that fits shares and gives up no
  page, which is what costs most. A client that ignores the notice, such
  as `draw`, keeps its size. `vt` is a toolkit window too: a resize gives
  it the cells that fit its terminal, every tab's lines wrapped again at
  the new width, and it paints its terminal whole.
- **Repainting** (`ui_changed` in
  [user/lib/ui/window.l0](../user/lib/ui/window.l0)): a window paints only
  where what it paints differs from what it painted last, as GTK diffs
  its render nodes. Every paint op is compared, as a multiset: an op both
  times paint is unchanged, wherever it is in the layout; a text is
  compared as the characters it shows where it shows them, not by the
  cell it is in; and a fill only where the other time's fills of its
  color do not cover. So when Disks grows wider, its sidebar is not
  painted again, only the segment bar, what moved and the strip the
  window grew by, about a tenth of the window. The damage is made
  disjoint, the largest first, so no pixel is painted twice.
- **Scrolling** a grid moves what it showed: the scroller's area says how
  high its rows are (`NAME.scroll.FIRST.MOST.SHOWN.STEP`), and when its
  first row moves by less than it shows, `ui_present` moves the area's
  pixels in the buffer (`render.l0`'s `canvas_copy_rows`), as GTK 3's
  copy of an area did, and paints only the rows that came into view and
  the scrollbar's slider, about a third of the rows.
- **A left press on the close button**, the round button at a title
  bar's right end, asks the window's client to close it, as
  `xdg_toplevel.close` does: a window notice of the window, then `clo`
  (`close_notice`). If the window is still open, and still that
  client's, 2 seconds later, on `wm`'s alarm, `wm` kills the client
  with `proc_kill`, and its exit closes its windows, as any client's
  does; if it cannot be killed, being a driver or already gone, `wm`
  closes the window itself. The toolkit gives the notice to its program
  as the action `win.close`, and closes the window itself, and asks
  `wm` to `end` the program, if the program does nothing with it (see
  [the toolkit](toolkit.md)), so every app closes at once, as before.
- **Frames**, as `wl_surface.frame`'s done: `wm` asks the display for
  its notices with `frames` as it starts (see [the display
  protocol](display.md#the-display-protocol)), and says so if it will
  not, its clients then told no frame. A client asks `frame ID` once
  for a change, before the `damage` that shows it; `wm` tells it, as a
  window notice of ID, `frm` and N (`shown_notice`), when the display
  tells its next frame, N being the display's. A frame the display told
  while `wm` was answering something else, before the client asked, may
  tell it a little early; none comes late, as the display counts one
  for every `damage`.
- **Releases**, as `wl_buffer.release`: once the display says one of
  the window's other buffers, which a commit or a resize took off the
  screen, is read no more (its `release` of that id), `wm` tells the
  client, as a window notice, `rel` and 0 (`release_notice`); the
  client paints that buffer again only then. Buffers are released in
  the order given up, so a client with two not shown takes a release as
  the oldest's. A window has three content ids, its banks: a commit
  makes the attached buffer's bank the content's, and a resize another
  with the chrome's, so the content shown and each other buffer are
  always under an id of their own.

## A large screen

On a screen of 2560×1440 or more, such as `make demo SCREEN=3840x2160`
(the virtio-gpu's `xres` and `yres`), the desktop is drawn at scale 2, as
GNOME's scale factor does: laid out in pixels of its own, half the
screen's each way, so a 4K screen is a desktop of 1920×1080, and drawn
at the screen's own resolution, each of its pixels 2×2 of the screen's.
Nothing is doubled: text is Source Sans 3, and Source Code Pro in
terminals, each glyph placed in the screen's own pixels; icons and the pointer are
outlines, and corners are rounded at twice the radius, all with smooth
edges. The boot argument `scale=1` or `scale=2` chooses instead.

- **`virtio-gpu`** takes the screen at the mode the device offers and says
  the scale in `info`; it knows nothing else of it.
- **`wm`** lays everything out in the desktop's pixels: windows, the top
  bar, the launcher, the pointer, `draw`'s shapes and the protocol's
  numbers. Its buffers, and its clients', are twice as wide and high.
  `display.l0` makes its places the screen's on the way to the driver.
- **The toolkit** paints its ops twice the size (`paint.l0`). Text comes
  from the font service's strikes, at 32 and 64 tall, the pointer from
  the face, `/etc/face`, and icons, at every scale, from `/etc/icons`
  ([user/lib/ui/face.l0](../user/lib/ui/face.l0)): coverage, how much of
  each pixel a shape covers, 0 to 15. Each pixel is mixed with what is
  under it by that much, since layers do not blend. A strike a window
  lacks is asked of `font` without waiting: the window answers the
  pointer and the keys while `font` makes it, and its text is drawn when
  it comes ([toolkit.md](toolkit.md), replies, not waits). So does a
  Files window while its folder's file server lists it.
- **The glyphs** are Source Sans 3's and Source Code Pro's TrueType outlines
  ([user/lib/format/ttf.l0](../user/lib/format/ttf.l0)) rasterized
  ([user/lib/gfx/glyphs.l0](../user/lib/gfx/glyphs.l0), with
  `user/lib/gfx/raster.l0`), curves worked out in `float`s and rounded to
  nearest: 16 samples a pixel row, each crossing to 1/256 of a pixel, by
  the nonzero rule, into strikes, regular and bold, 32 tall for text and
  64 for large text: by [tools/mkstrike](../tools/mkstrike/mkstrike.l0) at
  the build for the sizes scales 1 and 2 draw, by `font` on the board for
  any other.
- **[tools/mkfont](../tools/mkfont/mkfont.l0)** makes the face at build time:
  the pointers' outlines in [fonts/cursors.paths](../fonts/cursors.paths)
  (`shape.l0`), rasterized the same way, arcs and strokes too.
- **[tools/mkicons](../tools/mkicons/mkicons.l0)** makes `/etc/icons`: the
  toolkit's symbolic icons are GNOME's own SVGs, under [icons/](../icons)
  (Adwaita's, and System Monitor's, each with its license and a `SOURCE`
  saying where it came from), drawn by the SVG library (`svg.l0`) at
  16, 32, 48, 64, 96 and 128. `make icon-sheet` draws them all into
  `build/icon-sheet.ppm` to look at. A new icon is its SVG copied there
  and its name in `icons.l0`'s `ui_icon_names`.
- **[tools/mkwallpaper](../tools/mkwallpaper/mkwallpaper.l0)** makes
  the wallpaper: [branding/wallpaper-dark.svg](../branding/wallpaper-dark.svg)
  drawn by the SVG library, opaque, at 1920×1080 into
  `/etc/wallpaper.qoi` and at 3840×2160 into `/etc/wallpaper2x.qoi`, as
  QOI ([user/lib/format/qoi.l0](../user/lib/format/qoi.l0)): 232 KB and
  530 KB, where PPMs would be 6 MB and 25 MB, more than the initramfs
  has room for. Every target's initramfs carries both.
- **Full-color icons**, as Nautilus and GNOME Disks show things, are
  Adwaita's SVGs under `icons/adwaita/scalable`: folder,
  text-x-generic, application-x-executable, drive-harddisk,
  drive-multidisk and computer (`icons.l0`'s `ui_image_names`).
  `tools/mkicon --image` draws each into `/etc/images/NAME.face`, its
  images at 16, 32, 48, 64 and 96 with their alpha. Files and Disks
  load the ones they show, at the sizes their scale paints only
  (`face.l0`'s `ui_images_load`), and paint them as `UiPImage`s, in the
  grid, the list and the sidebar; a sidebar row or a tile whose image
  is missing shows its symbolic icon.
- **`vt`**'s cells are still 8×16 of the desktop's pixels; it scrolls by
  copying 32 of its buffer's rows a line.
- **The launcher** shows each app's `icon2x.ppm`, which `tools/mkicon`
  draws at 96×96 from the same `icon.svg` or `icon.draw`.

The GPU composes the screen as it does at scale 1, from the buffers
where they are. It does not draw: the installed QEMU has no virgl, so
the guest's CPU paints every pixel. A 4K screen's backing is more runs
than a 1280×800 one's, so the 64-entry control queue has less to spare
(see [Limits](display.md#limits)).

## Limits

- **Disks shows the one disk, and cannot take anything away.** It can
  make a partition of free space, give a partition a new volume, format
  a mounted volume, keeping its label and size, and have `fs` rescan;
  it cannot delete, resize or relabel a partition or a volume (Files and
  `relabel` relabel one), nor choose a partition's type or name. Sizes
  are typed in kB, whatever the disk's size. Its window is a fixed 880
  by 520, as every window is, and it reads the disk only when it opens
  and when asked.
- **Files works on one thing at a time, and does not copy.** It selects
  one thing, so there is no selecting several, no rubber band, no
  dragging and dropping, no cut, copy or paste, and no trash: Delete
  deletes for good, and a folder only once it is empty. It lists a place
  when it goes there and after it changes something, not when another
  program does, until Refresh. A file is shown as text only,
  its first 64 KB, 2000 lines of 240 characters at most, ASCII; and a
  program it starts has no terminal. With nothing to copy, Ctrl-C and
  Ctrl-V do nothing. Its window, like every
  client-decorated one, has no shadow.
- Only toolkit windows can be resized or maximized (`draw` ignores the
  size notice, so a double click on its title bar leaves it as it is).
- Any client may place, raise or close another's windows, draw on
  the desktop and read the screen (`place`, `raise`, `dismiss`,
  `paste`, `capture`): nothing asks which may. A `place` of a window whose client ignores the size notice
  moves it only if it is already that size.
- **Terminal (`vt`) is a terminal of lines, not a screen.** Its only
  shortcuts are Ctrl-Shift-T for a tab and Shift-Page Up and Down for a
  page of the scrollback.
  There is no selecting, copying or pasting; no escape sequence moves
  the cursor, colors text or clears the screen (the line editing drops
  them); and a program is not told the terminal's size, so nothing it
  writes is laid out for it. Its scrollbar shows only while the view is
  back, and its slider is not dragged. A Terminal's windows, all in one
  `vt`, have at most 31 tabs between them, as `vt` waits on a port a
  tab and its app's one port, which every window's notices share, a set
  of at most 32; a closed tab's port, of any window, is kept for the
  next, since no call gives one back.
  A client paints what changed for every size it is asked for, all of it
  when the size outgrows its buffer, and `wm` restacks the screen once:
  on this host's QEMU Disks's drag paints about 13 ms a size, and the
  restack takes 11.5. A layout whose parts all move with the width, as
  a grid whose columns stretch does, paints most of itself all the
  same. A toolkit window paints the buffer the screen does not show,
  `vt`'s terminal too, and while it is resized a third, so that it
  paints the next size while `wm` restacks (see [the
  toolkit](toolkit.md)). `wm` opens a region for each window, its
  chrome's, and closes it when the window closes; the proc runtime keeps
  at most 64 open at once, so `wm`, which keeps four of its own (the
  desktop, the pointer, the top bar and the launcher) and one for the
  status menu's card, can have 59 windows open at once (one fewer while
  a screenshot's area is chosen), and open them for ever; a resize past a buffer's
  room holds one more for a moment, and is refused if there is none. The
  pointers are the seven `wm` makes: a client asks for one of them by name,
  and cannot give an image of its own. The close button asks
  its client to close the window, and gives it 2 seconds to, however
  long it needs, as a dialog asking to save would: then it is killed,
  whatever it is doing. The pointer has
  one button that does anything, the left: `wm` passes the others on to
  the window under the pointer, and the toolkit drops them.
- **The status menu has a screenshot button, settings that do nothing
  yet, power, and the default output's volume**, and nothing more of
  GNOME's quick settings: no toggles, no other device's volume, no
  mute. The volume it sets is the audio server's, kept only until the
  server restarts or reloads `/etc/audio`. A change another client
  makes shows only when the card opens again.
- **A screenshot is of an area chosen with the pointer, and nothing
  else**: there is no screen or window mode, no Print Screen key, no
  dimming outside the area, no handles to change it once the button is
  up, and no notice that it was saved but the log's line. The frozen
  screen is what was chosen on; `snip` captures the screen as it is a
  moment later, which differs only where something drew meanwhile. A
  screenshot is saved at the screen's own pixels, to
  `/Volumes/data/user`, which the demo's 744 KB volume fills after a
  few full-screen ones.
- **Any process may set the clock**, with `set S`, as many times as it
  likes; `rtc clock` asks nothing of who sets it. What a set moved a
  PL031 by is kept only while `rtc clock` runs, so QEMU's board is back
  at the host's time after a reboot; only the Pi 5's RTC is written.
- **The zone is fixed at US Pacific time.** Nothing chooses another,
  on QEMU or a Pi 5, until a configuration tool can; there is no tz
  database, only the US rule of 2007, taken for every year (before 2007
  too, when the US changed on other Sundays). The bar does not say the
  zone, and a minute's time that crosses a change is shown in the old
  zone until `wm` has the new one's answer, a moment later.
