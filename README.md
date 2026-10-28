# L0S

A microkernel written in L0, for QEMU's aarch64 `virt` board, and the start
of an operating system around it.

- **[The specification](spec/README.md)**: what L0S is today and how it
  works, area by area, each with its limits.
- **[The roadmap](roadmap/INDEX.md)**: the goals in flight, how far along
  each is, and what each waits for.

```bash
make demo                                 # boot to the shell on this terminal, and type at it
make demo-system                          # the same, from build/system.img's System volume, a copy of it
make demo SCREEN=3840x2160                # on a 4K screen, the desktop drawn at scale 2
make demo CPUS=1                          # on a board of one CPU; 4 by default, the kernel and processes passing messages on CPU 0, those computing on the rest
make all                                  # type check, host tests, board tests, end-to-end
make boot ETC=tests/e2e/ipc/etc           # boot every program with that etc, non-interactively
make pi5-card                             # build/pi5-card: the boot partition's files for a Raspberry Pi 5
make pi5-netboot                          # build/pi5-tftp: the same as a TFTP root, to boot a Pi 5 over the network
make pi5-shell                            # as make demo, on the Pi 5: build the TFTP root without hvs (PI5_SHELL_NO), then picocom on /dev/ttyUSB0 to its shell
tools/pi5-boot [--console] [--reboot]      # build that, check dnsmasq serves it, and read the Pi 5's UART while it boots; --reboot types reboot at the running board's shell instead of a power-cycle
make -s doc Q=port_send                   # the libraries' documentation, as l0 doc gives the standard library's
make -s doc Q=sbin/wm/wm                  # a file by the end of its path; names and searches reach the programs too
```

Start with [the interactive demo](spec/demo.md); the tests are in
[spec/testing.md](spec/testing.md).

Agents working on L0S: see [AGENTS.md](AGENTS.md), the skills in [.claude/skills](.claude/skills) and
the rules in [.claude/rules](.claude/rules).

Requirements:
- `l0`, and Docker running. Board images are linked in l0's container.
- `qemu-system-aarch64`.
- `bsdtar`, which writes the archive. It comes with macOS.
