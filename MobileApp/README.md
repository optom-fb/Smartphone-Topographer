# CameraRecorder mobile acquisition

CameraRecorder is the Android acquisition component used by the MATLAB
laptop GUI. It supplies the live phone preview, camera controls, video
recording, phone-side timing data, and a small control service that MATLAB
can reach through USB.

The Android source and APK are intentionally not included in this examiner
submission. This folder documents how the installed app fits into the
prototype, what the operator sees, which files are produced, and the current
limitations. The image-processing pipeline can be evaluated independently
with the trial images in `Data`.

## CameraRecorder pathway in the MATLAB GUI

In smartphone mode, the live camera preview stays on the phone while the
MATLAB panel reports connection, acquisition, and transfer status.

## What the phone app provides

- a full-screen camera preview with a fixed circular alignment guide;
- **NORMAL**, **SLOW**, and **SLOWER** capture-mode selection;
- shared **Auto/Manual** exposure control with 1-10 shutter and ISO sliders;
- a recording indicator, saved filename, connection information, and
  controller status;
- local MP4 recording and a corresponding timing CSV; and
- remote `START`, `STOP`, and `STATUS` control for the laptop workflow.

For this submitted MATLAB pathway, use **NORMAL** mode. The high-speed modes
remain development options and are not part of the validated acquisition
workflow.

## Requirements

- an Android phone with CameraRecorder already installed;
- camera and microphone permissions granted to the app;
- an unlocked phone connected by a USB data cable;
- USB debugging enabled and the laptop authorised on the phone;
- Android Debug Bridge (ADB) available on the laptop; and
- MATLAB opened in the root of this repository.

The documented bench device is a Samsung Galaxy Note9 (SM-N960F) running
Android 10. Other phones may expose different frame rates, resolutions, and
manual-exposure ranges.

## First-time acquisition workflow

1. Open CameraRecorder on the unlocked phone and choose **NORMAL** mode.
2. Confirm that the phone shows a live preview and is not already recording.
3. Leave exposure on **Auto**, or set the shutter and ISO before recording.
   These settings are locked while a recording is active.
4. Connect the phone to the laptop by USB and accept the USB-debugging prompt
   if Android displays one.
5. In MATLAB, run:

   ```matlab
   run_LaptopCaptureGUI
   ```

6. Select **Smartphone CameraRecorder (USB)** and then **Connect smartphone
   (status only)**. The MATLAB GUI creates a temporary ADB-forwarded route to
   the app's control service on port 8080.
7. Enter the output subfolder and filename beginning. The filename beginning
   may contain letters, digits, `_`, and `-`.
8. Connect the Arduino only when the guided Placido illumination sequence is
   required, then start the recording from the MATLAB GUI.
9. Wait for the GUI to confirm that recording stopped and both phone files
   were transferred. The original files remain on the phone.

The MATLAB button is labelled **status only** because the phone remains the
live alignment display. The laptop checks the app state; it does not stream
the phone preview into MATLAB.

## Communication and state checks

The current integration uses ADB over USB to forward an unused laptop port
to the app's HTTP service on phone port 8080. MATLAB sends a safe filename
prefix with `START:<prefix>`, sends `STOP` at the end, and polls `STATUS` to
confirm the actual recording state.

An HTTP acknowledgement only confirms receipt of a command. MATLAB therefore
waits for `is_recording=true` before starting its host timing record and for
`is_recording=false` before transferring files. The phone must be idle and
in **NORMAL** mode when the connection is made.

## Guided 13-second sequence

When Arduino-guided acquisition is selected, the nominal host sequence is:

| Time | White Placido illumination |
|---|---|
| 0-3 s | Off |
| 3-8 s | On continuously |
| 8-13 s | Five 0.5 s off/on pairs |
| End | Explicitly switched off before phone recording stops |

These are host commands rather than camera-exposure triggers. The prototype
does not provide a hardware trigger between phone exposure and illumination.

## Files created by one phone run

CameraRecorder stores the video below
`/sdcard/Movies/placido_data` and the timing CSV below
`/sdcard/Documents/placido_data`. The MATLAB GUI copies the matching pair to
a unique folder below:

```text
Data/GUI Data/Smart_Phone/<optional subfolder>/<unique run>/
```

That folder contains:

- the transferred `.mp4` recording;
- the transferred phone timing `.csv`;
- `phone_host_protocol.csv`, containing planned and observed host events;
- `phone_commands.csv`, containing commands, UTC times, responses, and
  durations; and
- `phone_session.json`, containing the final session state and file hashes.

The transfer checks that each phone file has stopped changing and compares
SHA-256 hashes before accepting the laptop copy. A failed or partial transfer
does not delete the phone original.

## Device and build record

The proposal records CameraX 1.4.1, Kotlin 2.2.10, Android Gradle Plugin
9.2.1, Gradle 9.4.1, minimum API 24, and target API 37. The exact installed
APK revision and its source hash still require confirmation before declaring
a fixed experimental build.

## Current limitations

- The Android source and installer are outside this submission, so an
  examiner without the prepared phone can review the documented interface
  and open the MATLAB GUI but cannot reproduce phone acquisition from this
  repository alone.
- There is no hardware trigger linking phone exposure to Arduino
  illumination.
- Focus, white balance, exposure response, encoded frame cadence, and phone
  timestamps require device-specific characterisation.
- Outputs are research-only reflected-image descriptors. They are not
  calibrated corneal topography or clinical measurements.

Return to the [main project instructions](../README.md) for image analysis
and the external-camera workflow.
