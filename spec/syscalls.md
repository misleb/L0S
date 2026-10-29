# System calls

`x8` holds the call number, `x0`–`x3` the arguments, and the result comes
back in `x0`. From L0, use the wrappers in `user/lib/sys/l0s.l0`.

## Calls 1–13: the process ABI of spec §10.3

The kernel answers these itself for the initramfs, a read-only file
system, and for a file of a volume under `/Volumes`, or of the system
volume once `/` is one, sends them to the volume's file server, as
[Volumes](storage.md#volumes) says, its answer the call's:

| Call | What the kernel does |
|---|---|
| open | modes 1 to 3, else -5. In the initramfs, to read: a new stream (3 and up), or -3 no such file, -8 a directory, -5 if the process has 16 open. To write: -8 a directory, -4 where the directory exists, -9 where it does not. In a volume: a new stream, once its server opens the file; -5 if the process's first file window to that server cannot be made (see [File windows](kernel.md#a-processs-memory)). A relative path is taken from the current directory (calls 290, 291), `/` to begin with, and its `.` and `..` taken out; one over 1024 bytes once made absolute is -5 |
| read | stream 0 reads a line from the process's terminal, if it has one (see Terminals), and otherwise the inittab's `stdin` file, with one cursor for everyone, until the initramfs is given up. Other streams read the file opened on them, from where the process left off, 0 at the end; a volume's at most 64 KB a call, through the process's file window to its server, or 4092 bytes, in the reply, with none; one of the initramfs's, once it is given up, reads as at its end |
| close | 0, or -5 for a stream that isn't open; a volume's file is closed by its server too |
| rename, remove | in the initramfs, -3 if there's no such file; otherwise -4 (-8 to remove a directory). In a volume, as its server says; between two file systems, -10 |
| write | streams 1 and 2 go to the process's terminal, if it has one, at most 4091 bytes per call, waiting while its queue is full; otherwise to the kernel's stdout and stderr, at most 64 KiB per call. A stream open on a volume's file is written by its server, up to 64 KB a call through the process's file window to it, or a message's worth with none; any other is -5 |
| exit | the process ends with that status |
| arg_count, arg | the process's arguments: those it was spawned with by `spawn_entry_with` or `spawn_image`, or else the inittab's `args` for its path |
| region | maps device registers for programs with a `dev` line, so `open_device` works, or for a range of the caller's DMA pages, returns where they are; -3 for any other |
| clock | not answered (-5): only a riscv64 process asks, and an aarch64 one reads the virtual counter itself |
| release | 0. The runtime makes it, never a program: each whole page of the heap in the range that is mapped is unmapped and its frame freed (see [Releasing](kernel.md#a-processs-memory)); part of a page, and anything outside the heap, are passed over |
| unregion | 0. The runtime makes it once a region is closed: the device registers a `region` call mapped there are unmapped, and their pages go back to the process's device pages, to be given again; a later touch of one faults. A region over the caller's own DMA or shared pages mapped nothing, and nothing of it changes; nor does anything for a range the call never mapped |

## The kernel's own calls, 256 up

An *entry* is an index into the initramfs's entries, numbered from 0.

The kernel answers each call with a word, as the table's Result says. A
wrapper that can fail reads that word as a type of its own, whose
constructors are every answer the call can have, so a `match` on what it
returns must handle each of them: `port_send` gives a `Sending`, one of
`(Sent)`, `(SendNoPort)`, `(SendFull)` and `(SendTooBig)`. Each type has
an `X_of` that reads the word (`sending_of`), and some a `X_why` that
says a failure in words (`sending_why`, `spawn_why`). With no kernel
beneath, as under `l0 test`, every word is -3, which a wrapper reads as
its -3 answer if it has one (`SendFull`, `WatchFull`, `IrqAbsent`) and
otherwise as its type's first failure.

| # | Wrapper | Returns | Result |
|---|---|---|---|
| 256 | `l0s_yield` | `int` | 0, after the others have run |
| 257 | `l0s_pid` | `int` | the caller's pid |
| 258 | `port_new` | `int` | a new port, which only the caller may receive on |
| 259 | `port_send port payload`, `port_send_bytes port b i j`, `port_forward port b` | `Sending`: `Sent`, `SendNoPort`, `SendFull`, `SendTooBig` | 0, or -1 no such port, -3 its queue (32) is full, -4 over 4096 bytes. A list, a range of bytes sent in place, or a message received passed on as it came |
| 260 | `port_receive port` | `Message`: `Message`, `RecvFailed` | waits; `(Message sender b)`, where sender 0 is the kernel and `b` the bytes received, the sender's pid and then the payload, which the `msg_` functions read in place and `msg_text` gives as a list |
| 261 | `port_try_receive port` | `Message` | the same, or `(RecvFailed)` at once if no message is waiting |
| 262 | `name_register port name` | `Registration`: `Registered`, `RegisterNoPort`, `RegisterTaken`, `RegisterTooLong` | 0, or -1 not your port, -2 the name is taken, -4 a name over 256 bytes |
| 263 | `name_lookup name` | `Lookup`: `Found`, `NotFound` | a port, or -1 (`name_await` retries with yields, `name_wait` with sleeps) |
| 264 | `spawn_entry e` | `Spawn`: `Spawned`, `SpawnNoEntry`, `SpawnNotProgram`, `SpawnTooBig`, `SpawnNoRoom` | a pid, or -1 no entry e, or the initramfs given up, -6 not a program, or not an ELF the kernel starts, -5 out of address spaces. `spawn_path` starts a program by its path, wherever `/` is |
| 265 | `wait_pid pid` | `Reaped`: `Reaped`, `WaitNoProc` | waits; the pid's exit status, its low 32 bits as a word never negative, which `wait_pid` reads back signed, or -1 for no such process |
| 266 | `sleep_until t`, `sleep_ns n` | `int` | 0, once `clock_ns` reaches t |
| 267 | `irq_bind irq port` | `IrqBinding`: `IrqBound`, `IrqAbsent`, `IrqDenied`, `IrqNoPort`, `IrqTaken` | 0, or -6 no `dev` line for the program, -1 not your port, -2 already bound, -3 no such interrupt on the board. After this, each interrupt sends the message `irq_notice irq` to the port |
| 268 | `irq_ack irq` | `IrqAck`: `IrqAcked`, `IrqNotPending` | 0, ending the interrupt once the driver has quieted its device; -1 if it is not yours or not taken |
| 269 | `entry_path_of e`, `entry_is_program e` | `(list int)`, `bool` | the entry's path, with a final `/` for a directory, or empty if there is no entry e or the initramfs has been given up; the kernel follows a program's with a NUL and `x`. `entry_paths` lists them all, and `program_entry` finds a program by name; `root_paths` lists `/` wherever it is |
| 270 | `proc_kill pid` | `Kill`: `Killed`, `KillNoProc`, `KillDenied` | 0, ending pid with status 130, any process but the caller; -6 if pid's program has a `dev` line, -1 if there is no such process or it is the caller. Ending pid 1 stops the system with status 130 |
| 271 | `proc_watch pid port` | `Watch`: `Watched`, `WatchNoProc`, `WatchFull` | 0, and the kernel sends `exit_notice pid status` to the caller's port when pid exits, or at once if it has. -1 if there is no such pid, or the port is not the caller's; -3 if 32 ports watch pid already. `exit_of` reads the notice |
| 272 | `spawn_entry_with e args` | `Spawn` | as `spawn_entry`, but the process gets args (sent as `encode_args` writes them) in place of the inittab's; -5 if they are not well formed, -4 over 4096 bytes |
| 273 | `proc_info pid`, `proc_path pid` | `(Option ProcInfo)`, `(list int)` | a `ProcInfo`: state (`state_running` … `state_exited`), parent, the program's entry, -1 for one started from an image, a detail (the port or pid it waits on, or an exited process's status), and its pages of memory: its own (its image's data, heap and stack, as far as it has touched them) and those it may share (its image's code and rodata, and at its device pages shared and DMA memory, which other processes may map too), counted without walking its pages: its device pages as they are mapped and unmapped, and its shared code and rodata by the image segments it shares; none if no process has that pid now: none has had it, or its slot has gone to another process (see [Processes and pids](kernel.md#processes-and-pids)). After the record's 24 bytes, as many as there is room for, the program's path, its entry's or its image's, which `proc_path` reads. To list every process, ask `proc_slot` for each slot's pid |
| 274 | `dma_alloc n` | `DmaAlloc`: `DmaPages`, `DmaDenied`, `DmaTooMany`, `DmaNoRoom` | the address of n zeroed pages a device can reach, at the caller's next device pages; -6 no `dev` line, -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 out of frames or device pages. They last until the system stops |
| 275 | `dma_address va` | `DmaWhere`: `DmaAddress`, `DmaAddressDenied`, `NotDma` | where a device reaches the caller's DMA page holding va, page aligned; -1 if no DMA page holds va, -6 no `dev` line |
| 276 | `tty_set port` | `TtyChange`: `TtySet`, `TtyNoPort` | 0, making port, a terminal, the caller's standard input, output and error, and those of every process it starts from then on; 0 gives back the kernel's own; -1 if there is no such port |
| 277 | `tty_get` | `Terminal`: `Terminal`, `KernelTerminal` | the caller's terminal's port, or 0 for the kernel's own |
| 278 | `shm_alloc n` | `ShmAlloc`: `ShmPages`, `ShmNoRoom`, `ShmTooMany` | the address of n zeroed pages to share, at the caller's next device pages, for any process; -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 out of frames or device pages. They are freed once every process that maps them has ended, unless one of those drives devices |
| 279 | `shm_share va n pid` | `ShmShare`: `ShmShared`, `ShmShareNoProc`, `ShmShareTooMany`, `ShmShareFailed` | where pid sees the caller's n shared or DMA pages from va, now mapped into pid's next device pages too, the same frames; -1 no such pid, -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 pages that are not the caller's, or pid out of device pages |
| 280 | `proc_slot i` | `Slot`: `SlotHeld`, `SlotUnused`, `NoSlot` | the pid slot i of the process table holds, live or exited, or last held; 0 if it has held none; -1 for no slot i, outside 1 to 255 |
| 281 | `shm_unmap va n` | `ShmUnmap`: `ShmUnmapped`, `ShmUnmapNotYours`, `ShmUnmapTooMany` | 0, the caller's n shared or DMA pages from va unmapped, each frame freed once no process maps it; -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 pages that are not the caller's, when none is unmapped |
| 282 | `shm_revoke va n pid` | `ShmRevoke`: `ShmRevoked`, `ShmRevokeNoProc`, `ShmRevokeDenied`, `ShmRevokeTooMany`, `ShmRevokeNotYours` | how many mappings pid had of the caller's n shared or DMA pages from va, all now unmapped; -1 no such pid, -6 pid is the caller or drives devices, -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 pages that are not the caller's |
| 283 | `fs_mount label uuid port` | `Mounting`: `Mounted`, `MountNoPort`, `MountTaken`, `MountBadLabel` | 0, the caller's volume label, of the partition whose UUID that is, as text, or none, mounted at `/Volumes/LABEL` from port, whose server is sent every call on a file there (see [Volumes](storage.md#volumes)) until the port goes; -1 not the caller's port, -2 the label is mounted already, -5 no label (1 to 15 letters, digits, `-`, `_`) or a UUID that is none |
| 284 | `mount_at i`, `mount_list` | `(Option MountInfo)` | mount i of the table, from 0, `/`: where it is, the port of its server, 0 for the kernel's own, and its partition's UUID, empty for none; none past the last. `mount_list` gives them all, and `fs_system_volume` the system volume's `/Volumes/LABEL` |
| 285 | `boot_args` | `(list (list int))` | the board's boot arguments, QEMU's `-append`, split at spaces; none under another operating system |
| 286 | `root_switch label` | `Switch`: `Switched`, `SwitchDenied`, `SwitchDone`, `SwitchNoVolume`, `SwitchBadLabel` | 0, the volume mounted as label made `/`, the system volume, for good, and the initramfs's bytes given up (see [Booting from a volume](boot.md#booting-from-a-volume)); -6 if the caller's program is not the initramfs's, -2 if `/` is a volume already, -1 if no such volume is mounted, -5 no label |
| 287 | `spawn_image path args image` | `Spawn` | as `spawn_entry`, but a program started from image, its bytes, named path, which `proc_path`, `ps` and the inittab's `args` know it by; given no args, the inittab's for path. It never drives a device. -6 for no image, or not an ELF the kernel starts, -4 the whole over 64 MB of image with the path and arguments, -5 bytes not laid out as `spawn_image_bytes` lays them |
| 288 | `mem_info` | `(Option MemInfo)` | a `MemInfo`: the pages processes' memory comes from, those given and those L0's `frame_free_count` says are left, about 1,840 MB with `-m 2G` and the kernel's heap of 192 MB and stack of 16 MB, and how many of them are given, each process's own and every shared, DMA or shared code and rodata page once, however many processes map it, each process's counted as `proc_info` counts them, so the call takes as long as there are processes, not pages; none under another operating system. What is not given is free; the kernel's page tables take from it, so the total moves a little |
| 289 | `fs_unmount label port` | `Unmounting`: `Unmounted`, `UnmountNotMounted`, `UnmountDenied`, `UnmountBadLabel` | 0, the volume label, which the caller mounted from port, unmounted: `/Volumes/LABEL` is in no volume from then on, and the label free; -1 if the port is not the caller's or mounted no such volume, -6 for the system volume, which is `/` for good, -5 no label |
| 290 | `chdir path` | `Chdir`: `ChdirDone`, `ChdirNoDir`, `ChdirNotDir`, `ChdirBad` | 0, the directory at path, from the current directory, made the caller's current one, and its children's, as spawn gives them; -3 if there is none, -9 if it is a file, -5 for a path over 1024 bytes or not the caller's to give, or one in a volume whose server has gone. The initramfs's, `/Volumes` and `/` the kernel answers itself; a path in a volume is checked with its server's `stat`, the caller waiting as for any file call |
| 291 | `getcwd`, `path_abs path` | `(list int)` | the current directory, an absolute path with no final `/`, `/` at the start; `path_abs` is a path made absolute from it, unless it starts with `/` already |
| 292 | `dma_addresses va n` | `(array int)` | where a device reaches each of the caller's DMA pages from the one holding va, n at most, a u64 each, up to the first that is not one: fewer than n then, none if va's is not; -6 no `dev` line, which the wrapper gives as none |
| 293 | `dma_sync va n dir` | `DmaSynced n`, `DmaSyncDenied`, `DmaSyncBad` | n of the caller's DMA pages from the one holding va, up to the first that is not one, made to agree between the CPU's caches and memory by L0's `frame_sync`, for a device that does not see the caches, as the Raspberry Pi 5's do not: dir 1 cleans (`dma_to_device`, after writing what it will read), 2 invalidates (`dma_from_device`, before reading what it wrote), 3 both; how many; -5 another dir, -6 no `dev` line |
| 294 | `log_write level text` | `Logging`: `Logged n`, `LogTooLong`, `LogRefused` | puts text, a line, in the kernel's log (see [The kernel's log](kernel.md#the-kernels-log)) as the caller's, at level 0 error, 1 warning, 2 info or 3 debug, stamped with the time and the caller's pid: its number, or -4 for over 512 bytes, -5 for another level or a buffer the caller may not give. A newline in the text is a space, and one at its end is dropped. Any process may. Any level but debug is written to the kernel's standard error too, a line each |
| 295 | `log_read seq`, `log_all` | `(list LogRecord)` | the messages in the log numbered seq or more, as many whole ones as 4096 bytes hold, oldest first, as `klog.l0` lays each out: a u64 number, a u64 time in ns since boot, a u16 pid, a byte of level, a u16 length, then the text. From the oldest kept if seq is older; none past the last. `log_all` reads them all, a read at a time. Any process may |
| 296 | `entry_size_of e` | `int` | how many bytes entry e of the initramfs holds, 0 for a directory, as Files shows its files' sizes; -1 (`err_no_port`) if there is no entry e or the initramfs has been given up, as 269 refuses it. Any process may |
| 297 | `alarm_at port t`, `is_alarm_notice m` | `int` | sends `port`, the caller's, the notice `alarm` from pid 0 when `clock_ns` reaches t, at once if it has; it replaces the port's earlier alarm, so there is at most one for a port. A driver that waits on its port for interrupts uses it to wake to do something on a time, as `gem` rechecks its link; 0, or -1 (`err_no_port`) if the port is not the caller's |
| 298 | `board_restart` | `(list int)`, why not | restarts the board by L0's `board_reset`, after the kernel logs `l0s: restarting the board, as NAME (pid N) asked`, ending every process with no word, as sh's `reboot` and wm's Restart ask. It does not return where the board restarts (the Pi 5, QEMU's aarch64 virt board); elsewhere -6 (`err_denied`), and the kernel logs a warning. Any process may |
| 299 | `shm_share_read va n pid` | `ShmShare`, as `shm_share` | as `shm_share`, but the pages are mapped into pid read only: a write of pid's there faults it, which ends it with status 139, and leaves the pages and their owner as they were. The font service shares its strikes so, that no client can change another's text. Its refusals are `shm_share`'s |
| 300 | `port_set ports` | `PortSetting`: `PortSetMade`, `PortSetNotYours`, `PortSetSize` | the caller's set of ports to wait on, given as a u32 each, in place of any it had: 0, or -1 a port not the caller's, -4 none, more than `port_set_limit` (32), or a length not a whole number of u32s, -5 bytes the caller may not give. Refused before anything changes |
| 301 | `port_receive_set` | `SetMessage`: `SetMessage`, `SetRecvFailed` | waits; `(SetMessage port m)`, the oldest message waiting on any port of the set and the port it came on, `m` as `port_receive` gives it. The kernel writes the sender, the payload and then the port, a u32; -1 the caller has no set, -4 no room for them, the message kept. `port_receive_any ports` is `port_set` and then this |
| 302 | `port_try_receive_set` | `SetMessage` | the same, or `(SetRecvFailed)` at once if no message is waiting (-2) |
| 303 | `name_unregister name` | `Unregistration`: `Unregistered`, `UnregisterNoName`, `UnregisterNotYours` | the name let go, free at once for `name_register`, and `name_lookup` no longer finds it: 0, or -1 no port holds it, -6 its port is not the caller's, -5 or -4 a name the caller may not give or over 256 bytes |

Listening to a driver, `keyboard_listen`, `pointer_listen` and
`input_listen`, gives a `Listen`: `Listening`, `NoDriver` or
`ListenRefused`.

IPC is asynchronous. A send copies the payload into the port's queue and
returns at once. A receive blocks until there is a message, and is given the
sender's pid with it. A request that wants an answer carries a reply port:
see `request` and `msg_reply` in `l0s.l0`, `msg_answer` in `server.l0`,
and `user/sbin/echo`, which sends each request's body back from the
bytes it came in. A message stays the bytes it came as: a server reads
what it needs where it is, and makes a list of a payload only to read it
as text. A header and a body that must become one message are joined
with `bytes_concat`, and a part of one is cut with `bytes_slice`, so
neither goes through a list
([probes/bytes](../probes/bytes/REQUEST-bytes-slice-join.md)), and memory
a process shares or gives a device, a disk's buffer, a file window, a
frame a card received, is copied to and from bytes at once
(`get_bytes_in`, `put_bytes_range`;
[probes/bytes](../probes/bytes/REQUEST-region-bytes.md)). What still
goes through a list: a device's registers, read a byte at a time, and
TCP's data, which its reassembly holds as lists.

When a process exits or is killed, its ports, names, interrupt bindings and
open files go with it. An interrupt it let go stays enabled, as none can be
disabled: if it comes again with no driver, the kernel holds it taken, not
ended, so a device left raising a level interrupt can't take CPU 0 for
ever, and the next process to bind it ends it first. Whoever waits for it is woken with its status, and
every port watching it gets a notice. Waiting with `watch` instead of `wait`
lets a process hear about an exit and other messages on one port. That is
how the shell waits for a job and for Ctrl-C at the same time.

A process that serves on several ports waits on all of them at once
with a *set*: `port_set` names them, up to 32 of its own, once, and
each `port_receive_set` answers with the oldest message waiting on any
of them and the port it came on. Every message queued on any port is
numbered as it is queued, so a busy port does not starve the others. A
send to any port of the set wakes the process; a port of it closed
leaves the set. A process has one set, kept until it sets another or
exits, so a loop whose ports stay the same sets them once. The message
comes as `port_receive` would give it, copied once from the kernel's
bytes to drop the port after it. A name a process registered goes when
it exits, or before, with `name_unregister`, so one process can hold a
name for a while on a port of its own and let it go.
