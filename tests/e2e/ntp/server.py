#!/usr/bin/env python3
# server.py PORT -- a stand-in SNTP server for the e2e case ntp, on the
# host's loopback, UDP, which the board reaches as 10.0.2.2 through QEMU's
# user network. It answers every client's request (mode 3) as a server
# at stratum 2 would (RFC 4330): mode 4, the request's transmit timestamp
# copied into the origin, and a transmit time that is always 2030-01-01
# 12:00:00 UTC, so the case knows what the clock is set to.
import socket
import struct
import sys

# 2030-01-01 12:00:00 UTC: Unix 1893499200, and NTP's seconds from 1900.
NTP_TIME = 1893499200 + 2208988800


def answer(request):
    if len(request) < 48 or request[0] & 7 != 3:
        return None
    origin = request[40:48]
    head = struct.pack(">BBbbII4s", 0x24, 2, 6, -20, 0, 0, b"GPS.")
    reference = struct.pack(">II", NTP_TIME, 0)
    received = struct.pack(">II", NTP_TIME, 0)
    sent = struct.pack(">II", NTP_TIME, 0)
    return head + reference + origin + received + sent


if __name__ == "__main__":
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", int(sys.argv[1])))
    while True:
        request, peer = s.recvfrom(512)
        reply = answer(request)
        if reply is not None:
            s.sendto(reply, peer)
