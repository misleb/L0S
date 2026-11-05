#!/usr/bin/env python3
# server.py PORT -- a small HTTPS server for the e2e case https, TLS 1.3
# only, on the host's loopback, which the board reaches as 10.0.2.2
# through QEMU's user network. Its certificate (cert.pem, key.pem) is a
# P-256 key for the address 10.0.2.2, signed by the case's own RSA test
# CA, which is the board's one root (etc/ssl/roots.pem); both are made
# for this test only and valid to 2046. Its answers are fixed, with no
# Date or Server header, so that the case's expected output is too:
#
#   /hello.txt     a line, with Content-Length
#   /big           300 lines of 64 bytes, several TLS records
#   POST /echo     {"got": BODY, "length": N}, the body read as JSON
#
# and a 404 for anything else. A connection is kept for the next request
# until the client closes it.
import json
import os
import socketserver
import ssl
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def big():
    return "".join("line %03d of 300, 64 bytes each: sealed, record by record\n" % i for i in range(1, 301)).encode()


PAGES = {
    "/hello.txt": b"hello over TLS\n",
    "/big": big(),
}


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            while self.answer():
                pass
        except (ssl.SSLError, ConnectionError):
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
        elif path in PAGES:
            self.whole("200 OK", "text/plain", PAGES[path])
        else:
            self.whole("404 Not Found", "text/plain", b"no such page\n")
        self.wfile.flush()
        return True

    def whole(self, status, ctype, body):
        self.wfile.write(
            ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n\r\n" % (status, ctype, len(body))).encode() + body
        )


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def get_request(self):
        sock, addr = super().get_request()
        return CONTEXT.wrap_socket(sock, server_side=True), addr


CONTEXT = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
CONTEXT.minimum_version = ssl.TLSVersion.TLSv1_3
CONTEXT.load_cert_chain(os.path.join(HERE, "cert.pem"), os.path.join(HERE, "key.pem"))

if __name__ == "__main__":
    with Server(("127.0.0.1", int(sys.argv[1])), Handler) as server:
        server.serve_forever()
