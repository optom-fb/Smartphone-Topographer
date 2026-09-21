#!/usr/bin/env python3
"""Logs CameraRecorder LSL events to CSV files in a DATA directory.

Subscribes to two LSL streams pushed by the CameraRecorder Android app:
  - "<name>_Markers" (irregular, string): one sample per recording, carrying
    the video filename, pushed right as the recording starts, and a "STOP"
    sentinel pushed when the recording ends.
  - "<name>" (regular, 3x double64): [frame_number, sensor_timestamp_ns,
    is_recording], pushed continuously by the camera's frame analyzer.

Also optionally subscribes to a third stream, --arduino-stream-name
(irregular, string; default "ArduinoControl"), pushed by the dummy/eventual
Arduino control server. This one is optional -- if it isn't found within
--arduino-resolve-timeout, camera logging still proceeds without it.

Every filename marker starts a new per-recording subdirectory of --data-dir,
named after that recording's video file (extension dropped; a _1, _2, ...
counter is appended if the name is already taken). Frame data samples up to
the next marker are written to --csv-name inside that subdirectory, and any
Arduino-control events in that same window are written to
--arduino-csv-name alongside it -- both keyed off the same per-recording
directory so other LSL streams' loggers can drop their own CSVs in there
too. The "STOP" marker closes both files immediately rather than leaving
them open (and accumulating idle preview frames/stray events) until the
next recording starts.

Every row is flushed to disk immediately, since on Windows the launching
GUI stops this process with taskkill /F (an immediate TerminateProcess)
rather than a SIGTERM the signal handler below can catch -- so there is no
guaranteed graceful shutdown to rely on for closing the file cleanly.

Usage:
    python3 lsl_recorder.py --data-dir /path/to/DATA [--stream-name CameraEvents]
"""

import argparse
import csv
import os
import signal
import sys
import time

import pylsl

RUNNING = True
STOP_MARKER = "STOP"


def handle_signal(signum, frame):
    global RUNNING
    RUNNING = False


def unique_recording_dir(data_dir, video_filename):
    base = os.path.splitext(video_filename)[0]
    candidate = os.path.join(data_dir, base)
    if not os.path.exists(candidate):
        return candidate
    n = 1
    while True:
        candidate = os.path.join(data_dir, f"{base}_{n}")
        if not os.path.exists(candidate):
            return candidate
        n += 1


def resolve_inlet(name, timeout, label):
    """Resolve a required stream, retrying forever -- the phone may not be
    streaming yet when this logger starts, and dying on a timeout just leaves
    a dead logger behind. Keeps waiting until the stream appears or the
    process is stopped."""
    print(f"Resolving LSL stream '{name}'...", flush=True)
    while RUNNING:
        streams = pylsl.resolve_byprop("name", name, timeout=timeout)
        if streams:
            print(f"Found {label} stream '{name}'.", flush=True)
            return pylsl.StreamInlet(streams[0])
        print(f"{label} stream '{name}' not found within {timeout:g}s -- retrying...", flush=True)
    raise SystemExit(0)


def resolve_inlet_optional(name, timeout, label):
    print(f"Resolving optional LSL stream '{name}'...", flush=True)
    streams = pylsl.resolve_byprop("name", name, timeout=timeout)
    if not streams:
        print(f"{label} stream '{name}' not found within {timeout}s -- continuing without it.", flush=True)
        return None
    print(f"Found {label} stream '{name}'.", flush=True)
    return pylsl.StreamInlet(streams[0])


def drain(inlet, writer, row_of):
    """Write out anything already buffered on inlet (non-blocking) before it's
    closed off -- otherwise a sample pushed just before STOP, but not yet
    polled, is silently lost when the file closes underneath it."""
    if inlet is None or writer is None:
        return
    while True:
        sample, ts = inlet.pull_sample(timeout=0.0)
        if sample is None:
            break
        writer.writerow(row_of(ts, sample))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", required=True, help="Directory to write per-recording subdirectories into")
    parser.add_argument("--stream-name", default="CameraEvents", help="Base LSL stream name")
    parser.add_argument("--csv-name", default="CameraServer.csv", help="Filename written inside each recording's subdirectory")
    parser.add_argument("--resolve-timeout", type=float, default=30.0)
    parser.add_argument("--arduino-stream-name", default="ArduinoControl", help="Optional Arduino-control marker stream name")
    parser.add_argument("--arduino-csv-name", default="Arduino.csv", help="Filename for Arduino-control events inside each recording's subdirectory")
    parser.add_argument("--arduino-resolve-timeout", type=float, default=3.0)
    args = parser.parse_args()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    os.makedirs(args.data_dir, exist_ok=True)

    marker_inlet = resolve_inlet(f"{args.stream_name}_Markers", args.resolve_timeout, "marker")
    data_inlet = resolve_inlet(args.stream_name, args.resolve_timeout, "data")
    arduino_inlet = resolve_inlet_optional(args.arduino_stream_name, args.arduino_resolve_timeout, "Arduino")

    csv_file = None
    csv_writer = None
    arduino_csv_file = None
    arduino_csv_writer = None

    print("Listening for events. Ctrl+C to stop.", flush=True)

    while RUNNING:
        marker, marker_ts = marker_inlet.pull_sample(timeout=0.05)
        if marker is not None:
            marker_text = marker[0]
            if marker_text == STOP_MARKER:
                drain(data_inlet, csv_writer, lambda ts, s: [f"{ts:.6f}", s[0], s[1], s[2]])
                drain(arduino_inlet, arduino_csv_writer, lambda ts, s: [f"{ts:.6f}", s[0]])
                if csv_file is not None:
                    csv_file.close()
                    print("Recording stopped, closed CSV.", flush=True)
                csv_file = None
                csv_writer = None
                if arduino_csv_file is not None:
                    arduino_csv_file.close()
                arduino_csv_file = None
                arduino_csv_writer = None
            else:
                video_filename = marker_text
                drain(data_inlet, csv_writer, lambda ts, s: [f"{ts:.6f}", s[0], s[1], s[2]])
                drain(arduino_inlet, arduino_csv_writer, lambda ts, s: [f"{ts:.6f}", s[0]])
                if csv_file is not None:
                    csv_file.close()
                if arduino_csv_file is not None:
                    arduino_csv_file.close()
                recording_dir = unique_recording_dir(args.data_dir, video_filename)
                os.makedirs(recording_dir, exist_ok=True)
                csv_path = os.path.join(recording_dir, args.csv_name)
                csv_file = open(csv_path, "w", newline="")
                csv_writer = csv.writer(csv_file)
                csv_writer.writerow(["# video_file", video_filename, "marker_lsl_timestamp", f"{marker_ts:.6f}"])
                csv_writer.writerow(["lsl_timestamp", "frame_number", "sensor_timestamp_ns", "is_recording"])
                csv_file.flush()
                print(f"New recording: {video_filename} -> {csv_path}", flush=True)

                if arduino_inlet is not None:
                    arduino_csv_path = os.path.join(recording_dir, args.arduino_csv_name)
                    arduino_csv_file = open(arduino_csv_path, "w", newline="")
                    arduino_csv_writer = csv.writer(arduino_csv_file)
                    arduino_csv_writer.writerow(["lsl_timestamp", "command"])
                    arduino_csv_file.flush()

        sample, data_ts = data_inlet.pull_sample(timeout=0.05)
        if sample is not None and csv_writer is not None:
            frame_number, sensor_timestamp_ns, is_recording = sample
            csv_writer.writerow([f"{data_ts:.6f}", frame_number, sensor_timestamp_ns, is_recording])
            csv_file.flush()

        if arduino_inlet is not None:
            arduino_sample, arduino_ts = arduino_inlet.pull_sample(timeout=0.05)
            if arduino_sample is not None and arduino_csv_writer is not None:
                arduino_csv_writer.writerow([f"{arduino_ts:.6f}", arduino_sample[0]])
                arduino_csv_file.flush()

    if csv_file is not None:
        csv_file.close()
    if arduino_csv_file is not None:
        arduino_csv_file.close()
    print("Stopped.", flush=True)


if __name__ == "__main__":
    main()
