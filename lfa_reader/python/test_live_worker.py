"""Headless test of lfa_live.Worker against a fake board on a pty (protocol incl. FRAME/MASK)."""
import os, pty, threading, time, tempfile, cv2
from make_synthetic import synth_sequence
import lfa_live

master, slave = pty.openpty()
log = []
def fw():
    buf = b""
    imgs, dks = synth_sequence(seed=3)
    while True:
        try: buf += os.read(master, 1024)
        except OSError: return
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1); t = line.decode().split()
            if not t: continue
            log.append(t)
            if t[0] in ("PING",): os.write(master, b"OK LFAREADER 1\r\n")
            elif t[0] in ("SET", "MASK", "LED"): os.write(master, b"OK\r\n")
            elif t[0] in ("CAP", "FRAME"):
                im = imgs["W"] if t[0] == "FRAME" else (dks["G"] if t[1] == "NONE" else imgs.get(t[1], imgs["W"]))
                ok, jpg = cv2.imencode(".jpg", im if t[0] == "CAP" else cv2.resize(im, (640, 480)))
                os.write(master, f"IMG {len(jpg)} 640 480\n".encode() + jpg.tobytes() + b"OK\n")
threading.Thread(target=fw, daemon=True).start()

w = lfa_live.Worker(os.ttyname(slave)); w.start()
print("event:", w.events.get(timeout=5))
w.send("set", "res", "VGA"); w.send("mask", 2); w.send("live", True)
time.sleep(1.5)
print("live frames received:", w.frame_id, "shape", w.latest.shape)
assert w.frame_id > 5
os.chdir(tempfile.mkdtemp())
w.send("session", ["G", "W", "R", "B"], {"G": 300, "W": 150, "R": 300, "B": 450}, 0, "SXGA", 4, "sessions/t1")
ev = w.events.get(timeout=20)
print("session event:", ev[0], sorted(os.listdir("sessions/t1")))
assert ev[0] == "session" and not w.live
w.send("quit"); time.sleep(0.3)
print("commands seen by board:", [" ".join(x) for x in log if x[0] != "FRAME"][:12])
