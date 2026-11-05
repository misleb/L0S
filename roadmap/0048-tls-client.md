# 0048: A TLS 1.3 client in L0

Track: Network · Status: active · Needs: 0041 (met), 0047 (for the Pi 5) · Spec: network.md, programs.md

## Why

0042's proxy ties the agent to the host and keeps its key there. With
TLS on the board the agent reaches its model's API itself, holds its
own key, and works on any network. TLS 1.3 alone is enough for today's
servers, and its parts are each well specified and tested by published
vectors, so each is a host test before any connection is made.

## Done when

- Libraries for SHA-256 and HMAC/HKDF, X25519, ChaCha20-Poly1305 and
  AES-128-GCM, each passing its RFC's test vectors under `l0 test`.
- Certificates: X.509 read from DER, a chain checked to a root in a
  store on the card, by ECDSA P-256 and RSA (PKCS#1 v1.5 and PSS)
  signatures, with names and dates checked.
- A TLS 1.3 client over `inet`'s TCP, which 0041's HTTP client uses for
  `https://`, refusing any connection it cannot check.
- `run http https://…` fetches a page from a real server on a Pi 5, and
  0043's agent reaches its API without the proxy.

## Steps

- [x] **The primitives**, each in `user/lib/crypto/` with its RFC's or
  NIST's vectors under `l0 test`: `sha512.l0` (SHA-384, SHA-512),
  `hkdf.l0` (a hash chosen at run time, a transcript's hash peeked as it
  grows, HMAC, HKDF, TLS 1.3's expand-label), `x25519.l0`,
  `chacha20.l0` (ChaCha20-Poly1305), `aesgcm.l0` (AES and GCM).
- [x] **Certificates**: `bignum.l0`, `rsa.l0` (PKCS#1 v1.5, PSS) and
  `ecdsa.l0` (P-256, P-384), verifying only; `format/der.l0` and
  `x509.l0`; `trust.l0`, a chain checked to roots for a host at a time;
  the roots, Mozilla's bundle, in `certs/roots.pem`, staged as
  `/etc/ssl/roots.pem`. Tested on real servers' chains as served.
- [x] **The client**, `proto/tls.l0`, pure: the handshake, the keys, the
  records; RFC 8448's simple 1-RTT handshake run through it byte for
  byte.
- [x] **https:// in httpc and `http`**: `https_connect`, `http_url_of`,
  `http_roots`; the e2e case `https`, against Python's TLS 1.3 on the
  host.
- [x] **The agent**: `api https://HOST` in `/etc/agent/config` reaches
  the API itself, the key as `/etc/agent/token`; `agentd`'s tool
  `fetch_url`, one HTTP or HTTPS request of its own to the internet.
- [ ] **Real servers from QEMU**: `make demo NET=user`, `run http
  https://example.com/` and a few more; `make agent-etc` with `api
  https://api.anthropic.com` and the key (the user's), `run ask`, and
  `fetch_url` from the agent. Log the handshake's time.
- [ ] **The Pi 5** (needs 0047's `random`): `run http https://…` and the
  agent straight to the API, the handshake timed.

## Spec changes

- network.md: TLS, its limits and its root store.
- programs.md: the libraries' rows.

## Log

- 2026-10-29: written, with 0041 to 0047 and 0049.
- 2026-11-05: steps written and the first five done in one change: the
  primitives, certificates and the client written as libraries, each
  tested on the host by published vectors, RFC 8448's trace, and the
  chains api.anthropic.com, letsencrypt.org (also through ISRG Root X1's
  RSA cross-sign), www.wikipedia.org (a wildcard) and example.com
  served that day; `http` speaks `https://`; the agent reaches the API
  over TLS when `api` says `https://`, and has `fetch_url`. On the host:
  X25519 about 3 ms, P-256 verify 3 ms, P-384 7 ms, RSA-2048 1.5 ms,
  RSA-4096 5 ms, ChaCha20-Poly1305 80 MB/s, AES-128-GCM 40 MB/s, the
  118 roots read in 4 ms. Beyond the plan: AES-256 and 192 too (no
  suite uses them yet); the ChaCha20 suite offered first, as the faster
  here.
- 2026-11-05: step 6 begun, on QEMU's user network with the bundle as
  roots: `run http` fetched example.com, www.wikipedia.org,
  letsencrypt.org, www.amazon.com, www.microsoft.com, github.com,
  www.google.com, 1.1.1.1 and 8.8.8.8 (by address, an iPAddress SAN)
  and www.cloudflare.com's trace (`tls=TLSv1.3`), and api.anthropic.com
  answered 401 without a key. badssl.com's hosts refuse the handshake
  (handshake_failure): they speak TLS 1.2 at most. Left for the user:
  the agent straight to the API with a key, and `fetch_url` from it.
