#!/usr/bin/env python3
# server.py PORT -- a small HTTP/1.1 server for the e2e case http, on the
# host's loopback, which the board reaches as 10.0.2.2 through QEMU's user
# network. Its answers are fixed, with no Date or Server header, so that
# the case's expected output is too:
#
#   /hello.txt     a line, with Content-Length
#   /big           300 lines of 64 bytes, more than a window holds
#   /chunked       lines in chunks, each its own, with a trailer
#   POST /echo     {"got": BODY, "length": N}, the body read as JSON
#   /events        an event stream: three events 200 ms apart, a comment
#                  between, and the stream held open 2 s after the last
#
# and a 404 for anything else. A connection is kept for the next request
# until the client closes it, as HTTP/1.1 has it.
import json
import socketserver
import sys
import time


def big():
    return "".join("line %03d of 300, 64 bytes each: windowed, segmented, in order\n" % i for i in range(1, 301)).encode()


PAGES = {
    "/hello.txt": b"hello from the host\n",
    "/big": big(),
}

CHUNKS = [b"chunks come\n", b"one by one,\n", b"each its own size\n"]

EVENTS = [
    b"event: greeting\ndata: hello\n\n",
    b": a comment, between events\n\n",
    b"event: tick\ndata: {\"n\": 2}\n\n",
    b"data: the last\ndata: of three\n\n",
]


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        while self.answer():
            pass

    # Reads one request and answers it: whether the connection goes on.
    def answer(self):
        line = self.rfile.readline()
        if not line:
            return False
        request = line.decode("latin-1").split()
        headers = {}
        while True:
            h = self.rfile.readline()
            if h in (b"\r\n", b"\n", b""):
                break
            name, _, value = h.decode("latin-1").partition(":")
            headers[name.strip().lower()] = value.strip()
        method = request[0] if request else "GET"
        path = request[1] if len(request) > 1 else "/"
        body = self.rfile.read(int(headers.get("content-length", "0")))
        if method == "POST" and path == "/echo":
            self.whole("200 OK", "application/json",
                       json.dumps({"got": json.loads(body), "length": len(body)}).encode())
        elif path == "/chunked":
            self.chunked()
        elif path == "/events":
            self.events()
        elif path in PAGES:
            self.whole("200 OK", "text/plain", PAGES[path])
        else:
            self.whole("404 Not Found", "text/plain", b"no such page\n")
        return True

    def whole(self, status, ctype, body):
        self.wfile.write(
            ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n\r\n" % (status, ctype, len(body))).encode() + body
        )

    def chunked(self):
        self.wfile.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n")
        for c in CHUNKS:
            self.wfile.write(b"%x;piece\r\n%s\r\n" % (len(c), c))
            self.wfile.flush()
        self.wfile.write(b"0\r\nX-Trailer: dropped\r\n\r\n")

    def events(self):
        self.wfile.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
        for e in EVENTS:
            self.wfile.write(b"%x\r\n%s\r\n" % (len(e), e))
            self.wfile.flush()
            time.sleep(0.2)
        time.sleep(2)
        self.wfile.write(b"0\r\n\r\n")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", int(sys.argv[1])), Handler) as server:
        server.serve_forever()
