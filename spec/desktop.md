# The desktop

```
 sh ─tty─ vt1 ─┐ compositor protocol                display protocol
     procmon ──┼──────────────────▶ wm ─────────────────────────▶ virtio-gpu ──▶ QEMU
       draw ───┘ (shared buffers)   ▲ ▲                           (or another driver)
                                    │ └── pointer ◀── usb-hid mouse ◀──┐ usb
                                    └──── keyboard ◀── usb-hid keyboard ◀─ xhci
                                             (or virtio-input tablet and keyboard)
```

Pixels never travel in messages. They move by sharing pages:

1. A client, such as `vt`, allocates its window's buffer with
   `shm_alloc`, shares it with `wm` with `shm_share`, and draws into it.
2. `wm` shares the same pages on to the display driver.
3. The driver builds the screen from the buffers where they are.

What goes over IPC is only which buffers there are, where each goes, and
which rectangles changed.

The display protocol, and what virtio-gpu does for the compositor, are in [display.md](display.md).

**The compositor protocol** ([user/lib/proto/wm.l0](../user/lib/proto/wm.l0)) is what
`wm` serves, as `compositor`, to its clients:

| Request | Does |
|---|---|
| `hello` | `compositor scale S`, so the client learns `wm`'s pid, to share with, and the scale to make its buffer at: S times W×H. Every other number, a window's size, place and damage, its top row, and the pointer, is the desktop's pixels |
| `window W H VA PORT TITLE` | a window of W×H pixels, its buffer at VA in `wm`, shared there with `shm_share`. It opens in front, cascading from 40, 40. Keys typed while it is in front, the pointer in it, and the notices below go to PORT, each a window notice naming ID. The reply is `window ID` |
| `csd W H VA PORT TITLE` | a window as `window` makes one, but one its client decorates, as GNOME's own apps do: `wm` draws no title bar or frame for it, all of it is the client's content, its four corners rounded to 12, and the border round it, its top's too, resizes it. The reply is `window ID` |
| `move ID` | the window dragged with the pointer from where it is, held where the pointer holds it, until the button is up: what a client that draws its own header bar asks as it is pressed, xdg_toplevel's move. Only while the left button is down after a press in that window, and nothing else is dragged (`not pressed`); only the window's client may ask |
| `damage ID X Y W H ...` | each rectangle of the window changed, ID X Y W H again for each, given to the display in one `damage` and shown together |
| `top ID T` | the window's rows read from its buffer's row T on, as a ring: how a client scrolls |
| `resize ID W H [VA N S]` | the window's content is now W×H: in the buffer it has, which must have room for it, its rows where they were, or in a new one at VA, N pages, its rows S of its own pixels apart, shared as a window's is: a client's answer to a size notice (below), or its own choice. `wm` gives the display the content and a chrome to fit under new ids, in the pages they had when they fit, shows them at once and forgets the old ids; the reply comes as soon as the display has the content, so the client paints the next size while `wm` finishes. The client frees an old buffer once the reply is ok. Only the window's client may ask |
| `edges ID E` | the window resized by its edges E with the pointer, from where it is, until the button is up, as by the border outside it, as xdg_toplevel's `resize` asks: what a client asks when the inside of its own edge is pressed. E adds the edges' bits, left 1, right 2, top 4, bottom 8: one side, or two that meet. As `move`, only the window's client may ask, while the left button is down after a press in the window and nothing else is dragged |
| `maximize ID` | the window made to fill the screen under the top bar, from 0, 32, its place and size kept; or, if it is maximized, put back where it was, at its size: what a double click on a client's own header bar asks. `wm` asks the client for the size with a size notice, as a drag of its right and bottom edges does, and places the window once it answers. Only the window's client may ask |
| `title ID TEXT` | a new title |
| `close ID` | the window gone. A client's windows also go when it exits, since `wm` watches it |
| `desktop CMD ...` | a drawing command, as `draw` takes them, drawn on the desktop |
| `windows` | a line a window, front first, then `pointer X Y`, and the pointer's name if it is not the arrow (`ew-resize`, `ns-resize`, `nwse-resize`, `nesw-resize` over a window's edges) |
| `apps` | the apps in `/Applications` read again, if `/` is a volume and its bundles are not those known, and the launcher's page painted again: what opening the launcher does already |

`wm`'s own buffers are the desktop (the wallpaper, and what `draw`
draws), buffer 0; the pointer's image (Adwaita's arrow, or a resize
pointer), 1; the top bar, 2; the launcher's page, 3; the L0S menu's card,
100000; and each window's
chrome, its title bar with the frame under it, one buffer as big as the
window: window i's content and chrome being 4 + 4i + 2k and 5 + 4i + 2k,
k a bank, 0 or 1. A resize gives the display a window's buffers at
their new size under the other bank's ids, shows them, and only then
forgets the old ones, since the display refuses to forget a buffer that
is on the screen. The layers it gives the driver are the desktop, then
each window from back to front, its chrome and then its content, then
the top bar over them all; while the launcher is open, the desktop, the
launcher under the bar, and the bar, the windows left out.

The top bar is GNOME Shell's: 32 rows across the screen, black, with
the **L0S menu**'s logo at its left, then **Applications**, a button its
label's width in Source Sans 3 (`bar_apps_w`, measured as the toolkit
measures text) and 12 either side, then the name of the front window's app in
white, or its title if its client is no app, and the date and time,
bold, in its middle, as GNOME shows them by default (`Oct 15  22:42`,
on a 24-hour clock). All of the bar's text is in Source Sans 3, as are
the title bars', the launcher's names and the L0S menu's, as GNOME
Shell's are in its interface font; the clock's digits are tabular, so
it does not move as the minutes change. An app's name is its bundle's manifest's: `wm`
reads every manifest in `/Applications` as it starts, and again each
time the launcher opens if `/` is a volume and the bundles in
`/Applications` are not those it knows, and names a window by where its
client's program is, from `proc_info`; the manifest of a program it has
not scanned yet is read at that moment. `wm`
repaints the bar when the front window or its title changes, when the
launcher opens or closes, and when the clock says a minute has begun.

**The L0S menu** ([user/sbin/wm/logo_menu.l0](../user/sbin/wm/logo_menu.l0)) is
the logo, `branding/logo.svg`'s mark painted flat in 22×22 pixels, in the
bar's first 32 columns, as the Apple menu is in macOS's. A click on it,
acting on its release over it, lights it with a pill and drops a card, 200
by 114, 4 in from the screen's edge and under the bar, in its own buffer
(id 100000, a layer over the windows and under the bar, in the display's
layers only while it is shown): **About L0S**, which starts the About app;
**Shut Down**, which kills pid 1 (`proc_kill 1`), so `boot` exits and
the kernel halts; and **Restart**, which restarts the board as `reboot`
does (`board_restart`). Neither tells anything first, a stand-in for a
safer shutdown. Esc, a click outside the card or on the bar closes it. While it
is open no window is told of the pointer or the keys
(`tests/logo-menu.sh`).

**The launcher** ([user/sbin/wm/launcher.l0](../user/sbin/wm/launcher.l0)) is GNOME
Shell's grid of apps. A click on Applications, acting on its release
over it, lights the button with a pill and shows a page under the bar,
`242424`, of each app's 48×48 icon with its name under it, in cells
136×104, in rows from 64 below the bar, in the middle of the screen, in
the archive's order, or, once `/` is a volume, the name order its file
server lists them in. A click on an app closes the page and starts the
app's program, which `wm` watches, as it does any client, so its slot
is free once it exits; it gets the inittab's arguments for it, and
`wm`'s terminal, the serial line. Esc, a click on the page, or
Applications again closes it. While it is open no window is told of
the pointer, the wheel or the keys. Its page is one buffer, painted
when `wm` starts and again when opening it finds a changed set of
bundles: the apps of the initramfs never change, but an app copied into
`/Applications` on a system volume, a bundle `mkdir`, `cp`, `write` and
`append` make, is there the next time it opens (`tests/launcher-install.sh`).
The clock is
`rtc clock` ([user/sbin/rtc](../user/sbin/rtc/rtc.l0)), which serves `clock`
([user/lib/proto/clock.l0](../user/lib/proto/clock.l0)): `listen` replies `time S`, S
the PL031's count of seconds, and sends `time S` again at the start of
every minute; `time` replies once. `wm` waits a second for a clock as
it starts, after the keyboard and the pointer; with none, the bar shows
no time. The PL031 has no time zone, and QEMU, booted by
`tools/qemu-boot.sh`, sets it to this machine's local time with `-rtc
base=localtime`, so the bar shows the count as it is.

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
draws its own header bars, the toolkit's `UiCsdBar`, and a press on one's
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
- **Keys** go to the front window's client, as the `KeyEvent` notices
  the keyboard driver sends.
- **The pointer**'s place, 0 to 32767 on each axis from the tablet, is
  scaled to the screen and sent to the driver as a `move`. A mouse's
  report, a `PointerMotion` from `usb-hid mouse`, moves it instead from
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
  2), the arrow elsewhere. Dragging asks the window's client for the size
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
  bar's right end, kills the window's client with `proc_kill`. Its exit
  then closes its windows, as any client's does. If the client cannot be
  killed, being a driver or already gone, `wm` closes the window itself.

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
  under it by that much, since layers do not blend.
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
  program it starts has no terminal. KeyEvent has no modifiers yet, so
  there is no Ctrl-C, Ctrl-V or Alt-Left. Its window, like every
  client-decorated one, has no shadow, and the pointer over the inside
  of its edge is the arrow until it is pressed there: a client cannot
  ask for a pointer's shape, so only the border outside shows the
  resize pointer before a press.
- Only toolkit windows can be resized or maximized (`draw` ignores the
  size notice, so a double click on its title bar leaves it as it is).
- **Terminal (`vt`) is a terminal of lines, not a screen.** KeyEvent has
  no modifiers yet, so there are no shortcuts: no Shift-PgUp to scroll
  back, no Ctrl-Shift-T for a tab; the wheel and the buttons do it all.
  There is no selecting, copying or pasting; no escape sequence moves
  the cursor, colors text or clears the screen (the line editing drops
  them); and a program is not told the terminal's size, so nothing it
  writes is laid out for it. Its scrollbar shows only while the view is
  back, and its slider is not dragged. Each tab's name costs a process, its
  relay, since a process waits on one port and a name goes only with
  the process that registered it.
  A client paints what changed for every size it is asked for, all of it
  when the size outgrows its buffer, and `wm` restacks the screen once:
  Disks's drag paints about 7 ms a size on QEMU, and the restack takes
  9. A layout whose parts all move with the width, as a grid whose
  columns stretch does, paints most of itself all the same. A client
  paints into the buffer the screen shows, so a frame can be shown half
  painted; its rows never move, as they did when a buffer's stride was
  its width, which tore a width drag in 2D mode. `wm` opens a region for each window, its
  chrome's, and closes it when the window closes; the proc runtime keeps
  at most 64 open at once, so `wm`, which keeps four of its own (the
  desktop, the pointer, the top bar and the launcher), can have 60
  windows open at once, and open them for ever; a resize past a buffer's
  room holds one more for a moment, and is refused if there is none. The
  pointer's image is painted again and given to the display whenever it
  changes between the arrow and a resize pointer. The close button kills its client at
  once: the client is not asked first, and cannot refuse. The pointer has
  one button that does anything, the left: `wm` passes the others on to
  the window under the pointer, and the toolkit drops them.
