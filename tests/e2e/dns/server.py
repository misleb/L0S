#!/usr/bin/env python3
# server.py PORT -- a small DNS server for the e2e case dns, on the
# host's loopback, UDP, which the board reaches as 10.0.2.2 through QEMU's
# user network. It answers A queries from a fixed table: l0s.test is
# 10.9.8.7; alias.l0s.test is a CNAME of it, answered with both records,
# the A after the CNAME, as a recursive server does; mail.l0s.test has
# only an MX record, so no address; anything else has no such name.
import socket
import struct
import sys

ADDRS = {"l0s.test": "10.9.8.7"}
CNAMES = {"alias.l0s.test": "l0s.test"}
MX_ONLY = {"mail.l0s.test"}


def name_bytes(name):
    return b"".join(bytes([len(label)]) + label.encode() for label in name.split(".")) + b"\0"


def read_name(msg, i):
    labels = []
    while msg[i]:
        labels.append(msg[i + 1 : i + 1 + msg[i]].decode())
        i += 1 + msg[i]
    return ".".join(labels), i + 1


def record(name, rtype, rdata):
    return name_bytes(name) + struct.pack(">HHIH", rtype, 1, 60, len(rdata)) + rdata


def answer(query):
    qid, flags = struct.unpack(">HH", query[:4])
    name, end = read_name(query, 12)
    question = query[12 : end + 4]
    records = []
    rcode = 0
    if name in CNAMES:
        target = CNAMES[name]
        records.append(record(name, 5, name_bytes(target)))
        records.append(record(target, 1, socket.inet_aton(ADDRS[target])))
    elif name in ADDRS:
        records.append(record(name, 1, socket.inet_aton(ADDRS[name])))
    elif name in MX_ONLY:
        records.append(record(name, 15, struct.pack(">H", 10) + name_bytes(name)))
    else:
        rcode = 3
    header = struct.pack(">HHHHHH", qid, 0x8180 | rcode, 1, len(records), 0, 0)
    return header + question + b"".join(records)


if __name__ == "__main__":
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", int(sys.argv[1])))
    while True:
        query, peer = s.recvfrom(512)
        try:
            s.sendto(answer(query), peer)
        except (IndexError, struct.error):
            pass
