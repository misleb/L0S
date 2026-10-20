#!/usr/bin/env python3
# server.py PORT -- a small HTTP/1.0 server for the e2e case http, on the
# host's loopback, which the board reaches as 10.0.2.2 through QEMU's user
# network. Its answers are fixed, with no Date or Server header, so that
# the case's expected output is too: /hello.txt, /big (300 lines of 64
# bytes, more than a window holds), and a 404 for anything else. Each
# answer is a header, an empty line, the body, and then the connection
# closes, as HTTP/1.0 has it.
import socketserver
import sys


def big():
    return "".join("line %03d of 300, 64 bytes each: windowed, segmented, in order\n" % i for i in range(1, 301)).encode()


PAGES = {
    "/hello.txt": b"hello from the host\n",
    "/big": big(),
}


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        request = self.rfile.readline().decode("latin-1").split()
        while self.rfile.readline() not in (b"\r\n", b"\n", b""):
            pass
        path = request[1] if len(request) > 1 else "/"
        if path in PAGES:
            body, status = PAGES[path], "200 OK"
        else:
            body, status = b"no such page\n", "404 Not Found"
        self.wfile.write(
            ("HTTP/1.0 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\n\r\n" % (status, len(body))).encode() + body
        )


class Server(socketserver.TCPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    with Server(("127.0.0.1", int(sys.argv[1])), Handler) as server:
        server.serve_forever()
