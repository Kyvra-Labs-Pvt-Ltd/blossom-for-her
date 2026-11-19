"""Headless test: fake ESP32 on a pty -> Reader -> Session -> calibration."""
import os, pty, threading, tempfile, cv2, numpy as np
from make_synthetic import synth_sequence
from lfa_capture import Reader, save_session, load_session
import lfa_gui

# ---- fake firmware ---------------------------------------------------------------
master, slave = pty.openpty()
state = {"h": 0.2}
def fw():
    buf = b""
    while True:
        try: buf += os.read(master, 1024)
        except OSError: return
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            t = line.decode().split()
            if not t: continue
            if t[0] == "PING": os.write(master, b"OK LFAREADER 1\r\n")
            elif t[0] == "SET": os.write(master, b"OK\r\n")
            elif t[0] == "CAP":
                imgs, dks = synth_sequence(heights=(state["h"], 0.4), seed=1)
                im = dks["G"] if t[1] == "NONE" else imgs[t[1]]
                ok, jpg = cv2.imencode(".jpg", im, [cv2.IMWRITE_JPEG_QUALITY, 95])
                os.write(master, b"I (12) noise line\r\n")
                os.write(master, f"IMG {len(jpg)} {im.shape[1]} {im.shape[0]}\n".encode() + jpg.tobytes() + b"OK\n")
threading.Thread(target=fw, daemon=True).start()

r = Reader(os.ttyname(slave), timeout=5)
assert r.ping(); r.set("res", "SXGA")
tmp = tempfile.mkdtemp()
S = lfa_gui.Session(tmp)
levels = [0.0, 0.03, 0.08, 0.15, 0.3, 0.5, 0.7]
concs  = [0, 5, 12, 25, 50, 100, 200]
for h, c in zip(levels, concs):
    state["h"] = h
    S.images, S.darks = r.capture_sequence(["G", "W", "B"], {"G": 300, "W": 150, "B": 450})
    S.roi = None
    S.auto_roi()
    if h == 0.7: S.analyze(); S.lock_windows(True)       # lock windows from a strong strip
    S.analyze()
    sig = S.signal("G", 0, 1, "area")
    S.add_standard("LH", c, sig, "G:area:T0/C1")
cal = S.fit("LH", "G:area:T0/C1", "auto")
print("model", cal.model, "R2 %.4f" % cal.r2)

state["h"] = 0.22                                        # unknown strip, true conc is between 25 and 50
S.images, S.darks = r.capture_sequence(["G", "W", "B"], {"G": 300})
S.roi = None; S.auto_roi(); S.analyze()
sig = S.signal("G", 0, 1, "area")
print("unknown signal %.3f -> predicted conc %.1f" % (sig, S.predict("LH", sig)))
print("log:", S.log_result("test", "LH", "", "G:area:T0/C1", sig, S.predict("LH", sig)))
save_session(tmp + "/sess", S.images, S.darks); i, d = load_session(tmp + "/sess"); print("session roundtrip", sorted(i), sorted(d))
