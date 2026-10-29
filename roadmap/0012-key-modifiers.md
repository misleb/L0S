# 0012: Modifier state in `KeyEvent`

Track: Desktop · Status: active · Needs: – · Spec: desktop.md, toolkit.md, programs.md, testing.md

## Why

`KeyEvent` has no modifiers, so there is no Shift-Tab, and Files has no
Ctrl-C, Ctrl-V or Alt-Left ([desktop.md, Limits](../spec/desktop.md#limits)),
nor Terminal any shortcut. The toolkit README listed it outside the
display layer.

The key path today: each keyboard driver (`virtio-input keyboard`, and
`usb-hid`, which serves the USB keyboard and mouse in one process)
keeps the modifiers held as `keymap.l0`'s bits and sends each key as
the notice `"key"` and three u32s, the code, pressed or released or
repeated, and the character, with Shift, Caps Lock and Ctrl already
applied (Ctrl with a letter is its control character, so Terminal
already sends Ctrl-C as 3). `wm` passes the notice's bytes on as they
came, after the window notice's `"win"` and id; the toolkit and `vt`
read it in place with `key_event_at`. So the modifiers go as a fourth
u32 at the notice's end: every field keeps its offset, `wm` keeps
passing the bytes on untouched, and the readers take one word more.

## Done when

- `KeyEvent` carries Shift, Ctrl and Alt, from both keyboards: a fourth
  field of bits, as they were held when the key went down or up, sent
  as the key notice's fourth u32. `tests/keyboard.sh` (virtio) and
  `tests/usb.sh` (the USB keyboard) see `keys` echo Ctrl and Alt with a
  key.
- Shift-Tab moves the focus back, round to the last; `tests/widgets.sh`
  sees the focus ring go forward with Tab and back with Shift-Tab.
- Files goes Back and Forward on Alt-Left and Alt-Right; Terminal opens
  a tab on Ctrl-Shift-T and scrolls back a page on Shift-Page Up and
  forward on Shift-Page Down. Files' Ctrl-C and Ctrl-V, which need a
  copy Files does not have, are a goal of their own (0036).
- `make check`, `make test` and `make e2e` pass.

## Steps

- [x] The modifiers in `KeyEvent`: a fourth field, `key_mod_shift`,
  `key_mod_ctrl` and `key_mod_alt` bits, sent as the notice's fourth
  u32; `keymap.l0` keeps Alt held too and makes the event
  (`keymap_event`), which both drivers send; every reader takes the
  field; `keys` echoes a key with Ctrl as `^X` and with Alt as `M-x`.
  Host tests in `l0s_test`, `keymap_test`, `keys_test`; `keyboard.sh`
  and `usb.sh` type Ctrl and Alt.
- [ ] Shift-Tab: `ui_route` moves the focus to the target before it
  (`ui_focus_prev`), round to the last. Host tests in `widget_test` and
  `window_test`; `widgets.sh` checks the ring.
- [ ] Files' Alt-Left and Alt-Right, Back and Forward, through the
  toolkit's `ui_key_mods`; Ctrl-C and Ctrl-V written as goal 0036.
  Host tests in `files_test`.
- [ ] Terminal's shortcuts: Ctrl-Shift-T a new tab, Shift-Page Up and
  Shift-Page Down a page of the scrollback. Host tests in `vt_test`;
  `vt.sh` opens a tab with Ctrl-Shift-T.

## Spec changes

- desktop.md: Files' limit loses its "no modifiers" sentence, keeping
  that it has no copy; Terminal's limit loses its, and says its
  shortcuts.
- toolkit.md: Shift-Tab, and `ui_key_mods`.
- programs.md: Files' and Terminal's keys.
- testing.md: what `widgets.sh` and `vt.sh` check.

## Log

- 2026-10-26: written from the toolkit README and desktop.md's Limits.
- 2026-10-28: steps written; the modifiers go as a fourth u32 at the
  key notice's end, so `wm` passes it on unchanged and no field moves.
- 2026-10-28: step 1: `KeyEvent`'s fourth field, from `keymap_event` in
  both drivers; `keys` echoes `^K` and `M-x`, which `keyboard.sh` and
  `usb.sh` type on each keyboard. An entry types nothing with Alt held.
