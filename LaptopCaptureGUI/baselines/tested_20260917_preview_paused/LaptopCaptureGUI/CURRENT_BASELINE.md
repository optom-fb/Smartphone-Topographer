# Fixed acquisition baseline — 17 September 2026

Baseline ID: `tested_20260917_preview_paused`.

This is the current agreed acquisition version. Preserve its behaviour unless
the author explicitly requests a change. An archived source snapshot and
SHA-256 manifest are stored in `baselines/tested_20260917_preview_paused/`.
This is a documented software baseline, not a filesystem or camera-driver lock.

## Fixed behaviour

- One laptop GUI selects external USB camera or USB-connected CameraRecorder.
- External bench configuration: USB Camera, `MJPG_1920x1080`, AVI playback
  rate 30 frames/s; Arduino COM7, 9600 baud, illumination output D3.
- External preview is available for alignment and pauses during recording;
  the last alignment image remains displayed. Preview resumes afterward.
- Pre-recording white OFF command and 0.15 s nominal pause; timed protocol:
  white OFF 0–3 s, solid ON 3–8 s, five alternating 0.5 s OFF/ON pairs 8–13 s,
  then explicit OFF. Camera IR is not controlled by this sequence.
- The 250 ms host-command lateness guard remains active. Incomplete runs
  retain failure metadata and are excluded from normal candidate extraction.
- Save roots: `Data/GUI Data/EXT_Camera` and `Data/GUI Data/Smart_Phone`.
- Phone preview remains on the phone; automatic video and log transfer is
  retained. Firmware and nominal shared protocol remain unchanged.

## Accepted external bench run

Run: `Data/GUI Data/EXT_Camera/Test/ExternalBench/USB_external_preview_paused_ext_20260917_175609_077`.

The GUI reports completion, 392 acquired and 392 written frames, resumed
preview and final OFF cleanup. The timing CSV records all protocol events;
maximum logged host-command lateness is 0.0775322 s. The author subsequently
confirmed that solid illumination and blinking both worked and accepted this
version as fixed for now. This observation is documented here without changing
the original run files.

This acceptance is a functional bench observation. It does not establish
frame-level physical LED timing, hardware synchronisation, locked exposure,
calibrated corneal measurements, optical safety or clinical validation.
The earlier successful phone test remains separate evidence; the phone
backend was not rerun during this external-camera acceptance test.

## Reproducibility

Archive copies preserve relative project paths and include the GUI, phone
client, protocol, location resolver, regression tests and Arduino firmware.
Verify their SHA-256 hashes against `SHA256_MANIFEST.csv` before restoring or
comparing a future change. No firmware was flashed while establishing this
baseline. Captures remain in their existing run folders; raw videos are not
duplicated in the source archive. Driver settings are not locked by this pack.
