"""
lfa_live.py - bench GUI: LED switches, live view, and automatic channel selection.

    python lfa_live.py

1. Pick the serial port, Connect.
2. Tick LEDs (e.g. White) and press "Start live". Move the strip / camera height / turn the
   lens barrel until the FOCUS score peaks and the strip sits inside the cyan box.
   Use the exposure slider so SAT stays ~0 % (no clipped pixels).
3. Fill in the per-LED exposures (use "<-" to copy the slider value), press "Run session".
   Images are saved to sessions/<timestamp>/; analysis automatically picks the clearest LED.
   (Re-open the folder later in lfa_gui.py for calibration work.)
"""
from __future__ import annotations

import datetime as dt
import os
import queue
import sys
import threading

import cv2
import numpy as np

from lfa_capture import Reader, list_ports, save_session

try:
    import tkinter as tk
    from tkinter import messagebox, ttk
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
    from matplotlib.figure import Figure
except ImportError:                      # pragma: no cover
    tk = None

LEDS = [("G", "Green 530 nm", 1), ("W", "White", 2), ("R", "Red", 4), ("B", "Blue", 8)]
DEFAULT_EXP = {"G": 300, "W": 150, "R": 300, "B": 450}


# =============================================================================
#  Worker thread: the ONLY code that touches the serial port
# =============================================================================
class Worker(threading.Thread):
    def __init__(self, port: str):
        super().__init__(daemon=True)
        self.port = port
        self.cmd_q: "queue.Queue" = queue.Queue()
        self.events: "queue.Queue" = queue.Queue()
        self.live = False
        self.latest = None
        self.frame_id = 0
        self.running = True
        self.reader = None

    def send(self, *cmd):
        self.cmd_q.put(cmd)

    def run(self):
        try:
            self.reader = Reader(self.port, timeout=6.0)
            ok = False
            for _ in range(3):
                try:
                    ok = self.reader.ping()
                    break
                except Exception:
                    pass
            self.events.put(("connected", ok))
        except Exception as e:
            self.events.put(("error", f"Could not open {self.port}: {e}"))
            return
        while self.running:
            try:
                cmd = self.cmd_q.get(timeout=0.0 if self.live else 0.05)
            except queue.Empty:
                cmd = None
            try:
                if cmd is not None:
                    self._do(cmd)
                elif self.live:
                    self.latest = self.reader.frame()
                    self.frame_id += 1
            except Exception as e:
                self.live = False
                self.events.put(("error", str(e)))
        self.reader.close()

    def _do(self, cmd):
        name, args = cmd[0], cmd[1:]
        r = self.reader
        if name == "mask":
            r.mask(args[0])
        elif name == "set":
            r.set(args[0], args[1])
        elif name == "live":
            self.live = bool(args[0])
        elif name == "session":
            leds, exps, gain, res, quality, folder = args
            self.live = False
            r.mask(0)
            r.set("res", res)
            r.set("quality", quality)
            imgs, darks = r.capture_sequence(leds, exps, gain=gain, with_dark=True)
            save_session(folder, imgs, darks)
            self.events.put(("session", folder, imgs, darks))
        elif name == "quit":
            self.running = False


# =============================================================================
#  GUI
# =============================================================================
class App(tk.Tk if tk else object):
    def __init__(self):
        super().__init__()
        self.title("LFA bench - LEDs, focus, session")
        self.worker = None
        self.photo = None
        self.seen = -1
        self.peak = 0.0
        self._deb = None
        self._build()
        self.after(30, self._tick)
        self.protocol("WM_DELETE_WINDOW", self._close)

    def _build(self):
        left = ttk.Frame(self, padding=8)
        left.pack(side="left", fill="y")
        self.view = tk.Label(self, bg="black", width=80, height=30)
        self.view.pack(side="left", fill="both", expand=True)

        def box(t):
            f = ttk.LabelFrame(left, text=t, padding=6)
            f.pack(fill="x", pady=4)
            return f

        b = box("1. Connection")
        self.port = tk.StringVar()
        self.port_cb = ttk.Combobox(b, textvariable=self.port, width=14)
        self.port_cb.grid(row=0, column=0)
        ttk.Button(b, text="Refresh", command=self._ports).grid(row=0, column=1)
        self.btn_conn = ttk.Button(b, text="Connect", command=self.connect)
        self.btn_conn.grid(row=0, column=2)
        self._ports()

        b = box("2. LEDs (any combination)")
        self.led_var = {}
        for i, (k, label, bit) in enumerate(LEDS):
            self.led_var[k] = tk.BooleanVar(value=False)
            ttk.Checkbutton(b, text=f"{k}  {label}", variable=self.led_var[k],
                            command=self.send_mask).grid(row=i, column=0, sticky="w")
        ttk.Button(b, text="All off", command=self.all_off).grid(row=4, column=0, sticky="ew", pady=2)

        b = box("3. Live view / focus")
        self.btn_live = ttk.Button(b, text="Start live", command=self.toggle_live)
        self.btn_live.grid(row=0, column=0, columnspan=2, sticky="ew")
        ttk.Label(b, text="Preview size").grid(row=1, column=0, sticky="w")
        self.prev_res = tk.StringVar(value="VGA")
        ttk.Combobox(b, textvariable=self.prev_res, values=["QVGA", "VGA", "SVGA"], width=7).grid(row=1, column=1)
        ttk.Label(b, text="Exposure").grid(row=2, column=0, sticky="w")
        self.exp = tk.IntVar(value=300)
        ttk.Scale(b, from_=0, to=1200, variable=self.exp, command=lambda _v: self._debounce()).grid(row=2, column=1, sticky="ew")
        self.exp_lbl = ttk.Label(b, text="300", width=5)
        self.exp_lbl.grid(row=2, column=2)
        ttk.Label(b, text="Gain").grid(row=3, column=0, sticky="w")
        self.gain = tk.IntVar(value=0)
        ttk.Scale(b, from_=0, to=30, variable=self.gain, command=lambda _v: self._debounce()).grid(row=3, column=1, sticky="ew")
        self.gain_lbl = ttk.Label(b, text="0", width=5)
        self.gain_lbl.grid(row=3, column=2)
        self.zoom = tk.BooleanVar(value=False)
        ttk.Checkbutton(b, text="2x zoom on centre", variable=self.zoom).grid(row=4, column=0, columnspan=2, sticky="w")
        ttk.Button(b, text="Reset peak", command=lambda: setattr(self, "peak", 0.0)).grid(row=5, column=0, columnspan=2, sticky="ew")

        b = box("4. Session")
        self.sess_use, self.sess_exp = {}, {}
        for i, (k, label, bit) in enumerate(LEDS):
            self.sess_use[k] = tk.BooleanVar(value=True)
            self.sess_exp[k] = tk.StringVar(value=str(DEFAULT_EXP[k]))
            ttk.Checkbutton(b, text=f"{k} exposure", variable=self.sess_use[k]).grid(row=i, column=0, sticky="w")
            ttk.Entry(b, textvariable=self.sess_exp[k], width=6).grid(row=i, column=1)
            ttk.Button(b, text="<-", width=3, command=lambda kk=k: self.sess_exp[kk].set(str(self.exp.get()))).grid(row=i, column=2)
        ttk.Label(b, text="Size").grid(row=4, column=0, sticky="w")
        self.sess_res = tk.StringVar(value="SXGA")
        ttk.Combobox(b, textvariable=self.sess_res, values=["SVGA", "XGA", "SXGA", "UXGA"], width=7).grid(row=4, column=1)
        self.btn_sess = ttk.Button(b, text="Run session", command=self.run_session)
        self.btn_sess.grid(row=5, column=0, columnspan=3, sticky="ew", pady=3)

        self.status = tk.StringVar(value="Not connected")
        ttk.Label(left, textvariable=self.status, wraplength=250, foreground="#444").pack(pady=6)

    # ---- helpers -----------------------------------------------------------------
    def _ports(self):
        ports = list_ports()
        self.port_cb["values"] = ports
        if ports and not self.port.get():
            self.port.set(ports[-1])

    def _msg(self, s):
        self.status.set(s)

    def _need(self):
        if not self.worker:
            self._msg("Connect first")
            return False
        return True

    def connect(self):
        if self.worker:
            self.worker.send("quit")
            self.worker = None
            self.btn_conn.config(text="Connect")
            self.btn_live.config(text="Start live")
            self._msg("Disconnected")
            return
        self.worker = Worker(self.port.get())
        self.worker.start()
        self.btn_conn.config(text="Disconnect")
        self._msg("Connecting...")

    def mask_value(self):
        return sum(bit for k, _l, bit in LEDS if self.led_var[k].get())

    def send_mask(self):
        if self._need():
            self.worker.send("mask", self.mask_value())

    def all_off(self):
        for v in self.led_var.values():
            v.set(False)
        self.send_mask()

    def _debounce(self):
        self.exp_lbl.config(text=str(int(self.exp.get())))
        self.gain_lbl.config(text=str(int(self.gain.get())))
        if self._deb:
            self.after_cancel(self._deb)
        self._deb = self.after(150, self._apply_exposure)

    def _apply_exposure(self):
        if self.worker:
            self.worker.send("set", "exposure", int(self.exp.get()))
            self.worker.send("set", "gain", int(self.gain.get()))

    def toggle_live(self):
        if not self._need():
            return
        if self.worker.live:
            self.worker.live = False
            self.btn_live.config(text="Start live")
            return
        self.worker.send("set", "res", self.prev_res.get())
        self.worker.send("set", "quality", 12)
        self._apply_exposure()
        self.send_mask()
        self.worker.send("live", True)
        self.btn_live.config(text="Stop live")

    # ---- session -----------------------------------------------------------------
    def run_session(self):
        if not self._need():
            return
        leds = [k for k, _l, _b in LEDS if self.sess_use[k].get()]
        try:
            exps = {k: int(self.sess_exp[k].get()) for k in leds}
        except ValueError:
            return self._msg("Exposure entries must be whole numbers")
        folder = os.path.join("sessions", dt.datetime.now().strftime("%Y%m%d_%H%M%S"))
        for v in self.led_var.values():
            v.set(False)
        self.btn_live.config(text="Start live")
        self.btn_sess.state(["disabled"])
        self._msg("Running session (about 10-20 s) - keep the box closed")
        self.worker.live = False
        self.worker.send("session", leds, exps, int(self.gain.get()), self.sess_res.get(), 4, folder)

    def _session_done(self, folder, imgs, darks):
        self.btn_sess.state(["!disabled"])
        notes = []
        for k, im in imgs.items():
            ch = {"G": 1, "W": 1, "R": 2, "B": 0}[k]
            p = np.percentile(im[:, :, ch], 99.9)
            notes.append(f"{k}:{p:.0f}" + (" CLIPPED-lower exposure" if p >= 253 else (" dim" if p < 90 else "")))
        self._msg(f"Saved {folder}\nbright-pixel level (aim 150-230): " + ", ".join(notes))
        self._results_window(folder, imgs, darks)

    def _results_window(self, folder, imgs, darks):
        from lfa_analysis import AnalysisParams, analyze_sequence, detect_bands, windows_to_bands
        res, err, det, scores = None, None, None, {}
        try:
            if not imgs:
                raise ValueError("No LED images were captured")
            params = AnalysisParams(band_names=("T", "C"))
            res = analyze_sequence(imgs, darks, None, params)

            # Rank each LED on assay-band clarity, focus, and clipping. The
            # customer/operator never has to choose an image or channel.
            channel_bands = {}
            channel_noise = {}
            for led, profile in res.A.items():
                bands, sigma = detect_bands(profile, params)
                channel_bands[led] = bands
                channel_noise[led] = sigma

                top_snrs = sorted((max(0.0, float(b.snr)) for b in bands), reverse=True)[:2]
                band_score = sum(min(snr, 20.0) for snr in top_snrs)
                band_score += 7.0 * min(len(bands), 2)

                crop = res.crops[led]
                clipped = float(((crop <= 3) | (crop >= 252)).mean())
                sharpness = float(cv2.Laplacian(crop.astype(np.float32), cv2.CV_32F).var())
                focus_score = min(float(np.log1p(max(0.0, sharpness))), 8.0)
                scores[led] = band_score + focus_score - 25.0 * clipped

            det = max(scores, key=scores.get)
            params.detect_led = det
            res.params.detect_led = det
            res.bands = channel_bands[det]
            res.noise[det] = channel_noise[det]
            windows = [(b.name, b.left, b.right) for b in res.bands]
            res.per_led = {
                led: windows_to_bands(profile, windows, params)
                for led, profile in res.A.items()
            }
            self._msg(
                f"Saved {folder}\nAuto-selected {det} LED for detection. "
                + "  ".join(f"{led}: {score:.1f}" for led, score in scores.items())
            )
        except Exception as e:
            err = e
            res = None
        win = tk.Toplevel(self)
        win.title(f"Session {os.path.basename(folder)}")
        fig = Figure(figsize=(11, 6.5), layout="constrained")
        n = len(imgs)
        gs = fig.add_gridspec(2, n, height_ratios=[1, 1])
        for i, (k, im) in enumerate(imgs.items()):
            ax = fig.add_subplot(gs[0, i])
            ax.imshow(cv2.cvtColor(im, cv2.COLOR_BGR2RGB))
            choice = " · AUTO SELECTED" if k == det else ""
            score_note = f"\nscore {scores[k]:.1f}" if k in scores else ""
            ax.set_title(f"LED {k}{choice}{score_note}", fontsize=9)
            ax.axis("off")
            if res is not None:
                c = res.roi.corners()
                ax.plot(*np.vstack([c, c[:1]]).T, "c-", lw=0.8)
        axp = fig.add_subplot(gs[1, :])
        if res is not None:
            fig.suptitle(f"Automatic detection channel: LED {det}", fontsize=12)
            col = {"G": "tab:green", "W": "0.4", "R": "tab:red", "B": "tab:blue"}
            for k, a in res.A.items():
                axp.plot(a, color=col.get(k, "k"), label=f"LED {k}")
            for b in res.bands:
                axp.axvspan(b.left, b.right, color="orange", alpha=0.15)
                axp.text(b.pos_px, axp.get_ylim()[1] * 0.9, f"{b.name}\nA={b.height:.3f}", ha="center", fontsize=8)
            axp.set_xlabel("position along strip (px)")
            axp.set_ylabel("absorbance")
            axp.legend(fontsize=8)
        else:
            axp.text(0.5, 0.5, f"Analysis skipped: {err}\n(images are saved - open the folder in lfa_gui.py)",
                     ha="center", va="center", transform=axp.transAxes)
            axp.axis("off")
        FigureCanvasTkAgg(fig, master=win).get_tk_widget().pack(fill="both", expand=True)

    # ---- live frame + events -------------------------------------------------------
    def _tick(self):
        w = self.worker
        if w:
            try:
                while True:
                    ev = w.events.get_nowait()
                    if ev[0] == "connected":
                        self._msg("Connected - board answered PING" if ev[1] else
                                  "Port opened but the board did not answer PING (see README troubleshooting)")
                    elif ev[0] == "error":
                        self._msg("Error: " + ev[1])
                        self.btn_live.config(text="Start live")
                        self.btn_sess.state(["!disabled"])
                    elif ev[0] == "session":
                        self._session_done(*ev[1:])
            except queue.Empty:
                pass
            if w.latest is not None and w.frame_id != self.seen:
                self.seen = w.frame_id
                self._show(w.latest)
        self.after(30, self._tick)

    def _show(self, frame):
        h, w = frame.shape[:2]
        y0, y1, x0, x1 = h // 4, 3 * h // 4, w // 4, 3 * w // 4
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        core = gray[y0:y1, x0:x1]
        score = float(cv2.Laplacian(core, cv2.CV_64F).var())
        self.peak = max(self.peak, score)
        sat = float((core >= 250).mean() * 100)
        img = frame.copy()
        if self.zoom.get():
            img = cv2.resize(img[y0:y1, x0:x1], None, fx=2, fy=2, interpolation=cv2.INTER_LINEAR)
        else:
            cv2.rectangle(img, (x0, y0), (x1, y1), (255, 255, 0), 1)
            cv2.line(img, (w // 2, 0), (w // 2, h), (255, 255, 0), 1)
            cv2.line(img, (0, h // 2), (w, h // 2), (255, 255, 0), 1)
        txt = f"FOCUS {score:7.1f}  (peak {self.peak:.1f})   SAT {sat:4.1f}%   max {int(core.max())}"
        cv2.putText(img, txt, (8, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 3)
        cv2.putText(img, txt, (8, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 1)
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        hh, ww = rgb.shape[:2]
        self.photo = tk.PhotoImage(data=b"P6\n%d %d\n255\n" % (ww, hh) + rgb.tobytes())
        self.view.config(image=self.photo, width=ww, height=hh)

    def _close(self):
        if self.worker:
            self.worker.send("quit")
        self.destroy()


def main():
    if tk is None:
        sys.exit("tkinter / matplotlib missing - on Linux: sudo apt install python3-tk; pip install -r requirements.txt")
    App().mainloop()


if __name__ == "__main__":
    main()
