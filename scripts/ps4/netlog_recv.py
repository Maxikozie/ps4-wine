#!/usr/bin/env python3
"""UDP netlog receiver for logs.sh: prints every line of every datagram, line-buffered.

The title sends 512-byte datagrams (orbis-compat's netlog scheme) to this host on
PS4_NETLOG_PORT (default 18194). Usage: netlog_recv.py PORT
"""
import socket
import sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 18194
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(("0.0.0.0", port))
except OSError as exc:
    print(f"[logs.sh] cannot bind UDP {port}: {exc}", flush=True)
    sys.exit(2)
while True:
    data, _addr = sock.recvfrom(65535)
    for line in data.decode("utf-8", "replace").splitlines():
        if line:
            print(line, flush=True)
