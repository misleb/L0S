# 0009: Alpha layers: shadows and smooth corners

Track: Display · Status: idea · Needs: – · Spec: display.md, desktop.md

## Why

No layer blends on virtio-gpu, so window corners are cut in whole pixels
and windows have no shadows ([toolkit.md, Limits](../spec/toolkit.md#limits)).
The toolkit's former "Later" list, item 4: alpha layers, small strips
composed by the driver. `hvs` already rounds the Pi 5's corners with
pixel alpha.

## Done when

- On QEMU, windows have Adwaita's shadows and antialiased corners.

## Steps

To be written.

## Spec changes

- display.md: how alpha strips are composed.
- toolkit.md and desktop.md: the "no shadows" and square-pixel corner
  limits go.

## Log

- 2026-10-26: written from the toolkit README's "Later" list.
