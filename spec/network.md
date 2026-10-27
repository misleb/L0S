# The network

Two processes make the network, a driver and a stack above it, as the
disk is `virtio-blk` and `fs`:

```
net, tftp,  ──inet──▶ inet ──nic──▶ virtio-net ──DMA──▶ virtio-net card ──▶ QEMU's user network
http        ◀─pong, udp,─      ◀─frm──                                      10.0.2.2: gateway, TFTP,
              tcp notices                                                     the host's loopback
```

`virtio-net` ([user/sbin/virtio-net](../user/sbin/virtio-net/virtio-net.l0))
drives QEMU's virtio-net. It takes the card's address from its
configuration (`VIRTIO_NET_F_MAC`), keeps 16 receive buffers of 2048
bytes on the card's receive queue, in DMA pages, and takes its interrupt
as a message: each frame the card has written is told to every process
listening, and its buffer given back. A frame fits in a message, so
frames travel in messages, not shared pages, both ways: one to send is
copied into the one transmit buffer, offered on the transmit queue, and
waited for, as `virtio-blk` waits. It serves **the nic protocol**
([user/lib/proto/nic.l0](../user/lib/proto/nic.l0)) as `nic`:

| Request | Does |
|---|---|
| `info` | `nic MAC`: the card's Ethernet address, as `52:54:00:12:34:56` |
| `stats` | `rx N tx N dropped N`: frames taken and sent, and those lost |
| `listen` | `ok`; then every frame taken comes to the reply port as a notice, `frm` and the frame, 14 to 1514 bytes |
| `send FRAME` | the frame, without its check sequence, put on the wire, padded to 60 bytes; answered only if the request names a reply port |

On the Raspberry Pi 5 the same protocol is served by `gem`
([user/sbin/gem](../user/sbin/gem/gem.l0)), so `inet` and everything above
it are the same there; see [The network on the Raspberry Pi
5](#the-network-on-the-raspberry-pi-5).

`inet` ([user/sbin/inet](../user/sbin/inet/inet.l0)) is IPv4: Ethernet,
ARP, IPv4, ICMP, UDP and TCP, with each packet built and read in
[packet.l0](../user/sbin/inet/packet.l0) and [segment.l0](../user/sbin/inet/segment.l0)
(TCP's). It listens to `nic`, and is
started as `inet dhcp`, which takes its address, netmask, router and
name server from a DHCP server (below), or as `inet [ADDR/PREFIX
[GATEWAY [DNS]]]`, which sets them, by default 10.0.2.15/24 behind
10.0.2.2, with 10.0.2.3 as the name server, QEMU's user network's own.
It answers ARP for its address and
keeps up to 64 neighbours' addresses that ARP tells it; holds up to 16
datagrams for 3 seconds while ARP finds their next hop, the gateway for
any address off the link, asking again after a second; answers ICMP echo
requests; and gives each UDP datagram to the client bound to its port,
answering one to a port no one is bound to with ICMP's port
unreachable. A datagram to its own address goes no further than `inet`.
It does not fragment, nor take fragments, so a datagram's data is at
most 1472 bytes. Everything it sends while dealing with one message,
frames and notices alike, waits in its state until that message is
done, which is how its tests see it. It serves **the inet protocol**
([user/lib/proto/inet.l0](../user/lib/proto/inet.l0)) as `inet`:

| Request | Does |
|---|---|
| `info` | `inet ADDR MASK GATEWAY MAC`: the interface |
| `dns` | `dns ADDR`: the name server the interface has, `0.0.0.0` for none, which a client's `inet_resolve` asks |
| `stats` | `rx N tx N dropped N arp N`: frames taken and sent, those passed over or lost, and the neighbours known |
| `arp` | a line `ADDR MAC` for each neighbour, by address |
| `bind PORT` | `bound PORT`: UDP datagrams to PORT come to the reply port from now on, as notices `udp SRC SPORT DPORT`, a newline, and the data; `bind 0` for a port `inet` picks, from 49152. Refused if another client holds PORT |
| `unbind PORT` | `ok`: no more of them; refused if PORT is another's |
| `send SPORT DST DPORT` | then a newline and the data: a datagram from SPORT to DPORT at DST; answered only if refused, or with `ok` if the request names a reply port |
| `ping DST SEQ` | an ICMP echo request to DST, whose id is the reply port's: answered only if refused; its reply comes to the reply port as `pong SRC SEQ TTL BYTES` |
| `connect ADDR PORT NPORT` | a TCP connection opened to PORT at ADDR, its notices to the client's port NPORT: `connecting ID LPORT`, the connection's number and local port. It is open once a notice says so |
| `listen PORT NPORT` | `listening PORT`: TCP connections to PORT are made, and told to NPORT; `listen 0` for a port `inet` picks, from 49152. Refused if PORT is listened to |
| `unlisten PORT` | `ok`: no more are made; those made go on. Only by the process that listens |
| `write ID` | then a newline and the data: given to connection ID, which sends it as the peer's window lets it; answered only if the request names a reply port. More than 16384 bytes not yet acknowledged resets the connection |
| `finish ID` | `ok`: connection ID is closed once its data is sent (a FIN) |
| `reset ID` | `ok`: connection ID is given up, with a reset |
| `tcp` | a line `ID STATE LPORT ADDR:RPORT` for each connection, then `listen PORT` for each listener; `none` for neither |

A client lets go of what it bound with `unbind`, and `inet` lets go of a
client whose port has gone when it next has something for it.

**TCP** (RFC 9293). A connection is made by `connect` or by a SYN to a
port that is listened to, goes through the three-way handshake, and is
a state machine, in [tcp.l0](../user/sbin/inet/tcp.l0), of the states of
the RFC's diagram. The machine is pure: an event, a segment, the application's `write` or
`finish`, or a timer's deadline, takes a connection and the time and
gives it back with the acts it calls for, which
[tcpstack.l0](../user/sbin/inet/tcpstack.l0) turns into frames, in `inet`'s
queue, and notices, and keeps the connections, 32 at most, and the
listeners. It keeps sequence and acknowledgement numbers modulo 2^32,
holds the data it has sent until it is acknowledged, and sends it again
when no acknowledgement comes: after 1 second, then 2, 4, 8, 16 and 16
more, and then gives up with a reset and `closed timeout`. A window of 8192 bytes is offered
always, the data being given to the client as it comes; the peer's is
kept, and a closed one probed with a byte. A segment that comes before
the bytes ahead of it is held, cut to the window, up to 16 of them, and
given to the client with them once they come, so that a segment lost
costs only itself. Segments carry at most 1460 bytes,
or what the peer's SYN says, so that no frame is over 1514. FIN
closes in either order, or both together, and TIME-WAIT, 4 seconds, lets
the client know the connection ended at once. A RST ends a connection
only if it is where the next byte is expected, as RFC 5961 has it, and a
segment to no connection or listener is answered with one. The TCP
checksum covers IPv4's pseudo-header. A connection to `inet`'s own address
is made inside it, with no frame. Its first sequence number is RFC
6528's: a clock that ticks every 4 microseconds, moved on by a hash of
the connection's ends keyed with a secret `inet` asks `random` for when
its first connection is made, so that one who does not know the secret
cannot guess where another's connection starts.

A client asks through its own reply port, and has the connection's notices
come to another, named in `connect` and `listen`, so that an answer is never
taken for a notice; it owns its connections by its pid. The notices, to that
port, are `tcp ID up` (opened), `tcp ID accepted SRC SPORT LPORT` (to
the listener, which is then the owner), `tcp ID data` and a newline and the data,
`tcp ID fin` (the peer will send no more), and the last of each connection,
`tcp ID closed WHY`: `closed`, `reset`, `refused`, `timeout`, `aborted` or
`overflow`. A client whose port has gone, or is full, loses its
connections, with a reset.

While it holds a connection `inet` looks at their timers every millisecond;
with none, it waits for a message.

**DHCP.** `inet dhcp` (the demo's line) starts with no address, and gets
one as a DHCP client (RFC 2131) before it registers as `inet`, so that
clients' `name_wait` waits for it. The messages are built and read in
[dhcp.l0](../user/sbin/inet/dhcp.l0), and the exchange is
[lease.l0](../user/sbin/inet/lease.l0), run over the stack itself: `inet`
binds UDP port 68 to its own port, so the stack takes what servers send
as it takes any datagram, to 255.255.255.255, which is ours at any
address, or to the address offered, once there is one; and it sends a
DISCOVER, and then a REQUEST of the offer it takes, from 0.0.0.0 port 68
to 255.255.255.255 port 67, as datagrams of its own, which wait in the
same queue as every frame it sends. The OFFER of an address and a
server, for this card and this exchange's xid, is taken; the ACK of that
address gives the stack its address, the netmask it names, or the
address's class's, the first router it names, or none, and the first
name server, or none; a NAK begins again. It sends again every 2
seconds, 5 times in all, and if no server has answered says so and
exits 1. Giving the demo another
network, `make demo NET=user,net=192.168.7.0/24,dhcpstart=192.168.7.50`,
shows the address it takes is the server's.

The lease is kept. Port 68 stays bound, and `inet` asks `rtc clock` to
tell it the time every minute, when it looks at the lease: once half
its time is gone it sends a REQUEST from its address to the server that
gave it (RENEWING), and once seven eighths are, broadcast to any server
(REBINDING), each asked again every minute until it is answered; an
ACK begins the lease again, and a NAK, or the lease running out, takes
the address away, and the exchange begins again from a DISCOVER. A
lease of 0xFFFFFFFF seconds is for ever.

**Names** (RFC 1035). A client resolves a name itself, with
`inet_resolve` in [inet.l0](../user/lib/proto/inet.l0): it asks `inet`
for its name server (`dns`), binds a UDP port, sends the query for the
name's IPv4 address, built in [dns.l0](../user/lib/format/dns.l0), to port
53 there, and reads the first A record of the answer, past any CNAME;
an address dotted is taken as it is, with nothing asked. It waits 2
seconds for the answer, asks 3 times in all, and drops anything else
that comes to its port meanwhile. The query's id is 16 bits asked of
`random`, or the clock's when there is none. `net`, `tftp` and `http`
take names this way.

`run net` uses it from a shell, as `ifconfig` and `ping` would, and
`run tftp HOST FILE [PATH]` fetches a file over TFTP, from QEMU's TFTP
server, which serves a directory at the gateway when the demo is made
with `make demo NET=user,tftp=DIR`:

```
l0s> run net
inet 10.0.2.15 netmask 255.255.255.0 gateway 10.0.2.2
ether 52:54:00:12:34:56
l0s> run net ping 10.0.2.2
64 bytes from 10.0.2.2: seq 1 ttl 255 time 5.4 ms
64 bytes from 10.0.2.2: seq 2 ttl 255 time 4.9 ms
64 bytes from 10.0.2.2: seq 3 ttl 255 time 5.0 ms
3 sent, 3 received
l0s> run net arp
10.0.2.2 52:55:0a:00:02:02
l0s> run net dns
dns 10.0.2.3
l0s> run net resolve example.com
104.20.23.154
```

QEMU's user network answers pings to its gateway itself, its TFTP
server is there too, and its name server, 10.0.2.3, asks the host's;
what goes beyond the gateway is QEMU's to carry. `run net resolve NAME
[SERVER [PORT]]` resolves a name, as the interface's name server
answers, or another's; `run net ping HOST` and `run net send HOST PORT
TEXT...` take names too, and `run net recv PORT` waits for a datagram
and shows it.

`run http [-i] [http://]HOST[:PORT][/PATH]` fetches a page over HTTP/1.0
(RFC 1945), through TCP, and writes it, with its header first for `-i`.
QEMU's user network reaches the host's loopback as 10.0.2.2, so a server
on the host, say `python3 -m http.server 8000 --bind 127.0.0.1`, is
fetched with `run http 10.0.2.2:8000/`. HOST is a name, resolved first,
or an address. It does not follow a redirect; a status that is not
2xx is said, after the page, and fails the command. `run net tcp` shows
the connections, and `run net echo PORT` listens to TCP PORT, sends back
what the first connection sends, and says how much, for a connection
from the host to a port forwarded to the board
(`make demo NET=user,hostfwd=tcp:127.0.0.1:7000-:7000`, then `nc 127.0.0.1
7000`).

## The network on the Raspberry Pi 5

```
inet ──nic──▶ gem ──MDIO──▶ BCM54213PE PHY ──▶ the RJ45 port
     ◀─frm──      ──DMA, 64 GB up──▶ RP1's GEM
```

`gem` ([user/sbin/gem](../user/sbin/gem/gem.l0)) drives the Pi 5's Ethernet
port and serves the nic protocol as `nic`, as `virtio-net` does on QEMU.
It is a first draft that has run nowhere: what it writes follows Linux's
macb driver and RP1's device tree, Raspberry Pi's rpi-6.12.y. The port
is RP1's Cadence GEM, at RP1's 0x40100000, which L0's region onto RP1
holds at 0x1F00100000 ([regs.l0](../user/sbin/gem/regs.l0)), and behind it
a Broadcom BCM54213PE PHY at MDIO address 1
([phy.l0](../user/sbin/gem/phy.l0)). It:

- knows the GEM by its module ID and checks that it takes 64-bit
  addresses, since RP1 reaches the Pi's memory at the CPU's addresses (not
  0x10_0000_0000 above them, which went nowhere on a board). It takes
  the GEM's interrupt, RP1's MSI-X vector 6, level-triggered (interrupt
  166), and wakes on the kernel's alarm (call 297) to look at the link;
  on a board `inet` got a DHCP lease through it. With no RP1, as on
  QEMU, it says so and exits 0
- takes the board's Ethernet address from the firmware,
  `GET_BOARD_MAC_ADDRESS` through the mailbox
  ([mailbox.l0](../user/lib/sys/mailbox.l0), shared with `rtc`), or else
  what the GEM's first specific address already holds
- sets the GEM up for RGMII with MDC at pclk / 128, resets the PHY, has
  it delay both clocks (rgmii-id: shadow 7's `RGMII_SKEW_EN`, shadow 3's
  `GTXCLK_EN`), advertises every speed and autonegotiates
- keeps a receive ring of 32 buffers of 2048 bytes and a transmit ring
  of 8, in 18 DMA pages, with 16-byte descriptors (`ADDR64`); the queues
  it does not use point at one descriptor marked used
- polls, as L0 gives no interrupt for RP1: the receive ring between
  requests, every millisecond when idle, and the PHY's link every half
  second. A link coming up sets NCFGR's speed and duplex, lays the rings
  out afresh and enables the GEM, as `macb_mac_link_up` does; a link
  going down disables it. Each is a line in the log
- sends one frame at a time and waits up to 100 ms for the GEM to mark
  its descriptor used; a frame that fails or never goes restarts the
  GEM, whose transmit side stops at an error

The Pi's DMA does not see the CPU's caches, so every page is cleaned
right after the CPU writes it and invalidated before it reads what the
GEM wrote. Four receive descriptors share a cache line, and cleaning a
line would undo what the GEM had written since into the others, so they
are given back four at a time, once the GEM has used all of the line's.

The first run should check, beside `gem`'s line, which names its
address and the PHY's ID (0x600d84a2 for this PHY's revision 2):
- that the firmware gives the address. Without it, and with nothing in
  SA1B and SA1T, `gem` fails
- that the PHY answers. "No PHY answers" means it is still held in
  reset by RP1's GPIO 32 (`phy-reset-gpios`, which Linux pulses), which
  `gem` does not drive, or the PHY is not at address 1
- the link line, and frames both ways: `inet`'s lease, `ping`. A link
  with nothing sent may mean RP1's Ethernet clocks were left off by the
  firmware (`clk_eth`, `clk_eth_tsu` in RP1's clocks block, which `gem`
  does not set up), or the RGMII delays are doubled or missing
- the AXI pipelining register, AMP at 0x54 (`cdns,ar2r-max-pipe`,
  `cdns,use-aw2b-fill`), which Raspberry Pi's macb adds, unconfirmed
- that DCFG1 gives the bus's width, and DCFG6 the queues there are

## Limits

- **The network is one card, IPv4's datagrams and a small TCP.**
  `virtio-net` drives the first card on the board, sends one frame at a
  time and waits up to 2 seconds for the card to take it, and accepts no feature but
  its address, so it neither offloads checksums nor merges buffers.
  On the Pi 5, `gem` also sends one frame at a time, waiting up to
  100 ms, takes frames of up to 1536 bytes in one buffer each, no
  jumbo frames and no multicast, and polls rather than taking
  interrupts.
  `inet` has one interface, set by its arguments or by DHCP, which
  takes no other options than the mask, the first router and the first
  name server. Its lease is looked at only when `rtc clock` tells it a
  minute has begun, so with no clock running it is never renewed, and
  a lease shorter than two minutes runs out before it is; one taken
  away leaves the clients' sockets and connections bound to an address
  that is gone. A name is resolved by each client, with no cache, to
  its first IPv4 address only, from one name server, over UDP alone, so
  an answer cut short is not asked again over TCP; while it waits the
  resolver drops anything else that comes to its client's port, and
  on a board with no virtio-rng its query's id is the clock's. It neither
  fragments nor takes fragments, so a datagram holds at most 1472 bytes;
  it has no IP options, and passes over every protocol but ICMP, UDP
  and TCP, without saying so; and it keeps at most 64 neighbours,
  starting again from one when it has as many, and 16 datagrams waiting
  for ARP, for 3 seconds. Any process may bind any port no one holds,
  and send from any port, bound or not.
- **TCP has the essentials, and little else.** `inet` holds 32
  connections, each with at most 16384 bytes of the client's data not
  yet acknowledged (more resets it), and offers a window of 8192 bytes
  that never changes. At most 16 segments that arrive out of order are
  held, within the window; one more is dropped, and asked for again once
  those before it come. The retransmission timeout
  is 1 second, doubled each time, whatever the round trip is, and every
  segment is acknowledged at once. There is no congestion control, no
  selective acknowledgement, window scaling, timestamps, urgent data,
  nor simultaneous open, and no MSS but the peer's SYN's; ICMP's errors
  do not end a connection, only the retransmissions' running out does
  (after 47 seconds). A client must take its notices as they come: if its
  port holds 32 messages, `inet` resets the connection that
  overflows it. Notices carry what came in the segments it came in, at
  most 1460 bytes each, so a client sees no message boundary of the
  sender's. A connection's owner is the pid that opened it, which is all
  the check there is. The first sequence number's offset is L0's `hash`
  of the ends and the secret, which is no cryptographic hash, and on a
  board with no virtio-rng there is no secret, so the first sequence
  number is the clock's, and guessable.
