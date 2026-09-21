# LSL / pylsl debugging notes — 2026-07-14

Symptom: `lsl_recorder.py` produced no output (no CSVs in DATA), and it was
unclear whether pylsl worked on this PC (BN448487) at all.

## What was found

1. **pylsl works on this machine.** Verified with `lsl_selftest.py` (import →
   outlet → discovery → sample round-trip). Early failures at the round-trip
   stage turned out to be a first-connection race: the first data connection
   sometimes breaks and liblsl's retry recovers within ~1 s. With a 30 s
   window the test passes consistently. pylsl 1.18.2 / liblsl 1.17.7.

2. **The Anaconda base python was the launch environment problem.** The bare
   `python` on PATH is Anaconda base (3.10.9); tests run from it failed where
   emava's venv passed. A dedicated venv was created at
   `CameraRecorderGUI\.venv` (built from the same Python 3.13 base as emava's)
   and passes the self-test reliably.

3. **Firewall rules were added** (admin, may or may not have been strictly
   necessary, but required for phone streams regardless):
   `LSL TCP` in/allow TCP 16572-16604, `LSL UDP` in/allow UDP 16571-16604.

4. **University network:** phone streams never resolved there (expected:
   client isolation / blocked multicast). Untested beyond that — private
   router is the working setup.

5. **Private router works.** `lsl_list.py` saw the phone's streams
   (`CameraEvents_Markers`, `CameraEvents`) from the PC. The remaining
   failure was a stale phone IP (192.168.1.100 vs actual 192.168.0.106)
   baked in at logger start, plus the logger dying after its 30 s resolve
   timeout before the phone was ready.

6. **Unresolved:** the CameraRecorder Android app froze once mid-recording
   (on the uni network, while its LSL consumer connection was stalling).
   Watch whether it recurs on the router with working streams.

## Changes made

`PlacidoExperimentController.m`
- Python field auto-fills with `.venv\Scripts\python.exe` when present
  (`defaultPythonExe`); ArduinoController.py now uses the same interpreter
  instead of hardcoded `python`.
- At logger start, `lsl_api.cfg` is regenerated next to `lsl_recorder.py`
  with `KnownPeers = {phone IP}` (unicast discovery — needed where multicast
  is blocked), and the recorder is spawned with that folder as its working
  directory so liblsl actually loads the file.
- Changing the phone IP field auto-restarts the logger (the IP is baked into
  the cfg at start, so edits didn't take effect before).
- IP field default updated to 192.168.0.106.

`lsl_recorder.py`
- Required streams now retry resolution forever instead of exiting after
  30 s, so the logger survives being started before the phone app.

## Helper scripts (keep or delete freely)

- `lsl_selftest.py` — 4-stage local pylsl check (import/outlet/resolve/data)
- `lsl_list.py` — lists every LSL stream visible on the network
- `lsl_probe.py`, `tcp_loopback_test.py` — one-off diagnostics, safe to delete

## Normal operation checklist

1. Phone + PC on the private router; phone IP in the GUI's IP field
2. Launch controller; activity log should show `KnownPeers = {…}`
3. `DATA/lsl_recorder.log` says "Found marker stream" once the phone app is up
4. Each recording creates `DATA/<video name>/CameraServer.csv` (+ Arduino.csv)
