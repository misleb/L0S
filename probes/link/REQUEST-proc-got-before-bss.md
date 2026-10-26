# Feature request: place `.got` in proc images' data, before `.bss`, so `.bss` stays out of the file

Status: open
Project: L0S, a microkernel in L0, whose 41 programs are `--target proc`
images in its initramfs

`proc-aarch64/layout.ld` names `.text`, `.rodata`, `.data` and `.bss`,
but not `.got`. Linked by the host's `ld.lld` 23 (LLD 23.1.3, as
`L0_VIRT_LD` names it on a machine with no Docker), the orphan `.got`
goes after `.bss`, in the same `PT_LOAD`. Then `.bss` can't be NOBITS at
the end of the file, so its zeros are written into the image:

```
$ readelf -SW build/bin/hello.img
  [ 3] .data   PROGBITS  00000000c0011000 012000 000008  WA
  [ 4] .bss    NOBITS    00000000c0011010 012008 0322d0  WA
  [ 5] .got    PROGBITS  00000000c00432e0 0442e0 000028  WA
$ readelf -lW build/bin/hello.img
  LOAD  0x012000 0xc0011000 ... FileSiz 0x032308 MemSiz 0x032308 RW
```

`hello` is 287,584 bytes, of which 205,520 are `.bss`'s zeros; the
Docker image's `lld-18` gave about 85 KB. Every program carries the same
200 KB or so, about 8 MB across L0S's initramfs. L0S's own tests that
measured a copied program's size, or filled a 14 MB volume with the
programs, failed until they were made not to depend on it.

## A correctness problem too

The script sets `__image_end = .` after `.bss`, before the orphan
`.got`, and `__heap_start = ALIGN(__image_end, 4096)`. Here `.got` is
`0xc00432e0` to `0xc0043308` and the heap starts at `0xc0044000`, past
it, but only because `.bss` did not end on a page. A program whose
`.bss` ended on a page boundary would start its heap on `.got`'s page,
at `.got` itself.

## Smallest change that would help

Name `.got` in the data segment, before `.bss`, and keep `__image_end`
after everything loaded:

```
  .data : { *(.data*) *(.sdata*) *(.got) *(.got.plt) } :data
  .bss : { *(.sbss*) *(.bss*) *(COMMON) } :data
  __image_end = .;
```

the same in `proc-riscv64`'s layout, and an `ASSERT` that no
allocated section lies past `__image_end` would catch the next orphan.
`virt-*` and `pi5-aarch64` layouts may want the same check.

## Which deliberate restriction this breaks

None: the segments, their permissions and the addresses section 10.3
fixes stay as they are.
