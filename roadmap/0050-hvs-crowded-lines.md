# 0050: `hvs` at 4K: lines crowded with planes still shown

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

## Done when

To be written: at least, the screen with five big windows overlapping
at 4K, any one dragged anywhere, shows no black lines, on the Pi 5.

## Steps

To be written from a board run that finds what a line can fetch:
planes and bytes a line, against where the black begins.

## Log

- 2026-10-29: written from 0038's step 6 board run.
