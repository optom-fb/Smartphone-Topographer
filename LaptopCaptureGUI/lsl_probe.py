#!/usr/bin/env python3
"""Probe the LSL TCP server directly with a raw socket.

Creates an outlet, resolves it, prints the exact address/port the resolver
advertises, then speaks the LSL protocol ("LSL:fullinfo") over a raw TCP
socket to see whether the outlet's server answers correctly.
"""

import re
import socket
import time

import pylsl

name = f"Probe_{int(time.time())}"
info = pylsl.StreamInfo(name, "Markers", 1, 0, pylsl.cf_string, f"uid_{name}")
outlet = pylsl.StreamOutlet(info)
print(f"Outlet created: {name}")

streams = pylsl.resolve_byprop("name", name, timeout=5.0)
if not streams:
    raise SystemExit("could not resolve own stream")

xml = streams[0].as_xml()
print("---- resolved shortinfo XML ----")
print(xml)
print("--------------------------------")

def tag(t):
    m = re.search(rf"<{t}>([^<]*)</{t}>", xml)
    return m.group(1) if m else None

v4addr = tag("v4address") or "127.0.0.1"
v4port = tag("v4data_port") or tag("v4service_port") or "16572"
print(f"Advertised v4address={tag('v4address')!r} data_port={tag('v4data_port')!r} service_port={tag('v4service_port')!r} hostname={tag('hostname')!r}")

hostname = tag("hostname")
if hostname:
    try:
        infos = socket.getaddrinfo(hostname, int(v4port))
        print(f"\n{hostname!r} resolves to: {sorted({i[4][0] for i in infos})}")
    except Exception as e:
        print(f"\n[FAIL] cannot resolve hostname {hostname!r}: {e}")

for host in [hostname, v4addr, "127.0.0.1"]:
    if not host:
        continue
    try:
        print(f"\nConnecting raw socket to {host}:{v4port} ...")
        s = socket.create_connection((host, int(v4port)), timeout=5.0)
        s.sendall(b"LSL:fullinfo\r\n")
        s.settimeout(5.0)
        data = b""
        try:
            while len(data) < 2000:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
        except socket.timeout:
            pass
        s.close()
        if data:
            print(f"[PASS] server replied ({len(data)} bytes). First 300:")
            print(data[:300])
        else:
            print("[FAIL] connected, but server sent nothing / closed the connection")
    except Exception as e:
        print(f"[FAIL] {type(e).__name__}: {e}")
