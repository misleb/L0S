# Feature request: slicing and joining bytes

Status: answered. L0 added both (spec 6.6, newlang 97e1c54, roadmap
0107), and L0S uses them at each place in the table below, which records
what it was. `want.l0` checks against L0S's helpers
(`l0 check common/abi.l0 common/text.l0 probes/bytes/want.l0`). Two
kinds of list remain: device memory, which is read a byte at a time
(a disk's buffer and a received frame, `get_bytes`), and TCP's data,
which its reassembly holds as lists, so `tcp_notify` converts it once.
Project: L0S, a microkernel in L0 for QEMU's virt board, heading for the
Raspberry Pi 5

L0S keeps data that arrives or leaves as bytes as `bytes`: messages,
files, frames, sectors, program images. It reads them in place with
`bytes_get`, and sends them as a range, since `supervisor_send`,
`space_write`, `write_bytes` and `proc_copy_in` all take one. Every
message a process receives is now its `supervisor_receive` bytes,
unchanged. Keys, the pointer, interrupts, exits, frames and file writes
are read from there without a list.

Some data can't stay bytes, though. A spec 6.6 `bytes` value can only
be made by `bytes_from_list`, or come from a read or a receive. No
builtin gives part of one, or two of them as one. So wherever a header
and a body must become one value, the body goes through a list, a cons
cell a byte, and back.

This asks for two builtins:

1. **`(bytes_slice b i j)`**: the bytes of `b` from `i` up to `j`, as
   bytes, under the same bounds rule as `write_bytes`.
2. **`(bytes_concat bs)`**: the bytes of each value in the list `bs`, in
   order, as one. A builder would do as well.

## What could not be written

`want.l0` beside this file is the code L0S would write with them. `l0
check` rejects it today, because neither builtin exists. These are the
places that still go through a list, and how much each copies:

| Where | What is joined | How big |
|---|---|---|
| `user/lib/sys/l0s.l0` `spawn_image_bytes` | path and arguments in front of a program image | the whole image, hundreds of KB |
| `kernel/kernel.l0` `write_remote` | `write H ` and the reply port in front of a write's data, to the file server | up to 4 KB, each write |
| `kernel/kernel.l0` `write_tty` | the reply port and `w` in front of a process's output, to its terminal | up to 4 KB, each write |
| `user/sbin/fs/fs.l0` `read_on` / `fs_reply_bytes` | the reply's word in front of the file's bytes, from the cluster it holds as `bytes` | up to 4 KB, each read |
| `user/sbin/fs/fs.l0` `ram_sectors` / `store_spliced` | a RAM volume's sectors into a cluster, and a write's piece into its sectors | a cluster, each read or write |
| `user/sbin/inet/inet.l0` `udp_in`, `tcpstack.l0` `tcp_notify` | a datagram's or segment's text header in front of its data, to a client | up to 1.5 KB, each packet |
| `user/sbin/virtio-net`, `user/sbin/gem` | `frm` in front of a frame received, to `inet` | up to 1.5 KB, each frame |
| `user/lib/format/l0fs.l0` `vol_load_in`, and `fs`'s `load_dirs` | a directory's clusters, padded, as one | a directory, each mount |

On the host, joining a 6-byte header to a 512 KB image the only way L0
allows takes 4.4 to 4.9 ms (`bytes_to_list`, `append`,
`bytes_from_list`). It also builds half a million cons cells on the way.
The L0S kernel and its processes run under QEMU's TCG, where it costs
more, and every spawn from a volume pays it.

## The workaround actually used

Everything that can avoid a join does:

- The value is read where it is, with (bytes, start, end) passed in
  place of a slice: `udp_of`, `tcp_of`, `icmp_of`, `decode_args_in`,
  `bytes_is_at`, the `msg_` accessors.
- What goes out is sent as a range, with `port_send_bytes`,
  `port_forward`, `put_bytes_range` and `disk_put_range`. A header and a
  body that go to a device go as two copies into its buffer, as
  `virtio-net` and `fs` now do.

The table above is what is left: places where one message, or one
value, has to hold both.

## Smallest change that would help

`bytes_slice` alone would remove the lists from reading. With it, a
received message could be split without copying it into a list, and
nothing would be built a byte at a time to throw away. `bytes_concat`
would remove the rest. Both copy `j - i`, or the sum of the lengths,
bytes once into a new value, which is what any join costs.

## Which deliberate restriction this breaks

None. Bytes stay immutable: both builtins make a new value, as
`bytes_from_list` does.
