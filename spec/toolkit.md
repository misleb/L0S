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
| `icons.l0` | The names of the symbolic icons, 16×16 at scale 1, GNOME's own: each is its SVG under [icons/](../icons) (Adwaita's, and System Monitor's for utilities-system-monitor), which `tools/mkicons` rasterizes into `/etc/icons` at the build. window-close, pan-down, pan-up, view-refresh, open-menu, system-search, drive-harddisk, the apps' utilities-terminal, utilities-system-monitor and view-app-grid, and the files' folder, text-x-generic, application-x-executable, go-previous, go-next, view-list, view-grid and computer, Terminal's tab-new, the check box's object-select, and list-add and user-trash, which To Do adds and deletes with. Also `ui_image_names`, the full-color icons Files and Disks show things with, Adwaita's under `icons/adwaita/scalable`, which `tools/mkicon --image` draws into `/etc/images/NAME.face`. | `*-symbolic` icons, and the full-color theme icons |
| `face.l0` | The face: the icons at the sizes its scale paints, from `/etc/icons`; the text's glyphs, Source Code Pro's and Source Sans 3's regular and bold at 16 and 32 times the scale, kept as `glyph.FACE.H` (`code`, `code-bold`, `sans`, `sans-bold`), each a strike (`format/strike.l0`) asked of the font service, `font`, which shares its pages with every program that asks, read in place (`UiStrike`), never copied, through one region over each of `font`'s arenas the strikes are in, so the desktop's strikes and the first others a program shows take it one region (`ui_strike_open`, `ui_strike_regions`); and, for the compositor alone at scale 2 (`ui_face_pointers`), the pointers `tools/mkfont` rasterized into `/etc/face`, which holds nothing else. With no `font`, no text is drawn, said once on standard error. An app's `icon.face` is the same format, its images' tables `image.N`, and so is each full-color icon's `/etc/images/NAME.face`, which a program loads by name, at the sizes its scale paints, with `ui_images_load` into a `UiImages`, and finds with `ui_image`. | the font and icon theme at a scale factor || `paint.l0` | the `UiPaint` ops (fill, rounded fill with antialiased corners, text, icon, an image of its own colors with alpha, `UiPImage`, as an app's `icon.svg` makes, N wide and as high as its table's shape makes it (`ui_image_h`), an icon's square, only its rows in the clip painted), placed by `gfx/rect.l0`'s `Rect` in the desktop's pixels; `ui_paint` runs them on a canvas at the face's scale, clipped, and returns it, so a canvas over an array (a test's, `tools/mkicon`'s) is painted too. At scale 2 each op is twice the size, and text and icons are the face's, each pixel mixed by how much it covers. Also `ui_buffer` and `ui_buffer_at` for shm buffers, and Adwaita's arrow cursor. | GSK render nodes |
| `metrics.l0` | Each face's units per em, the advance of each of codes 32 to 126, the widest of them, and the kerning of each pair of them GPOS adjusts, in font units, as defs (`ui_m_sans_adv`, `ui_m_sans_kern` and the rest), which `tools/mkmetrics` writes from the fonts at the build and `make check` compares: so text is measured with no face and no file, and `ui_layout` and its host tests need neither. | Pango's font metrics |
| `widget.l0` | `UiWidget` (label, text in a face and height a program names (`UiText`), a part keyed by what it shows, its layout kept while that is the same (`UiKeyed`, `ui_keyed_self`), button, box, expand, pad, separator, header bar, view, level bar, status, status page, grid, space, panes.l0's sidebar, segment bar, properties and modal, entry.l0's entry, a window's own header bar, nav.l0's path bar, toggle group and tab bar, icon_view.l0's icon view, menu.l0's popover, lines.l0's lines, entry.l0's text area, a picture, a widget that shrinks, and a drawing area); `UiState`; `ui_layout` into `UiNode`s, a column giving each child its height at the column's width (`ui_height_in`: a text area as its rows take it, padding, boxes and what holds one widget as what they hold, any other its natural height); `ui_hit`, `ui_focus_next`, `ui_paint_nodes`, each node's ops cut to the node at the pixel, as `gtk_snapshot_push_clip` cuts a widget's, and its damage diffed as so cut (`UiCutOp`); scrollers (`UiScroller`, `ui_scroll_of`, `ui_scroll_hit`). `UiCsdBar START TITLE END CLOSES` is the header bar of a window that draws its own (`ui_open_csd`): any widget as its title, in the bar's middle as far as there is room, the window's close button at its end if CLOSES (`ui_close_action`), and its ground the window's to drag (`ui_move_action`), or, with a double click, to maximize and restore. `UiDrawingArea NAME W H` is an area the program paints itself, as `vt` paints its terminal: its node sets off `NAME.drawing`, has no ops, and nothing of the toolkit's is painted or damaged there, not even the window's ground (`ui_drawn`, `ui_drawing_rect`). `UiPicture PIXELS` is an image of its own colors, a `UiCov` of ARGB words as `format/png_read.l0` decodes one: it asks no room, and is fitted to what it is given, at its aspect, never enlarged, in its middle (`ui_picture_ops`); keep it in a `UiKeyed` named for what it shows, so its pixels are not compared. `UiShrinks CHILD` asks no width, its child's height, so expanders of it in a row share the row evenly whatever they hold. | `GtkLabel`, `GtkButton`, `GtkBox` (homogeneous), `AdwHeaderBar`, `GtkLevelBar`, `AdwStatusPage`, `GtkAdjustment`, `GtkPicture`, `GtkDrawingArea` |
| `grid.l0` | A data grid: columns, typed cells (text, number, size, as `format_size` says it and sorted by its bytes, level, status, icon), sorting by column, selection, keyboard movement, scrolling by the wheel, down and, when its columns are wider than it, across, and overlay scrollbars down and across whose sliders drag. `ui_grid_page`, a toolbar of Refresh, a status line and End Process over a grid, as `widgets` and `procmon` are, and `ui_selected_line`. | `GtkColumnView`, `GtkScrolledWindow` |
| `panes.l0` | A window of panes: `UiSidebar`, rows of an icon, a title and a line, one selected; `UiSegmentBar`, a whole in parts each as wide as its share by weight (`ui_shares`), each plain or muted (`UiSegPlain`, `UiSegMuted`), at any height: a title over a line at `ui_segbar_h`, the title alone lower, no text as a usage bar; one part selected and moved along by Left and Right (`ui_segbar_key`), or, with prefix `""`, none and no targets; `UiProps`, a dimmed name before each value, which is any widget; `UiModal` and `ui_alert`, an alert dialog on a card over everything beneath, which is dimmed (`ui_scrim`) and no longer a target, and `ui_alert_form`, one with widgets, such as properties holding entries, between its lines and its buttons. Rows and parts carry `PREFIX.select.KEY`, read back by `ui_select_key`. | `AdwNavigationSplitView`'s sidebar, `GtkListBox` `.navigation-sidebar`, GNOME Disks' volume grid and Usage's storage bar, `AdwAlertDialog` and its extra child |
| `entry.l0` | `UiEntry NAME TEXT PLACEHOLDER WIDTH`, a line of text: `UiEntryText`, its text and cursor, kept by the program; `ui_entry_keyed`, typing at the cursor, Backspace, Delete, Left, Right, Home and End; drawn on the text's color at 10%, with the accent's ring and a cursor while it has the focus, the placeholder dimmed while it is empty. `UiTextArea NAME TEXT PLACEHOLDER WIDTH MOST` is the same text, cursor, actions and keys, Enter still its `activate`, its text wrapped at its spaces into rows (`ui_area_rows`, every character kept, the spaces after a row's last word hanging past its end, a word too long for a row cut where it no longer fits), a button high for one row and a row of text (20) higher for each more, up to MOST, after which the rows around the cursor show (`ui_area_h`, `ui_area_node`); a press is placed in the row under it (`ui_entry_char_at_xy`), the rows above those shown counted as text of no width. | `GtkEntry`, a `GtkTextView` that grows |
| `nav.l0` | What a window that goes from place to place puts in its header bar: `UiPathBar PREFIX LABELS`, a button for each part of a path on 10% of the text color, the last, where one is, bold and no target, each other going to its depth, `PREFIX.select.N`, the first ones folded into `...` when it is too narrow; and `UiToggleGroup PREFIX TOGGLES KEY`, linked `UiToggle`s, an icon or a label each, the active one raised on the card's ground, or on dark the text's color at 20% over the group's, lighter than it (the card's there is darker), `PREFIX.select.KEY`; and `UiTabBar PREFIX TABS KEY`, a tab bar under a header bar, 40 high on its ground, its `UiTab`s, each a key and a title, sharing its width, 34 high, the selected one raised, the text's color at 10% (13% under the pointer, 7% for another), each its title in the middle and a round close button at its end: a tab sets off `PREFIX.select.KEY`, its close button `PREFIX.close.KEY` (`ui_tab_close_key`). | Nautilus' path bar, `AdwToggleGroup`, `AdwTabBar` |
| `icon_view.l0` | `UiIconView`, a grid of `UiTile`s, an icon 48 square at three times the size, in the accent or dimmed, and a name under it, as many across as fit, in the middle; one selected, rounded in the selection's tint, by a press or the keys (`ui_icon_key`: the arrows, a row for Up and Down, Home, End, Page Up and Page Down, its columns from `ui_win_icon_cols`), a press between them selecting none (`ui_icon_action`); a scroller by rows of tiles, with the grid's overlay scrollbar (`ui_scrollbar_on`). | `GtkGridView` |
| `lines.l0` | `UiLines`, text that wraps and scrolls, as a chat's list of wrapping labels: `UiPara`s (a text, a kind, `UiLinePlain`, `UiLineStrong` in bold, `UiLineDim`, `UiLineBad` in the error's red, or a chat's bubble, `UiLineIncoming` at the start on a card and `UiLineOutgoing` at the end on the accent, an icon before its first row or none, and an action its rows set off or none) wrapped at their spaces and newlines to the width they get, a bubble to three quarters of it (`ui_bubble_share`), on a ground rounded 12 as wide as its widest row and 12 each side, 6 past its rows, a blank row between it and the top or the next paragraph, each of its rows painting its own part of the ground (`ui_bubble_ground`) so it scrolls by rows, and a bubble's foot room kept under the rows shown, a word too long for a row cut where it no longer fits (`ui_wrapped`, each candidate line measured whole); rows of `ui_text_row_h` (20) on a view's ground, a row with an action tinted under the pointer; a scroller by rows, with the grid's overlay scrollbar, showing the end while its first row is -1 (`ui_lines_shown_from`, `ui_lines_first`). | `GtkListView` of wrapping `GtkLabel`s |
| `menu.l0` | `UiPopover BASE MENU`, a popover menu over the window: a `UiMenu` of `UiItem`s, insensitive ones dimmed, and `UiItemSep`s, on a card, under the node of an action (`UiBelow`) or at a point (`UiAt`, as for a right click), kept inside the window; nothing beneath is a target while it is open, and a press outside it sets off `PREFIX.dismiss`. | `GtkPopoverMenu` |
| `draw_cmd.l0` | The desktop's drawing commands: render.l0's, Adwaita's colors by name, `round`, `button` and `icon X Y NAME [SCALE [COLOR]]`. Used by `draw` to check a command, by `wm` to draw it, and by `tools/mkicon` to draw an app's icon. | — |
| `window.l0` | A client window: `ui_open`, or `ui_open_csd` for one that draws its own header bars, which the compositor neither draws nor frames, a press on a `UiCsdBar`'s ground asking it to move the window, and a second press there within 400 ms to maximize or restore it (the press is the click told, as the compositor takes its release), and a left press inside the window's edge, `ui_csd_edge` (3) deep and within `ui_csd_corner` (20) of a corner both edges (`ui_csd_edges`), before anything under it, asking it to resize the window by those edges; the pointer's shape asked of the compositor as the pointer moves (`ui_pointer_at`: the I-beam over an entry, the resize pointer inside that edge); `ui_event_of`, `ui_route` (hover, press, click on release, a double click, `ui_win_double`, the same action set off again within 400 ms, a right press as `UiContext`, set off as `context.X.Y.TARGET` and read back by `ui_context_of`, Tab and Shift-Tab focus, Enter/Space, the wheel and scrollbar drags, keys to an entry with the focus, a close asked as `win.close`, `UiWin`'s `.close_asked`, `ui_win_close_kept`), `ui_present` (repaints only what changed, in the buffer the screen does not show, which it then gives the compositor, and no more until the frame shows it and the other is released, `UiDb`, a third kept while the window is resized; closes a window whose close the program did nothing with; all of it after the user resized the window, `UiResize`, in the buffer it has when that has room), `ui_win_scroller`, `ui_win_icon_cols`, `ui_win_focusing`, `ui_entry_update`; for a program that paints a drawing area itself, `ui_win_drawing` the canvas to draw it on now, the buffer painted next, or later, `UiWin`'s `.face` to draw with, `ui_win_drew` what it drew, shown at the next `ui_present`, and `ui_win_lost` to know when to draw all of it again, `ui_win_titled` to retitle the window, and `ui_win_wm_pid`; `ui_key_of` and `ui_key_pressed`, the key an event is, and `ui_key_mods`, the Shift, Ctrl and Alt held with it. Needs `user/lib/proto/wm.l0`. | `GtkWindow`, event controllers, `GtkGestureClick`'s n-press and secondary button |
| `uiapp.l0` | An app's windows, any number, on one port: a `UiApp`, the compositor, the port, the face they share, so a strike is opened once for all of them, and its `UiWin`s by id. `ui_app_start`; `ui_app_open` and `ui_app_open_csd` one more window on the app's port, refused, saying so, past the regions the process has left (each window's two buffers two, a resize's third one more, each of `font`'s arenas its strikes are in one, however many strikes it holds, of 64, 8 kept for the program's own: `ui_app_regions`, `ui_regions_room`); `ui_app_next` the next message, put together (`UiAppNext`), and `ui_app_event` what it is, `(UiAppEvent ID EVENT)`, the window the compositor's notice names and `ui_event_of`'s event for it, ID -1 for none of the app's (an exit, anything else; `ui_app_event_lost` for a port gone); `ui_app_route` and `ui_app_present`, `ui_route` and `ui_present` on window ID, put back by its id (`ui_app_win`, `ui_app_put`); `ui_app_close` one; `ui_app_count`, `ui_app_ids`. `ui_open` and `ui_open_csd` are an app started for one window. `ui_app_start` registers the app's port as its name, `app.EXEC`, EXEC its program's file name (`ui_app_named`; a second of the same program goes without); a launch of the app while it runs (`wm`'s, an `open`, [desktop.md](desktop.md)) is an event of no window, `UiOpen REPLY ARGS`, and routing it sets off the action `app.open` (`ui_open_action`, its arguments `ui_open_args`) and answers `shown 0`, so the app's front window comes forward and nothing more opens; an app that opens something for it says so with `ui_app_opening` and answers each itself with `ui_app_shown`, the window to bring forward. A program of one window routing with `ui_route` has the same default. The answer is told, never waited on. | `GApplication`'s windows, `GtkWindow`, its name, activate and open |

| `uiloop.l0` | The loop a window and an app keep, `UiLoop`: the messages taken and not yet handed out, what waits taken before each step and put together (`ui_loop_take`, `ui_together`: a run's last move, its wheel's turns as one, a window's last size); the ports it waits on as one set, the window's, the toolkit's reply port, the program's, and the program's own (`ui_loop_own`, `UiGotPort`); each step's times (`UiTimes`: routed, painted), its stages (`UiStages`: route, update and view, layout, wait, paint, present), and the slow step's line, said at the debug level once a step is over a frame (`ui_frame_ns`, 16 ms; `ui_slow_line`, `ui_slow_due`, `ui_times_stepped`) | GLib's main loop, and GTK's frame clock's timings |

| `controls.l0` | The controls a settings page, a form or a list of things to do is made of, as libadwaita draws them: `UiSwitch NAME ON`, a pill 48 by 26 in the accent while on, the trough's color off, its knob 20, white, at the end it is at; `UiCheck NAME ON LABEL`, a square of 16, rounded 4, in the accent with Adwaita's `object-select` check while on, its label 6 after it, the whole a target; each setting off `NAME.toggle` on a click, or Enter or Space with the focus on it, which `ui_toggled NAME ON ACTION` turns into what it shows next. `UiScale NAME V MIN MAX W`, a slider W wide: a trough 6 high from half a knob in from either end, the accent up to its knob, the knob 20, white, ringed 2 round while focused, its node the slider and that ring round it; its node's action `NAME.scale.MIN.MAX` (`ui_scale_node_action`), which holds no value so the focus stays on it as it changes, and which window.l0 turns into `NAME.set.N` as it is pressed and dragged (`ui_scale_set_at`, the value under the pointer, to the nearest), and `NAME.step.-1` or `NAME.step.1` for Left and Right while it has the focus (`ui_scale_keyed`), its release setting off nothing; `ui_scale_value NAME V MIN MAX ACTION` the value after either, a step a twentieth of its range, kept in it. `UiSpinner PHASE SIZE`, eight dots round a circle, dot PHASE in the text's color and those behind it fainter, 12% a dot; `ui_spinner_next` turns it, on an alarm every `ui_spinner_ns`, 100 ms, as the gallery turns its own. Placed at the start of the room they get, in its middle up and down. | `GtkSwitch`, `GtkCheckButton`, `GtkScale`, `AdwSpinner` |
| `list.l0` | `UiList (UiListData PREFIX ROWS FIRST)`, a boxed list, libadwaita's `.boxed-list` of `AdwActionRow`s: on a card rounded as a window, rows 50 high, a line between each two, each `UiListRow KEY ICON START TITLE SUBTITLE END ACTIONABLE`: an icon or none, a widget at its start (a check box, as a list of things to do has) and one at its end (a switch, a button), each over the row, so a press on it is its own, its title over its subtitle, dimmed, ellipsized between them. `ui_list_row KEY TITLE SUBTITLE` is a row of text set off when clicked, the rest given by its fields, `(.end row (UiSwitch "wifi" on))`. An actionable row sets off `PREFIX.select.KEY` (`ui_select_key`) and is tinted under the pointer, 3 inside it, rounded 8. A scroller by rows, its area `PREFIX.scroll.FIRST.MOST.SHOWN.50` and the grid's overlay scrollbar, so the wheel and the slider scroll it; the program keeps its first row with `ui_list_first`. Its natural size 320 wide and as high as its rows, at most five; in a `UiExpand` it takes the room there is. | `GtkListBox.boxed-list`, `AdwActionRow`, `AdwSwitchRow` |
| `page.l0` | What apps kept composing for themselves, composed once of the widgets above, laying out and painting nothing of its own: `ui_page TITLE LINE CHILDREN` (title large, the line dimmed, each left out if empty, the children 12 apart, 18 in), `ui_heading_row TITLE BUTTONS` (the title large, the buttons at the row's end), `ui_value` (a property's text), `ui_footer` and `ui_with_footer` (a separator and a dimmed line at a pane's foot), `ui_toolbar_page START STATUS END BODY` (a toolbar of buttons and a centered dimmed line over a separator and the body: `ui_grid_page` is one), `ui_split SIDEBAR PANE`, `ui_entry_w N` (an entry that holds N of the widest characters), `ui_at_least W CHILD`, `ui_cancel_button` (`dialog.cancel`, `ui_cancel_action`) and `ui_confirm HEADING LINES ACTION LABEL DESTRUCTIVE` (an alert of Cancel and one button), `ui_toggles LABELS` (toggles keyed by their labels), and for a list keyed by a function, `ui_without` (an element taken out by its key) and `ui_key_after` (the key to select then: the next, or the one before the last, as GNOME's tab bars choose), with `ui_tab_key` for a tab bar's tabs. Disks, Files, About, Installer, Widgets and Terminal use them. | `AdwPreferencesPage`'s title, `AdwHeaderBar`'s packing, `AdwAlertDialog`'s responses, `AdwTabView`'s selection on close |
| `testing.l0` | What a host test asks of a view, made once (`UI_TESTING`, linked into the toolkit's tests and every program's that links the toolkit, never a program): `ui_laid W WIDTH HEIGHT`, a widget laid out as a window in the light style; `ui_has_target` and `ui_target_at`, whether an action is a target and where, as `X Y W H`; `ui_texts`, every text painted, in order, each followed by `\|`; `ui_has_text`, whether one is. | — |
| `run.l0` | A program of one window run from its state, view and update, so it writes no loop: `ui_run WHO TITLE W H S0 VIEW UPDATE` (and `ui_run_csd`), the view a function from the state to a `UiWidget`, the update one from the state, the action, the event and the window to a `UiStepped`, the window and the state; the update given `app.start` (`ui_start_action`) once as the window opens; a close it does not keep (`ui_win_close_kept`) closing the window and ending the program, 0. | `GtkApplication`'s run |
| `preview.l0` | An app's views painted on the host, before any board: `UiShot NAME W H WIDGET`, a scene; `ui_shot_canvas`, a widget laid out and painted as `ui_present` paints a window's client area, in the program's style, nothing hovered or focused; `ui_host_face`, the face it paints with at scale 1, the build's `icons.face` and the eight strikes of `ui_text_names` read from `build/strikes`; `ui_preview`, a preview's whole `main`, each scene written as a PNG (`format/png.l0`). Linked as `UI_PREVIEW`, by previews and its test only. | — |

The Makefile links either `UI_CORE` (every file but `window.l0`,
`uiapp.l0`, `uiloop.l0`, `run.l0`, `preview.l0` and `testing.l0`; needs
only `RENDER`: `ppm.l0`, `rect.l0` and `render.l0`) or `UI_CORE` plus
`UI_WINDOW` (`window.l0`, `uiapp.l0`, `uiloop.l0`, `run.l0` and
`user/lib/proto/appopen.l0`, an app's name and its open; needs
`user/lib/proto/wm.l0` too).

## How a program uses it

L0 passes a function as an argument but keeps none in a value, so a widget
can't hold a callback. A widget that
does something holds an **action name** instead, as GActions are named
(`"app.refresh"`, `"procs.sort.2"`). The program follows the Elm
architecture:

```
view   : state -> UiWidget
update : state, action, event, window -> state and window
```

A program of one window hands both to `ui_run` (`run.l0`), which runs
its loop, so it writes none:

```
(def gallery_step ((g Gallery) (action (list int)) (ev UiEvent) (w UiWin)) (UiStepped Gallery)
  (UiStepped w (gallery_update g action ev (ui_win_scroller w (gallery_prefix)))))

(def widgets () int
  (ui_run "widgets" "Widgets" 640 440 (gallery_new) gallery_view gallery_step))
```

The first argument names the program as it fails (`complain_as`), the
title the window. The update is given the window so that it can ask a
server, set an alarm, give the loop its own ports, focus an entry or
find a scroller, and gives it back with the state, a `UiStepped`. It is
given `app.start` (`ui_start_action`), with no event, once as the window
opens, before the first present: About keeps no state, System Monitor
reads its table and sets its first alarm there and at each alarm,
Installer gives the loop install's terminal while it runs, Agent
focuses its entry and looks for `agentd`. A close (`win.close`) the
update does not keep with `ui_win_close_kept` closes the window and
ends the program, 0. `ui_run_csd` opens a window that draws its own
header bar, as Fonts'. Widgets, About, System Monitor, Fonts, Installer
and Agent are run so; Disks, Files and Terminal keep loops of their own,
Files and Terminal over a `UiApp`. What `ui_run` does is the loop:

```
(match (ui_open "Title" 640 400) ...)                       once
(ui_win_next w)                     -> (UiWinNext w1 event)   the next, put together
(ui_route w1 event)                 -> (UiRouted w2 action)  action may be ""
(update state action event)         -> state2
(ui_present w2 (view state2))       -> w3                     paints what changed
```

`user/lib/ui/run.l0` is that loop in full, and `user/apps/widgets/widgets.l0`
an app run by it, with a toolbar and a data grid.

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

**Paced, in two buffers.** A window has two buffers, as a Wayland
client keeps two: the one the screen shows, and the one `ui_present`
paints (`UiDb`, its `UiBack`s), made at the first present that changes
something, with room to grow, and made again only if the window
outgrows it; and while the window is resized, a third, as Mesa's
Wayland clients keep one when they must. `ui_present` lays the view out, finds what changed
(`ui_plan`: as below, or what a scroll did not move in, or after a
resize what changed and what the window grew by), copies over from the
buffer shown what the other lacks, the boxes it changed since that one
was painted, but for what it paints now (`ui_copy_boxes`,
`ui_copied_over`, a row at a time, read as bytes and written as a
range), moves a scroll's rows, and paints. It then asks the compositor
for the next frame (`frame ID`, before the damage, as `wl_surface.frame`
is), and gives it the buffer: `attach ID VA N S` and a `damage` of what
it lacked and what changed, which shows it in the place of the one
shown; or, after a resize, `resize ID W H VA N S` naming it. The buffer
given up is the one painted next, lacking what changed. Until the
compositor tells the window its frame (`frm`) and the release of the
buffer given up (`rel`), which come as events `ui_route` takes
(`UiOther` saying `ui.frame` and `ui.release`), `ui_present` paints
nothing, and what changes meanwhile is painted at the next present, all
at once, since its damage is found from the nodes painted last. So a
window paints at most once a frame, and never into a buffer the screen
reads. A display that tells neither within `ui_pace_ns`, 100 ms, is
waited for no longer. Each window then holds two regions of the
process's 64 (`ui_app_regions`).

While the window is resized, a size asked (`UiResize`) and not yet
told, it waits for no frame, as the compositor asks a size only once it
has the last, which paces it as well; and if no buffer not shown is
released yet, it makes a third (`ui_back_pick`) rather than wait for the
restack that shows the last size to release one, so it paints the next
size while the compositor restacks. Its buffers not shown are a list,
the oldest given up first, and a release is the oldest's
(`ui_backs_released`). Once it presents unresized, it gives a third up
as soon as it is released, to the compositor too (`detach ID VA`,
`ui_backs_kept`). A third holds one more region, which
`ui_app_regions` keeps for one window at a time.

**Drawing areas, paced too.** A program that paints a
`UiDrawingArea` itself, as `vt` its terminal, paints the buffer
`ui_present` gives next, as GTK's drawing areas draw into their
window's next frame: `ui_win_drawing` gives the canvas to draw on,
that buffer brought up to what the screen shows first, so only what
changed need be drawn (`UiDrawOn`), or says to draw later while the
window waits (`UiDrawLater`), the program keeping what it would have
drawn; `ui_win_drew` tells what was drawn, which the next `ui_present`
damages with the rest, and which the program calls after. What the area
showed is not in the buffer once a resize makes another or the
compositor will not have one (`ui_win_lost` counts those times), and the
program then draws all of it again. A window whose next buffer cannot
be shared with the compositor is painted, and drawn, in the buffer
shown from then on, unpaced (`ui_win_single`).

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

**Keyed parts.** A part of a view a program keys by what it shows,
`UiKeyed KEY CHILD`, keeps its layout, and so its paint, from the last
present while its key is the same, it is laid out in the same place,
and what its look depends on beyond itself is the same (`ui_key_sig`:
the ground, the backdrop, the style, and the actions under the
pointer, pressed and focused, each only if it is one of the part's
own). `ui_present` finds the parts of the last layout by the mark laid
before each (`ui_kept_mark`, a node of no place, which nothing hits or
paints; `ui_kept_of`) and gives them to the layout with the state
(its `.kept`), so a hover over a button lays out that button, not
the page beside it. `ui_keyed_self NAME W` keys a part by itself, its
hash, as `ui_grid_page` keys its grid; a part holding images is keyed
by a cheaper value, as Files keys its items by their names, kinds and
sizes and its views' state (`fl_items_key`), and Fonts its page by the
face.

**Replies, not waits.** A window's loop waits on three ports of its
app's, as the process's set (`port_set`, made by the loop the first
time): the window's, the toolkit's reply port, and the program's.
`ui_present` asks `font` for a strike it lacks (`ui_face_asking`), its
answer to the toolkit's reply port, and goes on: the strike is kept as
asked (`UiStrikeAsked`) and its text drawn as none. When the answer
comes the loop takes it into the face (`ui_face_answered`, by the
strike the answer names, as `font` answers a strike once it is ready,
not in the order asked; an answer that names none is the oldest
ask's), forgets the text from it as
painted in each window, and their keyed parts (`ui_win_restruck`), and
hands each window `UiReply -1`, so the program presents it and the
text is drawn. A program asks a server the same way, `ui_win_ask W TAG
PORT BODY` or `ui_app_ask`: the request sent with the program's reply
port and never waited on, and its answer handed out as `UiReply TAG
MESSAGE` (of no window, for an app), the tags in the order asked;
`ui_reply_of` reads one. One that cannot be sent is answered at once,
the message `RecvFailed`. Files lists a folder on a volume so, and asks
each volume's size, its refreshes, its changes, a file's text and its
idle pieces the same, as Disks reads a drive and makes its changes,
one request out at a time ([programs.md](programs.md)); the fs
protocol's bodies and reply readers (`fs_list_body`, `fs_open_body`,
`fs_df_of` and the rest, `user/lib/proto/fs.l0`) and the disk
protocol's (`disk_read_body`) are what they ask with.

**A program's own ports.** A program that has ports of its own to wait
on gives them to the loop, `ui_win_ports W PORTS` or `ui_app_ports`,
and they join the set: what comes on one is handed out as `UiPort PORT
MESSAGE` (`ui_port_of`), before the windows' notices, as replies are.
Given again with other ports, as one is added or let go, the set is
made again at the next take. Terminal's tabs' ports are so: a set
holds `port_set_limit` (32) ports, the app's and the toolkit's two
reply ports among them, so its windows have at most 29 tabs between
them. A set the kernel refuses is said as a warning, and the loop waits
on the window's port alone.

**A timer.** A window that refreshes on a timer asks the kernel's alarm
for its port, `ui_win_alarm W T`, and takes it as an event
(`ui_is_alarm`), asking the next, as System Monitor reads its table
each second: the loop waits for a message or the alarm, never polls.

**Idle work.** A program with work too long for one step says so,
`ui_win_idling W true` or `ui_app_idling`, and does it a bounded piece
at a time: while nothing waits on its ports, the loop hands out
`UiIdle` (`ui_is_idle`) rather than wait, and the program does one
piece and presents; any message that comes is taken first. Files looks
at a listed folder's files and apps so, a thing a piece, and says it has
none left.

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
to close (`UiWin`'s `.close_asked`). A program answers by closing the window
(`ui_close`) and ending, as Files, Fonts and Terminal do; one that keeps
it, as one asking first whether to save would, calls
`ui_win_close_kept`. One that does nothing with it presents the window
again, and `ui_present` closes it instead and asks the compositor to
`end` the program (`compositor_end`), since L0 has no call that ends a
program but returning from `main`: so Disks closes as it did when the
close button killed it. A program run by `ui_run` needs neither: the
runner closes the window and returns.

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

### A new app

`tools/l0s-app-new NAME TITLE [DIR] [--bundle APP]` writes an app of
one window in the shape To Do has (`user/apps/todo`), small enough to
replace: `NAME.l0`, a record of state, its view a `ui_page` of a count
and a button, its update a chain of tests on the action, its step and
`ui_run`; `NAME_test.l0`, tests of the update and the view (`UI_TESTING`)
and that it fails with no compositor; `main.l0`; and `preview.l0`, two
scenes. With `--bundle`, the bundle's manifest, named TITLE, and an
`icon.draw`. It writes over nothing, and what it writes checks, passes
its tests, previews and builds as written (`test_proxy.py`'s
`Scaffold`). The `l0s-ui` skill's `apps.md` goes on from there: what a
person asks for, the widget, its actions, what the state keeps and the
update's line, for each of the widgets above.

### Previewing on the host

A view is a function of the program's state, and laying it out and
painting it need no kernel, so an app's look is seen on the host, in
seconds, before it is built for the board. Its `preview.l0`, beside
its `main.l0`, is a `main` of its own that names its scenes, each a
`UiShot` of a file name, a size and the view of some state, built with
the app's own functions, so a scene after a click is one more call of
its update:

```
(def main () int
  (ui_preview (cons (UiShot "main" 640 440 (gallery_view (gallery_new)))
                    (cons (UiShot "selected" 640 440
                            (gallery_view (gallery_update (gallery_new) "procs.select.6" (UiOther 0 "") (ui_no_scroller))))
                          (nil UiShot)))))
```

`make preview APP=NAME` builds it on the host with the app's sources
(never its `main.l0`, which a preview leaves out as the app leaves out
`preview.l0`) and `UI_PREVIEW`, and runs it: each scene laid out at its
size and painted as `ui_present` paints the window's client area, in
the dark style, on the window's ground, nothing hovered, pressed or
focused, with the board's own strikes and icons as the build made them
(`build/strikes`, `build/icons.face`), into
`build/preview/NAME/SCENE.png`. What the board's compositor adds, the
title bar and frame, is not in it. The pixels are the board's: the
gallery's selected row is 36 56 80 in its preview as in
`tests/widgets.sh`'s screen dump. The builder's sessions do the same
with `l0s-app-preview` ([network.md](network.md)).

### Scrolling

A widget that scrolls, the grid, the icon view and lines, is a
**scroller**. Its layout
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

Lines (`UiLines`) show the end when the program keeps their first row
-1, as a chat does: `ui_lines_first` turns a `scrollto` back to -1 when
it reaches the most there is, so rows that come later are shown as they
come until the person scrolls up from the end.

A scroller wider than it shows scrolls across too. The grid is, when its
columns add up to more than its width: it keeps how many pixels of them
are scrolled off to the left in `UiGridState`'s last field, and lays its
header and cells out that far to the left, in nodes no wider than it,
so painting cuts them at its edges at the pixel: a cell's text there
shows part of a character, and its icon or level bar part of itself, as
GTK's scrolled window shows them. Two more
nodes say so: all of it, beneath the rest, `NAME.across.LEFT.MOST`, and
a strip along its bottom, short of the scrollbar down,
`NAME.acrossbar.LEFT.MOST.SPAN.SLIDER`, with an overlay slider as long
as the share of the columns shown. `ui_route` reads them as it reads
the scroller's down: the wheel's steps across over either, a press on
the strip off the slider, and a drag of the slider set off
`NAME.acrossto.N`, N pixels to be scrolled off, which `ui_grid_action`
keeps. A step across is 48 pixels (`ui_wheel_across`); a turn with
steps down as well scrolls down. Since it scrolls across, a grid asks
only 40 a column across of the box it is in, as GTK's scrolled window
asks no more than its least, not its columns' widths. Files' preview of a file is a grid of
one column as wide as its widest line, so a long line is scrolled to.

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

### The pointer's shape

As the pointer moves in a window, `ui_route` asks the compositor for the
pointer it wants there (`ui_pointer_at`), with the compositor
protocol's `cursor ID NAME`, but only when it differs from the one last
asked, which `UiWin` keeps: over an entry the I-beam, `text`, as
GtkEntry's; inside the edge of a window that draws its own decorations,
where a press resizes it (`ui_csd_edges`), the resize pointer of those
edges (`ui_edges_pointer`), as the compositor shows over the border
outside; else the arrow. A program needs no code for it.

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
  are in the accent, destructive ones in red. Tinted ones (`UiBtnTinted`)
  are the accent at 25%, 35% and 50% over the ground, the accent's color
  their label's, as a keypad's operators; colored ones (`UiBtnColored
  C`) any color of the theme's, as suggested and destructive are of
  theirs, with white on it. `UiBtnFill KIND` is a button of KIND that
  fills all the room it is laid out in, asking a square a button high,
  so keys in a row share it evenly. Insensitive buttons are drawn
  at half strength and aren't targets.
- **Clicks** activate on release over the same target, as GTK's do. The
  keyboard focus ring (accent at half) appears only after Tab, except on
  an entry, which shows it, and its cursor, whenever it has the focus.
  Tab takes the focus to the next target, round to the first, and
  Shift-Tab to the one before, round to the last (`ui_focus_next`,
  `ui_focus_prev`); Esc takes it away.
- **Entries** are a button high, 6 px round, on 10% of the text color,
  their text 9 px in, their cursor a pixel wide.
- **Empty states** use a status page: a large dim icon, a title, and what to
  do next.
- **Switches** are 48 by 26, their knob 20 and white, 3 in from the end
  they are at, the pill in the accent when on and the text's color at
  15% when off (20% under the pointer). **Check boxes** are 16 square,
  rounded 4, the same colors, with Adwaita's check while on. **Sliders**
  are 26 high, their trough 6, round, filled in the accent to a white
  knob of 20. A **spinner** is eight dots turning a dot each 100 ms.
- **Boxed lists** are a card rounded 12, rows 50 high with a line between
  each two, 12 in: an icon, a widget, the title over a dimmed subtitle,
  and a widget at the row's end.
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
  service's strikes, in pages every program shares and reads in place,
  a region an arena of them: each glyph only as wide as its ink, placed
  from its pen by its box.
  An entry or a value that must hold n characters of any kind is made
  `ui_chars_w` wide, n of the face's widest.
  A program may also show text in any face `font` names at a line height
  of its own, `UiFontAt FACE H` (8 to 128 of the screen's pixels), as
  Fonts does: the widget `UiText TEXT FONT ALIGN`, in the text's color,
  or a `UiPText` of it. It is measured by `metrics.l0`'s face of that
  name, or as Source Code Pro if there is none, at that line; its strike,
  `glyph.FACE.H·s`, is asked of `font` by `ui_present` the first time
  a layout shows it, and kept in the window's face for its life, read
  through the region over its arena, opened once for every strike in
  that arena; one `font` will not give is kept as none, not asked for
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
  A window paints four times the pixels at 2, so painting keeps its work
  a pixel small: a fill of 16 pixels across or more over a buffer is
  one copy a row of the color's pixels, made once as bytes
  (`render.l0`'s `fill_rows`, `canvas_fill`), not a write every two
  pixels; text, icons and images are drawn a row at a time, the row's
  place and its columns in the clip found once (`UiPxRow`), each pixel
  then put by its index, a word of a glyph's coverage outside the clip
  skipped whole, and an edge mixed in one function (`ui_cov_mix`, the
  same pixel as `ui_mix`).

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
- A window keeps a third buffer only while it is resized, and gives it
  up at its first present after once the compositor releases it: one
  shown between the sizes of a drag, as a hover's, gives it up too, and
  the next size shares a new one with the compositor. Copying over what
  the buffer painted lacks costs about half a millisecond a size of
  Disks's drag on QEMU. A scripted drag of the gallery's edge, 160 moves
  30 ms apart, showed 153 to 155 sizes with the third, where two buffers
  showed 132 to 135.
- A window whose next buffer cannot be shared with the compositor, which
  has no room for it (at 4K, see [display.md, Limits](display.md#limits)),
  is painted in the buffer shown from then on, unpaced, so a frame may
  show it half painted: said once, as a warning, and that buffer not
  shared again. A buffer keeps a quarter more of each side, and 64
  pixels, as room to grow.
- A program that paints a drawing area draws, while its window waits
  for a frame, nothing: it keeps what is due (`vt` the rows its output
  changed and how far it scrolled, `Due`) and draws it at the next step
  the window may. It draws through the toolkit only into the buffer
  `ui_win_drawing` gives, and calls `ui_present` after, which it must,
  or what it drew is not shown.
- An app's regions are counted by the toolkit, not asked of the
  kernel, which has no call for it: `ui_app_open` knows its windows and
  its face's strikes, and keeps 8 for the rest, so a program that opens
  more of its own than that can still run out. An app's loop does one
  message a step, after putting together what waits, a window's whole
  step each time; only a run of one window's moves and turns, with
  nothing else of it between, is put together, so moves of a window
  with a key between them are two steps. The toolkit cannot keep a
  program from blocking itself: a request it waits on in its update,
  or a piece of idle work longer than a frame, stops its windows as
  long, which the slow step's line then says. Its own requests, the
  strikes, are replies, and so are the apps' (Disks' reads and changes,
  Files' listings, sizes, changes, previews and idle pieces); what each
  still does in its step is a kernel call, or a request too small to
  matter: Files reads an app's manifest as it starts the app, and Disks
  asks a disk registered since its start its size, once, at Refresh. A
  program's own asks go one at a time: Disks has one request out, and
  Files one a window, a listing's, a file's or a change's, the next
  asked as each answer comes, so a folder of many files is listed a
  reply at a time, each reply a step. The
  slow step's line is wall time, the time from the route to the
  present's end, not the process's own: a step another process shares
  its CPU with, or the first after the board idles, is longer than it
  would be alone. Replies are matched to asks in the order asked, so
  a program's asks go to servers that answer in order, as `fs` does
  one client's. A program ends
  only by returning from `main`, so one that does nothing with a close
  is ended by the compositor at its asking (`end`).
- Scrolling is by whole rows down and by 48 pixels across: the wheel's
  steps are counted, not its speed, and there is no kinetic scrolling.
  Only the grid scrolls across.
- An entry does not scroll its text, which is cut short with `...`, so an
  entry is made as wide as what it will hold, and has no selection,
  copying or pasting. A text area wraps instead, but past its most rows
  shows only those around the cursor, with no scrollbar; Up and Down do
  not move between its rows, and Home and End go to its text's ends.
- A height for a width is asked only by a column of its children: a
  text area in a row is as high as the row's other children make it
  unless the row is in a column, and a grid, list or lines never ask it.
- A picture is scaled by the nearest pixel, so an image is decoded at
  the size it is shown (`png_fit`) to look as it should.
- Lines wrap every paragraph at each layout, measuring each candidate
  line whole, so their cost grows with all they hold, not with what
  shows; nothing of them is keyed. Their text cannot be selected or
  copied, and a row is one line of 16 high, so they show no larger text.
- A slider steps a twentieth of its range for Left and Right, which a
  program cannot change, and has no marks or value drawn on it. A
  spinner is dots, not AdwSpinner's arc, since nothing is drawn by hand
  but rounds and fills, and it turns only as its program's alarm turns
  it. A boxed list's rows are all 50 high, a line of title and one of
  subtitle at most; it shows no selection and takes no keys but the
  focus's Tab and Enter, and it scrolls by whole rows, each its own
  node, so it shows whole rows only.
- A preview paints at scale 1 only, in a state nothing has touched: no
  hover, press or focus, so an entry shows no cursor and no ring. Its
  face has the interface's eight strikes and the symbolic icons, so text
  in another face or height (`UiFontAt`), full-color images
  (`ui_images_load`'s, which read `/etc/images`) and a drawing area,
  which its program paints, are not drawn. Its PNGs are not compressed:
  a 640 by 440 window is about 845 KB.
