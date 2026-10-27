# 0012: Modifier state in `KeyEvent`

Track: Desktop · Status: idea · Needs: – · Spec: desktop.md, toolkit.md

## Why

`KeyEvent` has no modifiers, so there is no Shift-Tab, and Files has no
Ctrl-C, Ctrl-V or Alt-Left ([desktop.md, Limits](../spec/desktop.md#limits)).
The toolkit README listed it outside the display layer.

## Done when

- `KeyEvent` carries Shift, Ctrl and Alt, from both keyboards.
- Shift-Tab moves the focus back.

## Steps

To be written.

## Spec changes

- desktop.md: the `KeyEvent` notice's modifiers, and Files' limit loses
  its "no modifiers" sentence.
- toolkit.md: Shift-Tab.

## Log

- 2026-10-26: written from the toolkit README and desktop.md's Limits.
