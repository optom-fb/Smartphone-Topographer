#!/usr/bin/env python3
"""List every LSL stream visible from this machine (any name, any host)."""

import pylsl

print("Scanning for ALL LSL streams (10 s)...")
streams = pylsl.resolve_streams(wait_time=10.0)
if not streams:
    print("No streams found at all.")
else:
    for s in streams:
        print(f"  name={s.name()!r}  type={s.type()!r}  host={s.hostname()!r}  "
              f"channels={s.channel_count()}  srate={s.nominal_srate()}")
print("Done.")
