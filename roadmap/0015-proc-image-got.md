# 0015: Proc images without `.bss`'s zeros

Track: Tooling · Status: done · Needs: [REQUEST-proc-got-before-bss](../probes/link/REQUEST-proc-got-before-bss.md) · Spec: kernel.md, boot.md

## Why

The proc linker script doesn't name `.got`, so a host `ld.lld` puts it
after `.bss` and writes `.bss`'s zeros into every image: about 200 KB a
program, 8 MB across the initramfs. And a `.bss` ending on a page would
start the heap on `.got`.

## Done when

- L0 lands the request, and L0S's images carry no `.bss` zeros.

## Steps

- [x] L0 places `.got` before `.bss` (the request).
- [x] Rebuild, and check the images' sizes and the initramfs's.

## Spec changes

- None: the spec quotes no image's size.

## Log

- 2026-10-26: written from probes/link's open request.
- 2026-10-26: L0 landed it (cd59cf3): every layout names `.got` in
  `.data`, and L0's suite refuses a proc image with a section loaded past
  the bss. Rebuilt: `hello.img` is 90,640 bytes (was 287,584), its data
  segment 0x30 in the file and 0x32318 in memory; none of the 43 images
  loads a section after `.bss`, and they total 12.5 MB. `make check` and
  `make test` (2558 passed) pass.
