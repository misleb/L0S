# 0015: Proc images without `.bss`'s zeros

Track: Tooling · Status: blocked · Needs: [REQUEST-proc-got-before-bss](../probes/link/REQUEST-proc-got-before-bss.md) · Spec: kernel.md, boot.md

## Why

The proc linker script doesn't name `.got`, so a host `ld.lld` puts it
after `.bss` and writes `.bss`'s zeros into every image: about 200 KB a
program, 8 MB across the initramfs. And a `.bss` ending on a page would
start the heap on `.got`. The request to L0 is still open.

## Done when

- L0 lands the request, and L0S's images carry no `.bss` zeros.

## Steps

- [ ] L0 places `.got` before `.bss` (the request).
- [ ] Rebuild, and check the images' sizes and the initramfs's.

## Spec changes

- None expected beyond sizes quoted in the spec, if any change.

## Log

- 2026-10-26: written from probes/link's open request.
