# The toolkit (user/lib/ui)

A small widget toolkit for L0S programs. It follows the
[GNOME Human Interface Guidelines](https://developer.gnome.org/hig/) and
draws as libadwaita does, in Adwaita's colors and sizes. `wm`'s title bars,
`vt`'s colors, `draw`'s commands, the `widgets` gallery, `procmon`,
`disks`, `files` and `fontview` are built on it.

## Files

| File | What it is | GTK / libadwaita |
|---|---|---|
| `theme.l0` | The palette (`blue_1`…`dark_5`), the light and dark styles' semantic colors, spacing, radii, sizes. Programs draw in the dark style: `ui_style` says so, the one place a setting for it will be read. Alpha colors are mixed with `ui_mix`, since no layer blends. Depends only on `ppm.l0`'s colors and `render.l0`'s glyph. | `@window_bg_color`, `@accent_bg_color`, … |
| `icons.l0` | The names of the symbolic icons, 16×16 at scale 1, GNOME's own: each is its SVG under [icons/](../icons) (Adwaita's, and System Monitor's for utilities-system-monitor), which `tools/mkicons` rasterizes into `/etc/icons` at the build. window-close, pan-down, pan-up, view-refresh, open-menu, system-search, drive-harddisk, the apps' utilities-terminal, utilities-system-monitor and view-app-grid, and the files' folder, text-x-generic, application-x-executable, go-previous, go-next, view-list, view-grid and computer, and Terminal's tab-new. Also `ui_image_names`, the full-color icons Files and Disks show things with, Adwaita's under `icons/adwaita/scalable`, which `tools/mkicon --image` draws into `/etc/images/NAME.face`. | `*-symbolic` icons, and the full-color theme icons |
| `face.l0` | The face: the icons at the sizes its scale paints, from `/etc/icons`; the text's glyphs, Source Code Pro's and Source Sans 3's regular and bold at 16 and 32 times the scale, kept as `glyph.FACE.H` (`code`, `code-bold`, `sans`, `sans-bold`), each a strike (`format/strike.l0`) asked of the font service, `font`, which shares its pages with every program that asks, read in place (`UiStrike`), never copied; and, for the compositor alone at scale 2 (`ui_face_pointers`), the pointers `tools/mkfont` rasterized into `/etc/face`, which holds nothing else. With no `font`, no text is drawn, said once on standard error. An app's `icon.face` is the same format, its images' tables `image.N`, and so is each full-color icon's `/etc/images/NAME.face`, which a program loads by name, at the sizes its scale paints, with `ui_images_load` into a `UiImages`, and finds with `ui_image`. | the font and icon theme at a scale factor || `paint.l0` | the `UiPaint` ops (fill, rounded fill with antialiased corners, text, icon, an image of its own colors with alpha, `UiPImage`, as an app's `icon.svg` makes), placed by `gfx/rect.l0`'s `Rect` in the desktop's pixels; `ui_paint` runs them on a canvas at the face's scale, clipped, and returns it, so a canvas over an array (a test's, `tools/mkicon`'s) is painted too. At scale 2 each op is twice the size, and text and icons are the face's, each pixel mixed by how much it covers. Also `ui_buffer` and `ui_buffer_at` for shm buffers, and Adwaita's arrow cursor. | GSK render nodes |
| `metrics.l0` | Each face's units per em, the advance of each of codes 32 to 126, the widest of them, and the kerning of each pair of them GPOS adjusts, in font units, as defs (`ui_m_sans_adv`, `ui_m_sans_kern` and the rest), which `tools/mkmetrics` writes from the fonts at the build and `make check` compares: so text is measured with no face and no file, and `ui_layout` and its host tests need neither. | Pango's font metrics |
| `widget.l0` | `UiWidget` (label, text in a face and height a program names (`UiText`), button, box, expand, pad, separator, header bar, view, level bar, status, status page, grid, space, panes.l0's sidebar, segment bar, properties and modal, entry.l0's entry, a window's own header bar, nav.l0's path bar, toggle group and tab bar, icon_view.l0's icon view, menu.l0's popover, and a drawing area); `UiState`; `ui_layout` into `UiNode`s; `ui_hit`, `ui_focus_next`, `ui_paint_nodes`; scrollers (`UiScroller`, `ui_scroll_of`, `ui_scroll_hit`). `UiCsdBar START TITLE END CLOSES` is the header bar of a window that draws its own (`ui_open_csd`): any widget as its title, in the bar's middle as far as there is room, the window's close button at its end if CLOSES (`ui_close_action`), and its ground the window's to drag (`ui_move_action`), or, with a double click, to maximize and restore. `UiDrawingArea NAME W H` is an area the program paints itself, as `vt` paints its terminal: its node sets off `NAME.drawing`, has no ops, and nothing of the toolkit's is painted or damaged there, not even the window's ground (`ui_drawn`, `ui_drawing_rect`). | `GtkLabel`, `GtkButton`, `GtkBox`, `AdwHeaderBar`, `GtkLevelBar`, `AdwStatusPage`, `GtkAdjustment`, `GtkDrawingArea` |
| `grid.l0` | A data grid: columns, typed cells (text, number, size, as `format_size` says it and sorted by its bytes, level, status, icon), sorting by column, selection, keyboard movement, scrolling by the wheel, and an overlay scrollbar whose slider drags. `ui_grid_page`, a toolbar of Refresh, a status line and End Process over a grid, as `widgets` and `procmon` are, and `ui_selected_line`. | `GtkColumnView`, `GtkScrolledWindow` |
| `panes.l0` | A window of panes: `UiSidebar`, rows of an icon, a title and a line, one selected; `UiSegmentBar`, a whole in parts each as wide as its share by weight (`ui_shares`), each plain or muted (`UiSegPlain`, `UiSegMuted`), at any height: a title over a line at `ui_segbar_h`, the title alone lower, no text as a usage bar; one part selected and moved along by Left and Right (`ui_segbar_key`), or, with prefix `""`, none and no targets; `UiProps`, a dimmed name before each value, which is any widget; `UiModal` and `ui_alert`, an alert dialog on a card over everything beneath, which is dimmed (`ui_scrim`) and no longer a target, and `ui_alert_form`, one with widgets, such as properties holding entries, between its lines and its buttons. Rows and parts carry `PREFIX.select.KEY`, read back by `ui_select_key`. | `AdwNavigationSplitView`'s sidebar, `GtkListBox` `.navigation-sidebar`, GNOME Disks' volume grid and Usage's storage bar, `AdwAlertDialog` and its extra child |
| `entry.l0` | `UiEntry NAME TEXT PLACEHOLDER WIDTH`, a line of text: `UiEntryText`, its text and cursor, kept by the program; `ui_entry_keyed`, typing at the cursor, Backspace, Delete, Left, Right, Home and End; drawn on the text's color at 10%, with the accent's ring and a cursor while it has the focus, the placeholder dimmed while it is empty. | `GtkEntry` |
| `nav.l0` | What a window that goes from place to place puts in its header bar: `UiPathBar PREFIX LABELS`, a button for each part of a path on 10% of the text color, the last, where one is, bold and no target, each other going to its depth, `PREFIX.select.N`, the first ones folded into `...` when it is too narrow; and `UiToggleGroup PREFIX TOGGLES KEY`, linked `UiToggle`s, an icon or a label each, the active one raised on the card's ground, `PREFIX.select.KEY`; and `UiTabBar PREFIX TABS KEY`, a tab bar under a header bar, 40 high on its ground, its `UiTab`s, each a key and a title, sharing its width, 34 high, the selected one raised, the text's color at 10% (13% under the pointer, 7% for another), each its title in the middle and a round close button at its end: a tab sets off `PREFIX.select.KEY`, its close button `PREFIX.close.KEY` (`ui_tab_close_key`). | Nautilus' path bar, `AdwToggleGroup`, `AdwTabBar` |
| `icon_view.l0` | `UiIconView`, a grid of `UiTile`s, an icon 48 square at three times the size, in the accent or dimmed, and a name under it, as many across as fit, in the middle; one selected, rounded in the selection's tint, by a press or the keys (`ui_icon_key`: the arrows, a row for Up and Down, Home, End, Page Up and Page Down, its columns from `ui_win_icon_cols`), a press between them selecting none (`ui_icon_action`); a scroller by rows of tiles, with the grid's overlay scrollbar (`ui_scrollbar_on`). | `GtkGridView` |
| `menu.l0` | `UiPopover BASE MENU`, a popover menu over the window: a `UiMenu` of `UiItem`s, insensitive ones dimmed, and `UiItemSep`s, on a card, under the node of an action (`UiBelow`) or at a point (`UiAt`, as for a right click), kept inside the window; nothing beneath is a target while it is open, and a press outside it sets off `PREFIX.dismiss`. | `GtkPopoverMenu` |
| `draw_cmd.l0` | The desktop's drawing commands: render.l0's, Adwaita's colors by name, `round`, `button` and `icon X Y NAME [SCALE [COLOR]]`. Used by `draw` to check a command, by `wm` to draw it, and by `tools/mkicon` to draw an app's icon. | — |
| `window.l0` | A client window: `ui_open`, or `ui_open_csd` for one that draws its own header bars, which the compositor neither draws nor frames, a press on a `UiCsdBar`'s ground asking it to move the window, and a second press there within 400 ms to maximize or restore it (the press is the click told, as the compositor takes its release), and a left press inside the window's edge, `ui_csd_edge` (3) deep and within `ui_csd_corner` (20) of a corner both edges (`ui_csd_edges`), before anything under it, asking it to resize the window by those edges; `ui_event_of`, `ui_route` (hover, press, click on release, a double click, `ui_win_double`, the same action set off again within 400 ms, a right press as `UiContext`, set off as `context.X.Y.TARGET` and read back by `ui_context_of`, Tab focus, Enter/Space, the wheel and scrollbar drags, keys to an entry with the focus, a close asked as `win.close`, `ui_win_close_asked`, `ui_win_close_kept`), `ui_present` (repaints only what changed; closes a window whose close the program did nothing with; all of it after the user resized the window, `UiResize`, in the buffer it has when that has room), `ui_win_scroller`, `ui_win_icon_cols`, `ui_win_focusing`, `ui_entry_update`; for a program that paints a drawing area itself, `ui_win_canvas` and `ui_win_face` to paint it with, `ui_win_damaged` to tell the compositor, `ui_win_titled` to retitle the window, and `ui_win_wm_pid`; `ui_key_of` and `ui_key_pressed`, the key an event is. Needs `user/lib/proto/wm.l0`. | `GtkWindow`, event controllers, `GtkGestureClick`'s n-press and secondary button |
| `uiapp.l0` | An app's windows, any number, on one port: a `UiApp`, the compositor, the port, the face they share, so a strike is opened once for all of them, and its `UiWin`s by id. `ui_app_start`; `ui_app_open` and `ui_app_open_csd` one more window on the app's port, refused, saying so, past the regions the process has left (each window's buffer one, a resize one more, each strike one, of 64, 8 kept for the program's own: `ui_app_regions`, `ui_regions_room`); `ui_app_next` the next message, put together (`UiAppNext`), and `ui_app_event` what it is, `(UiAppEvent ID EVENT)`, the window the compositor's notice names and `ui_event_of`'s event for it, ID -1 for none of the app's (an exit, anything else; `ui_app_event_lost` for a port gone); `ui_app_route` and `ui_app_present`, `ui_route` and `ui_present` on window ID, put back by its id (`ui_app_win`, `ui_app_put`); `ui_app_close` one; `ui_app_count`, `ui_app_ids`. `ui_open` and `ui_open_csd` are an app started for one window. `ui_app_start` registers the app's port as its name, `app.EXEC`, EXEC its program's file name (`ui_app_named`; a second of the same program goes without); a launch of the app while it runs (`wm`'s, an `open`, [desktop.md](desktop.md)) is an event of no window, `UiOpen REPLY ARGS`, and routing it sets off the action `app.open` (`ui_open_action`, its arguments `ui_open_args`) and answers `shown 0`, so the app's front window comes forward and nothing more opens; an app that opens something for it says so with `ui_app_opening` and answers each itself with `ui_app_shown`, the window to bring forward. A program of one window routing with `ui_route` has the same default. The answer is told, never waited on. | `GApplication`'s windows, `GtkWindow`, its name, activate and open |

| `uiloop.l0` | The loop a window and an app keep, `UiLoop`: the messages taken and not yet handed out, what waits taken before each step and put together (`ui_loop_take`, `ui_together`: a run's last move, its wheel's turns as one, a window's last size); each step's times (`UiTimes`: routed, painted), its stages (`UiStages`: route, update and view, layout, wait, paint, present), and the slow step's line, said at the debug level once a step is over a frame (`ui_frame_ns`, 16 ms; `ui_slow_line`, `ui_slow_due`, `ui_times_stepped`) | GLib's main loop, and GTK's frame clock's timings |

The Makefile links either `UI_CORE` (every file but `window.l0`,
`uiapp.l0` and `uiloop.l0`; needs only `RENDER`: `ppm.l0`, `rect.l0` and
`render.l0`) or `UI_CORE` plus `UI_WINDOW` (`window.l0`, `uiapp.l0`,
`uiloop.l0` and
`user/lib/proto/appopen.l0`, an app's name and its open; needs
`user/lib/proto/wm.l0` too).

## How a program uses it

L0 has no function values, so a widget can't hold a callback. A widget that
does something holds an **action name** instead, as GActions are named
(`"app.refresh"`, `"procs.sort.2"`). The program follows the Elm
architecture:

```
view   : state -> UiWidget
update : state, action, event -> state
```

and its loop is:

```
(match (ui_open "Title" 640 400) ...)                       once
(ui_win_next w)                     -> (UiWinNext w1 event)   the next, put together
(ui_route w1 event)                 -> (UiRouted w2 action)  action may be ""
(update state action event)         -> state2
(ui_present w2 (view state2))       -> w3                     paints what changed
```

`user/apps/widgets/widgets.l0` is that loop in full, with a toolbar and a data grid.

**Put together.** `ui_win_next` (and `ui_app_next`, below) takes the
next message through the window's loop (`uiloop.l0`'s `ui_loop_take`):
first everything that waits on the port, up to 64 at once
(`port_try_receive`), after what it holds already, then the whole put
together (`ui_together`) as GTK compresses motion before a frame; if
nothing waits, the next is waited for, and what came with it taken too.
Of a window's run of pointer moves and wheel turns, no other message of
that window between them (a press, a release, a key, a leave, a focus,
or anything else, which ends the run), only the last move is kept, and
one wheel turn, at the last's place, its steps the run's sum; of the
sizes a window is asked, only the last. A move is a pointer notice whose
buttons are the window's before it, as the toolkit last knew them, so a
press or a release is never one. Nothing else is dropped or reordered:
keys, presses, releases, an open, an exit, another window's notices and
anything not the compositor's stay as they came. So a step slower than
the pointer takes the last of the moves that came meanwhile, not each
in turn. `ui_event_lost` says the port is gone.

**Many windows.** An app of more than one window starts a `UiApp` and
opens each on its port; its loop is:

```
(match (ui_app_start) ...)                                  once
(ui_app_open_csd app "Title" 880 560)  -> (UiAppOpened app2 id), and more
(ui_app_next app)                      -> (UiAppNext app1 (UiAppEvent id event))   id -1 for none
(ui_app_route app id event)            -> (UiAppRouted app2 action)
(update state id action event)         -> state2                  the window's own
(ui_app_present app2 id (view state2 id))                         paints what changed
(ui_app_close app id)                                             on win.close
```

Each window has its own widgets' state, nodes, damage and buffer, so an
event of one changes and repaints that one alone; Files keeps its own
state for each by the window's id. `ui_app_next` and `ui_app_event` are
the one place the loop takes its messages; the app's loop puts them
together as a window's does, each window's runs by its own buttons. A window an app presents again
with its close unanswered is closed by `ui_app_present`, and the app
ended with its last, as `ui_present` does.

**A slow step said.** A step is what one message does: routed
(`ui_route`), the program's update and view, then `ui_present`'s
layout, any wait on a server (a strike asked of `font`), paint, and
present (the damage told, or a resize). The toolkit times each stage
with `clock_ns`, the route's in the window's loop (`uiloop.l0`'s
`UiTimes`) and the rest in `ui_present`, the update and view being
what lies between; a step longer than a frame, 16 ms, is said once at
the debug level, in the program's name, which `dmesg` shows, and again
only after a step under it:

```
fontview: slow step: 37.3 ms: route 0.1, update and view 2.0, layout 20.3, wait 0.0, paint 10.0, present 4.9
```

So the next slow app says where its time goes. A present with no route
before it, as a program's first, or `vt`'s after output, has no route
or update of its own.

**Closing.** `ui_event_of` takes the compositor's window notices of its
own window only (any other is `UiOther`). The compositor's close button
comes as `UiCloseAsked`, and the window's own (`UiCsdBar`'s, which sets
off `ui_close_action`) as a click: either way `ui_route` sets off
`win.close`, as GTK's `close-request`, and keeps the window as asked
to close (`ui_win_close_asked`). A program answers by closing the window
(`ui_close`) and ending, as Files, Fonts and Terminal do; one that keeps
it, as one asking first whether to save would, calls
`ui_win_close_kept`. One that does nothing with it presents the window
again, and `ui_present` closes it instead and asks the compositor to
`end` the program (`compositor_end`), since L0 has no call that ends a
program but returning from `main`: so the gallery, System Monitor,
Disks and About close as they did when the close button killed them.

**Launched again.** The app's port is its name, `app.EXEC` (EXEC its
program's file name), which `ui_app_start` registers, so a launch of a
running app, from the launcher or `open`, reaches it rather than
starting it again ([desktop.md](desktop.md), the launcher). The launch
comes as an `open` request, the event `UiOpen REPLY ARGS` of no window
(`ui_message_event`, for `ui_app_event` and `ui_event_of` alike), and
routing it sets off `app.open`, its arguments `ui_open_args`'s. Unless
the app has said it answers opens itself (`ui_app_opening`), the
toolkit answers `shown 0` as it routes it, so the app's front window
comes to the front and nothing more opens, which is all a program of
one window, routing with `ui_route`, does. One that opens a window for
it, as Files does, answers with `ui_app_shown app event ID`, the window
to bring forward. The answer is told (`port_tell`), never waited on.

### Scrolling

A widget that scrolls, the grid so far, is a **scroller**. Its layout
keeps how it is scrolled in two nodes' actions, as a `GtkAdjustment`
would hold it: its area, `NAME.scroll.FIRST.MOST.SHOWN.STEP`, STEP its
rows' height, by which `ui_present` moves the area's pixels when it
scrolls rather than painting them again, and its
scrollbar's strip, `NAME.scrollbar.FIRST.MOST.SPAN.SLIDER`. `ui_route`
reads them to scroll it with no help from the program. The wheel over
either, a press on the strip off the slider, and a drag of the slider set
off `NAME.scrollto.N` at once, which `ui_grid_action` turns into row N
first. The keys that move the selection scroll it into view from where
the grid is shown, so the program passes the window's scroller:

```
(ui_grid_key view code (ui_win_scroller w2 "procs"))
```

The layout no longer keeps the selection in view on its own, so the wheel
can scroll it away, as in GTK. A step of the wheel is three rows
(`ui_wheel_rows`).

### Entries

An entry's text and cursor are the program's, a `UiEntryText` in its
state, as everything is in the Elm architecture. The entry's node has the
action `NAME.entry`. A press on it gives it the focus and sets off
`NAME.place.N`, the character the pointer is before. While it has the
focus, and is laid out, every key but Tab and Esc goes to it: Enter sets
off `NAME.activate`, as GtkEntry's `activate`, and any other `NAME.edit`,
Space included. The program passes each to `ui_entry_update`, which gives
the text after an edit or a place, and the text unchanged after any other
action:

```
(ui_entry_update "size" text action event)
```

A dialog that asks for something puts the focus on its entry as it opens,
with `ui_win_focusing w "size.entry"` before it presents, so typing goes
there at once. `user/apps/disks` does both.

Every name is `ui_…` and every type or constructor `Ui…`. All files given
to `l0` are one namespace, and a duplicate is a compile error.

## The HIG, as encoded here

- **Spacing** 6 between related things, 12 between groups, 18 around a page
  (`ui_space_s/m/l`).
- **Header bars** are 46 px with a centered bold title, controls packed 6 px
  from either edge, and a shade line underneath. In the backdrop they're
  darker, the window's own ground, with a dimmed title.
- **Buttons** are 34 px tall (24 px round title buttons) with a 6 px radius.
  The ground goes from 10% to 15% to 30% of the text color for rest, hover
  and pressed. Flat buttons have no ground until hovered. Suggested buttons
  are in the accent, destructive ones in red. Insensitive buttons are drawn
  at half strength and aren't targets.
- **Clicks** activate on release over the same target, as GTK's do. The
  keyboard focus ring (accent at half) appears only after Tab, except on
  an entry, which shows it, and its cursor, whenever it has the focus.
- **Entries** are a button high, 6 px round, on 10% of the text color,
  their text 9 px in, their cursor a pixel wide.
- **Empty states** use a status page: a large dim icon, a title, and what to
  do next.
- **Sidebars** are 220 wide on libadwaita's sidebar ground (`ebebed`), rows
  of 48 with a 32 px icon, the selected one rounded in 10% of the text.
- **Dialogs** are libadwaita's alert dialog: a 320-wide card, its corners a
  window's, a bold heading, its lines, and its buttons sharing a row; the
  window beneath is mixed 30% with black, since nothing can blend, and
  takes no press until the dialog is answered.
- **Text** is the interface's in Source Sans 3, as GNOME's is in its
  proportional face, each character as wide as its advance: every
  widget's (labels, buttons, header bars, sidebars, alerts, the path
  bar, toggles, tabs, menus, status pages, entries, the icon view and
  the grid's cells, numbers too), and `wm`'s title bars, top bar,
  launcher and L0S menu. Source Code Pro, in cells 8×16, is the
  terminal's, `vt`'s, as GNOME Console's is, and `draw`'s `char`'s:
  what must line up in columns. Text is ASCII only, ellipsized with
  `...`, bold is the bold face, and large text is twice the line, 32.
  Both are 16 rows a line, at one em, 5/6 of the line. At the
  desktop's scale 2 the line is 32 of the screen's pixels, smooth,
  bold its own weight. The glyphs are the font
  service's strikes, in pages every program shares and reads in place:
  each glyph only as wide as its ink, placed from its pen by its box.
  An entry or a value that must hold n characters of any kind is made
  `ui_chars_w` wide, n of the face's widest.
  A program may also show text in any face `font` names at a line height
  of its own, `UiFontAt FACE H` (8 to 128 of the screen's pixels), as
  Fonts does: the widget `UiText TEXT FONT ALIGN`, in the text's color,
  or a `UiPText` of it. It is measured by `metrics.l0`'s face of that
  name, or as Source Code Pro if there is none, at that line; its strike,
  `glyph.FACE.H·s`, is asked of `font` by `ui_present` the first time
  a layout shows it, and kept in the window's face for its life, one
  region each; one `font` will not give is kept as none, not asked for
  again, and its text not drawn.
  A width is `ui_text_w s font bold scale`, `font` a `UiFont`, `UiMono`
  or `UiSans`: the sum of the characters' advances in font units
  (`metrics.l0`), each pair kerned as the font's GPOS says (its `kern`
  feature's pair adjustments, `ui_font_kern`; Source Sans 3's `AV` is
  14 units closer, `To` 66), turned into the desktop's pixels once and rounded up,
  so it never depends on where the text starts; `ui_ellipsized` cuts by
  it. `ui_text_font` is the face the interface's text is in. A
  `UiPText` carries its `UiFont`, and each glyph is drawn with its pen
  at the sum of the advances before it, turned into the screen's pixels
  at the face's scale and rounded, and its box at the strike's bearing
  from the pen: so text at scale 2 is placed in the screen's own pixels,
  not doubled from 1's. Bold is the bold face's own advances. An
  entry's cursor and the character a press is before are found by the
  same sums (`ui_text_pen`). A change of face is damage.
  Source Sans 3's default figures are tabular: every digit is one
  advance, 497 units, bold 528, so numbers line up in columns in it
  as they do in Source Code Pro, right-aligned in a grid's number,
  size and level cells, in Monitor's columns, and in the top bar's
  clock, which keeps its place as the minutes change. No glyph
  substitution (`tnum`) is needed, and none is read.
- **Scale 2**, on a large screen, is GNOME's scale factor: everything is
  laid out in the desktop's pixels, as at 1, and painted at twice the size
  at the screen's resolution. A program does nothing for it: `ui_open`
  learns the scale from the compositor, and makes its buffer and face at it.

## Limits

- No layer blends (virtio-gpu 2D), so a corner is antialiased only against a
  color the op is given, or against the pixel already in the same buffer
  (`-1`). Window corners are rounded by the display's shaped layers, which
  cut whole pixels, so they aren't antialiased. There are no window
  shadows.
- Two faces, Source Sans 3 for the interface and Source Code Pro for
  terminals and columns, each regular and bold, ASCII only, at any
  height from 8 to 128 on request; the toolkit draws them at lines of 16
  and 32, and at a program's own height with `UiFontAt`. Text is placed
  by advances and GPOS's pair kerning only: no ligatures, no glyph
  substitution (`tnum`, `onum`, small caps), no hinting, and pens on
  whole pixels. A face `metrics.l0` has no table for is measured as
  Source Code Pro's cells. Icons are
  smooth at every scale, at 16, 32, 48 and 64 times it, rasterized at
  the build, never at run time. Icons and text scale by whole numbers. Text's edges are mixed with
  what is under them, as corners are, against the pixel already there.
- An app's regions are counted by the toolkit, not asked of the
  kernel, which has no call for it: `ui_app_open` knows its windows and
  its face's strikes, and keeps 8 for the rest, so a program that opens
  more of its own than that can still run out. An app's loop does one
  message a step, after putting together what waits, a window's whole
  step each time; only a run of one window's moves and turns, with
  nothing else of it between, is put together, so moves of a window
  with a key between them are two steps. A program ends
  only by returning from `main`, so one that does nothing with a close
  is ended by the compositor at its asking (`end`).
- Scrolling is by whole rows: the wheel's steps are counted, not its
  speed, and there is no kinetic scrolling. The wheel across, which the
  driver reports, scrolls nothing yet.
- An entry does not scroll its text, which is cut short with `...`, so an
  entry is made as wide as what it will hold, and has no selection,
  copying or pasting.
