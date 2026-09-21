# CameraRecorder mobile acquisition

This folder documents the Android CameraRecorder component used with the MATLAB laptop GUI. The Android source project is intentionally not included in this submission; the examiner can review the acquisition role, protocol, file layout, and limitations here.

## Role in the prototype

CameraRecorder runs on the smartphone and provides the camera preview, exposure and ISO controls, recording, local event logging, and a small HTTP control service. MATLAB `LaptopCaptureGUI/PlacidoLaptopCaptureApp.m` coordinates the phone and the separate Arduino controlled white Placido illumination.

The phone is aligned using its own screen. The current MATLAB baseline does not stream live phone video to the laptop. After recording, MATLAB transfers the MP4 and phone CSV into a unique run folder and verifies matching SHA-256 hashes. Phone originals are not deleted.

## Host protocol

The GUI uses Android Debug Bridge USB forwarding to the phone HTTP service on port 8080. The supported commands are START, STOP, and STATUS, plus mode and exposure settings. HTTP OK alone is not proof that recording is active; MATLAB confirms `is_recording=true` through STATUS before starting the host timing record.

The nominal guided acquisition is 13 seconds: white light OFF from 0–3 s, solid ON from 3–8 s, five longer OFF/ON blocks from 8–13 s, and an explicit OFF before stopping. These are host commands. They are not exposure triggers and do not establish the optical transition time in the encoded video.

## Device and build record

The documented bench device is a Samsung Galaxy Note9 (SM-N960F), Android 10. The proposal records CameraX 1.4.1, Kotlin 2.2.10, Android Gradle Plugin 9.2.1, Gradle 9.4.1, minimum API 24, and target API 37. The installed APK revision and its source hash still require confirmation before a fixed experimental build is declared.

## Limitations

This prototype has no hardware trigger linking phone exposure to Arduino illumination. Focus, white balance, exposure response, encoded frame cadence, and phone file timestamps require device-specific characterisation. The current image-processing outputs are research-only reflected-image descriptors and are not calibrated corneal topography or clinical measurements.

See `LaptopCaptureGUI/README.md` for the operator workflow and the proposal methods documents for the full acquisition and timing discussion.
