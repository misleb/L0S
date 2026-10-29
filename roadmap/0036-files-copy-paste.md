# 0036: Files copies, cuts and pastes

Track: Desktop · Status: idea · Needs: – · Spec: desktop.md, programs.md

## Why

Files works on one thing at a time and does not copy: there is no cut,
copy or paste, so no Ctrl-X, Ctrl-C or Ctrl-V
([desktop.md, Limits](../spec/desktop.md#limits)). Since 0012 the keys
carry Ctrl, so only the copy itself is missing: Files would keep what
was copied or cut, and copy a file's data, or a folder's whole tree,
from one place to another, on one volume or across two, as `sh`'s `cp`
does for one file, without holding its window still while it does
(the toolkit's idle work, 0033's).

## Done when

- Ctrl-C and Ctrl-X keep the selection, and Ctrl-V copies it into the
  place shown, or moves it there, with the menu's Copy, Cut and Paste
  doing the same.
- A copy of a large file, or of a folder, leaves the window answering,
  and says how far it has gone.

## Steps

To be written.

## Spec changes

- desktop.md: Files' limit loses "no cut, copy or paste".
- programs.md: Files' row, its copying.

## Log

- 2026-10-28: written from 0012, whose modifiers it needs no more than
  the keys already give.
