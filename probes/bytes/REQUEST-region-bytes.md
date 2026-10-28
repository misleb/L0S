# Feature request: a region's bytes as bytes, and bytes into a region

Status: answered. L0 added `region_read_bytes` and `region_write_bytes`
(spec 6.12), which the library gives a program as `device_read_bytes`
and `device_write_bytes` on an `IoDevice`. L0S uses them through
`l0s.l0`'s `put_bytes_range`, now one copy for every caller (the disk's
buffer, `fs`'s windows, the network drivers' transmit buffers, audio),
and the new `get_bytes_in`: in `fs`'s `window_got` and `store_read`
(through `disk.l0`'s `disk_get_bytes`), Disks' sector reads, and both
network drivers' received frames (`nic.l0`'s `frame_notice_bytes`).
`get_bytes` stays a byte at a time for registers, virtio's
configuration among them, which must be read once each.
Project: L0S, a microkernel in L0 for QEMU's virt board and the
Raspberry Pi 5

L0S moves bulk data between processes through shared pages: a disk's
sectors through a buffer the file server shares with the disk's driver
(`user/lib/proto/disk.l0`'s `DiskBuf`), and now a file's data through a
window the kernel maps into the file server for each client (roadmap
0023, `user/sbin/fs/fs.l0`'s `window_got` and `window_put`). A process
reaches those pages as a region, `dma_open`'s `IoDevice`, and the only
way into or out of one is `device_read8` to `device_read64` and their
writes, one access at a time.

So a region's bytes become `bytes` only through a list: `get_bytes`, a
`device_read8` and a cons cell a byte, then `bytes_from_list`. And
`bytes` go into a region a `device_write8` at a time
(`put_bytes_range`). The kernel itself has `space_read` and
`space_write`, which copy a range at once; a process has nothing alike.

This asks for two builtins, or a library function that does no worse:

1. **`(region_read_bytes d off n)`**: the n bytes of region d from off,
   as bytes, under the bounds rule of `device_read8`.
2. **`(region_write_bytes d off b i j)`**: the bytes of b from i up to
   j written into d from off, as `write_bytes` takes a range.

Neither needs to be one access of a width, as a device register's read
must be: they are for ordinary memory shared or allocated for DMA, which
a region over DMA pages already is.

## Where L0S would use them

| Where | What | How big |
|---|---|---|
| `user/sbin/fs/fs.l0` `window_got` | a client's write, from its window | up to 64 KB, each write |
| `user/sbin/fs/fs.l0` `window_put` | a read's bytes, into the client's window | up to 64 KB, each read |
| `user/sbin/fs/fs.l0` `store_read`, `disk.l0` `disk_get` | sectors read, from the disk's buffer | up to 32 KB, each disk read |
| `user/sbin/fs/fs.l0` `store_write`, `disk.l0` `disk_put_range` | sectors to write, into the disk's buffer | up to 32 KB, each disk write |
| `user/sbin/virtio-net`, `user/sbin/gem` | a frame received, from its DMA buffer | up to 1.5 KB, each frame |

## The workaround used

`get_bytes` and `bytes_from_list` to read, `put_bytes_range` to write.
For a 64 KB write that is 65,536 calls and as many cons cells, which
the window was meant to save the file server, as it saved the kernel
the messages.
