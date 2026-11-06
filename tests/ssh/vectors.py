#!/usr/bin/env python3
"""The vectors user/lib/proto/ssh_test.l0 checks the SSH client against.

An SSH server's side of the first key exchange, written apart from the
L0 code, on Python's cryptography: with the client's secret and cookie
fixed, and the server's, it makes what the server sends (its version
line, KEXINIT, ECDH reply, NEWKEYS, then a SERVICE_ACCEPT and a channel
DATA sealed under its new keys), and what the client must send after
the host key is accepted (its NEWKEYS and a SERVICE_REQUEST sealed under
its keys), for each cipher. Prints them as hex, one NAME HEX a line.

    python3 -I tests/ssh/vectors.py
"""

import hashlib
import struct

from cryptography.hazmat.primitives import poly1305
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


def u32(v):
    return struct.pack(">I", v)


def string(b):
    return u32(len(b)) + b


def names(ns):
    return string(",".join(ns).encode())


def mpint(b):
    b = b.lstrip(b"\0")
    if b and b[0] & 0x80:
        b = b"\0" + b
    return string(b)


def raw(k):
    return k.public_bytes(Encoding.Raw, PublicFormat.Raw)


CLIENT_SECRET = bytes([0x11] * 32)
CLIENT_COOKIE = bytes([0x22] * 16)
SERVER_COOKIE = bytes([0x33] * 16)
SERVER_SECRET = bytes([0x44] * 32)
HOST_SEED = bytes([0x55] * 32)
V_C = b"SSH-2.0-L0S_1.0"
V_S = b"SSH-2.0-TestServer_1.0"


def kexinit(cookie, kex, hostkeys, ciphers, macs):
    return (bytes([20]) + cookie + names(kex) + names(hostkeys) + names(ciphers) + names(ciphers)
            + names(macs) + names(macs) + names(["none"]) + names(["none"]) + names([]) + names([])
            + b"\0" + u32(0))


I_C = kexinit(CLIENT_COOKIE,
              ["curve25519-sha256", "curve25519-sha256@libssh.org", "ext-info-c", "kex-strict-c-v00@openssh.com"],
              ["ssh-ed25519", "ecdsa-sha2-nistp256", "rsa-sha2-512", "rsa-sha2-256"],
              ["chacha20-poly1305@openssh.com", "aes256-gcm@openssh.com", "aes128-gcm@openssh.com"],
              ["hmac-sha2-256", "hmac-sha2-512"])


def chacha(key, seq, counter, data):
    nonce = struct.pack("<Q", counter) + struct.pack(">Q", seq)
    return Cipher(algorithms.ChaCha20(key, nonce), None).encryptor().update(data)


def padded(payload, block, with_len):
    base = 1 + len(payload) + (4 if with_len else 0)
    pad = block - base % block
    if pad < 4:
        pad += block
    return bytes([pad]) + payload + bytes(pad), 1 + len(payload) + pad


def plain_packet(payload):
    inner, n = padded(payload, 8, True)
    return u32(n) + inner


class Sealer:
    def __init__(self, cipher, key, iv):
        self.cipher, self.key, self.iv, self.count = cipher, key, iv, 0

    def seal(self, seq, payload):
        if self.cipher == "chacha20-poly1305@openssh.com":
            inner, n = padded(payload, 8, False)
            main, hdr = self.key[:32], self.key[32:]
            lc = chacha(hdr, seq, 0, u32(n)) + chacha(main, seq, 1, inner)
            otk = chacha(main, seq, 0, bytes(32))
            return lc + poly1305.Poly1305.generate_tag(otk, lc)
        inner, n = padded(payload, 16, False)
        fixed, ctr = self.iv[:4], int.from_bytes(self.iv[4:], "big")
        nonce = fixed + ((ctr + self.count) % 2**64).to_bytes(8, "big")
        self.count += 1
        return u32(n) + AESGCM(self.key).encrypt(nonce, inner, u32(n))


def derive(k, h, letter, sid, n):
    out = hashlib.sha256(k + h + letter + sid).digest()
    while len(out) < n:
        out += hashlib.sha256(k + h + out).digest()
    return out[:n]


def key_len(cipher):
    return {"chacha20-poly1305@openssh.com": 64, "aes256-gcm@openssh.com": 32, "aes128-gcm@openssh.com": 16}[cipher]


def exchange(cipher):
    host = Ed25519PrivateKey.from_private_bytes(HOST_SEED)
    k_s = string(b"ssh-ed25519") + string(raw(host.public_key()))
    eph = X25519PrivateKey.from_private_bytes(SERVER_SECRET)
    q_s = raw(eph.public_key())
    q_c = raw(X25519PrivateKey.from_private_bytes(CLIENT_SECRET).public_key())
    i_s = kexinit(SERVER_COOKIE, ["curve25519-sha256", "kex-strict-s-v00@openssh.com"], ["ssh-ed25519"],
                  [cipher], ["hmac-sha2-256"])
    from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PublicKey
    shared = eph.exchange(X25519PublicKey.from_public_bytes(q_c))
    k = mpint(shared)
    h = hashlib.sha256(string(V_C) + string(V_S) + string(I_C) + string(i_s) + string(k_s)
                       + string(q_c) + string(q_s) + k).digest()
    reply = bytes([31]) + string(k_s) + string(q_s) + string(string(b"ssh-ed25519") + string(host.sign(h)))
    n = key_len(cipher)
    c2s = Sealer(cipher, derive(k, h, b"C", h, n), derive(k, h, b"A", h, 12))
    s2c = Sealer(cipher, derive(k, h, b"D", h, n), derive(k, h, b"B", h, 12))
    # The server's packets 0 to 2 in the clear, then, the strict exchange
    # having reset its numbers, 0 and 1 sealed.
    server = (V_S + b"\r\n" + plain_packet(i_s) + plain_packet(reply) + plain_packet(bytes([21]))
              + s2c.seal(0, bytes([6]) + string(b"ssh-userauth"))
              + s2c.seal(1, bytes([94]) + u32(0) + string(b"hello from the server\n")))
    # The client's: KEXINIT 0 and ECDH_INIT 1 (which the test checks too),
    # then NEWKEYS 2, and, reset, SERVICE_REQUEST 0.
    client = plain_packet(bytes([21])) + c2s.seal(0, bytes([5]) + string(b"ssh-userauth"))
    return server, client, k_s, h


def main():
    print("hostkey", exchange("chacha20-poly1305@openssh.com")[2].hex())
    print("client_start", (V_C + b"\r\n" + plain_packet(I_C)).hex())
    for tag, cipher in [("chacha", "chacha20-poly1305@openssh.com"), ("aes256", "aes256-gcm@openssh.com"),
                        ("aes128", "aes128-gcm@openssh.com")]:
        server, client, _, h = exchange(cipher)
        print(f"{tag}_server", server.hex())
        print(f"{tag}_client", client.hex())
        print(f"{tag}_h", h.hex())


if __name__ == "__main__":
    main()
