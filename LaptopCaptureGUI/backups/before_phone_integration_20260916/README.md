# Laptop camera capture GUI

`PlacidoLaptopCaptureApp.m` is the laptop-only camera application. It is
separate from `CameraRecorderGUI`, which is for the phone app.

## What this version does

- Opens a full-screen MATLAB preview from a Windows/UVC camera, with an
  image-anchored alignment overlay.
- Lets you choose the camera and its supplied capture format.
- Saves a lossless PNG snapshot below `Data/Images`.
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
video** becomes available. It saves two matching files below `Data/Videos`,
using the same subfolder and filename beginning as the PNG setup images. For
example:

```text
Data/Videos/Test/Camera/eye_20260814_120000_000.avi
Data/Videos/Test/Camera/eye_20260814_120000_000_timing.csv
```

The AVI uses Motion JPEG and is logged directly to disk, avoiding a large
1080p memory buffer. The matching timing CSV records the planned and actual
time of every Arduino `A` (white light on) and `O` (white light off) command,
as well as the acquired and written frame counts.

The guided recording first sends an explicit OFF command, waits 0.15 seconds
for the alignment light to extinguish, keeps the in-app preview active, runs
for 13 seconds, and writes the full video directly to disk. The preview is a
best-effort operator view: while recording, it deliberately refreshes the
graphics display at up to 8 frames/s so that 1080p drawing does not stall the
interface. This does not discard or resize frames being written to the AVI.
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

The saved AVI is healthy even though the interactive preview appeared delayed.
The application now leaves MATLAB's preview open during direct disk logging.
MATLAB documents that preview can skip visual display frames while logging,
without affecting frames recorded to memory or disk. This is deliberately used
to keep a useful, current operator view while protecting the AVI.

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
Data/Images/Test/Camera/eye_20260813_173000_123.png
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
