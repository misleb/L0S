# Feature request: PCIe interrupts on the virt board, INTx and then MSI

Status: landed, as newlang roadmap 0106 (1586fc8)
Project: L0S, a microkernel in L0 for QEMU's virt board, heading for the
Raspberry Pi 5

> **Since landing:** `irq_virt_test.l0` passes 6/6 under `l0 test
> --target virt`. The virt aarch64 board gives INTA to INTD as 35 to 38,
> level-sensitive, a function's line its pin turned by its slot as gpex
> swizzles it, and the GICv2m frame's SPIs as 80 to 143, edge-triggered
> once enabled, raised by writing the number to 0x08020040. `xhci` and
> `sdhci` still poll: moving them to `irq_bind` is L0S's to do next.
> Without `-nic none`, QEMU's default virtio-net-pci takes slot 00:01.0,
> which moves the other functions' slots and so their INTx lines. The
> Pi 5 (bcm2712's MIP) and the riscv64 board are unchanged, as asked.

L0S drives two PCIe devices on QEMU's aarch64 virt board, using the
regions roadmap 0101 gave it: `qemu-xhci`, which the demo's USB keyboard
and mouse are on, and `sdhci-pci`, its SD card. Neither can take an
interrupt, because the host gives none for PCIe. So both drivers poll.
`xhci` reads its event ring every millisecond while idle, so `ps` always
shows it `ready` or `sleeping`, never waiting. `sdhci` spins on its
status registers for each command. The virtio drivers, the UART and the
RTC sleep until their interrupt comes in as a message, which `irq_bind`
gives them in the L0S kernel. The PCIe drivers should do the same.

This asks for two things, in the order L0S would use them:

1. **INTx:** on the virt aarch64 board, the PCIe host bridge's four
   legacy lines, the GIC's 35 to 38
2. **MSI:** on the same board, the GICv2m frame's 64 SPIs, the GIC's 80
   to 143, which the host already drives and keeps from being a region

## What could not be written

`probes/usb/irq_virt_test.l0` enables each of them. On the board
(`l0 test --target virt probes/usb/irq_virt_test.l0`), all six get -3:

```
not ok 1 - test_intx_a
  # not ok INTA
  #   got:  -3
  #   want: 0
...
not ok 5 - test_msi_first
  # not ok MSI 80
  #   got:  -3
  #   want: 0
not ok 6 - test_msi_last
  # not ok MSI 143
  #   got:  -3
  #   want: 0
# 0 passed, 6 failed
```

Section 10.3 says why. The virt board's host gives 0, 33, 34, 39 and 48
to 79, and of PCIe it says that "the devices' interrupts are none of the
board's, and so are no region and no interrupt". So
`(interrupt_enable 36)` is -3, and nothing a kernel can do brings a PCIe
device's interrupt to its `interrupt_wait` or ends a thread's `user_run`
for it.

On the demo's board, `pcie` reads each function's interrupt pin, and its
`virt_intx` swizzles it by slot, as QEMU's `gpex` does:

```
pcie: 00:01.0 1b36:000d class 0x0c0330, irq 36, BAR 0 at 0x10000000, 16.4 kB
pcie: 00:02.0 1b36:0007 class 0x080501, irq 37, BAR 0 at 0x10004000, 256 bytes
```

The xHCI raises INTB, 36, and the SD host controller INTC, 37. With them,
each driver would `irq_bind` its number to its port, as `virtio-input`
does with its transport's, set its device's interrupt enables (the
xHCI's USBCMD.INTE and interrupter 0's IMAN.IE; SDHCI's Normal Interrupt
Signal Enable), and wait on its port for a request or a notice. On a
notice it would read the device's status, clear it, and `irq_ack`.

## The workaround actually used

Polling. `xhci` checks every controller's event ring after each request
and sleeps 1 ms when there is nothing. A keyboard or mouse reports every
1 to 10 ms, so nobody notices the delay. What it costs is a process that
wakes 1,000 times a second for ever, on a board where every other driver
sleeps. `sdhci` polls its Present State and interrupt status registers
around each command, with a 1 ms sleep once a wait has polled a hundred
times. On the Pi 5, a CPU waking for no reason costs real power. These
loops work, so this blocks nothing. It is the last of the demo's
drivers that can't wait for its device.

## Smallest change that would help

**1. INTx.** Four more rows in section 10.3's table of the virt aarch64
board's interrupts:

| Number | Interrupt | The GIC's ID |
| --- | --- | --- |
| 35 to 38 | the PCIe host bridge's INTA to INTD | 35 to 38 |

They are SPIs 3 to 6. QEMU's device tree gives them in the
`pcie@10000000` node's `interrupt-map`, level-sensitive and active high,
so the host leaves them level in `GICD_ICFGR`, as it does the PL011's. A
level interrupt stays pending while the device holds its line. Section
6.14 already says what that means: an interrupt still pending when
`interrupt_done` ends it is taken again. A driver therefore clears its
device's status before it acknowledges, which the L0S kernel's
`irq_ack` already requires.

**2. MSI.** Sixty-four more rows:

| Number | Interrupt | The GIC's ID |
| --- | --- | --- |
| 80 to 143 | the GICv2m frame's MSI SPIs | 80 to 143 |

QEMU's virt board gives its GICv2m frame, at 0x08020000, SPIs 48 to 111,
the GIC's 80 to 143. `MSI_TYPER` at 0x08020008 says so, and the host can
read the range from there rather than fix it. These are edge-triggered:
a device raises one by writing its number to `MSI_SETSPI_NS`,
0x08020040. The frame stays the host's, as 10.3 already says, so no
program maps it. A driver only writes that address and a number into
its device's MSI or MSI-X capability, through the ECAM, which it already
has. Section 10.3 would say which address that is, so that a driver
need not know the frame.

MSI matters because INTx lines are shared. Four lines serve every slot
on the bus: slot 5 raises INTB as slot 1 does. In the L0S kernel an
interrupt is bound to a single port, so two drivers on one line can't
both bind it. With MSI, every device, and every interrupter or queue of
one, gets a number of its own. A third PCIe device on the demo's board
would collide on INTx, and with MSI would not.

## Left out, on purpose

- **The Raspberry Pi 5.** RP1's interrupts, its USB controllers'
  included, reach the GIC-400 through bcm2712's MIP, an MSI-to-SPI
  bridge between PCIe and the GIC that the firmware sets up and Linux's
  `irq-bcm2712-mip` drives. That is a separate request, once L0S boots on
  the Pi, and will need the MIP's SPI range from the device tree.
- **The riscv64 virt board.** Its PCIe INTx lines are the PLIC's
  sources 32 to 35, and it has no GICv2m. L0S does not use PCIe there
  yet, so they can wait, but they would make a matching row.
- **MSI-X tables beyond the first vector, and interrupt affinity.**
  There is one CPU, and one vector per device is enough.

## Which deliberate restriction this breaks

None. Every interrupt still starts disabled, and the host still drives
the GIC and its MSI frame itself, so no program can disable, route or
fake an interrupt behind it. These are more rows in a table the host
already keeps.

## Alternatives considered

- **Only MSI.** MSI alone is enough for `qemu-xhci` and `sdhci-pci`,
  which both have the capability. INTx is still the smallest step that
  lets a driver wait, and it is what a device without MSI falls back on.
- **Polling less often.** A longer sleep in `xhci` costs input latency,
  and still never lets the driver sleep for good.
- **A doorbell from the kernel's timer.** The L0S kernel could wake
  drivers on a tick. That is polling moved into the kernel, and it
  still can't tell a driver that its device has something.
