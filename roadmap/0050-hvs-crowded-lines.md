# 0050: `hvs` at 4K: crowded lines and a whole-screen flash

Track: Display · Status: idea · Needs: 0038 · Spec: display.md

## Why

Seen on a Pi 5 at 3840×2160, scale 2, in roadmap 0038's step 6 run:
with a few big windows open and System Monitor dragged off the screen's
bottom edge, a black band showed where it overlapped the others, and
moved with it as it was dragged up and down. The background, set to a
color for the run, did not show there, so those were not pieces left
out for the line memory: the HVS fetched too little of those lines in
time, as display.md's Limits saw before, at 4K with more than five
windows, when frames were fetched whole.

A plane is fetched across every line it covers, hidden or not, so where
several big windows overlap, each line fetches all of them.

Also seen in 0038's step 7 runs, with a few big windows open, moved and
resized: now and then the whole screen below the top bar shows the
HVS's background for a frame. No list left pieces out then, and
HANDLE_ERROR was 0; STATUS's EMPTY bit and the fetcher, fetch and list
status words change every frame, so none of them marks it, and moving
the window off the bottom edge sometimes stopped it. Whether it is the
HVS falling behind a whole frame, or a list taken before it is all
written, is not known.

## Done when

To be written: at least, the screen with five big windows overlapping
at 4K, any one dragged anywhere, shows no black lines and no frame of
the background alone, on the Pi 5.

## Steps

To be written from a board run that finds what a line can fetch:
planes and bytes a line, against where the black begins; and one that
tells a whole-screen flash's cause, a list taken half written or the
HVS behind, by what it shows when each is forced.

## Log

- 2026-10-29: written from 0038's step 6 board run.
