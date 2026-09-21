#!/usr/bin/env python3
"""Arduino control server -- HTTP/LSL front end for the light-control Uno.

Independent of PlacidoExperimentController/CameraRecorder entirely -- this is its own
standalone server with its own console window, not something the camera
controller owns or manages. It just happens to use the same command-string
convention the phone's HTTP server uses (?cmd=COMMAND in the query string).

Every command received logs, pushes a matching LSL marker, and (if an
Arduino UNO running LightController.ino is connected) forwards a mapped
single-char command to it over serial. If no Arduino is connected, or the
serial write fails, that's logged and everything else keeps working --
this was originally a pure dummy/placeholder and still behaves like one
when there's no hardware attached (see ARDUINO_LIGHT_CONTROL_TODO.md).

Run it directly, in its own terminal or however you like -- it pops up its
own console window showing every command it receives, live.

Usage:
    python3 ArduinoController.py [--port 8095] [--stream-name ArduinoControl]
                                  [--serial-port auto] [--serial-baud 9600] [--no-gui]
"""

import argparse
import datetime
import http.server
import queue
import socketserver
import threading
import time
import urllib.parse

import pylsl
import serial
import serial.tools.list_ports

try:
    import msvcrt  # Windows-only; used for headless (--no-gui) spacebar detection
except ImportError:
    msvcrt = None

marker_outlet = None
serial_conn = None
log_queue = queue.Queue()

# Maps the phone/GUI-driven HTTP commands onto the Arduino's 3-phase light
# protocol (see LightController/LightController.ino). RUNNING has no
# light-side effect -- ARDUINO_LIGHT_CONTROL_TODO.md only defines
# ARM/ACQUIRE/OFF, and RUNNING->STOP fire back-to-back from the same
# button press anyway. The ACQUIRE flash settles to solid separately, via
# the SETTLE command (spacebar in this server's console -- see settle_light()).
HTTP_TO_SERIAL_COMMAND = {
    "START": "A",    # ARM: solid on
    "ACQUIRE": "Q",  # ACQUIRE: flash until settled
    "STOP": "O",     # OFF
}

# Substrings matched against "<description> <hwid>".lower(). Covers the
# common cases (official/CH340/WCH clones), plus the generic Windows CDC
# driver string ("USB Serial Device") that boards without a vendor-specific
# driver show up as -- e.g. the lab's UNO on COM6 reports exactly that, with
# VID:PID 0843:5740 (added below by exact match, since that string alone is
# too generic to hint on by itself).
ARDUINO_PORT_HINTS = ("arduino", "ch340", "wch.cn", "usb serial", "usb-serial", "2341", "1a86")
ARDUINO_VID_PID_HINTS = ("0843:5740",)


class CommandHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        cmd = params.get("cmd", [None])[0]

        # A bare GET with no ?cmd= is treated as a silent liveness probe
        # (e.g. PlacidoExperimentController checking whether to spawn its
        # own instance) -- not logged or pushed to LSL as a real command.
        if cmd is not None:
            ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
            log_queue.put(f"[{ts}] Received command: {cmd!r} (path={self.path!r})")

            if marker_outlet is not None:
                marker_outlet.push_sample([cmd])
                log_queue.put(f"[{ts}] LSL marker sent: {cmd!r}")

            serial_code = HTTP_TO_SERIAL_COMMAND.get(cmd)
            if serial_code is not None:
                send_serial(serial_code, cmd)

        body = f"OK: {cmd}".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # suppress the default per-request stderr logging; our lines go to log_queue instead


def open_lsl_outlet(stream_name):
    global marker_outlet
    try:
        info = pylsl.StreamInfo(stream_name, "Markers", 1, 0, pylsl.cf_string, "dummy_arduino_server")
        marker_outlet = pylsl.StreamOutlet(info)
        log_queue.put(f"LSL marker stream '{stream_name}' opened.")
    except Exception as exc:
        log_queue.put(f"Could not open LSL stream (continuing without it): {exc}")


def find_arduino_port():
    ports = list(serial.tools.list_ports.comports())

    for port in ports:
        haystack = f"{port.description} {port.hwid}".lower()
        if any(hint in haystack for hint in ARDUINO_PORT_HINTS):
            return port.device
        if any(vid_pid in haystack for vid_pid in ARDUINO_VID_PID_HINTS):
            return port.device

    # Nothing matched by name/ID -- if there's exactly one serial port on
    # the system at all, it's overwhelmingly likely to be the Uno (nothing
    # else in this lab setup shows up as a COM port), so just use it rather
    # than fail outright.
    if len(ports) == 1:
        log_queue.put(f"No named/ID match, but {ports[0].device} is the only serial port present -- using it.")
        return ports[0].device

    return None


def open_serial(port_arg, baud):
    global serial_conn
    port = port_arg
    if not port or port == "auto":
        port = find_arduino_port()
        if port is None:
            log_queue.put("No Arduino-like serial port found -- continuing without hardware "
                           "(commands still logged/pushed to LSL).")
            return
    try:
        serial_conn = serial.Serial(port, baud, timeout=1)
        time.sleep(2)  # let the Uno finish its power-on-open auto-reset before we write to it
        log_queue.put(f"Connected to Arduino on {port} at {baud} baud.")
    except Exception as exc:
        serial_conn = None
        log_queue.put(f"Could not open serial port {port!r} (continuing without hardware): {exc}")


def send_serial(code, label):
    if serial_conn is None:
        log_queue.put(f"(no Arduino connected -- '{label}' not sent over serial)")
        return
    try:
        serial_conn.write(code.encode())
        log_queue.put(f"Serial -> Arduino: {code!r} ({label})")
    except Exception as exc:
        log_queue.put(f"Serial write failed: {exc}")


def settle_light():
    """Stop a flashing ACQUIRE light and settle it solid. Currently unused
    by anything (not bound to SPACE or any command) -- kept as a ready-to-
    wire-up option; see ARDUINO_LIGHT_CONTROL_TODO.md."""
    send_serial("S", "SETTLE")


def abort_light():
    """Force the light off. Triggered by pressing SPACE in this server's
    console (GUI or headless) -- an operator kill switch, independent of
    anything PlacidoExperimentController sends."""
    send_serial("O", "OFF (spacebar)")


def run_console_gui(port):
    import tkinter as tk
    from tkinter.scrolledtext import ScrolledText

    root = tk.Tk()
    root.title(f"Arduino Control Server -- port {port}")
    root.geometry("560x380")

    text = ScrolledText(root, state="disabled", wrap="word", font=("Menlo", 11))
    text.pack(fill="both", expand=True, padx=8, pady=(8, 0))

    hint = tk.Label(root, text="Press SPACE to turn the light off immediately.", fg="#555555")
    hint.pack(fill="x", padx=8, pady=(4, 8))

    def append(line):
        text.configure(state="normal")
        text.insert("end", line + "\n")
        text.configure(state="disabled")
        text.see("end")

    def drain_queue():
        try:
            while True:
                append(log_queue.get_nowait())
        except queue.Empty:
            pass
        root.after(100, drain_queue)

    def on_space(_event):
        abort_light()

    root.bind_all("<space>", on_space)

    append(f"Listening on port {port}. Waiting for commands...")
    root.after(100, drain_queue)
    root.mainloop()


def spacebar_pressed_headless():
    """Non-blocking spacebar check for --no-gui mode. Windows-only (msvcrt);
    a no-op elsewhere, since there's no portable stdlib way to read a single
    keypress without Enter."""
    if msvcrt is None:
        return False
    if msvcrt.kbhit():
        return msvcrt.getch() == b" "
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8095)
    parser.add_argument("--stream-name", default="ArduinoControl", help="LSL marker stream name")
    parser.add_argument("--serial-port", default="auto",
                         help="Arduino serial port (e.g. COM5), or 'auto' to detect it")
    parser.add_argument("--serial-baud", type=int, default=9600)
    parser.add_argument("--no-gui", action="store_true", help="Run headless (print to stdout instead of a console window)")
    args = parser.parse_args()

    open_lsl_outlet(args.stream_name)
    open_serial(args.serial_port, args.serial_baud)

    socketserver.ThreadingTCPServer.allow_reuse_address = True
    server = socketserver.ThreadingTCPServer(("0.0.0.0", args.port), CommandHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    log_queue.put(f"Arduino control server listening on port {args.port}.")

    if args.no_gui:
        print(f"Arduino control server listening on port {args.port}. Ctrl+C to stop. "
              f"Press SPACE to turn the light off immediately.", flush=True)
        try:
            while True:
                try:
                    print(log_queue.get(timeout=0.05), flush=True)
                except queue.Empty:
                    pass
                if spacebar_pressed_headless():
                    abort_light()
        except KeyboardInterrupt:
            pass
    else:
        try:
            run_console_gui(args.port)
        except KeyboardInterrupt:
            pass

    server.shutdown()
    server.server_close()
    if serial_conn is not None:
        serial_conn.close()


if __name__ == "__main__":
    main()
