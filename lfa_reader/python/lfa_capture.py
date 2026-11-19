"""
lfa_capture.py - talk to the ESP32-S3 strip imager over USB serial.

Command line (no GUI):
    python lfa_capture.py --port COM5 --out session1            # G, W, B + dark frames
    python lfa_capture.py --port /dev/ttyACM0 --leds G W B X --exposure G=250 W=120 B=400
"""
from __future__ import annotations

import argparse
import os
import time
from typing import Dict, Iterable, Optional, Tuple

import cv2
import numpy as np
import serial
import serial.tools.list_ports


def list_ports():
    return [p.device for p in serial.tools.list_ports.comports()]


class Reader:
    def __init__(self, port: str, baud: int = 115200, timeout: float = 8.0):
        self.ser = serial.Serial(port, baud, timeout=timeout)
        try:                          # don't reset the board when opening the port
            self.ser.dtr = False
            self.ser.rts = False
        except OSError:               # virtual ports (tests) don't support modem lines
            pass
        time.sleep(0.3)
        self.ser.reset_input_buffer()

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass

    # ---- low level -----------------------------------------------------------
    def _send(self, line: str):
        self.ser.write((line + "\n").encode())

    def _readline(self) -> str:
        return self.ser.readline().decode(errors="replace").strip()

    def command(self, line: str) -> str:
        """Send a command, return the first 'OK...' line (raises on ERR)."""
        self.ser.reset_input_buffer()
        self._send(line)
        t0 = time.time()
        while time.time() - t0 < self.ser.timeout + 2:
            r = self._readline()
            if r.startswith("OK"):
                return r
            if r.startswith("ERR"):
                raise RuntimeError(f"{line!r} -> {r}")
        raise TimeoutError(f"No reply to {line!r}")

    # ---- high level ----------------------------------------------------------
    def ping(self) -> bool:
        return "LFAREADER" in self.command("PING")

    def set(self, key: str, value) -> None:
        self.command(f"SET {key} {value}")

    def led(self, name: str) -> None:
        self.command(f"LED {name}")

    def capture(self, led: str, exposure: Optional[int] = None,
                gain: Optional[int] = None) -> np.ndarray:
        """Capture one frame with the given LED on ('NONE' = dark frame). Returns BGR."""
        cmd = f"CAP {led}"
        if exposure is not None:
            cmd += f" {int(exposure)}"
            if gain is not None:
                cmd += f" {int(gain)}"
        return self._image(cmd)

    def frame(self) -> np.ndarray:
        """Newest frame with the LEDs left as they are (live view)."""
        return self._image("FRAME")

    def mask(self, m: int) -> None:
        """Switch several LEDs at once: G=1 W=2 R=4 B=8 (0 = all off)."""
        self.command(f"MASK {int(m)}")

    def _image(self, cmd: str) -> np.ndarray:
        self.ser.reset_input_buffer()
        self._send(cmd)
        t0 = time.time()
        while time.time() - t0 < self.ser.timeout + 5:
            line = self._readline()
            if line.startswith("ERR"):
                raise RuntimeError(f"{cmd!r} -> {line}")
            if line.startswith("IMG "):
                n = int(line.split()[1])
                data = self.ser.read(n)
                if len(data) != n:
                    raise IOError(f"Short image: got {len(data)} of {n} bytes")
                self.ser.readline()                      # trailing "OK"
                img = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
                if img is None:
                    raise IOError("JPEG decode failed")
                return img
        raise TimeoutError(f"No image for {cmd!r}")

    def capture_sequence(self, leds: Iterable[str] = ("G", "W", "B"),
                         exposures: Optional[Dict[str, int]] = None,
                         gain: int = 0, with_dark: bool = True
                         ) -> Tuple[Dict[str, np.ndarray], Dict[str, np.ndarray]]:
        """One LED at a time (+ a dark frame at the same exposure for each).
        Returns (images, darks) keyed by LED name."""
        exposures = exposures or {}
        images, darks = {}, {}
        for led in leds:
            exp = exposures.get(led)
            images[led] = self.capture(led, exp, gain if exp is not None else None)
            if with_dark:
                darks[led] = self.capture("NONE", exp, gain if exp is not None else None)
        return images, darks


# ---- session folders (shared with the GUI) --------------------------------------
def save_session(folder: str, images: Dict[str, np.ndarray], darks: Dict[str, np.ndarray]):
    os.makedirs(folder, exist_ok=True)
    for led, im in images.items():
        cv2.imwrite(os.path.join(folder, f"{led}.png"), im)
    for led, im in darks.items():
        cv2.imwrite(os.path.join(folder, f"dark_{led}.png"), im)


def load_session(folder: str) -> Tuple[Dict[str, np.ndarray], Dict[str, np.ndarray]]:
    images, darks = {}, {}
    for fn in sorted(os.listdir(folder)):
        stem, ext = os.path.splitext(fn)
        if ext.lower() not in (".png", ".jpg", ".jpeg", ".bmp"):
            continue
        im = cv2.imread(os.path.join(folder, fn), cv2.IMREAD_COLOR)
        if im is None:
            continue
        if stem.lower().startswith("dark_"):
            darks[stem[5:].upper()] = im
        elif len(stem) <= 2:
            images[stem.upper()] = im
    return images, darks


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--out", default="session")
    ap.add_argument("--leds", nargs="+", default=["G", "W", "B"])
    ap.add_argument("--exposure", nargs="*", default=[], help="e.g. G=250 W=120")
    ap.add_argument("--res", default=None)
    a = ap.parse_args()
    exp = {k: int(v) for k, v in (e.split("=") for e in a.exposure)}
    r = Reader(a.port)
    print("ping:", r.ping())
    if a.res:
        r.set("res", a.res)
    ims, dks = r.capture_sequence(a.leds, exp)
    save_session(a.out, ims, dks)
    print("saved to", a.out)
