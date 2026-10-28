---
name: l0s-ui
description: UI conventions for L0S. The toolkit in user/lib/ui (GNOME HIG and libadwaita look, the ui_/Ui naming, theme colors and sizes, widgets, the Elm-style client window loop), the compositor wm (its buffers, layer order, title bars, frames, top bar, geometry, hit testing, input routing, drag), and what the display driver can and can't do. Use when changing anything that draws or takes pointer or keyboard input: user/lib/ui, wm, vt, widgets, procmon, draw, virtio-gpu, display.l0, wm.l0, or the screen tests.
---

# UI in L0S

The look is GNOME's: the [HIG](https://developer.gnome.org/hig/) and
libadwaita's Adwaita style, dark. `spec/toolkit.md` describes the
toolkit for people; `spec/desktop.md` the compositor, and `spec/display.md`
the display. This is the working summary, with the rules.

## Rules

1. **Colors and sizes come from `user/lib/ui/theme.l0`.** No hex literal or
   pixel size outside it, except a program's own layout arithmetic. A new
   one goes in the theme with a test in `theme_test.l0`. The one exception
   is `render.l0`'s (`user/lib/gfx`) plain color names (`red`, `cyan`...) for `run draw`,
   which predate the toolkit.
2. **Every toolkit name is `ui_…`, every type and constructor `Ui…`.** All
   files are one namespace; the toolkit is linked into `wm`, `vt`, `draw`,
   `widgets`, `procmon` and `disks`, so a bare name there clashes sooner or
   later. Colors' channels are `ppm.l0`'s `rgb`, `rgb_red` and the rest, and
   a corner's cut `render.l0`'s `corner_cut`, shared with the display
   driver.
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
  `(ui_headerbar_bg (ui_style) front)` is `303030` in front and `242424`
  in the backdrop (light: `ebebeb` and `fafafa`). Others: `ui_window_bg`, `ui_view_bg`, `ui_fg`, `ui_dim_fg
  s bg`, `ui_border s bg`, `ui_headerbar_fg`, `ui_headerbar_shade`,
  `ui_selected_bg bg`, `ui_focus_ring bg`, `ui_accent_bg`, the terminal's
  `ui_term_bg`, `ui_term_fg` (GNOME Console's `1e1e1e` and white), and
  `ui_desktop_bg`. `(ui_style)` is dark, and is the one place a light/dark
  setting will be read: never pick a style anywhere else. Host tests that
  pin a style's colors pass `(UiLight)` or `(UiDark)` themselves.
- **Named colors** are libadwaita's palette, in the string `ui_palette`
  (`blue_3`, `dark_4`, `accent`...), found by `ui_color_named`. A color used
  in code also gets a one-line def, `(def ui_blue_3 () int (ui_hex "3584e4"))`.
- **A semantic color** is `(if (ui_is_dark s) DARK LIGHT)`.
- **There is no alpha.** No layer blends, so "10% of the text color" is
  `ui_mix fg bg 10`, against the ground it will be drawn on.
- Colors are ints `0xRRGGBB`; `ui_hex "rrggbb"` reads one; tests compare
  `(hex_digits c 6)`.

## Painting and widgets

- **Rectangles** are `user/lib/gfx/rect.l0`'s `Rect` (x, y, width,
  height) everywhere: layout, painting, the protocols' damage, the
  display driver. `rect_x`…`rect_h`, `rect_x1`/`rect_y1` (just past the
  end), `rect_clip` (cut to a screen is a clip with `(Rect 0 0 w h)`),
  `rect_union` (`rect_union_all` of a list), `rect_overlaps`, `rect_has`,
  `rect_inset`; an empty one (`rect_empty`, `rect_none`) holds nothing.
  `rect_merge` joins damage until no two rectangles overlap (the display
  driver merges a `damage` request's with it); `rect_minus` and
  `rects_minus` subtract, which `ui_changed`'s `ui_merged` uses to make a
  window's damage disjoint without growing it. Never declare another
  rectangle or another merge.
- **Damage is diffed from paint ops** (`ui_changed` in `window.l0`): old
  and new nodes' ops compared as multisets (`ui_op_key` makes a text its
  drawn characters and extent), a fill only where same-color fills on the
  other side don't cover. Never add damage by hand in an app; an op that
  paints the same pixels must compare equal, or it is repainted for
  nothing.
- **`paint.l0`**: the ops `UiPFill` (`ui_fills rs c` for many),
  `UiPRound` (antialiased only against the color given, or `-1`, the
  pixel already there), `UiPText` (aligned, bold as a double strike,
  ellipsized with `...`, scale 1 or 2), `UiPIcon`. `ui_paint canvas font
  clip ops` runs a list. `ui_buffer w h` makes a shared buffer and its
  `Canvas`.
- **A canvas** (`render.l0`) is over a shared region or, for host tools
  and tests, an array (`canvas_new w h color`, read back with
  `canvas_pixel`). Every drawing and painting function returns the canvas
  drawn on: over a region it is the same one, over an array the only one
  holding the pixels, so pass it on and keep no other. Host tests draw
  this way (`paint_test.l0`, `render_test.l0`), and so does
  `tools/mkicon`.
- **Text** is Source Code Pro in cells 8×16 (`ui_char_w`, `ui_char_h`),
  smooth at every scale, ASCII only.
  `ui_text_w s bold scale` measures.
- **Icons** are GNOME's own SVGs under `icons/` (Adwaita's symbolic
  ones, each project's license and `SOURCE` beside them), named in
  `icons.l0`'s `ui_icon_names` (`window-close`, `view-refresh`...), drawn
  by the SVG library (`user/lib/gfx/svg.l0`) at build time by
  `tools/mkicons` into `/etc/icons`, smooth at every scale. No icon is
  drawn by hand. `UiPImage` paints a full-color image with alpha, an
  app's `icon.face` (mkicon draws it from the bundle's `icon.svg`).
- **Full-color icons** (`icons.l0`'s `ui_image_names`: folder,
  text-x-generic, application-x-executable, drive-harddisk,
  drive-multidisk, computer) are Adwaita's `icons/adwaita/scalable/NAME.svg`,
  drawn by `mkicon --image` into `/etc/images/NAME.face`. A program
  loads the ones it shows once, `(ui_images_load names (ui_win_scale w))`
  (only the sizes its scale paints: they are a word a pixel), keeps the
  `UiImages`, and passes `(ui_image im NAME)` on: to `UiSideRow`'s last
  field, a `UiCellImage`, or a `UiTileDrawn`'s `UiPImage`.
  `ui_icon_or_image` falls back to the symbolic icon when none was
  loaded, as on the host. Files and Disks do this; status pages stay
  symbolic, as GNOME's are.
- **`widget.l0`**: a `UiWidget` tree (`UiLabel`, `UiButton`, `UiBox`,
  `UiExpand`, `UiPad`, `UiSeparator`, `UiHeaderBar`, `UiView`, `UiLevel`,
  `UiStatus`, `UiStatusPage`, `UiGrid`, `UiSpace`, and `panes.l0`'s
  `UiSidebar`, `UiSegmentBar`, `UiProps`, `UiModal`, `entry.l0`'s
  `UiEntry`, `nav.l0`'s `UiTabBar`, and `UiDrawingArea`, an area the
  program paints itself, which the toolkit never paints or damages,
  as `vt`'s terminal). `ui_layout widget rect
  state bg` lays it out into `UiNode`s; `ui_paint_nodes` paints them;
  `ui_hit nodes x y` gives the action under a point.
- **`grid.l0`**: the data grid, typed cells, sorting, selection, keys,
  the wheel, and an overlay scrollbar whose slider drags.
- **`panes.l0`**: what a window of panes needs:
  `UiSidebar` (rows of an icon, title and line on the sidebar's ground),
  `UiSegmentBar` (a whole in parts by weight, `ui_shares`, each part
  `UiSegPlain` or `UiSegMuted`; any height, showing a title and a line,
  the title alone, or no text, as a usage bar; prefix `""` for a bar
  nothing in is chosen; Left and Right with `ui_segbar_key`), `UiProps`
  (a dimmed name, then any widget), and
  `UiModal` with `ui_alert` (a card over the window, everything beneath
  mixed with black by `ui_scrim` and no longer a target; `ui_alert_form`
  puts widgets, such as properties with entries, between its lines and
  its buttons). Rows and parts carry `PREFIX.select.KEY`; `ui_select_key`
  reads it back. `user/apps/disks` uses them all.
- **Entries** (`entry.l0`): `UiEntry NAME TEXT PLACEHOLDER WIDTH`, the
  text and cursor a `UiEntryText` in the program's state. Its node's
  action is `NAME.entry`; a press focuses it and sets off `NAME.place.N`;
  with the focus on it (and it laid out), `ui_route` sends every key but
  Tab and Esc to it, Enter as `NAME.activate` and the rest as
  `NAME.edit`, so Space types. The update passes the action and event to
  `ui_entry_update NAME text action ev`. A dialog focuses its entry as it
  opens with `ui_win_focusing w "NAME.entry"` before presenting. A
  focused entry shows its ring whenever it has the focus, not only after
  Tab. No scrolling or selection: make it as wide as it must hold.
- **Scrollers** (`widget.l0`): a widget that scrolls keeps how it is
  scrolled in its nodes' actions, `NAME.scroll.FIRST.MOST.SHOWN.STEP` for
  its area (STEP its row height, rows laid out from the area's top) and
  `NAME.scrollbar.FIRST.MOST.SPAN.SLIDER` for its scrollbar's strip,
  since the view cannot write state. `ui_route` reads them for the wheel
  and drags and sets off `NAME.scrollto.N`; keys that move a selection
  take `ui_win_scroller w NAME` to scroll it into view. The layout does
  not keep a selection in view by itself. `ui_present` sees FIRST move by
  less than SHOWN (`ui_scroll_moved`), moves the area's pixels
  (`canvas_copy_rows`) and paints only what came into view
  (`ui_scrolled_changed`).
- **Actions, not callbacks.** L0 has no function values, so a widget that
  does something carries an action name, as GActions are named:
  `"app.refresh"`, `"procs.sort.2"`, `"procs.select.6"`, `"win.close"`.

## A client window (`window.l0`)

The Elm architecture: a `data` for the state, a `view` from state to a
`UiWidget`, an `update` from state, action and event to a state. The loop,
from `user/apps/widgets/widgets.l0`:

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
must also refresh on a timer polls instead (`user/apps/procmon/procmon.l0`: a
`port_try_receive`, and an idle branch that sleeps). `ui_key_pressed ev`
is the code of a key pressed or repeated, -1 for anything else, and
`ui_grid_page` the toolbar-over-grid page `widgets` and `procmon` share.
Linking a window needs `RENDER`, `UI_CORE`, `UI_WINDOW` and `WMLIB`
(`LIBS_widgets`).

## The compositor (`user/sbin/wm/wm.l0`)

It owns the screen through the display protocol and keeps windows for its
clients. It never copies a window's pixels: each is a shared buffer, and the
driver composes them.

- **The L0S menu** (`user/sbin/wm/logo_menu.l0`): the logo in the bar's
  first 32 columns (`menu_logo_w`; Applications and the title follow it),
  a card (`menu_w` by `menu_h`, buffer `menu_id` 100000, layered under the
  bar by `menu_layered` only while shown) of About L0S, Shut Down
  (`proc_kill 1`) and Restart (`board_restart`). Its state is `Bar`'s `Menu`, its press/release like the
  launcher's (`menu_act`); `pointer_held` keeps windows off the pointer
  while it or the launcher is up.
- **Buffers**: desktop 0, pointer 1, top bar 2, launcher 3, and window
  `i`'s content `4 + 4i + 2k` and chrome `5 + 4i + 2k` (its title bar with
  the frame under it, one buffer the window's size), k its bank
  (`launcher_id`, `content_id i k`, `chrome_id i k`; `win_bank`). A resize
  gives the display the window's buffers under the other bank and forgets
  the old ids after the restack: the display refuses to forget a buffer
  on the screen. `Bufs` keeps each buffer's pages and where the display
  has them, so a size that fits is given again in the same pages
  (`display_buffer_at`); the driver keeps pages mapped while any id is
  over them.
- **Resizing** (`edges_at`, `resize_geometry`, `Drag`'s `Resizing`,
  `resize_asked`, `resize_replied`): the frame's sides and foot and a
  6-pixel border outside the window are `OnEdge win edges` (bits
  `edge_left`...); within `resize_corner` (20) of a corner, wherever the
  window has nothing of its own (`free_at`: outside, cut corners, frame,
  the content's cut corners), both edges. Dragging asks the client with
  `size_notice` and never has two asks out (`Sizing`'s `asking`); the
  client answers with the wm protocol's `resize ID W H` (in place,
  `window_resize_in_place`) or `resize ID W H VA N` (a new buffer,
  `window_resize`). `wm` answers once the display has the content, asks
  for the next size at once, then makes the chrome, restacks and gives up
  what is unused, moving the window for a left or top edge so the
  opposite edge stays. A toolkit window takes `UiResize` in `ui_route`
  (`ui_resized`: in its buffer if it has room, `UiInPlace`, else a new one
  with `ui_grown` room, the old kept as `UiSwap` until wm has the new) and
  the next `ui_present` paints what changed and the exposed strip, or all
  of a new buffer (`ui_swapped`). The canvas is the whole buffer, its
  stride its width; `UiMem` keeps the window's size. Apps need no code;
  `vt`, which paints its terminal in a `UiDrawingArea` itself, rewraps
  its cells and paints the area whole before `ui_present`. The cost that matters is pages shared and
  given up, not pixels: keep resizes in place.
- **The pointer's image** (`pointer_shaped`, `pointer_wanted`,
  `resize_cursor`): buffer 1, painted again with `ui_paint_named_cursor`
  and given with `display_cursor` and its hot spot (`ui_cursor_hot_x`) only
  when it changes: `ew-resize`, `ns-resize`, `nwse-resize`, `nesw-resize`
  over edges or while they are dragged, the arrow `""` elsewhere. `Ptr`
  keeps its canvas and name; `windows` reports the name. A new pointer
  needs its 1x art in `ui_cursor_art`, its hot spot, and its shapes as
  `cursor NAME` in `fonts/cursors.paths`.
- **Layers**, bottom first (`layers ws shown`): the desktop; each window from the back,
  its chrome at `x, y`, its content at `x + edge, y + 46`; then the top
  bar over everything. While the launcher is shown: the desktop, the
  launcher at `0, 32`, the bar, and no window. The pointer is the
  driver's cursor, not a layer.
- **Window geometry**: `Win` keeps the content's size `cw` by `ch`, as the
  client asked and as `windows` reports it. The window is `outer_w cw` = `cw +
  2·edge` wide; its frame is `frame_h ch` = `ch + edge` high under the 46-row
  title bar, `edge` = 2, the chrome `chrome_h ch` high. The frame is painted
  only where it shows: the sides, the foot, and its bottom corners
  (`frame_rects`, in the chrome's rows), in the title bar's ground
  (`frame_ops`), and those same rectangles are its damage.
- **Corners**: `display_shape` rounds the chrome's top corners
  (`top_radius`, 12) and bottom ones (`bottom_radius`), and the content's
  inside them (`inner_radius`, 12 − edge); `shape_window`. `cut_off` uses the
  driver's own formula (`render.l0`'s `corner_cut`), so a press in a cut
  corner is no window's but grabs that corner's edges.
- **Hit testing**: `hit` gives `OnEdge win edges`, `OnClose`, `OnTitle`,
  `OnContent win cx cy` (content coordinates), `OnFrame` or `OnDesktop`,
  frontmost first; `on_bar` is checked before it. A new kind of region
  means a new `Hit` constructor, and every match on `Hit` gains an arm.
- **Title bars** are toolkit header bars (`title_nodes`, with
  `ui_st_backdropped` for the back windows) repainted by `titles` whenever
  the front window changes; `titles` also repaints the frames and the top
  bar.
- **The top bar** (`bar_ops`, `draw_bar`): 32 rows, black. At its start
  Applications, `bar_apps_w` (120) wide, on a pill (`ui_bar_active_bg`)
  while the launcher is open; then, from 120, the front window's app's
  name (`Win`'s last field, from `client_app`: `proc_info`'s entry, its
  path, the manifest of the bundle it is in, `app.l0`), or its title if
  it is no app's (`bar_title`); and `clock_text` of the time, bold, in
  its middle. `rtc clock` tells `wm` the time each minute
  (`user/lib/proto/clock.l0`). `Bar` also keeps the apps, read once at start
  (`app_bundles`), and the `Launcher`. Windows open below it (`cascade`
  starts at 40), and a drag keeps their top at `below_bar`.
- **The launcher** (`user/sbin/wm/launcher.l0`, and wm's section "the
  launcher"): GNOME Shell's app grid, a page `w` by `h − 32` under the
  bar, `ui_launcher_bg`, painted once in `with_launcher`. Cells
  `ui_app_cell_w` by `ui_app_cell_h` (136×104), in rows from 64, in the
  middle (`launcher_cell`); the 48×48 icon 44 in and 12 down, the name
  under it. Icons are PPMs blitted as they are: no alpha, so
  `tools/mkicon` draws them on the launcher's ground. A press is noted as
  a target (`launcher_target`: Applications −2, the bar −3, the page −4,
  an app its index), and the release acts (`launcher_act`): an app
  starts (`started`, watched as a client), Applications toggles, the
  page closes. While it is shown, or a press on Applications holds the
  pointer (`launcher_busy`), no window gets the pointer, wheel or keys;
  Esc closes it.
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

## The display (`user/lib/proto/display.l0`, `user/sbin/virtio-gpu/virtio-gpu.l0`)

virtio-gpu's 2D mode: the host composes the screen from a list of memory
runs that the driver builds from the layers, so no guest code copies pixels.

- **No blending**, no alpha layers, no shadows. Corners are cut whole pixels
  by shaped layers (`shape ID TL TR BL BR`); the layer beneath shows through.
- **`damage`** is a transfer and a flush of rectangles; batch them into one
  request (`ui_present` does).
- **A restack** (`layers`) rebuilds the backing. The driver keeps every
  screen row and rebuilds only the rows of layers that moved, scrolled or
  changed buffer (`rows_restacked`, `dirty_rows`); a change of layer order
  rebuilds them all; rows alike (`Stripe`) share who shows along them. With
  two windows a drag's restack takes about 9 ms on QEMU: 5 building the
  changed rows, 3 on the run list and the attach (one backing, replaced
  whole), 1 showing. More layers make every restack dearer: think twice before adding one
  per window.
- **Scrolling** is a ring: a client can change its window's `top` row
  instead of copying, but only one with no header bar of its own, which
  would scroll too: `vt`, client-decorated, copies its rows with
  `canvas_copy_rows`, once a batch of output.
- **The cursor** is the device's own, 64×64, moved without touching the
  screen; a new image is a `cursor` request again, a few commands.
- **The 64-region limit** (`l0s-dev`): at most 64 open at once. `wm`
  opens one region a window, its chrome's, closed with `ui_buffer_free`
  when it closes, and keeps four of its own: desktop, pointer, top bar,
  launcher. A buffer remade, as for a resize past its room, frees the old
  one the same way.
- **`buffer ID W H VA N S`** gives a buffer N pages, more than W×H may
  take, its rows S pixels apart (`Buffer`'s stride; 2D `layer_runs`
  addresses rows by it, GL makes the texture S wide), and the driver takes
  their addresses with one `dma_addresses` call; the same pages may be
  another ID at another size, and `forget` unmaps them only with the
  last. A width change with the same S keeps every row in place, which a
  stride equal to the width did not: that tore width drags in 2D mode.
- **3D mode** (`user/sbin/virtio-gpu/gl.l0`, `compose.l0`, `virgl.l0`): on
  QEMU's `virtio-gpu-gl-device` the driver makes each buffer a texture and
  composes the screen with virgl copies (`make demo` does when
  `tools/qemu-gl` says gl; `GPU=2d` doesn't). The host's texture is
  updated **only by `damage`**: whatever a client or `wm` paints after
  giving a buffer must be damaged, or GL mode shows the old pixels while
  2D mode, which reads the pages at every restack, hides the omission.
  Same look, same protocol; only copies, no blending.
- **The Pi 5** (`user/sbin/hvs/`, a draft that has run nowhere): the
  same protocol served by the HVS's planes, each layer a plane fetched
  from the client's pages through the IOMMU, so `damage` is only a cache
  clean there. What every display driver reads from requests alike
  (`Layer`, `Corners`, `scale_of`, `info_reply`) is
  `user/lib/proto/display_server.l0`. A screen is at most 16 planes, so
  another layer per window costs more there than in 2D mode. A rounded
  layer is a plane with pixel alpha: every pixel a region canvas writes
  is opaque, 0xff in its fourth byte (`render.l0`'s `canvas_opaque`;
  `put_argb` alone keeps an alpha, for the pointer), and `hvs` writes
  that byte 0 in the pixels `corner_cut` cuts (`hvs/corners.l0`).
- **No GPU drawing.** The GPU only composes (2D mode: the host; 3D mode:
  copies). Every pixel is the guest's.

## Scale (`face.l0`, `spec/desktop.md`'s "A large screen")

On a screen of 2560×1440 or more (or boot argument `scale=2`), `info`
says scale 2. Layout is in the desktop's pixels, half the screen's each
way; buffers and painting are in the screen's.

- **Logical everywhere above the canvas**: theme sizes, `UiNode`s, hit
  tests, `wm`'s geometry, the wm protocol's sizes, damage, top rows and
  pointer, `draw`'s coordinates. Never multiply by the scale in a layout.
- **Where the scale is applied**: `ui_paint` (ops and clip ×s, rounds at
  radius ×s, text and icons from the face); `ui_buffer_at w h s`; `display.l0`
  (places, rectangles, top rows, radii and moves ×s; a buffer's W H are its
  own pixels); `draw_cmd.l0`'s `ui_draw_*` (render.l0's shapes, s thick);
  `vt` (cells ×s, its rows copied ×s); the launcher's `icon2x.ppm`.
- **The face**, a `UiFace`: scale, the icons of `/etc/icons` at the
  sizes the scale paints (`icon.NAME.N`, N = 16·k·s, `ui_icon_sizes`;
  coverage 0–15, 16 levels a word), and the text's strikes, asked of the
  font service `font` (`user/sbin/font`, `proto/font.l0`):
  `glyph.regular.H` and `glyph.bold.H`, H = 16·text scale·s (16, 32, 64),
  each a `UiStrike` over the pages `font` shares, read in place, each
  glyph its ink's box (`format/strike.l0`). Only `wm` adds `/etc/face`'s
  `cursor` tables, at scale 2 (`ui_face_pointers`). A pixel is mixed with
  what is under it by its level (`ui_cov_put`); a missing strike or icon
  is not drawn (`ui_face_has_text`, and a window that cannot say so does
  not open). A boot that starts `wm` starts `/sbin/font` before it.
  Host tests make one with `ui_face_none` (no tables) or `(UiFace s
  tables strikes)` with their own (`paint_test.l0`'s `box_face`, and
  `face1_glyphs`, a strike as bytes, `UiStrikeBytes`).
- **Bold at 2** is the bold face, not a double strike; widths are still the
  logical `ui_text_w`.
- **A new icon** is GNOME's SVG of it copied unchanged into
  `icons/adwaita/symbolic/NAME-symbolic.svg` (listed in that `SOURCE`), or
  another GNOME project's `icons/PROJECT/symbolic/` with its license, and
  NAME added to `ui_icon_names`. `make icon-sheet` shows it at every
  size. If the SVG library refuses it, it names what it cannot draw.
