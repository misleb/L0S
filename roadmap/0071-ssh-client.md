# 0071: An SSH client: a shell, a command and a file on another machine

Track: Network · Status: active · Needs: 0048 (its cryptography, met), 0047 (for the Pi 5) · Spec: network.md, programs.md, testing.md

## Why

L0S reaches other machines only by HTTP. With SSH a board runs a
command on another machine, opens its shell, and copies files to and
from it, as any Unix does, and the cryptography it needs is 0048's but
for Ed25519. L0S's terminals are of lines (desktop.md, Limits), so the
shell is one of lines too: a pty that echoes nothing, its escape
sequences dropped.

## Done when

- Ed25519, SSH's data types, keys, known_hosts, the transport and the
  connection protocol as libraries, each tested on the host: Ed25519 by
  RFC 8032's vectors, keys by ssh-keygen's, the exchange and packets by
  a server written apart from them.
- `ssh` runs a command and a shell on the host's own OpenSSH, and `scp`
  copies a file up and down, in an e2e case, by key; a password asked
  hidden on the terminal.
- `ssh` and `scp` reach a real server from QEMU and from a Pi 5.

## Steps

- [x] **Ed25519**, `crypto/ed25519.l0`: RFC 8032's vectors.
- [x] **Keys**: `format/sshwire.l0`; `crypto/sshkey.l0`, blobs and their
  signatures (Ed25519, ECDSA P-256, RSA by SHA-256 and SHA-512), the
  private key file, fingerprints, known_hosts; `base64_encode`.
- [x] **The transport**, `proto/ssh.l0`: curve25519-sha256, the strict
  exchange, ChaCha20-Poly1305 and AES-GCM, checked against
  `tests/ssh/vectors.py`.
- [x] **Authentication and the channel**, `proto/sshconn.l0`.
- [x] **A hidden line**, tty.l0's `"s"`, for the password.
- [x] **`ssh`**, over `proto/sshc.l0`, the connection and the login.
- [x] **`scp`**, the scp protocol, one file each way.
- [x] **The e2e case** `ssh`, against the host's `sshd` run as the
  user.
- [ ] **Real servers from QEMU**: `make demo NET=user`, `ssh` to the
  host's own `sshd` on port 22 by password, a shell and `scp` both
  ways; `ssh -T git@github.com` by key. A new host's key answered
  `yes`, remembered on a system volume.
- [ ] **The Pi 5** (needs 0047's `random`): `ssh` to a machine on its
  network, the exchange and the login timed.

## Spec changes

- network.md: SSH, and its Limits. (In with steps 1 to 8.)
- programs.md: `ssh` and `scp`, and the libraries. (In.)
- testing.md: the `ssh` case, `@USER@`. (In.)

## Log

- 2026-11-06: written, and steps 1 to 8 done in one change. The
  transport matched Python's side of the exchange byte for byte with
  each cipher at its first run; against OpenSSH 10.6's `sshd` on the
  host, through QEMU's user network, a command, its standard error and
  exit status, `scp` both ways and a shell on a pty worked at the
  first boot. The e2e case takes 4 s. Not reached by any test: a
  password and keyboard-interactive (an `sshd` not run as root lets in
  only by key) and a new host's key asked about; nor any server but
  OpenSSH.
