# 0070: Screenshots as GNOME takes them

Track: Desktop · Status: idea · Needs: – · Spec: desktop.md, display.md, programs.md, testing.md

## Why

The status menu's screenshot button freezes the screen, an area is
dragged out on it with the pointer, and `snip` saves it as a PNG under
`/Volumes/data/user` ([desktop.md](../spec/desktop.md#screenshots),
its Limits). That is one of the three things GNOME's screenshot tool
does, and less of it:

- There is no screen mode and no window mode, and no Print Screen key
  to start one (`wm` would grab it, as `speech` grabs F12).
- Outside the area is not dimmed: no layer blends (0009), so it would
  be a second copy of the frozen screen, darkened, kept beside the
  first.
- The area cannot be moved or resized by handles once the button is up,
  and the release takes it at once, with no button to confirm.
- Nothing says it was saved but the log's line: there is no notice, and
  no notices at all yet.
- `snip` captures the screen again as it is a moment after the release,
  not the frozen pixels `wm` holds, which differ where something drew
  meanwhile.
- `hvs` serves no `capture`, so on the Pi 5 the button does nothing.
- The demo's `/Volumes/data` is 744 KB, a few full screens at most.

## Done when

- To be written.

## Steps

None yet: an `idea` until Done when is written.

## Spec changes

To be written with the steps.

## Log

- 2026-11-06: written, as the status menu's first screenshots landed:
  what they leave out of GNOME's.
