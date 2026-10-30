# The L0S specification

What L0S is today and how it works. This is a description of what exists
and runs, never of what is planned: plans are goals in the
[roadmap](../roadmap/INDEX.md), and a goal that lands changes these pages
in the same change.

## What L0S is

A microkernel written in L0, for QEMU's aarch64 `virt` board, and the start
of an operating system around it.

The kernel is an ordinary L0 program built with `--target virt`, with a
heap of 192 MB and a stack of 16 MB (the Makefile's `KERNEL_HEAP_MB` and
`KERNEL_STACK_MB`) in place of L0's 1,024 and 256, so that the rest of the
board's RAM, about 1,840 MB at `-m 2G`, is the frames processes are made
of. It runs at EL1 and runs processes at EL0, each in its own address space. It boots from
an **initramfs**: a cpio archive, in the same newc format as Linux's, of the
programs it can run and the files they can read. An `/etc/inittab` inside
says what starts at boot. L0S can also be copied onto a volume of the disk,
and booted from it: given `root=UUID`, its first process makes that volume
`/`, the **system volume**, and the kernel gives the initramfs up (see
[Booting from a volume](boot.md#booting-from-a-volume)).

A process is any L0 program built with `--target proc`, so it runs
unchanged, and can read the initramfs's files with the ordinary `open_in`.
Processes talk through ports. Device drivers are processes too: the kernel
maps a device's registers into a driver and passes its interrupts on as
messages.

## The pages

Each page ends with its own **Limits**: what L0S does not do yet, or does
only so far. A goal that lifts a limit links to it.

| Page | What it covers |
|---|---|
| [demo.md](demo.md) | The interactive demo: the pid table, who talks to whom, the shell and its commands, driving L0S from an agent, terminals |
| [desktop.md](desktop.md) | The compositor `wm`: buffers and layers, the compositor protocol, the top bar, the L0S menu, the launcher, frames, input; a large screen at scale 2 |
| [toolkit.md](toolkit.md) | The toolkit in `user/lib/ui`: its files, the Elm-style loop, scrolling, entries, the HIG as encoded |
| [display.md](display.md) | The display protocol, `virtio-gpu`'s 2D and 3D modes, shaped layers and batched damage, `hvs` on the Raspberry Pi 5 |
| [sound.md](sound.md) | Sound on the Pi 5's HDMI0, the audio protocol |
| [storage.md](storage.md) | Disks and their drivers, partitions, volumes and L0FS, `fs` |
| [fat32.md](fat32.md) | FAT32 volumes |
| [network.md](network.md) | The network card drivers, `inet`: IPv4, UDP, TCP, DHCP, DNS; the Pi 5's Ethernet |
| [devices.md](devices.md) | Randomness, USB and PCIe |
| [boot.md](boot.md) | How it boots, app bundles, booting from a volume |
| [pi5.md](pi5.md) | L0S on the Raspberry Pi 5: the card, netboot, what runs there |
| [kernel.md](kernel.md) | The kernel's loop and scheduling, its log, processes and pids, a process's memory |
| [syscalls.md](syscalls.md) | The system calls: the process ABI and the kernel's own calls |
| [agent.md](agent.md) | `agentd`, the agent: its conversation and prompt caching, its loop |
| [programs.md](programs.md) | Every program and library, where it lives and what it holds |
| [testing.md](testing.md) | The tests: what each `make` target runs, the e2e cases, the screen tests |

## Keeping it true

A change that makes any of this false fixes the page in the same change:
the tables of programs, libraries, protocols, system calls, the demo's
pids, tests, and limits most of all.
