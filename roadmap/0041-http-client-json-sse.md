# 0041: An HTTP/1.1 client library, with JSON and server-sent events

Track: Agent · Status: idea · Needs: – · Spec: network.md, programs.md

## Why

The agent of 0043 talks to a model's API and to MCP servers, and both
are HTTP/1.1 carrying JSON, the model's answers streamed as server-sent
events. L0S has `http` ([user/bin/http](../user/bin/http/http.l0)), a
program that fetches a page over HTTP/1.0 and writes it out; there is
no library a program links to ask a server, nothing that writes or
reads JSON, and nothing that reads an event stream. Each is plain
code over `inet`'s TCP, testable on the host, and the first thing every
other goal of this track needs.

## Done when

- A library makes HTTP/1.1 requests (`POST` with a body, headers in and
  out, `Content-Length` and chunked bodies, a connection kept for the
  next request) over `inet`'s TCP, and `http` is built on it.
- A JSON library writes and reads values (objects, arrays, strings with
  their escapes and UTF-8, numbers, `true`, `false`, `null`), reading
  a body in place as bytes, with host tests from RFC 8259's cases.
- A server-sent events reader gives a stream's events as they arrive,
  each its `event` and `data`, from a body that comes in pieces.
- A screen-free e2e case fetches and posts to a server on the host
  (10.0.2.2) and reads its JSON.

## Steps

To be written. Leads: TCP's window of 8192 bytes and 16384 unacknowledged
(network.md's Limits) bound how fast a body comes, which is enough for
an API's answers; a stream's events must be given out as they arrive,
not once the body ends. "Bytes, not lists": a body stays `bytes`, and
JSON is read from it in place.

## Spec changes

- network.md: the HTTP/1.1 client, JSON and the event reader.
- programs.md: the libraries' rows.

## Log

- 2026-10-29: written, with 0042 to 0049, from the idea of an agent
  that lives on L0S.
