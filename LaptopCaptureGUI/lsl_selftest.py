#!/usr/bin/env python3
"""pylsl self-test: verifies install, outlet creation, discovery, and data flow.

Run:  python lsl_selftest.py
All four stages PASS -> pylsl itself is fine; if lsl_recorder.py still finds
nothing, the problem is network discovery (firewall / phone on different
subnet), not pylsl.
"""

import sys
import time

def fail(stage, exc):
    print(f"[FAIL] {stage}: {exc}")
    sys.exit(1)

# Stage 1: import + library
try:
    import pylsl
    ver = pylsl.library_version()
    print(f"[PASS] import pylsl (pylsl {pylsl.__version__}, liblsl {ver//100}.{ver%100})")
    print(f"       liblsl info: {pylsl.library_info()}")
except Exception as e:
    fail("import pylsl -- is it installed? try: pip install pylsl", e)

# Stage 2: create outlet (unique name per run, so stale/zombie outlets from
# previous runs can't be mistaken for this one)
name = f"SelfTest_{int(time.time())}"
try:
    info = pylsl.StreamInfo(name, "Markers", 1, 0, pylsl.cf_string, f"uid_{name}")
    outlet = pylsl.StreamOutlet(info)
    print(f"[PASS] StreamOutlet created ({name})")
except Exception as e:
    fail("StreamOutlet creation", e)

# Stage 3: resolve own stream (loopback discovery)
try:
    streams = pylsl.resolve_byprop("name", name, timeout=5.0)
    for s in streams:
        print(f"       resolved: name={s.name()!r} host={s.hostname()!r} uid={s.uid()!r}")
    if not streams:
        print("[FAIL] resolve: outlet exists but was not discovered on loopback.")
        print("       This is almost always Windows Firewall blocking UDP multicast")
        print("       for python.exe. Allow Python through the firewall (private")
        print("       networks) and retry.")
        sys.exit(1)
    print("[PASS] stream resolved via network discovery")
except Exception as e:
    fail("resolve_byprop", e)

# Stage 4: pull a sample end-to-end. Push repeatedly and allow up to 30 s so
# a broken first connection + liblsl's retry loop still gets a chance -- we
# want to know if data EVENTUALLY flows, and how long it took.
try:
    inlet = pylsl.StreamInlet(streams[0])
    t0 = time.time()
    sample = None
    while time.time() - t0 < 30.0:
        outlet.push_sample([f"hello_{int((time.time()-t0)*10)}"])
        sample, ts = inlet.pull_sample(timeout=1.0)
        if sample is not None:
            break
    elapsed = time.time() - t0
    if sample is None:
        print(f"[FAIL] no data received within {elapsed:.0f} s (TCP data path blocked?)")
        sys.exit(1)
    print(f"[PASS] sample round-trip: {sample[0]!r} after {elapsed:.1f} s")
except Exception as e:
    fail("data transfer", e)

print("\nAll stages passed -- pylsl is working on this machine.")
print("If lsl_recorder.py still can't find the phone's streams, check that the")
print("phone and PC are on the same Wi-Fi/subnet and the firewall allows LSL")
print("(UDP 16571 + TCP/UDP 16572-16604).")
