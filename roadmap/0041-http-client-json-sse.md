# 0041: An HTTP/1.1 client library, with JSON and server-sent events

Track: Agent · Status: active · Needs: – · Spec: network.md, programs.md, testing.md

## Why

The agent of 0043 talks to a model's API and to MCP servers, and both
are HTTP/1.1 carrying JSON, the model's answers streamed as server-sent
events. L0S has `http` ([user/bin/http](../user/bin/http/http.l0)), a
program that fetches a page over HTTP/1.0 and writes it out; there is
no library a program links to ask a server, nothing that writes or
reads JSON, and nothing that reads an event stream. Each is plain
code over `inet`'s TCP, testable on the host, and the first thing every
other goal of this track needs.

Two things in `inet`'s client side stand in the way. A request's body,
a conversation with its tools, is tens of kilobytes, and a client that
writes more than 16384 bytes not yet acknowledged has its connection
reset (network.md's Limits), with nothing to tell it when there is room
again. And `tcp_write` takes a list, and `tcp_event_of` gives a data
notice's bytes as one, so a body would go through a list both ways
("Bytes, not lists").

## Done when

- A client may write a body of any length to a connection: a write
  that would pass 16384 bytes held is refused, the connection kept, and
  the client told when there is room. Writes and data notices are bytes,
  read and sent in place.
- A JSON library writes and reads values (objects, arrays, strings with
  their escapes and UTF-8, numbers, `true`, `false`, `null`), reading
  a body in place as bytes, with host tests from RFC 8259's cases.
- A server-sent events reader gives a stream's events as they arrive,
  each its `event` and `data`, from a body that comes in pieces, the
  same events wherever the pieces are cut.
- A library makes HTTP/1.1 requests (`POST` with a body, headers in and
  out, `Content-Length`, chunked and close-delimited bodies, a
  connection kept for the next request) over `inet`'s TCP, giving the
  body in pieces as they come, and `http` is built on it.
- The `http` e2e case fetches and posts to a server on the host
  (10.0.2.2) over HTTP/1.1, reads its JSON, and reads an event stream
  whose events are written as they come. `make check`, `make test` and
  `make e2e` pass.

## Steps

- [x] **TCP writes from bytes, paced.** In
  [proto/inet.l0](../user/lib/proto/inet.l0): `tcp_write_bytes n id b
  i j`, the range sent as `write ID` requests of at most `tcp_write_max`
  bytes, each the header made once and the piece joined by
  `bytes_concat` (or `port_send_bytes` of a message built once), never
  a list; and `tcp_event_in b`, a notice read in place from the bytes
  received, whose data is `(TcpDataAt id start)`, its offset into `b`,
  beside the list `TcpData` the old readers keep. In `inet`
  ([tcpstack.l0](../user/sbin/inet/tcpstack.l0), [tcp.l0](../user/sbin/inet/tcp.l0)):
  a `write` that names a reply port is answered `ok HELD`, the bytes
  now held unacknowledged, or `error: full HELD` if it would pass 16384,
  which leaves the connection as it was; once a refused writer's held
  bytes fall to half, its notice port is told `tcp ID room N`, a new
  `TcpEvent`, `TcpRoom`. A write with no reply port resets as now, so
  `net` and `http` are unchanged. `tcp_write_bytes` waits for `room`
  when refused, taking other notices that come meanwhile into a list it
  gives back, so none is lost. Tests: tcp.l0's and tcpstack.l0's host
  tests (a write past the bound refused and the connection kept; `room`
  after the acknowledgement; a write with no reply port still resets);
  inet_test's codec of `room` and of `tcp_event_in` on notices built
  with `message_new`. The `http` and `net_echo` e2e cases still pass.
- [x] **JSON.** [format/json.l0](../user/lib/format/json.l0), pure, for
  the board and host tools alike: `(data Json (JNull) (JBool bool)
  (JInt int) (JNum (list int)) (JStr bytes) (JArr (list Json)) (JObj
  (list JField)))`, `(data JField (JField bytes Json))`. A number that
  fits an `int` is `JInt`, any other (a fraction, an exponent, too big)
  is `JNum`, its text as read, which `json_float` gives as a `float`.
  An object keeps its fields in the order read, so it is written back
  as it came and a tool's input is the model's; objects are a handful
  of fields, and `json_get o "name"` finds the first. Reading:
  `json_read b i j`, a `(Result JsonAt (list int))` with the index
  after the value and why not (with the offset), `\uXXXX` and surrogate
  pairs made UTF-8, a lone surrogate, a control character in a string
  or bytes that are not UTF-8 refused, nesting bounded (64). Writing:
  `json_bytes v`, compact, built as reversed pieces and made bytes once;
  strings escaped as RFC 8259 requires and nothing more. Helpers for
  what the agent reads: `json_get`, `json_at`, `json_text` (a `JStr`'s
  bytes, or none), `json_int`, `json_obj` (fields from a list, for
  writing). Tests: RFC 8259's examples (section 13's object and array),
  JSONTestSuite's kinds by name (`y_` read, `n_` refused: a trailing
  comma, a leading zero, a single quote, an unclosed string, a lone
  surrogate, nesting past the bound), a seeded property test of
  `json_read` after `json_bytes` on a few hundred random values giving
  the value back. Makefile: `JSON`, its `l0_test` line, `DOC_SRCS`;
  programs.md's row; network.md's paragraph on JSON.
- [x] **Server-sent events.** [format/sse.l0](../user/lib/format/sse.l0),
  pure: `(data Sse ...)`, the line not yet ended (bytes), the event's
  name and its data lines so far; `sse_more s b i j` gives `(SseMore s
  events)`, each `(SseEvent name data)`, name `message` if none was
  given, data the `data:` lines joined by newlines, as bytes. Lines end
  at CR, LF or CRLF, a CRLF cut between two pieces included; a line
  starting `:` is a comment; `id` and `retry` are read and passed over;
  an event is given at the blank line that ends it, and one the stream
  ends inside is dropped, as the WHATWG's HTML standard says
  ("Interpreting an event stream"). Tests: the standard's examples; the
  stream of a Messages API answer (message_start to message_stop) fed
  whole, then cut in two at every offset, then a byte at a time, each
  giving the same events (a property test); a comment and a `retry`
  between events. `SSE`, its test line, programs.md's row, network.md.
- [ ] **HTTP/1.1 messages.** [format/http.l0](../user/lib/format/http.l0),
  pure: `http_request method host path headers body`, the request's
  bytes, `Host`, `Content-Length` for a body, headers as given;
  `(data HttpRead ...)`, a response read as it comes: `http_more r b i
  j` gives `(HttpMore r parts)`, each part `(HttpHead status reason
  headers)`, `(HttpBody bytes)` as the body arrives, or `(HttpEnd
  keep)`, whether the connection may be used again. It reads the status
  line and headers up to 16384 bytes (more is `HttpBad`), passes over
  1xx answers, and then a body by `Transfer-Encoding: chunked` (sizes
  in hex, extensions passed over, trailers read and dropped), by
  `Content-Length`, or to the connection's end (`http_closed r`, which
  ends such a body and refuses one cut short), and no body for 204,
  304 or an answer to `HEAD`. `http_header headers name` finds a header
  ignoring case. Tests: RFC 9112's examples; a chunked body cut at every
  offset giving the same body; two answers back to back on one stream,
  the second read after the first's `HttpEnd`; a body cut short; a head
  over the bound; `Connection: close` making `keep` false.
- [ ] **The client.** [proto/httpc.l0](../user/lib/proto/httpc.l0),
  over `inet` (`HTTP` in the Makefile is `INETLIB` with `format/http.l0`
  and it): `(data HttpConn ...)`, the inet, the port its notices come
  to, the connection, its host, and the `HttpRead`. `http_connect n np
  host port` resolves and opens, waiting for `up` (a `Result`);
  `http_send c req` writes a request's bytes with `tcp_write_bytes`;
  `http_feed c m`, a message that came to `np`, gives `(c, parts)`,
  and sends nothing, so a program waiting on several ports (0043's
  `agentd`, with `port_receive_set`) feeds it what comes; `http_next c
  deadline`, for a program that waits on nothing else, receives on
  `np` until it has parts or the deadline passes; `http_close c`.
  A connection kept (`HttpEnd` with keep) takes the next request; one
  the server closed is opened again by `http_reuse c`. Tests: under
  `l0 test` there is no inet, so `http_connect` fails and says so (the
  entry points' test); `http_feed` on notices built with `message_new`
  (up, data in three pieces of a chunked answer, fin, closed) gives the
  head, the body's pieces and the end; a `closed reset` mid-body is
  `HttpFailed`. programs.md's row; network.md.
- [ ] **`http` on the library, and the e2e case.** `http` becomes
  `http [-i] [-j] [-e] [-d BODY] [-H 'NAME: VALUE']... URL`: HTTP/1.1,
  `GET`, or `POST` of BODY with `-d` (`Content-Type: application/json`
  unless a `-H` names one); `-i` writes the head first; `-j` reads the
  body as JSON and writes it back compact on one line, or says where it
  is not JSON and fails; `-e` reads it as an event stream and writes a
  line `EVENT DATA` for each event as it comes, with its data's
  newlines as spaces. Its body is written as each piece comes. The
  e2e case's [server.py](../tests/e2e/http/server.py) speaks HTTP/1.1:
  `/hello.txt` and `/big` with `Content-Length`, `/chunked` in chunks,
  `POST /echo` answering `{"got": BODY, "length": N}`, `/events` three
  events 200 ms apart, a comment between them; `typed` adds a POST with
  `-j`, `/chunked`, and `-e /events`, whose lines must come, the case
  shows, though the stream is still open (the server holds it 2 s after
  the last). `expected` follows. testing.md's `http` case; network.md's
  `http` paragraph and programs.md's row.

## Spec changes

- network.md: `inet`'s `write` answered `ok HELD` or refused `full`, and
  the `room` notice (the inet table, TCP's Limits); the HTTP/1.1
  client, JSON and the event reader, a section after TCP; `http` as it
  is now.
- programs.md: `http`'s row; the rows of `format/json.l0`,
  `format/sse.l0`, `format/http.l0` and `proto/httpc.l0`.
- testing.md: the `http` case, HTTP/1.1, JSON and events.

## Log

- 2026-10-29: written, with 0042 to 0049, from the idea of an agent
  that lives on L0S.
- 2026-10-29: steps written, with 0042's and 0043's. Two needs found in
  `inet`'s client side and made the first step: a request's body is
  more than the 16384 bytes a connection may hold unacknowledged, which
  resets it today with nothing to say when there is room; and writes
  and data notices go through lists. The window of 8192 bytes bounds
  how fast an answer comes, which is enough for an API's streamed
  answers. JSON objects keep their fields in order, a list, not a
  `Map`: they are small, and are written back as they came.
- 2026-10-29: step 1 landed. `tcp_write_bytes` takes the notice port
  too, `tcp_write_bytes n np id b i j`, since it waits there for
  `room`, and gives a `TcpWrote`: the notices it kept, each its
  message's bytes, and why it stopped, if it did. `room N` says how
  many bytes may be written now (16384 less what is held). A refused
  write whose connection already holds half or less is told `room` at
  once. The flag lives in tcp.l0's `Conn` (a ninth field), and the
  notice is the act `ConnRoom`, so tcp_test.l0 tests it with the rest
  of the machine; tcpstack's own tests are inet_test.l0's, as before.
  `tcp_event_in` takes a message's bytes, the pid first, as received.
- 2026-10-29: step 2 landed. Beside the helpers named, `json_whole`
  (a value with nothing but white space around it), `json_items`,
  `json_fields`, `json_bool`, `json_field` and `json_str`; a `JsonAt`
  is the value and the index after it, and errors read `at N: WHY`, N
  from the start given. `json_float` gives an `Option float` (none for
  a value that is not a number), from the first 19 digits scaled in
  floats, within an ulp or two, not a correctly rounded conversion.
  A string with no escape is sliced from the input as it is; one with
  escapes is made once from a list of what they mean.
- 2026-10-29: step 3 landed. The reader is `sse_new` and `sse_more`;
  its state holds the unended line as a list of the pieces' bytes,
  joined once the line ends, and a CR that ended a piece. `sse_name`
  and `sse_data` read an event. Beside the cuts at every offset and a
  byte at a time, 300 random cuts in three.
