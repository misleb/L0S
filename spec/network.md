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
| `link` | `link up` or `link down`: whether the card has a link; QEMU's always does |
| `stats` | `rx N tx N dropped N`: frames taken and sent, and those lost |
| `listen` | `ok`; then every frame taken comes to the reply port as a notice, `frm` and the frame, 14 to 1514 bytes, and each change of the link as `lnk up` or `lnk down` |
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
| `write ID` | then a newline and the data: given to connection ID, which sends it as the peer's window lets it. A request that names a reply port is answered `ok HELD`, the bytes the connection now holds not yet acknowledged, or, if they would pass 16384, `error: full HELD`: the data is not taken, the connection is kept, and its notice port is told `tcp ID room N` once what it holds falls to half. One that names none is answered nothing, and more than 16384 resets the connection |
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
`tcp ID fin` (the peer will send no more), `tcp ID room N` (a write
refused as full may be made again, N bytes of it), and the last of each connection,
`tcp ID closed WHY`: `closed`, `reset`, `refused`, `timeout`, `aborted` or
`overflow`. A client whose port has gone, or is full, loses its
connections, with a reset.

A client writes a body of any length with `tcp_write_bytes`, which sends
a range of bytes as `write` requests of at most 2048 bytes, each its head
made once and joined to its piece as bytes, answered to its reply port;
refused as full, it waits on the notice port for `room` and sends the
piece again, keeping every other notice that comes meanwhile and giving
them back, in order, so none is lost. `tcp_event_in` reads a notice in
place from the bytes received, a data notice as `TcpDataAt ID START`,
where in those bytes its data begins; `tcp_write` and `tcp_event_of`, on
lists, are the older programs'.

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
seconds, 5 times in all once the card has a link, and if no server has
answered says so and exits 1. A DISCOVER sent with no link is lost, so
`inet` asks the driver for the link (`link`) once it listens, counts
tries only while the link is up, and when the driver's notice says the
link has come up, sends at once and counts from one again; a link that
has not come in 30 seconds it reports, and exits 1. A Pi 5's link comes
up a few seconds after `gem` starts, which before this lost the boot's
DHCP about one time in seven. Giving the demo another
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

`run http [-i] [-j] [-e] [-d BODY] [-H NAME:VALUE]... [http://]HOST[:PORT][/PATH]`
asks a server over HTTP/1.1, with the client library (below): a `GET`,
or with `-d` a `POST` of BODY, as `application/json` unless a `-H`
names the `Content-Type`. It writes the body as each piece comes, with
`-i` the head first (the status and reason, then each header); with
`-j` it reads the body as JSON and writes it back compact on one line,
or says where it is not JSON and fails; with `-e` it reads it as an
event stream and writes a line `EVENT DATA` for each event as it comes,
its data's newlines as spaces. The shell does not quote, so BODY and a
header are each one word. QEMU's user network reaches the host's
loopback as 10.0.2.2, so a server on the host, say `python3 -m
http.server 8000 --bind 127.0.0.1`, is fetched with `run http
10.0.2.2:8000/`. HOST is a name, resolved first, or an address. It
does not follow a redirect; a status that is not 2xx is said, after
the body, and fails the command. `run net tcp` shows
the connections, and `run net echo PORT` listens to TCP PORT, sends back
what the first connection sends, and says how much, for a connection
from the host to a port forwarded to the board
(`make demo NET=user,hostfwd=tcp:127.0.0.1:7000-:7000`, then `nc 127.0.0.1
7000`).

## HTTP, JSON and server-sent events

What a program says to a web service is plain code over `inet`'s TCP,
in libraries any program links, each tested on the host.

**JSON** (RFC 8259), in [json.l0](../user/lib/format/json.l0), pure:
a value is a `Json`, `JNull`, `JBool`, `JInt` (a number that fits an
`int`), `JNum` (any other number, its text as read, which `json_float`
reads as a `float`), `JStr` (a string's bytes, UTF-8, its escapes
replaced), `JArr`, or `JObj`, whose `JField`s keep the order they came
in, so an object is written back as it was read. `json_read b i j`
reads a value in place from a range of bytes and gives the index after
it, `json_whole` one with nothing but white space around it; either says
where it stopped and why, as `at N: WHY`. It refuses what the RFC does
not allow: a trailing comma, a leading zero, a single quote, a string
not closed, a control character in a string, bytes that are not UTF-8,
a lone surrogate (a pair of `\u` escapes is one character, made UTF-8),
and arrays and objects nested past 64. `json_bytes` writes a value
compact, its pieces joined once, escaping in strings only the quote,
the backslash and control characters. `json_get` (an object's first
field of a name), `json_at`, `json_items`, `json_fields`, `json_text`,
`json_int`, `json_bool` read what a program wants of a value, and
`json_obj`, `json_field` and `json_str` make one to write.

**Server-sent events**, `text/event-stream` as the WHATWG's HTML
standard reads it ("Interpreting an event stream"), in
[sse.l0](../user/lib/format/sse.l0), pure: `sse_more s b i j` takes the
next piece of a body, read in place, and gives the reader after it and
the events the piece ended, each an `SseEvent` of its name (`message`
if the stream gave none) and its data, the `data:` lines joined by
newlines. A line ends at CR, LF or CRLF, a CRLF cut between two pieces
included, and the part of a line a piece leaves is held until it ends,
so the events are the same wherever the pieces are cut. A line that
starts with `:` is a comment; `id`, `retry` and any other field are
passed over; a blank line ends an event, which is given if it has data,
and one the stream ends inside is never given.

**HTTP/1.1's messages** (RFC 9112), in
[http.l0](../user/lib/format/http.l0), pure: `http_request method host
path headers body` is a request's bytes, `METHOD PATH HTTP/1.1`, `Host`,
the headers as given, and `Content-Length` for a body (or any `POST`,
`PUT` or `PATCH`), its head made bytes once and joined to the body. An
`HttpRead` reads the response as the connection gives it:
`http_more r b i j` takes the next piece and gives the reader after it
and the parts the piece gave, `HttpHead STATUS REASON HEADERS`,
`HttpBody BYTES` as the body comes, and `HttpEnd KEEP`, whether the
connection may carry the next request (not if the response said
`Connection: close`, or was HTTP/1.0 without `keep-alive`, or its body
ran to the close); `HttpBad WHY` for what is not a response, after
which it reads nothing more. The head is read whole, up to 16384 bytes,
its lines ended by CRLF or LF; a 1xx answer is passed over; the body is
chunked (sizes in hex, extensions passed over, trailers read and
dropped), or of a `Content-Length`, or what comes until the connection
closes, which `http_closed` ends, refusing any other body cut short;
`204`, `304` and the answer to `HEAD` have none. After an end the
reader reads the next response from what follows, so two may come back
to back. `http_header` finds a header ignoring case.

**The client**, in [httpc.l0](../user/lib/proto/httpc.l0), is those
messages over `inet`'s TCP. An `HttpConn` is the stack, the client's
port its connection's notices come to, the connection, its host and the
reader of its responses. `http_connect n np host port` resolves the host
and opens a connection, waiting up to 30 seconds for `up` (with
`alarm_at` on the notice port); `http_send c req` writes a request's
bytes with `tcp_write_bytes`, and `http_ask c method path headers body`
makes the request for the connection's host first. A program that waits
on several ports gives each message that comes to the notice port to
`http_feed c b`, which reads it in place, `TcpDataAt`, into the parts of
a response and sends nothing; one that waits on nothing else calls
`http_next c deadline`, which receives there until parts come or the
deadline passes. The server's `fin` ends a body that runs to the close;
the connection's end in the middle of a response is `HttpFailed WHY`. A
connection whose response ended with `keep` takes the next request, and
`http_reuse c` opens one the server closed again; `http_close` finishes
it.

## Reaching a model's API

```
ask ──HTTP──▶ inet ──▶ the host's proxy ──HTTPS, x-api-key──▶ api.anthropic.com
    ◀─events──       ◀─ streamed as it comes ─
```

A model's API is HTTPS only, and L0S has no TLS, so a board reaches
Anthropic's Messages API through a proxy on the development host,
[tools/api-proxy](../tools/api-proxy/proxy.py), in Python with aiohttp
in its own venv (`make proxy` makes `build/proxy/venv` and the boards'
token, `build/proxy/token`, 32 random hex digits made once, mode 600).
`make proxy-run [PROXY_LISTEN=ADDR:PORT]` runs it on 127.0.0.1:8765
unless given, with that token and the host's `ANTHROPIC_API_KEY`,
without which it will not start. It:

- listens on the one address it is given, which must be loopback or
  private (RFC 1918), never `0.0.0.0`, or it says so and exits;
- takes `POST /v1/messages` and `/v1/messages/count_tokens` and nothing
  else, any other path or method a 404, and refuses a request without
  `Authorization: Bearer TOKEN`, compared in constant time, with a 401
  whose message is "the proxy refused this board's token"; its own
  refusals are JSON in the API's error form;
- sends the body upstream as it came, `https://api.anthropic.com`
  unless `--upstream` names another base URL, with the board's
  `content-type`, `anthropic-version` and `anthropic-beta` and no other
  header of the board's, and `x-api-key` added;
- passes back the answer's status and `content-type`, and its body as
  each piece comes, never gathered; an answer that breaks off upstream
  closes the board's connection, so the board sees it cut short;
- counts what is spent and refuses nothing for it: each answer's usage
  (input, output, cache written, cache read, from `message_start` and
  `message_delta`, or a JSON answer's) is a JSON line in
  `build/proxy/usage.jsonl` with its time (UTC), path, model and status,
  and `proxy.py --day [YYYY-MM-DD]` totals a day's.

On the board, [proto/model.l0](../user/lib/proto/model.l0) is the
provider behind one interface. It finds the proxy and the token in two
files:

- `/etc/agent/config`, a line each, `#` a comment: `api HOST:PORT`, the
  proxy, which is needed; `model NAME`, `claude-sonnet-5-5` if none;
  `max_tokens N`, 8192 if none; any other key is left for its program;
- `/etc/agent/token`, the board's token, its first line.

`model_request` makes a request's bytes, `POST /v1/messages` with the
token as its bearer, `anthropic-version: 2023-06-01` and a body of
`model`, `max_tokens`, `stream: true` and the `system`, `messages` and
`tools` given as `Json`, so a caller adds `cache_control` where it
wants it; `model_events` reads each event of the stream as
`ModelEvent`s: `MText` (a block's text as it comes), `MToolStart` and
`MToolInput` (a tool's use and its input's JSON in pieces),
`MBlockStop`, `MStop` (why the answer stopped), `MUsage` (each count -1
where the event does not say it) and `MError`; `ping` gives none.

`ask TEXT...` ([user/bin/ask](../user/bin/ask/ask.l0)) asks it a
question: it reads the configuration, opens `api`, posts the words as
one user message, and writes each text piece as it comes, then a
newline. A 401 says the proxy refused the board's token, any other
refusal or an `error` event says the API's error message, and a
missing configuration says which file is missing.

A board on QEMU's user network reaches a proxy on the host's loopback
as 10.0.2.2: `api 10.0.2.2:8765`. A Pi 5 reaches it at the host's
address on the LAN its DHCP lease is on, where the proxy must listen on
that address (`make proxy-run PROXY_LISTEN=192.168.1.10:8765`, `api
192.168.1.10:8765`).

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
  going down disables it. Each is a line in the log, and a `lnk up` or
  `lnk down` notice to each listener
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
  yet acknowledged (more is refused, or resets it if the write named no
  reply port), and offers a window of 8192 bytes
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
- **JSON is read whole, and its numbers roughly.** `json_read` reads a
  value from bytes that hold all of it, so a body is gathered before it
  is read; `json_float` reads a number's first 19 digits and scales them
  by powers of ten in floats, which is the nearest float or within an
  ulp or two of it. An object's fields are a list, found by name one by
  one, which suits the handful an API's object has.
- **HTTP is plain HTTP/1.1, a request at a time.** There is no TLS, so
  only `http://`; a connection carries one request and then its
  response, never several in flight; a head may be at most 16384 bytes;
  no content coding (gzip) is asked for or read, and `http` follows no
  redirect. A connection's notices go to one port, which `http_connect`
  waits on alone, passing over another connection's.
- **A model's API is the host's.** The key and the TLS are the host's
  proxy's: the board speaks plain HTTP to it over the local network,
  so a board is tied to a host that runs it, and anything on that
  network that has the board's token can spend on the host's key. The
  proxy knows one token, forwards to one base URL, and caps nothing it
  counts; `ask` sends one message, with no system prompt and no tools.
