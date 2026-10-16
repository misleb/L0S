---
description: L0S UI rules, for the toolkit, the compositor, its clients and the display
paths:
  - "user/lib/ui/**"
  - "user/lib/display.l0"
  - "user/lib/wm.l0"
  - "user/wm/**"
  - "user/vt/**"
  - "user/widgets/**"
  - "user/procmon/**"
  - "user/draw/**"
  - "user/virtio-gpu/**"
  - "tests/*.sh"
globs: user/lib/ui/**,user/lib/display.l0,user/lib/wm.l0,user/wm/**,user/vt/**,user/widgets/**,user/procmon/**,user/draw/**,user/virtio-gpu/**,tests/*.sh
alwaysApply: false
---

# L0S UI rules

The `l0s-ui` skill has the detail; load it before changing these files.

- The look is GNOME's HIG and libadwaita's Adwaita. Colors and sizes come
  from `user/lib/ui/theme.l0` only, each new one with a test in
  `theme_test.l0`. There is no alpha: mix with `ui_mix` against the ground.
- Toolkit names are `ui_…`, its types and constructors `Ui…`.
- A widget carries an action name (`"app.refresh"`), never a callback. A
  click acts on release over what was pressed.
- A change to geometry (sizes, offsets, borders, the top bar) changes `wm`'s
  hit test (`hit`, `cut_off`), `wm_test.l0`'s pinned pixels, and the screen
  tests' coordinates, in the same change.
- Every layer makes every restack dearer; batch `damage` into one request.
- Changes here are verified on the screen: `make e2e`, or the one screen test
  that covers them (`tests/vt.sh`, `widgets.sh`, `procmon.sh`,
  `gpu-screen.sh`).
