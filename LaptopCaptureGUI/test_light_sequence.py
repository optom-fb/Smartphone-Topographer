#!/usr/bin/env python3
"""Cycles the Arduino light through ARM -> ACQUIRE -> OFF, 2s per state, 5
times -- a quick hardware/firmware smoke test independent of
PlacidoExperimentController and ArduinoController.py's HTTP/LSL layer.

Talks directly to the Uno's serial port (auto-detected the same way
ArduinoController.py does, or pass --serial-port COM5 to override).

Usage:
    python3 test_light_sequence.py [--serial-port auto] [--serial-baud 9600]
"""

import argparse
import time

import serial

from ArduinoController import find_arduino_port

STATES = [
    ("A", "ARM (solid on)"),
    ("Q", "ACQUIRE (flashing)"),
    ("O", "OFF"),
]
HOLD_SECONDS = 2
CYCLES = 5


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial-port", default="auto",
                         help="Arduino serial port (e.g. COM5), or 'auto' to detect it")
    parser.add_argument("--serial-baud", type=int, default=9600)
    args = parser.parse_args()

    port = args.serial_port
    if not port or port == "auto":
        port = find_arduino_port()
        if port is None:
            raise SystemExit("No Arduino-like serial port found -- pass --serial-port COM<N> explicitly.")

    conn = serial.Serial(port, args.serial_baud, timeout=1)
    time.sleep(2)  # let the Uno finish its power-on-open auto-reset before writing to it
    print(f"Connected to {port} at {args.serial_baud} baud.")

    try:
        for cycle in range(1, CYCLES + 1):
            print(f"-- Cycle {cycle}/{CYCLES} --")
            for code, label in STATES:
                conn.write(code.encode())
                print(f"  {code} ({label})")
                time.sleep(HOLD_SECONDS)
    finally:
        conn.write(b"O")  # leave the light off, not mid-cycle, however this exits
        conn.close()
        print("Done -- light off, serial closed.")


if __name__ == "__main__":
    main()
