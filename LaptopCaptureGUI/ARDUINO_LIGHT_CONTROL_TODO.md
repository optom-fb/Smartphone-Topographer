# Arduino UNO light control

## Goal
An Arduino UNO controls a light via its own program. The same on/off
signal driving the light is "split off" to LSL as its own event stream, so
light state is recorded alongside camera and (future) other LSL streams.

## Hardware
- Arduino UNO, driving the light through a MOSFET gated by pin 3 (not the
  light directly). See `LightController/LightController.ino`.
- **There is no phone/CameraRecorder link to the Uno.** The Android app
  (CameraRecorder) is not involved in driving the light. `ArduinoController.py`
  is the "something" that sends commands to the Uno and pushes the matching
  LSL event, running as its own independent process (started/stopped by
  `PlacidoExperimentController.m`, but not otherwise controlled by it).
- Three phases, implemented in `LightController.ino` as single-char serial
  commands (9600 baud):
  - **ARM** (`'A'`): light solid on.
  - **ACQUIRE** (`'Q'`): flashes *indefinitely* -- one 30fps frame on, one
    frame off (so each captured frame is fully lit or fully dark), which is
    an actual flash frequency of ~15Hz, not 30Hz -- until stopped. Pressing
    SPACE in `ArduinoController.py`'s console (GUI or
    headless) during ACQUIRE sends **OFF** (`'O'`), killing the light --
    this is the operator's way to end a flash sequence right now.
  - **OFF** (`'O'`): light off (zero).

  The firmware also supports a **SETTLE** (`'S'`) command (stop flashing,
  go solid instead of off) via `settle_light()` in `ArduinoController.py`,
  but nothing currently sends it -- SPACE sends OFF, not SETTLE. Kept as a
  ready-to-wire-up option if a "flash then hold solid" behavior is wanted
  later instead of "flash then off".
- LSL: the `ArduinoControl` stream is pushed at the same instant a command
  is sent to the Uno, logged into the same per-recording directory
  structure that `lsl_recorder.py` already creates (`Arduino.csv` alongside
  `CameraServer.csv`), using the existing `CameraEvents_Markers`-driven
  folder-per-recording mechanism.

## ArduinoController.py
The "something" that drives the Uno + pushes to LSL is `ArduinoController.py`
(same folder as `PlacidoExperimentController.m`). It's meant to be run on its
own, however you like -- its own terminal, its own launcher, whatever -- and
pops up its own Tkinter console window showing every command it receives
live (`--no-gui` runs headless with plain stdout logging instead, e.g. for
scripted testing). Requires `pyserial` (`pip install pyserial`) in addition
to `pylsl`.

On startup it auto-detects the Uno's serial port (matching common
Arduino/CH340 USB descriptors) unless `--serial-port` is given explicitly.
If no Arduino is found, or the serial write fails, that's logged and
everything else (HTTP + LSL) keeps working -- same as the original dummy
placeholder's behavior when nothing is listening on the wire.

HTTP command -> Uno mapping (`HTTP_TO_SERIAL_COMMAND` in
`ArduinoController.py`):

| HTTP `?cmd=` | Sent when | Uno command |
|---|---|---|
| `START` | first button press (phone recording starts) | `'A'` ARM |
| `ACQUIRE` | second button press | `'Q'` ACQUIRE (starts flashing) |
| `RUNNING` | third button press | *(no serial command)* |
| `STOP` | third button press, right after RUNNING | `'O'` OFF |
| *(SPACE in this server's console)* | manual, any time | `'O'` OFF |

**Relationship to `PlacidoExperimentController` (revised from the original
"fully independent" plan)**: it's independent in the sense that it's a
separate process with its own window and its own LSL push, and it works
fine run entirely on its own with nothing else running. But
`PlacidoExperimentController` does now interact with it in two ways:
1. **Lifecycle**: on startup it spawns `ArduinoController.py` only if
   nothing's already listening on its port, and only ever kills the
   instance it spawned itself (never one that was already running).
2. **Commands**: pressing the record button sends it a matching
   notification at each step -- `START` (recording started on the phone),
   `ACQUIRE` (local UI transition), `RUNNING` (local UI transition), `STOP`
   (recording stopped) -- via the same `?cmd=` HTTP convention as the
   phone. These are fire-and-forget/best-effort; a failure to reach it
   never blocks or breaks the actual recording flow.

`lsl_recorder.py` already has a corresponding optional third inlet for
`ArduinoControl`, writing `Arduino.csv` into the same per-recording
directory as `CameraServer.csv` (keyed off the same `CameraEvents_Markers`
filename marker), so the logging side is done.

**Python/Tk gotcha (macOS)**: `ArduinoController.py` needs a Python with a
*working* Tkinter, and Apple's bundled `/usr/bin/python3` has Tcl/Tk 8.5,
which renders blank and burns CPU on modern macOS instead of showing the
console window (found this the hard way -- the server answered HTTP
requests fine the whole time, the window just never displayed anything).
`ensureArduinoServerRunning` in `PlacidoExperimentController.m` now prefers
`/usr/local/bin/python3` (python.org's installer) if present. See the main
`README.md`'s "Python setup" section for the full explanation and how to
check/fix this on a new machine.

## Verified against real hardware (2026-07-14)
Uno on COM6, MOSFET on pin 3. Ran `test_light_sequence.py --serial-port
COM6` (ARM -> ACQUIRE -> OFF, 2s each, 5 cycles) and visually confirmed
correct behavior each cycle: solid on, then flashing, then off. Confirms
`lightOn()`/`lightOff()`'s HIGH=on/LOW=off polarity assumption is correct
for this wiring (no swap needed).

That first pass only confirmed *that* it flashes, not the exact rate --
`FLASH_HALF_PERIOD_MS` was 17 (giving ~29.4Hz, a full flash cycle roughly
once per frame) when originally written from a loose "~30fps/50% duty"
description. Corrected to 33 (one 30fps frame on, one frame off -- the
actual intended meaning: each captured frame fully lit or fully dark, ~15Hz
real flash frequency). Not yet re-verified visually against hardware since
the correction -- worth confirming the flash looks right (and re-timing it
with a camera/scope if the exact frequency matters) next time the Uno's
connected.

One gotcha hit along the way, not a code bug: after ad-hoc testing (GUI-mode
`ArduinoController.py`, manual serial commands), the light could be left
solid on or mid-flash with nothing connected to COM6 to turn it off --
because whatever last sent a command had already exited. Unplugging the
Uno (power-cycle -> `setup()` calls `lightOff()`) or manually sending `'O'`
both clear it. Not a bug to fix, just a reminder: the light stays in
whatever state it was last commanded into until something sends another
command -- there's no watchdog/timeout that turns it off on its own.

## Open questions
1. ARM timing spec beyond "solid on" -- none yet.
2. Auto-detect (`find_arduino_port` in `ArduinoController.py`) hasn't been
   tested with multiple serial devices plugged in at once -- only
   confirmed working via explicit `--serial-port COM6` so far.
3. OFF -- likely just "zero", probably no further spec needed.

## Related existing code
- `lsl_recorder.py` -- CameraEvents logger; already has the optional
  `ArduinoControl` inlet + `Arduino.csv` output described above.
- `ArduinoController.py` -- the HTTP+LSL+console-window server described
  above; talks to the Uno over serial when one's connected, degrades to
  logging/LSL-only otherwise. Independent process; run it however you like.
- `LightController/LightController.ino` -- the Uno-side firmware: a tiny
  non-blocking state machine reacting to `'A'`/`'Q'`/`'S'`/`'O'` over serial.
- `PlacidoExperimentController.m` -- MATLAB camera controller; manages
  `ArduinoController.py`'s lifecycle (spawn-if-not-running,
  kill-if-owned) and sends it START/ACQUIRE/RUNNING/STOP notifications
  from the record button, as described above.
