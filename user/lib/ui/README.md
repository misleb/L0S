# user/lib/ui — the L0S toolkit

A small widget toolkit for L0S programs. It follows the
[GNOME Human Interface Guidelines](https://developer.gnome.org/hig/) and
draws as libadwaita does, in Adwaita's colors and sizes. `wm`'s title bars,
`vt`'s colors, `draw`'s commands and the `widgets` gallery are built on it.

## Files

| File | What it is | GTK / libadwaita |
|---|---|---|
| `theme.l0` | The palette (`blue_1`…`dark_5`), the light and dark styles' semantic colors, spacing, radii, sizes. Alpha colors are mixed with `ui_mix`, since no layer blends. Depends on nothing. | `@window_bg_color`, `@accent_bg_color`, … |
| `icons.l0` | 16×16 symbolic icons, kept as `#`/`.` art: window-close, pan-down, pan-up, view-refresh, open-menu, system-search. | `*-symbolic` icons |
| `paint.l0` | `UiRect`; the `UiPaint` ops (fill, rounded fill with antialiased corners, text, icon); `ui_paint` runs them on a canvas, clipped. Also `ui_buffer` for shm buffers and Adwaita's arrow cursor. | GSK render nodes |
| `widget.l0` | `UiWidget` (label, button, box, expand, pad, separator, header bar, view, level bar, status, status page, grid, space); `UiState`; `ui_layout` into `UiNode`s; `ui_hit`, `ui_focus_next`, `ui_paint_nodes`. | `GtkLabel`, `GtkButton`, `GtkBox`, `AdwHeaderBar`, `GtkLevelBar`, `AdwStatusPage` |
| `grid.l0` | A data grid: columns, typed cells (text, number, level, status, icon), sorting by column, selection, keyboard movement, overlay scrollbar. | `GtkColumnView` |
| `draw_cmd.l0` | The desktop's drawing commands: render.l0's, Adwaita's colors by name, `round` and `button`. Used by `draw` to check a command and by `wm` to draw it. | — |
| `window.l0` | A client window: `ui_open`, `ui_event_of`, `ui_route` (hover, press, click on release, Tab focus, Enter/Space), `ui_present` (repaints only what changed). Needs `user/lib/wm.l0`. | `GtkWindow`, event controllers |

The Makefile links either `UI_CORE` (every file but `window.l0`; needs only
`render.l0`) or `UI_CORE` plus `UI_WINDOW` (`window.l0`; needs
`user/lib/wm.l0` too).

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

`user/widgets/widgets.l0` is that loop in full, with a toolbar and a data grid.

Every name is `ui_…` and every type or constructor `Ui…`. All files given
to `l0` are one namespace, and a duplicate is a compile error.

## The HIG, as encoded here

- **Spacing** 6 between related things, 12 between groups, 18 around a page
  (`ui_space_s/m/l`).
- **Header bars** are 46 px with a centered bold title, controls packed 6 px
  from either edge, and a shade line underneath. In the backdrop they're
  lighter with a dimmed title.
- **Buttons** are 34 px tall (24 px round title buttons) with a 6 px radius.
  The ground goes from 10% to 15% to 30% of the text color for rest, hover
  and pressed. Flat buttons have no ground until hovered. Suggested buttons
  are in the accent, destructive ones in red. Insensitive buttons are drawn
  at half strength and aren't targets.
- **Clicks** activate on release over the same target, as GTK's do. The
  keyboard focus ring (accent at half) appears only after Tab.
- **Empty states** use a status page: a large dim icon, a title, and what to
  do next.
- **Text** is the 8×16 bitmap font, so text is ASCII only, ellipsized with
  `...`, bold is a double strike, and large text is scaled 2×.

## Limits

- No layer blends (virtio-gpu 2D), so a corner is antialiased only against a
  color the op is given, or against the pixel already in the same buffer
  (`-1`). Window corners are rounded by the display's shaped layers, which
  cut whole pixels, so they aren't antialiased. There are no window
  shadows.
- One bitmap font and one size of icon. Icons and text scale by whole
  numbers.
- No scroll wheel yet. The grid scrolls to keep its selection in view.

## The display layer

Two Wayland-style changes to the display layer (`user/lib/display.l0`,
`user/virtio-gpu/virtio-gpu.l0`) came with the toolkit:

- **Shaped layers** (`shape ID TL TR BL BR`), like an opaque region. The
  driver narrows a layer's runs on its corner rows, so a window's 12 px
  corners show what's beneath with no blending. `wm` shapes every window,
  and its hit test (`ui_corner_cut`, the driver's formula) lets a press in
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
6. **Client-side decorations**: a `csd` window flag and `move ID`
   (`xdg_toplevel.move`), so programs draw their own header bars.

Outside the display layer: wheel events from virtio-input, and modifier
state in `KeyEvent` (for Shift-Tab).
