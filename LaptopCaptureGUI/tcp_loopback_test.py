#!/usr/bin/env python3
"""Raw TCP test, no LSL: can this machine connect to itself on the LSL ports?

Tests both 127.0.0.1 and the machine's own LAN IP -- LSL connects via the
latter, so if loopback passes but LAN-IP fails, a firewall/AV rule is
blocking python.exe on real interfaces.
"""

import socket
import threading

PORT = 16573

def try_pair(host):
    try:
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((host, PORT))
        srv.listen(1)
        srv.settimeout(5.0)

        result = {}
        def accept():
            try:
                conn, _ = srv.accept()
                result["data"] = conn.recv(16)
                conn.close()
            except Exception as e:
                result["err"] = e
        t = threading.Thread(target=accept)
        t.start()

        cli = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        cli.settimeout(5.0)
        cli.connect((host, PORT))
        cli.sendall(b"ping")
        cli.close()
        t.join(6.0)
        srv.close()

        if result.get("data") == b"ping":
            print(f"[PASS] TCP self-connection via {host}:{PORT}")
        else:
            print(f"[FAIL] {host}:{PORT} -- connected but no data ({result.get('err')})")
    except Exception as e:
        print(f"[FAIL] TCP self-connection via {host}:{PORT} -- {type(e).__name__}: {e}")

print("Hostname:", socket.gethostname())
addrs = {"127.0.0.1"}
try:
    for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
        addrs.add(info[4][0])
except Exception as e:
    print("Could not enumerate LAN IPs:", e)

for host in sorted(addrs):
    try_pair(host)
