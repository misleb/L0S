# 0026: The font service lets strikes go, and knows who holds them

Track: Toolkit · Status: idea · Needs: – · Spec: programs.md, toolkit.md

## Why

Goal [0019](0019-font-service.md) left `font` simple, and these are its
limits ([programs.md](../spec/programs.md), `font`'s row):

- A strike is kept for as long as `font` runs, never freed, so a
  program that asks for many heights grows `font` for good, up to its
  device pages; heights are bounded (8 to 128), faces are four, so the
  worst is 484 strikes, some 9 MB.
- `stats` counts the processes a strike was given to, the dead too:
  nothing tells `font` a client exited, and the kernel takes the
  mappings back by itself.
- Every program with a window holds four of its 64 regions open for the
  strikes it draws from, `wm` among them, which also opens two per
  window.
- `font` is one process answering one request at a time: a strike it
  must make (0.2 to 1.2 s on QEMU) holds up every other client's ask
  behind it, even for one already made.

## Done when

- To be written: when `font` lets an unused strike go (no live holder,
  and not one of the stored ones), how it learns a holder exited
  (`exit_notice`, as `fs` watches its clients), and whether a program
  reads its strikes through one region, the pages of all of them
  shared as one run.

## Steps

## Spec changes

## Log

- 2026-10-27: written from 0019's limits.
