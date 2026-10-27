# 0005: The HVS's end-of-frame interrupts

Track: Display · Status: idea · Needs: – · Spec: display.md

## Why

`hvs` doesn't take the HVS's end-of-frame interrupts
([display.md](../spec/display.md#the-display-on-the-raspberry-pi-5),
"Not yet"), so it can't change the display list between frames or tell
clients when a frame has been shown.

## Done when

- `hvs` takes the end-of-frame interrupt, and changes the display list
  only between frames.

## Steps

To be written.

## Spec changes

- display.md: the "Not yet" line goes, and the Pi 5 section says how a
  frame is paced.

## Log

- 2026-10-26: written from display.md.
