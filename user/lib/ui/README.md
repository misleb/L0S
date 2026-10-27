# user/lib/ui — the L0S toolkit

A small widget toolkit for L0S programs. It follows the
[GNOME Human Interface Guidelines](https://developer.gnome.org/hig/) and
draws as libadwaita does, in Adwaita's colors and sizes. `wm`'s title bars,
`vt`'s colors, `draw`'s commands, the `widgets` gallery, `procmon`,
`disks` and `files` are built on it.

## Files

| File | What it is | GTK / libadwaita |
|---|---|---|
| `theme.l0` | The palette (`blue_1`…`dark_5`), the light and dark styles' semantic colors, spacing, radii, sizes. Programs draw in the dark style: `ui_style` says so, the one place a setting for it will be read. Alpha colors are mixed with `ui_mix`, since no layer blends. Depends only on `ppm.l0`'s colors and `render.l0`'s glyph. | `@window_bg_color`, `@accent_bg_color`, … |
| `icons.l0` | The names of the symbolic icons, 16×16 at scale 1, GNOME's own: each is its SVG under [icons/](../../../icons) (Adwaita's, and System Monitor's for utilities-system-monitor), which `tools/mkicons` rasterizes into `/etc/icons` at the build. window-close, pan-down, pan-up, view-refresh, open-menu, system-search, drive-harddisk, the apps' utilities-terminal, utilities-system-monitor and view-app-grid, and the files' folder, text-x-generic, application-x-executable, go-previous, go-next, view-list, view-grid and computer. Also `ui_image_names`, the full-color icons Files and Disks show things with, Adwaita's under `icons/adwaita/scalable`, which `tools/mkicon --image` draws into `/etc/images/NAME.face`. | `*-symbolic` icons, and the full-color theme icons |
| `face.l0` | The face: the icons at the sizes its scale paints, from `/etc/icons`; and the coverage `tools/mkfont` rasterized into `/etc/face`: Source Code Pro's glyphs, regular and bold, at three sizes (16, 32 and 64 tall), and the pointer. An app's `icon.face` is the same format, its images' tables `image.N`, and so is each full-color icon's `/etc/images/NAME.face`, which a program loads by name, at the sizes its scale paints, with `ui_images_load` into a `UiImages`, and finds with `ui_image`. | the font and icon theme at a scale factor |
| `paint.l0` | the `UiPaint` ops (fill, rounded fill with antialiased corners, text, icon, an image of its own colors with alpha, `UiPImage`, as an app's `icon.svg` makes), placed by `gfx/rect.l0`'s `Rect` in the desktop's pixels; `ui_paint` runs them on a canvas at the face's scale, clipped, and returns it, so a canvas over an array (a test's, `tools/mkicon`'s) is painted too. At scale 2 each op is twice the size, and text and icons are the face's, each pixel mixed by how much it covers. Also `ui_buffer` and `ui_buffer_at` for shm buffers, and Adwaita's arrow cursor. | GSK render nodes |
| `widget.l0` | `UiWidget` (label, button, box, expand, pad, separator, header bar, view, level bar, status, status page, grid, space, panes.l0's sidebar, segment bar, properties and modal, entry.l0's entry, a window's own header bar, nav.l0's path bar and toggle group, icon_view.l0's icon view and menu.l0's popover); `UiState`; `ui_layout` into `UiNode`s; `ui_hit`, `ui_focus_next`, `ui_paint_nodes`; scrollers (`UiScroller`, `ui_scroll_of`, `ui_scroll_hit`). `UiCsdBar START TITLE END CLOSES` is the header bar of a window that draws its own (`ui_open_csd`): any widget as its title, in the bar's middle as far as there is room, the window's close button at its end if CLOSES (`ui_close_action`), and its ground the window's to drag (`ui_move_action`). | `GtkLabel`, `GtkButton`, `GtkBox`, `AdwHeaderBar`, `GtkLevelBar`, `AdwStatusPage`, `GtkAdjustment` |
| `grid.l0` | A data grid: columns, typed cells (text, number, size, as `format_size` says it and sorted by its bytes, level, status, icon), sorting by column, selection, keyboard movement, scrolling by the wheel, and an overlay scrollbar whose slider drags. `ui_grid_page`, a toolbar of Refresh, a status line and End Process over a grid, as `widgets` and `procmon` are, and `ui_selected_line`. | `GtkColumnView`, `GtkScrolledWindow` |
| `panes.l0` | A window of panes: `UiSidebar`, rows of an icon, a title and a line, one selected; `UiSegmentBar`, a whole in parts each as wide as its share by weight (`ui_shares`), each plain or muted (`UiSegPlain`, `UiSegMuted`), at any height: a title over a line at `ui_segbar_h`, the title alone lower, no text as a usage bar; one part selected and moved along by Left and Right (`ui_segbar_key`), or, with prefix `""`, none and no targets; `UiProps`, a dimmed name before each value, which is any widget; `UiModal` and `ui_alert`, an alert dialog on a card over everything beneath, which is dimmed (`ui_scrim`) and no longer a target, and `ui_alert_form`, one with widgets, such as properties holding entries, between its lines and its buttons. Rows and parts carry `PREFIX.select.KEY`, read back by `ui_select_key`. | `AdwNavigationSplitView`'s sidebar, `GtkListBox` `.navigation-sidebar`, GNOME Disks' volume grid and Usage's storage bar, `AdwAlertDialog` and its extra child |
| `entry.l0` | `UiEntry NAME TEXT PLACEHOLDER WIDTH`, a line of text: `UiEntryText`, its text and cursor, kept by the program; `ui_entry_keyed`, typing at the cursor, Backspace, Delete, Left, Right, Home and End; drawn on the text's color at 10%, with the accent's ring and a cursor while it has the focus, the placeholder dimmed while it is empty. | `GtkEntry` |
| `nav.l0` | What a window that goes from place to place puts in its header bar: `UiPathBar PREFIX LABELS`, a button for each part of a path on 10% of the text color, the last, where one is, bold and no target, each other going to its depth, `PREFIX.select.N`, the first ones folded into `...` when it is too narrow; and `UiToggleGroup PREFIX TOGGLES KEY`, linked `UiToggle`s, an icon or a label each, the active one raised on the card's ground, `PREFIX.select.KEY`. | Nautilus' path bar, `AdwToggleGroup` |
| `icon_view.l0` | `UiIconView`, a grid of `UiTile`s, an icon 48 square at three times the size, in the accent or dimmed, and a name under it, as many across as fit, in the middle; one selected, rounded in the selection's tint, by a press or the keys (`ui_icon_key`: the arrows, a row for Up and Down, Home, End, Page Up and Page Down, its columns from `ui_win_icon_cols`), a press between them selecting none (`ui_icon_action`); a scroller by rows of tiles, with the grid's overlay scrollbar (`ui_scrollbar_on`). | `GtkGridView` |
| `menu.l0` | `UiPopover BASE MENU`, a popover menu over the window: a `UiMenu` of `UiItem`s, insensitive ones dimmed, and `UiItemSep`s, on a card, under the node of an action (`UiBelow`) or at a point (`UiAt`, as for a right click), kept inside the window; nothing beneath is a target while it is open, and a press outside it sets off `PREFIX.dismiss`. | `GtkPopoverMenu` |
| `draw_cmd.l0` | The desktop's drawing commands: render.l0's, Adwaita's colors by name, `round`, `button` and `icon X Y NAME [SCALE [COLOR]]`. Used by `draw` to check a command, by `wm` to draw it, and by `tools/mkicon` to draw an app's icon. | — |
| `window.l0` | A client window: `ui_open`, or `ui_open_csd` for one that draws its own header bars, which the compositor neither draws nor frames, a press on a `UiCsdBar`'s ground asking it to move the window; `ui_event_of`, `ui_route` (hover, press, click on release, a double click, `ui_win_double`, the same action set off again within 400 ms, a right press as `UiContext`, set off as `context.X.Y.TARGET` and read back by `ui_context_of`, Tab focus, Enter/Space, the wheel and scrollbar drags, keys to an entry with the focus), `ui_present` (repaints only what changed; all of it after the user resized the window, `UiResize`, in the buffer it has when that has room), `ui_win_scroller`, `ui_win_icon_cols`, `ui_win_focusing`, `ui_entry_update`; `ui_key_of` and `ui_key_pressed`, the key an event is. Needs `user/lib/proto/wm.l0`. | `GtkWindow`, event controllers, `GtkGestureClick`'s n-press and secondary button |

The Makefile links either `UI_CORE` (every file but `window.l0`; needs only
`RENDER`: `ppm.l0`, `rect.l0` and `render.l0`) or `UI_CORE` plus `UI_WINDOW`
(`window.l0`; needs `user/lib/proto/wm.l0` too).

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
(port_receive (ui_win_port w))      -> message
(ui_event_of w message)             -> event
(ui_route w event)                  -> (UiRouted w2 action)  action may be ""
(update state action event)         -> state2
(ui_present w2 (view state2))       -> w3                     paints what changed
```

`user/apps/widgets/widgets.l0` is that loop in full, with a toolbar and a data grid.

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
- **Text** is Source Code Pro in cells 8×16, so text is ASCII only, ellipsized with
  `...`, bold is the bold face, and large text is scaled 2×. At the
  desktop's scale 2 it is the same cells, 16×32 of the
  screen's pixels, smooth, bold its own weight.
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
- One monospaced face, smooth at every scale. Icons are
  smooth at every scale, at 16, 32, 48 and 64 times it, rasterized at
  the build, never at run time. Icons and text scale by whole numbers,
  and the face is ASCII only, as the font is. Text's edges are mixed with
  what is under them, as corners are, against the pixel already there.
- Scrolling is by whole rows: the wheel's steps are counted, not its
  speed, and there is no kinetic scrolling. The wheel across, which the
  driver reports, scrolls nothing yet.
- An entry does not scroll its text, which is cut short with `...`, and
  has no selection, copying or pasting.

## The display layer

Two Wayland-style changes to the display layer (`user/lib/proto/display.l0`,
`user/sbin/virtio-gpu/virtio-gpu.l0`) came with the toolkit:

- **Shaped layers** (`shape ID TL TR BL BR`), like an opaque region. The
  driver narrows a layer's runs on its corner rows, so a window's 12 px
  corners show what's beneath with no blending. `wm` shapes every window,
  and its hit test (`render.l0`'s `corner_cut`, as the driver cuts) lets a press in
  a cut corner fall through.
- **Batched damage and minimal restacks.** One `damage` takes many rects,
  like `wl_surface.commit`, in the display protocol and the compositor's.
  A `layers` change flushes only the bands of rows that changed, and the
  driver builds again only the rows of the layers that changed.
  `ui_present` sends its boxes in one request.

### Later

1. **Source viewports and subsurfaces** (`wp_viewporter`, `wl_subsurface`).
   A grid body could scroll as a ring under a still header, and all title
   bars could share one atlas buffer, easing the 64-region limit.
2. **An interrupt-driven, pipelined virtio queue**, plus frame and
   buffer-release callbacks, so clients can pace and double-buffer.
3. **A cursor set** and `wp_cursor_shape`: an I-beam over text, switched
   with one `UPDATE_CURSOR`.
4. **Alpha layers** for shadows and antialiased window corners: small
   strips composed by the driver.
5. **Output events** for mode changes.

Done since: **client-side decorations**, `wm`'s `csd` request and its
`move ID` (`xdg_toplevel.move`), so a program draws its own header bars
(`ui_open_csd`, `UiCsdBar`), as Files does; such a window has no chrome
of `wm`'s, so it costs no layer or region of its own beyond its content.
Still to do for them: maximizing by a double click on the header bar,
and a resize of its own (`xdg_toplevel.resize`) from inside its edge.

Outside the display layer: modifier state in `KeyEvent` (for Shift-Tab).
