#!/usr/bin/env python3
"""Disposable TCP/HTTP peers for ucitest; serves fixed test bytes, never files."""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import socketserver
import threading


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(5)
        payload = self.request.recv(1024)
        if payload:
            self.request.sendall(payload)


class UDP(socketserver.BaseRequestHandler):
    def handle(self):
        _, sock = self.request
        sock.sendto(b"0123456789abcdef", self.client_address)


class HTTP(BaseHTTPRequestHandler):
    def do_GET(self):
        status = 200 if self.path.lower() == "/hello" else 404
        body = b"ultimate sdk test peer\n"
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", required=True, help="this host's LAN address")
    args = parser.parse_args()
    with socketserver.TCPServer((args.bind, 6464), Echo) as tcp, \
            socketserver.UDPServer((args.bind, 6464), UDP) as udp, \
            HTTPServer((args.bind, 8099), HTTP) as http:
        threading.Thread(target=tcp.serve_forever, daemon=True).start()
        threading.Thread(target=udp.serve_forever, daemon=True).start()
        print(f"NET_PEER={args.bind}:6464 HTTP_PEER={args.bind}:8099", flush=True)
        try:
            http.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            tcp.shutdown()
