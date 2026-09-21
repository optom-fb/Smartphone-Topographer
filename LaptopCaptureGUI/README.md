# Placido Experiment Controller

A MATLAB app that remotely controls the CameraRecorder Android app
(`~/AndroidStudioProjects/CameraRecorder`) -- start/stop recording, change
frame rate -- and logs its LSL events to CSV files.

## Running it

From the `placido` directory (one level up):

```matlab
run_PlacidoExperimentController
```

That just adds this folder to the path and starts `PlacidoExperimentController`.
You can also `cd` into this folder and run `PlacidoExperimentController` directly.

## Files

| File | Purpose |
|---|---|
| `PlacidoExperimentController.m` | The GUI itself (MATLAB `classdef` app) |
| `lsl_recorder.py` | Subscribes to the phone's LSL streams and writes CSV logs (launched automatically by the GUI) |
| `ArduinoController.py` | Dummy Arduino-control server + console window, runnable on its own (see `ARDUINO_LIGHT_CONTROL_TODO.md`); the GUI spawns it if not already running and sends it START/ACQUIRE/RUNNING/STOP notifications |
| `ARDUINO_LIGHT_CONTROL_TODO.md` | Planning note for the not-yet-hardware-backed Arduino-control feature |

## Connecting to the phone

The GUI has two mutually exclusive ways of reaching the phone, picked with
the "Connection" dropdown:

### WiFi (HTTP)

Sends commands as a plain `GET` request to the phone's built-in HTTP
server (see the CameraRecorder Android app's own README for the server
side of this). The request URL is built from an editable template:

```
http://{ip}:{port}/?cmd={cmd}
```

- **IP address**: the phone's WiFi IP, shown on its screen when the app is
  open. This has to be reachable from the Mac -- if the phone is on a
  hotspot/router with client (AP) isolation enabled, direct WiFi
  connections between the Mac and phone will silently time out. A USB
  workaround in that case: `adb forward tcp:8080 tcp:8080`, then set the
  IP field to `127.0.0.1`.
- **Port**: `8080` by default.
- **URL format**: editable in case the app's HTTP server is ever changed.

### Bluetooth

Classic Bluetooth SPP, using MATLAB's `bluetooth()`/`bluetoothlist()`
(Instrument Control Toolbox). "Scan" lists paired/discoverable devices,
"Connect" opens a serial-style connection, and commands are sent as plain
text lines (`writeline`).

## Commands sent

Both connection modes send the exact same command strings; only the
transport differs.

| GUI action | Command sent | Effect on the phone |
|---|---|---|
| START button | `START` (or `START:<prefix>` if the prefix field is filled in) | Begins recording. File is named `<prefix>-<timestamp>.mp4` (or `CameraRecorder-<timestamp>.mp4` with no prefix), saved to `Movies/placido_data`. |
| STOP button | `STOP` | Ends the current recording. |
| "NORMAL (30fps)" radio | `NORMAL` | Standard capture: 30fps, highest quality. |
| "SLOW (120fps)" radio | `SLOW` | 120fps capture -- plays back as slow motion. |
| "SLOWER (240fps)" radio | `SLOWER` | 240fps capture (HD quality) -- plays back as slow motion. **Disabled in the GUI for now** (radio button present but not selectable). |

These three are a mutually-exclusive radio group (`ModeButtonGroup` in
`PlacidoExperimentController.m`), mirroring the phone's own capture state --
only one rate can be active at a time.

## Manual exposure control (not yet implemented on the phone)

The GUI has an Exposure switch (Auto/Manual) and a 1-10 slider, sending:

| GUI action | Command sent | Intended effect on the phone |
|---|---|---|
| Exposure switch -> Manual | `EXPOSURE:<n>` (current slider value, 1-10) | Disable auto-exposure (Camera2 `CONTROL_AE_MODE_OFF`) and apply a manual exposure level. |
| Exposure slider, while in Manual | `EXPOSURE:<n>` | Update the manual exposure level. |
| Exposure switch -> Auto | `AE_AUTO` | Re-enable auto-exposure (`CONTROL_AE_MODE_ON` or whichever auto mode the app normally uses). |

The `<n>` scale (1-10) is deliberately coarse and unit-less -- the phone app
maps each level to whatever `SENSOR_EXPOSURE_TIME` value makes sense for its
sensor and use case; the GUI doesn't assume nanoseconds, milliseconds, or
any particular range. **Neither `EXPOSURE:<n>` nor `AE_AUTO` is handled by
`MainActivity.handleCommand` yet** -- this is a command convention proposed
from the GUI side (see `PlacidoExperimentController.m`'s
`onExposureSwitchChanged`/`onExposureSliderChanged`), not a confirmed or
implemented protocol. Whoever implements this on the Android app is free to
renegotiate the exact command strings/scale if something else fits the
Camera2/CameraX integration better -- update both sides together if so.

The phone's HTTP server responds to each request with `OK: <command>`;
Bluetooth just receives the raw bytes with no reply. Either way, the GUI's
"Recording" lamp is a **best-effort local indicator** -- it reflects the
last command *this GUI* sent successfully, not a live status pushed back
from the phone, since neither transport has a persistent feedback channel
for that.

## Keeping the phone in sync with the GUI

There's no readback from the phone, so the GUI can't *verify* the phone
actually matches what's displayed -- only reduce the chance of drift by
re-sending its current state at points that matter:

- **At GUI startup** (`syncPhoneSettings`, called from the constructor):
  pushes the current mode radio selection and exposure switch/slider state,
  so the phone doesn't stay in whatever it was left in from a previous
  session.
- **Right before every recording starts** (same `syncPhoneSettings`, called
  from `onStartToggle`'s `'IDLE'` case): re-sends mode + exposure
  immediately before `START`, catching drift from an earlier radio/slider
  change that got missed (dropped packet, phone not listening yet, etc.).

All of this is still fire-and-forget, like every other command -- a failed
send is logged but never blocks recording. True verification (only
capturing if the phone confirms it actually matches) would need a real
status readback from the phone, which doesn't exist yet; see the Manual
exposure control section above for the same caveat.

## LSL event logging

Separately from the WiFi/Bluetooth command channel, the phone also
broadcasts two LSL streams continuously (regardless of which connection
mode is used for commands, since LSL runs over its own network protocol):

- **`CameraEvents`** (regular, 3x double64): `[frame_number,
  sensor_timestamp_ns, is_recording]`, pushed for every camera frame.
- **`CameraEvents_Markers`** (irregular, string): one sample per
  recording, carrying the video's filename, pushed the instant a
  recording starts (before the frame stream's `is_recording` flips to 1).

When the GUI launches, it auto-starts `lsl_recorder.py` in the background
(see its "LSL Event Logging" panel for the DATA directory, Python
interpreter, and a Start/Stop Logger toggle). For every filename marker it
receives, it creates a subdirectory of DATA named after that recording
(with a `_1`, `_2`, ... counter if the name's taken), and writes
`CameraServer.csv` inside it with every frame sample from that marker up
to the next one. The per-recording folder is deliberately generic so that
other future LSL streams (see `ARDUINO_LIGHT_CONTROL_TODO.md`) can drop
their own CSVs into the same folder.

Requires `pylsl` (`pip install pylsl`) and a working `liblsl` on the Mac
running this GUI -- on Apple Silicon Macs, pylsl's bundled binary doesn't
cover arm64, so `brew install labstreaminglayer/tap/lsl` is needed too;
on Windows/Intel Mac, `pip install pylsl` alone should be enough.

## Python setup

Two different Python scripts, two different requirements:

- **`lsl_recorder.py`** only needs `pylsl` (see above). No GUI, no
  extra Tk requirement.
- **`ArduinoController.py`** needs `pylsl`, `pyserial` (`pip install
  pyserial`; talks to the Arduino UNO over USB serial -- see
  `ARDUINO_LIGHT_CONTROL_TODO.md`), *and* a Python build with a working
  Tkinter (it pops up its own console window). This is where macOS has a
  real gotcha:

  Apple's bundled `/usr/bin/python3` ships **Tcl/Tk 8.5**, which is known
  to render blank and burn high CPU for Tkinter windows on modern macOS
  (this bit us during development -- the server ran and answered HTTP
  requests fine, but its window never displayed anything). Check which
  Tk version a given `python3` has:

  ```
  python3 -c "import tkinter; print(tkinter.TkVersion)"
  ```

  If that prints `8.5`, that Python isn't usable for `ArduinoController.py`'s
  window. Install Python from [python.org](https://www.python.org/downloads/mac-osx/)
  instead (bundles Tk 8.6+), then `pip install pylsl` for *that* Python
  specifically (it's a separate site-packages from the system one).

  `PlacidoExperimentController.m`'s `ensureArduinoServerRunning` already
  accounts for this: on Mac it prefers `/usr/local/bin/python3` (the
  python.org installer's typical symlink location) if present, falling
  back to plain `python3` otherwise. If your python.org install lives
  somewhere else, either symlink it there or edit that method directly.
  Windows python.org builds don't have this legacy-Tk problem, so no
  special handling is needed there.
