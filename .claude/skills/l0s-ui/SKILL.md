---
name: l0s-ui
description: UI conventions for L0S. The toolkit in user/lib/ui (GNOME HIG and libadwaita look, the ui_/Ui naming, theme colors and sizes, widgets, the Elm-style client window loop), the compositor wm (its buffers, layer order, title bars, frames, top bar, geometry, hit testing, input routing, drag), and what the display driver can and can't do. Use when changing anything that draws or takes pointer or keyboard input: user/lib/ui, wm, vt, widgets, procmon, draw, virtio-gpu, display.l0, wm.l0, or the screen tests.
---

# UI in L0S

The look is GNOME's: the [HIG](https://developer.gnome.org/hig/) and
libadwaita's Adwaita style, light. `user/lib/ui/README.md` describes the
toolkit for people; the README's "The desktop" section, the compositor and
display. This is the working summary, with the rules.

## Rules

1. **Colors and sizes come from `user/lib/ui/theme.l0`.** No hex literal or
   pixel size outside it, except a program's own layout arithmetic. A new
   one goes in the theme with a test in `theme_test.l0`. The one exception
   is `render.l0`'s plain color names (`red`, `cyan`...) for `run draw`,
   which predate the toolkit.
2. **Every toolkit name is `ui_…`, every type and constructor `Ui…`.** All
   files are one namespace; the toolkit is linked into `wm`, `vt`, `draw`,
   `widgets` and `procmon`, so a bare name there clashes sooner or later.
3. **Follow the HIG's numbers**, already in the theme: spacing 6 between
   related things, 12 between groups, 18 around a page (`ui_space_s/m/l`);
   header bars 46 (`ui_headerbar_h`) with a bold centered title; buttons 34
   high (`ui_button_h`), radius 6 (`ui_button_radius`), round title buttons 24
   (`ui_titlebutton`); window corners 12 (`ui_window_radius`); rows 30.
4. **A click acts on release, over the target it was pressed on.** The focus
   ring shows only after Tab. An insensitive button is drawn faded and is no
   target.
5. **Geometry changes move three things together**: the drawing, `wm`'s hit
   test, and the pixel coordinates in the screen tests (see `l0s-testing`).
   `wm_test.l0` pins exact pixels; recompute them.

## The theme (`theme.l0`)

- **Semantic colors take the style**:
  `(ui_headerbar_bg (ui_style) front)` is `ebebeb` in front and `fafafa`
  in the backdrop. Others: `ui_window_bg`, `ui_view_bg`, `ui_fg`, `ui_dim_fg
  s bg`, `ui_border s bg`, `ui_headerbar_fg`, `ui_headerbar_shade`,
  `ui_selected_bg bg`, `ui_focus_ring bg`, `ui_accent_bg`, the terminal's
  `ui_term_bg`, `ui_term_fg` (GNOME Console's `1e1e1e` and white), and
  `ui_desktop_bg`. `(ui_style)` is light; dark is there but unused.
- **Named colors** are libadwaita's palette, in the string `ui_palette`
  (`blue_3`, `dark_4`, `accent`...), found by `ui_color_named`. A color used
  in code also gets a one-line def, `(def ui_blue_3 () int (ui_hex "3584e4"))`.
- **A semantic color** is `(if (ui_is_dark s) DARK LIGHT)`.
- **There is no alpha.** No layer blends, so "10% of the text color" is
  `ui_mix fg bg 10`, against the ground it will be drawn on.
- Colors are ints `0xRRGGBB`; `ui_hex "rrggbb"` reads one; tests compare
  `(hex_digits c 6)`.

## Painting and widgets

- **`paint.l0`**: `UiRect`; the ops `UiPFill`, `UiPRound` (antialiased only
  against the color given, or `-1`, the pixel already there), `UiPText`
  (aligned, bold as a double strike, ellipsized with `...`, scale 1 or 2),
  `UiPIcon`. `ui_paint canvas font clip ops` runs a list. `ui_buffer w h`
  makes a shared buffer and its `Canvas`.
- **Text** is the 8×16 bitmap font (`ui_char_w`, `ui_char_h`), ASCII only.
  `ui_text_w s bold scale` measures.
- **Icons** are 16×16 `#`/`.` art in `icons.l0`, named as GNOME's symbolic
  icons (`window-close`, `view-refresh`...).
- **`widget.l0`**: a `UiWidget` tree (`UiLabel`, `UiButton`, `UiBox`,
  `UiExpand`, `UiPad`, `UiSeparator`, `UiHeaderBar`, `UiView`, `UiLevel`,
  `UiStatus`, `UiStatusPage`, `UiGrid`, `UiSpace`). `ui_layout widget rect
  state bg` lays it out into `UiNode`s; `ui_paint_nodes` paints them;
  `ui_hit nodes x y` gives the action under a point.
- **`grid.l0`**: the data grid, typed cells, sorting, selection, keys,
  the wheel, and an overlay scrollbar whose slider drags.
- **Scrollers** (`widget.l0`): a widget that scrolls keeps how it is
  scrolled in its nodes' actions, `NAME.scroll.FIRST.MOST.SHOWN` for its
  area and `NAME.scrollbar.FIRST.MOST.SPAN.SLIDER` for its scrollbar's
  strip, since the view cannot write state. `ui_route` reads them for the
  wheel and drags and sets off `NAME.scrollto.N`; keys that move a
  selection take `ui_win_scroller w NAME` to scroll it into view. The
  layout does not keep a selection in view by itself.
- **Actions, not callbacks.** L0 has no function values, so a widget that
  does something carries an action name, as GActions are named:
  `"app.refresh"`, `"procs.sort.2"`, `"procs.select.6"`, `"win.close"`.

## A client window (`window.l0`)

The Elm architecture: a `data` for the state, a `view` from state to a
`UiWidget`, an `update` from state, action and event to a state. The loop,
from `user/widgets/widgets.l0`:

```
(match (ui_open "Widgets" 640 400) ...)     once: UiOpenedWin or UiOpenFailed
(port_receive (ui_win_port w))              a message
(ui_route w (ui_event_of w message))        (UiRouted w2 action), action "" for none
(gallery_update g action event)             the new state
(ui_present w2 (gallery_view g2))           repaints and damages only what changed
```

Events are `UiKey`, `UiPress`, `UiRelease`, `UiMotion` (window coordinates),
`UiLeave`, `UiFocus front`, `UiScroll x y dx dy` (the wheel, in steps, down
and right positive), `UiExit pid status` and `UiOther`. A window that
must also refresh on a timer polls instead (`user/procmon/procmon.l0`: a
`port_try_receive`, and an idle branch that sleeps). Linking a window needs
`UI_CORE`, `UI_WINDOW` and `WMLIB` (`LIBS_widgets`).

## The compositor (`user/wm/wm.l0`)

It owns the screen through the display protocol and keeps windows for its
clients. It never copies a window's pixels: each is a shared buffer, and the
driver composes them.

- **Buffers**: desktop 0, pointer 1, top bar 2, and window `i`'s content
  `3 + 3i`, title bar `4 + 3i`, frame `5 + 3i` (`content_id`, `title_id`,
  `frame_id`).
- **Layers**, bottom first (`layers`): the desktop; each window from the back,
  its title bar at `x, y`, its frame at `x, y + 46`, its content at
  `x + edge, y + 46`; then the top bar over everything. The pointer is the
  driver's cursor, not a layer.
- **Window geometry**: `Win` keeps the content's size `cw` by `ch`, as the
  client asked and as `windows` reports it. The window is `outer_w cw` = `cw +
  2·edge` wide; its frame is `frame_h ch` = `ch + edge` high under the 46-row
  title bar, `edge` = 2. The frame is painted only where it shows: the sides,
  the foot, and its bottom corners (`frame_ops`), in the title bar's ground.
- **Corners**: `display_shape` rounds the title bar's top corners
  (`top_radius`, 12), the frame's bottom ones (`bottom_radius`) and the
  content's inside them (`inner_radius`, 12 − edge). `cut_off` uses the
  driver's own formula (`ui_corner_cut`), so a press in a cut corner falls
  through to what is beneath.
- **Hit testing**: `hit` gives `OnClose`, `OnTitle`, `OnContent win cx cy`
  (content coordinates), `OnFrame` or `OnDesktop`, frontmost first; `on_bar`
  is checked before it. A new kind of region means a new `Hit` constructor,
  and every match on `Hit` gains an arm.
- **Title bars** are toolkit header bars (`title_nodes`, with
  `ui_st_backdropped` for the back windows) repainted by `titles` whenever
  the front window changes; `titles` also repaints the frames and the top
  bar.
- **The top bar** (`bar_ops`, `draw_bar`): 32 rows, black, the front
  window's title at its start and `clock_text` of the time, bold, in its
  middle. `rtc clock` tells `wm` the time each minute (`user/lib/clock.l0`).
  Windows open below it (`cascade` starts at 40), and a drag keeps their top
  at `below_bar`.
- **Input**: keys go to the front window's port. The pointer goes, relative
  to the content, to the window whose content it is in, or to the one a press
  in its content grabbed until every button is up, with a leave notice when
  it goes. A title bar press raises and starts a drag; the close button kills
  the client (`close_pressed`); the frame and content raise. The wheel
  (`wheeled`) goes to the window the pointer would. The tablet's driver
  sends a report's `WheelEvent` before its `PointerEvent`, so a client has
  scrolled before the pointer's next place is hit-tested, and the hover
  shows what is under the pointer now.
- **Drags** move the window on every event but rebuild the screen only once
  `drag_ns` (20 ms) has passed since the last rebuild *ended*. Timing from
  its start made every queued event rebuild once more, and the window fell
  further and further behind.
- **State**: `Wm` and `Win` are big records matched in full in nearly every
  function. To add a field, replace-all the exact pattern text with the Edit
  tool, then let `l0 check` name the remaining patterns with other binding
  names.

## The display (`user/lib/display.l0`, `user/virtio-gpu/virtio-gpu.l0`)

virtio-gpu's 2D mode: the host composes the screen from a list of memory
runs that the driver builds from the layers, so no guest code copies pixels.

- **No blending**, no alpha layers, no shadows. Corners are cut whole pixels
  by shaped layers (`shape ID TL TR BL BR`); the layer beneath shows through.
- **`damage`** is a transfer and a flush of rectangles; batch them into one
  request (`ui_present` does).
- **A restack** (`layers`) rebuilds the backing. The driver keeps every
  screen row and rebuilds only the rows of layers that moved, scrolled or
  changed buffer (`rows_restacked`, `dirty_rows`); a change of layer order
  rebuilds them all. With two windows a drag's restack takes about 15 ms on
  QEMU. More layers make every restack dearer: think twice before adding one
  per window.
- **Scrolling** is a ring: a client changes its window's `top` row instead of
  copying (`vt` does).
- **The cursor** is the device's own, 64×64, moved without touching the
  screen.
- **The 64-region limit** (`l0s-dev`): `wm` opens two regions a window.
