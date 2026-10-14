#!/usr/bin/env python3
"""Repository stand-ins on a loopback port for the zypper-packages scenario scripts.

The scripts install python3 in the test container and start this file there, so that a check of a timeout or of
a retry never depends on a public mirror being slow or broken. Standard library only.

  fixture_server.py failing <port> <log>
      Answers every request with status 500 and appends "<METHOD> <path>" to <log>.
  fixture_server.py stalling <port> <log>
      Accepts every connection, appends the time it did so, in seconds since the epoch, to <log>, and never
      sends a byte.
  fixture_server.py silent <port>
      Listens without accepting and fills its own queue, so that later connection attempts get no answer.
  fixture_server.py slow <port> <directory> <seconds>
      Serves the files under <directory>. A request for a path ending in .rpm gets the file of that name in
      <directory>/packages, sent in <seconds> pieces one second apart.
"""

import http.server
import pathlib
import socket
import sys
import time

ADDRESS = "127.0.0.1"


class FailingHandler(http.server.BaseHTTPRequestHandler):
    """Logs the request line's method and path, then answers 500."""

    log_path = ""

    def answer(self):
        with open(self.log_path, "a", encoding="ascii") as log:
            log.write(f"{self.command} {self.path}\n")
        self.send_response(500)
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()

    do_GET = answer
    do_HEAD = answer
    do_CONNECT = answer

    def log_message(self, format, *args):
        pass


class SlowHandler(http.server.SimpleHTTPRequestHandler):
    """Serves a directory; a package file is sent in pieces one second apart."""

    packages = pathlib.Path()
    pieces = 1

    def do_GET(self):
        if not self.path.endswith(".rpm"):
            super().do_GET()
            return
        content = (self.packages / pathlib.PurePosixPath(self.path).name).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/x-rpm")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        size = len(content) // self.pieces + 1
        for start in range(0, len(content), size):
            self.wfile.write(content[start : start + size])
            self.wfile.flush()
            time.sleep(1)

    def do_HEAD(self):
        if not self.path.endswith(".rpm"):
            super().do_HEAD()
            return
        size = (self.packages / pathlib.PurePosixPath(self.path).name).stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/x-rpm")
        self.send_header("Content-Length", str(size))
        self.end_headers()

    def log_message(self, format, *args):
        pass


def serve_failing(port, log_path):
    FailingHandler.log_path = log_path
    http.server.ThreadingHTTPServer((ADDRESS, port), FailingHandler).serve_forever()


def serve_stalling(port, log_path):
    listener = socket.create_server((ADDRESS, port))
    connections = []
    while True:
        connection, _ = listener.accept()
        with open(log_path, "a", encoding="ascii") as log:
            log.write(f"{int(time.time())}\n")
        # Kept open and never answered.
        connections.append(connection)


def serve_silent(port):
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((ADDRESS, port))
    listener.listen(0)
    # The kernel completes connections until the queue is full and then drops further attempts unanswered. These
    # connections fill it and are kept open; the ones that no longer complete are the proof that it is full.
    fillers = []
    for _ in range(8):
        filler = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        filler.setblocking(False)
        filler.connect_ex((ADDRESS, port))
        fillers.append(filler)
    while True:
        time.sleep(3600)


def serve_slow(port, directory, seconds):
    root = pathlib.Path(directory)
    SlowHandler.packages = root / "packages"
    SlowHandler.pieces = seconds

    def handler(*args):
        return SlowHandler(*args, directory=str(root))

    http.server.ThreadingHTTPServer((ADDRESS, port), handler).serve_forever()


def main(arguments):
    mode = arguments[0]
    port = int(arguments[1])
    if mode == "failing":
        serve_failing(port, arguments[2])
    elif mode == "stalling":
        serve_stalling(port, arguments[2])
    elif mode == "silent":
        serve_silent(port)
    elif mode == "slow":
        serve_slow(port, arguments[2], int(arguments[3]))
    else:
        sys.exit(f"unknown mode {mode}")


if __name__ == "__main__":
    main(sys.argv[1:])
