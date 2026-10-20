#!/usr/bin/env python3
# peer.py PORT -- the host's end of the e2e case net_echo: connects to
# PORT on the loopback, which QEMU forwards to port 7000 of the board,
# sends a message of 12000 bytes, closes its sending end, and reads until
# the board closes its own. It exits 0 if what came back is what it sent.
# The board may not be listening yet, when QEMU accepts the connection and
# then drops it; so it tries again, for 50 seconds.
import socket
import sys
import time

port = int(sys.argv[1])
message = b"hello over tcp\n" + bytes((i * 7) % 251 for i in range(12000))
deadline = time.time() + 50
while time.time() < deadline:
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=2)
        s.sendall(message)
        s.shutdown(socket.SHUT_WR)
        s.settimeout(15)
        got = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            got += chunk
        s.close()
        if got == message:
            sys.exit(0)
        if got:
            print("what came back differs: %d bytes of %d" % (len(got), len(message)))
            sys.exit(1)
    except OSError as e:
        print("try again:", e)
    time.sleep(0.5)
print("no connection was served")
sys.exit(1)
