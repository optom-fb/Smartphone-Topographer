# Laptop camera capture GUI

`PlacidoLaptopCaptureApp.m` now offers **External USB camera (IR)** and
**Smartphone CameraRecorder (USB)** in one laptop GUI. The older
`CameraRecorderGUI` controller is separate; do not run its illumination
controller alongside this GUI.

## Capture storage (updated 17 September 2026)

New captures use `D:\MATLAB\placido\Data\GUI Data`:

```text
GUI Data/
  Smart_Phone/<optional subfolder>/<unique phone run>/
    <original phone filename>.mp4
    <original phone filename>.csv
    phone_host_protocol.csv
    phone_commands.csv
    phone_session.json
  EXT_Camera/<optional subfolder>/<unique external run>/
    <filename>.avi
    <filename>_timing.csv
    external_session.json
```

The optional subfolder defaults to `Test`; leave it empty to save directly
under the selected camera folder. External snapshots have their own unique
snapshot folders inside EXT_Camera. Existing recordings are not moved or
deleted. The completed combined phone bench run has a hash-verified copy in
Smart_Phone/Test; its LOCATION_NOTE explains retained original metadata paths.

Phone MP4 review: run `step00_review_smartphone_video` from the scripts folder
or add that folder to the MATLAB path. Select the desired MP4. PNG candidates,
CSV and contact sheets are saved inside that run's unique `Frame_Review_*`
folder. Frames are sampled by video time, without assigning IR, white-ON or
transition labels from host time. No image is automatically recommended.
Review the recording and manually select a sharp, fully illuminated ring frame
from a sustained-light segment. Set `constants.step01.inputImagePath` in
`config/placidoConstants.m` to the full PNG path, then run Steps 01-03.
Do not run the video-mode master pipeline on phone MP4 using AVI timing
assumptions. A bench video of an ordinary object is a software test and is
not an appropriate corneal-analysis input.

External AVI Step-00 discovery now searches both GUI Data/EXT_Camera and the
legacy Data/Videos folders. Its derived frames remain in Data/Derived/VideoFrames
and can feed the existing automatic Step-01 selection. Steps 01-03 keep their
existing Data/Output destinations, with camera/source subfolders retained.

External live preview pauses during disk logging to reduce GUI rendering
load on the host-controlled illumination sequence. The last alignment frame
remains displayed and preview resumes afterward, including after an aborted
run. The recorded stream stays at the selected native format.
`external_session.json` records completion/failure, counts, video hash, source
hashes. Automatic driver-setting queries are excluded from end/error cleanup;
inspect settings separately using the read-only settings window. Incomplete runs
write `*_partial_timing.csv`, which is not a successful guided timing sidecar.
The first external bench attempt on 17 September 2026 is retained and marked
incomplete. A subsequent full recording required offline metadata recovery
after a settings-serialization stall; its manifest explicitly records that
recovery and unavailable original settings. The metadata writer is corrected
to avoid serializing MATLAB driver objects, and a subsequent build removes
automatic driver queries from end/error cleanup. A later repeat aborted before
the first scheduled ON event because a host command was over 250 ms late;
that repeat is incomplete and its partial log must not be used for phase
selection. Operator observation did not confirm illumination in the external
tests. Recording/file verification is separate from a physical lighting test.

## Smartphone workflow (added 16 September 2026)

1. Connect the unlocked Android phone by USB and authorise USB debugging.
   Open CameraRecorder on the phone and select NORMAL. No app installation
   or camera launch is performed by this GUI.
2. Run `PlacidoLaptopCaptureApp` in MATLAB from this folder. Select
   **Smartphone CameraRecorder (USB)**, then **Connect smartphone (status only)**.
   Exactly one authorised Android device must be attached. ADB is located in
   `%LOCALAPPDATA%/Android/Sdk/platform-tools/adb.exe`.
   Alternatively, run `PlacidoLaptopCaptureApp('phone')` to open smartphone
   mode directly, without first scanning Windows camera drivers.
3. Align using the **phone screen**. The recovered app does not expose a
   live video-preview endpoint. Laptop alignment overlays and snapshots are
   therefore disabled for this backend. Show camera settings reads STATUS;
   it does not change exposure or ISO. A recorded frame is shown after transfer.
4. For an authorised illumination experiment, separately choose the correct
   Arduino port and connect it. Phone connection does not connect the Arduino
   or turn LEDs on. The guided-record button requires both connections.
5. Set the optional subfolder and filename beginning. The subfolder applies
   below `Data/GUI Data/Smart_Phone` for phone acquisition.
6. Select **Record guided 13 s video**. The GUI sends white OFF, waits 150 ms,
   sends phone START and waits for STATUS `is_recording=true`. The nominal
   13-second illumination clock starts at that host confirmation, not at the
   first encoded video frame. It sends A at 3 s; O at 8 s; alternating A/O at
   half-second boundaries through A at 12.5 s; and O at 13 s, then phone STOP.
   `placidoGuidedPlan.m` supplies the same schedule to both camera backends.
7. After STOP is confirmed, the GUI automatically copies the matching MP4
   from `/sdcard/Movies/placido_data` and CSV from
   `/sdcard/Documents/placido_data` into a unique run subfolder. This file
   layout is verified on this Note9 running Android 10; older Android file
   layouts are not supported by this transfer implementation. Phone originals
   are never deleted. Transfers require stable remote SHA-256 and matching
   local SHA-256. Existing local files are never overwritten.

Each phone run saves:

- Original MP4 and phone CSV, retaining the phone-generated filenames.
- `phone_host_protocol.csv`: planned and actual host Arduino-command times,
  measured relative to receipt of recording-active STATUS.
- `phone_commands.csv`: HTTP requests, UTC send/return times, elapsed duration,
  responses and failures. HTTP OK alone does not establish successful recording.
- `phone_session.json`: completion/failure, settings reported by the app,
  protocol origin, Arduino port/baud, source hashes, transferred file hashes,
  decoded frame count, video metadata and phone timing sample count.

Phone CSV samples come from the app's analysis callbacks; they are **not
validated one-to-one timestamps for encoded MP4 frames**. Host time and phone
sensor/LSL time are separate clocks. Host protocol time zero is **not MP4 time
zero**. The MP4 may exceed 13 seconds due to startup confirmation and stopping
latency. The smartphone's IR sensitivity/illumination is not established: the
initial phase is called **white OFF**, not guaranteed IR-only. Automatic
exposure remains as set on the phone. The app can also include audio if its
microphone permission is granted; the GUI does not change that permission.

Do not feed these host logs into Step-00's existing AVI timing assumptions.
MP4 discovery and validated host-to-video alignment remain separate downstream
work. No synchronisation, irradiance safety, optical calibration or clinical
validation is claimed by this integration.

**Cancellation/failure:** Cancel recording or close requests attempt Arduino
OFF followed by phone STOP. Status is checked before each scheduled command;
communication errors, premature phone stopping or commands over 250 ms late
abort the run rather than compressing missed light blocks. The 250 ms limit
is a software guard, not a validated scientific timing tolerance. A failed
STOP keeps recording ownership and requires attention; no new guided recording
is enabled until resolved. Cable loss can prevent STOP reaching the phone;
stop manually on the phone in that case. Phone data and partial laptop files
remain available after failures. Metadata writing is attempted on failed runs.

For a failed transfer after STOP, reconnect and recover the unique prefix from
`phone_session.json` into a **new** destination (avoid overwriting partial runs):

```matlab
phone = PlacidoPhoneClient;
phone.connect();                          % app must be idle in NORMAL mode
files = phone.fetchRecording(prefix, newRecoveryFolder);
phone.disconnect();
```

`testPhoneIntegration` uses simulated transport only. It checks schedule,
SHA-256, successful and failed commands, ownership, file transfer integrity,
overwrite protection and multiple-device rejection. It does not run hardware.
The full Arduino/phone protocol still requires a physical bench validation.

The pre-integration GUI and README are preserved in
`backups/before_phone_integration_20260916/`.

## What this version does

- Opens a full-screen MATLAB preview from a Windows/UVC camera, with an
  image-anchored alignment overlay.
- Lets you choose the camera and its supplied capture format.
- Saves a lossless PNG snapshot below `Data/GUI Data/EXT_Camera`.
- Adds a timestamp to every filename so an earlier capture is never replaced.
- Records a guided 13-second pilot sequence directly to disk, together with a CSV
  file that logs the intended and actual Arduino light-command times.
- Shows the camera driver's available settings and current values without
  changing them.
- Lists available serial ports and connects to the separate Arduino light
  controller at 9600 baud.
- Provides manual **White Placido light ON (15 s)** and **White Placido light OFF**
  controls for the external, Arduino/MOSFET-driven white LEDs.
- Sends an explicit OFF command immediately after connecting and whenever this
  app is closed normally.

The video feature is a first pilot-recording tool, not a validated measurement
protocol. The camera's built-in IR LEDs are not exposed as a UVC control and
are not controlled by this app or the Arduino.

The live preview appears in the main app window. A yellow circle marks an
adjustable approximate iris diameter and a green crosshair marks the literal
image centre. These are positioning aids only: they do not change raw pixels,
measure the pupil, calibrate the camera, or prevent a recording. Adjust the
circle to roughly match the iris, then align the pupil towards the crosshair.

## How to run it

1. Close the Windows Camera app, Zoom, Teams, and any other app using the
   camera.
2. In MATLAB, change Current Folder to this `LaptopCaptureGUI` folder.
3. Run:

   ```matlab
   PlacidoLaptopCaptureApp
   ```

4. Choose **USB Camera** and `MJPG_1920x1080`, then select **Start camera +
   Arduino**. The app starts the preview, connects to the selected Arduino
   port (currently the known port **COM7**), and turns the external white
   Placido light ON for mire focus and iris alignment. A live stream appears
   in the main app with the iris guide and crosshair. The firmware switches
   the light OFF after 15 seconds as an independent safety limit; press the
   manual **White Placido light ON (15 s)** button again if more alignment
   time is needed. The separate Arduino button is only needed if you later
   need to reconnect it, carry out a manual light check, or select a different
   port.
5. Set an image folder such as `Test/Camera` and a filename beginning such as
   `eye`.
6. Use **Save PNG snapshot** when the image is ready.

### Guided pilot video

After both the camera preview and Arduino are connected, **Record guided 13 s
video** becomes available. It saves two matching files in a unique run below `Data/GUI Data/EXT_Camera`,
using the same subfolder and filename beginning as the PNG setup images. For
example:

```text
Data/GUI Data/EXT_Camera/Test/eye_ext_20260917_120000_000/eye_20260917_120000_000.avi
Data/GUI Data/EXT_Camera/Test/eye_ext_20260917_120000_000/eye_20260917_120000_000_timing.csv
```

The AVI uses Motion JPEG and is logged directly to disk, avoiding a large
1080p memory buffer. The matching timing CSV records the planned and actual
time of every Arduino `A` (white light on) and `O` (white light off) command,
as well as the acquired and written frame counts.

The guided recording first sends an explicit OFF command, waits 0.15 seconds
for the alignment light to extinguish, pauses the in-app preview, runs
for 13 seconds, and writes the full video directly to disk. The displayed
alignment frame is frozen during recording. This does not discard or resize
frames being written to the AVI. The 250 ms host-command lateness guard remains
active; a late sequence is marked incomplete rather than accepted as valid.
Its fixed first sequence is:

1. 3 seconds with the white Placido light OFF.
2. 5 seconds with the white Placido light solid ON.
3. Five 0.5-second OFF blocks alternating with five 0.5-second ON blocks.
4. An explicit OFF command before saving and restoring preview.

All camera and light controls are disabled while this pilot sequence runs. Aim
the disc safely away from eyes during the first test. The existing Arduino
15-second automatic cutoff remains a separate backup, but should not occur in
this 13-second sequence. In normal use, the video sequence stops itself at 13
seconds; 15 seconds is the Arduino's independent fail-safe limit, not the
intended recording duration.

### First guided-video pilot result (2026-08-14)

`pilot_20260814_134911_048.avi` was saved successfully with 370 acquired and
370 written frames: 12.33 seconds at 30 fps. Its timing CSV and visual frame
review show that the solid-light and slower OFF/ON sections changed the image
as commanded. The generated contact sheet and brightness timeline are stored
beside the normal analysis output in `Data/Output/Test/Camera`.

Earlier versions left preview active during disk logging. A later external
bench run aborted because a host command exceeded the 250 ms lateness limit.
Preview is now paused to reduce rendering load. This change requires a new
end-to-end bench test; it does not establish the cause of the earlier delay
or prove physical illumination timing.

### Second guided-video pilot result (2026-08-14)

`eye_20260814_140514_608.avi` contains 359 frames at 30 fps (11.97 seconds),
and its CSV reports all 359 acquired frames were written to disk. The revised
absolute-time scheduling worked well: every LED command was within 13 ms of
its planned time. The IR-only frames clearly show the pupil; the solid-light
frames show the Placido rings; and the 0.5-second OFF/ON blocks are visibly
separated. The final OFF command is a safety command at the end of the file,
so it is not intended as another pupil-analysis block.

The diagnostic review also confirms a remaining image-quality issue: automatic
exposure/gain reacts strongly to the white rings, occasionally overexposing
the ON frames. Before collecting analysis data, we should add and test a
manual exposure/gain lock using the driver controls. The two review images are
saved in `Data/Output/Test/Camera` beside this project's other outputs.

### Three follow-up recordings (2026-08-14)

The first follow-up recording, `eye_20260814_142824_733.avi`, is a failed
lighting capture: its CSV proves that MATLAB sent the expected serial commands,
but the image did not change and the external ring was not visibly on. Do not
use that AVI for analysis. The following two AVIs are valid captures:
`eye_20260814_143034_104.avi` (363/363 acquired/written frames) and
`eye_20260814_143212_502.avi` (364/364 acquired/written frames). Both show the
expected IR-only, solid-ring, and OFF/ON image states.

The external light should always be checked visually with the manual ON/OFF
buttons before a session. A future reliability upgrade is to make the Arduino
run the complete timing sequence locally and report acknowledgements; this will
remove small Windows scheduling variation and make an unexpected non-response
easier to identify.

### Step 00: extract analysis candidates from one guided video

Run `scripts/step00_extract_guided_video_frames.m` after recording a valid
AVI. By default it selects the newest AVI with a matching timing CSV; set its
`INPUT_VIDEO_PATH` only when you deliberately want an older video. The script uses
the matching timing CSV's actual host-command times to select three IR-only
pupil candidates, three solid-light ring candidates, and an OFF/ON-pair
candidate from every blinking block listed in the CSV (five pairs in the
current protocol). It saves the PNGs, a maximised contact-sheet window, and a
manifest to:

```text
Data/Derived/VideoFrames/<video subfolder>/<video filename>/
```

The contact sheet must be reviewed before analysis. The CSV records commanded
light state rather than directly measuring LED illumination, so a recording
with no physical light response must be rejected even if its serial commands
are present. The manifest's middle solid-light frame is initially marked as the
recommended Step-01 input. Pupil detection remains separate until validation
against manually reviewed images is complete.

The pilot also shows that the camera's automatic exposure/gain adapts visibly
when the white rings turn on and off. The on frames contain usable rings but
brightly expose the surrounding eye; the off frames show a clearer pupil. We
must choose and lock manual exposure and gain before accepting videos as
measurement data.

### Manual Arduino light test

The presently connected Arduino is Windows USB serial device **COM7**. The app
will prefer COM7 if it is available, but always confirm that you are choosing
the USB serial device rather than a Bluetooth COM port.

1. With the external white Placido light aimed safely at the test setup, select
   **COM7** under **Arduino port (white Placido LEDs)**.
2. Select **Connect Arduino**. Wait roughly two seconds while opening the board
   resets it. The app then sends a second explicit **OFF** command.
3. Confirm the status says the light is OFF.
4. Select **White Placido light ON** briefly and visually confirm the external
   white LEDs illuminate.
5. Select **White Placido light OFF** and visually confirm they are off.
6. Select **Disconnect Arduino** when finished. Closing the app also sends OFF.

If MATLAB crashes, the USB cable is removed, or the app cannot send OFF, the
current Arduino firmware can retain its most recent light state. In that case,
use the physical power/USB disconnect as the fallback safe-off action. We will
add a controlled firmware timeout before using the system for recording.

### Confirmed Arduino/MOSFET hardware test (2026-08-14)

The complete external white-Placido-light path has been checked on this laptop:

- Arduino Uno USB serial port: `COM7` at 9600 baud.
- Arduino `D3` is connected to XY-MOS `TRIG/PWM`; Arduino `GND` is connected
  to XY-MOS `GND`.
- The separate low-voltage DC supply is connected to XY-MOS `VIN+` / `VIN-`;
  the Placido ring is connected to `OUT+` / `OUT-`.
- `LightController.ino` was compiled for an Arduino Uno and uploaded to the
  board. It starts with the light OFF.
- With the DC supply disconnected, a five-second `A` command switched the
  XY-MOS indicator LED on, and `O` switched it off.
- With the supply connected and the disc aimed safely away from eyes, a
  0.75-second `A` command illuminated the white Placido ring and the following
  `O` command switched it off. This was repeated successfully after moving the
  supply to a different USB port.
- The MATLAB laptop capture GUI was then connected to COM7 and its manual
  **White Placido light ON** and **White Placido light OFF** buttons were each
  confirmed to control the ring correctly.

This confirms only the manual switching path. Do not use the `Q` flashing
command or collect participant data until the longer-block timing test and the
laboratory's optical-safety protocol have been completed.

### Confirmed Arduino safety cutoff (2026-08-14)

The firmware now applies a 15-second maximum duration to every solid or
flashing light command. It was uploaded to the Uno and tested with the full
Placido ring connected: one `A` command lit the ring, the Arduino emitted its
`SAFETY_OFF` status message, and the ring switched itself off after about
15 seconds. The laptop/app still sends `O` normally; this timeout is an
independent fallback, not a replacement for the normal OFF command.

### Guided video sequence used by the current app

The current capture mode records one continuous video rather than a sequence
of unrelated still images. Still PNG snapshots remain available for focus and
setup checks. First use **Start camera + Arduino**: it turns the white light
ON so that the mires can be centred and focused. Then use the record button;
it turns the light OFF before recording and uses this conservative pattern:

1. **0--3 seconds:** camera/IR only; white Placido light OFF. These frames are
   candidates for pupil detection.
2. **3--8 seconds:** white Placido light continuously ON. These frames are
   candidates for ring detection.
3. **8--13 seconds:** alternate five longer OFF/ON blocks, each about
   0.5 seconds each, rather than the older 33 ms flash command. Each block
   contains several 30-fps frames, allowing transition or rolling-shutter
   frames to be rejected.
4. **End (13 seconds):** white Placido light explicitly OFF and video saved with timing
   metadata.

The first pilot will use the focused 1920-by-1080 stream at 30 fps. The seller
lists a possible 1280-by-720 60-fps mode, but it must be confirmed in MATLAB
on this particular camera. Higher frame rate may help select cleaner
transitions, but it does not solve rolling-shutter synchronisation and reduces
the pixel detail available for the rings. It is therefore a later comparison,
not the starting protocol.

Use **Show camera settings** while preview is running to view the driver
settings. For now it is read-only: we will decide which settings should be
locked only after checking the values supported by this exact camera.

If the external camera was connected after this app opened, select **Refresh
camera list** before starting preview. Stop preview before using that button.
It resets MATLAB's camera adaptor so it can discover newly connected USB
cameras. Do not use it while another Image Acquisition Toolbox capture is
running in the same MATLAB session.

For example, the first saved image might be:

```text
Data/GUI Data/EXT_Camera/Test/eye_snapshot_20260917_120000_000/eye_20260917_120000_000.png
```

To analyse that image, set `INPUT_IMAGE_PATH` in
`scripts/step01_detect_placido_rings.m` to the saved file and run the normal
three-step workflow.

## Important setup note

This first version preserves the camera's current driver settings. Before
collecting research data, we will inspect its available exposure, gain, white
balance, and focus controls, then lock the appropriate settings. Do not use
automatic image adjustments for a measurement protocol.

## What comes next

Do not use the existing Arduino `Q` flashing command for data collection yet.
The UVC camera has a rolling shutter and no hardware trigger, so the old 33 ms
on/off sequence does not prove that each frame is fully lit or fully dark.
After manual ON/OFF has been checked, we will add a new conservative firmware
mode using longer light blocks, record a short pilot video, inspect individual
frames for banding/partial illumination, and only then add paired pupil/ring
processing.
Current fixed acquisition baseline: see [CURRENT_BASELINE.md](CURRENT_BASELINE.md).
The accepted 17 September 2026 version pauses external preview during recording;
its source snapshot and SHA-256 manifest are retained under `baselines/`.
