# 0042: A model's API reached through a proxy on the host

Track: Agent · Status: idea · Needs: 0041 · Spec: network.md, testing.md

## Why

A model's API is HTTPS only, and L0S has no TLS (0048 gives it one,
a goal of its own). Until then a small proxy on the development host
takes the board's plain HTTP on the local network, adds the API key,
and forwards it over TLS, so 0043's agent can run long before L0S
speaks TLS itself. The key stays on the host, and the board is tied to
it; 0048 lifts both.

## Done when

- `tools/` has the proxy: it listens on the local network only, takes
  requests for one API's paths and no others, refuses any request
  without the token the board was given, adds the key from the host's
  environment, and streams the answer back as it comes.
- A program on L0S sends a message to the model through it and writes
  the answer as it streams, on QEMU (through 10.0.2.2) and on a Pi 5.
- The proxy's own tests run with `make test`, against a stand-in for
  the API, so no test needs a key or the network.

## Steps

To be written. Open: which API (the agent's model is not yet chosen,
so the proxy forwards to one base URL it is given); where the board's
token lives on its card; whether the proxy also counts what is spent,
since an agent acting on its own needs a budget (0043).

## Spec changes

- network.md: reaching a model's API, through the proxy.
- testing.md: the proxy's tests.

## Log

- 2026-10-29: written, with 0041 and 0043 to 0049.
