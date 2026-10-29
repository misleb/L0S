# 0048: A TLS 1.3 client in L0

Track: Network · Status: idea · Needs: 0041, 0047 · Spec: network.md, programs.md

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

To be written. Leads: the order above, the primitives first; the
board's clock must know the date to check a certificate's; time each
handshake on the Pi 5, since big-number arithmetic for RSA in L0 may be
slow.

## Spec changes

- network.md: TLS, its limits and its root store.
- programs.md: the libraries' rows.

## Log

- 2026-10-29: written, with 0041 to 0047 and 0049.
