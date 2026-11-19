"""
lfa_gui.py - desktop GUI for the ESP32-S3 lateral-flow strip reader.

    pip install -r requirements.txt
    python lfa_gui.py

Workflow
  1. Connect to the board, press "Capture sequence" (or "Open session folder" to
     re-analyse saved images; try the folder produced by --demo).
  2. "Auto ROI" finds the strip; or drag a rectangle on the image to set it by hand.
  3. "Analyze": bands are detected on the detect-LED profile and measured on every LED.
  4. Calibration: enter the known concentration -> "Add standard"; after >= 3-5
     standards press "Fit calibration". Unknown strips then get a predicted conc.
"""
from __future__ import annotations

import csv
import datetime as dt
import os
import queue
import sys
import threading
from dataclasses import replace
from typing import Dict, List, Optional

import cv2
import numpy as np

from lfa_analysis import (AnalysisParams, AnalysisResult, Calibration, Roi, analyze_sequence,
                          band_signal, find_strip, fit_calibration)

try:                                   # GUI libs are optional so Session can be unit-tested headless
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
    from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
    from matplotlib.figure import Figure
    from matplotlib.widgets import RectangleSelector
except ImportError:                    # pragma: no cover
    tk = None

HORMONES = ["LH", "E3G", "PDG", "FSH", "other"]
LEDS = ["G", "W", "R", "B"]
DEFAULT_EXPOSURE = {"G": 300, "W": 150, "R": 300, "B": 450}


# =============================================================================
#  Session: all the non-GUI state & logic
# =============================================================================
class Session:
    def __init__(self, workdir: str = "lfa_data"):
        self.workdir = workdir
        os.makedirs(workdir, exist_ok=True)
        self.images: Dict[str, np.ndarray] = {}
        self.darks: Dict[str, np.ndarray] = {}
        self.roi: Optional[Roi] = None
        self.params = AnalysisParams(band_names=("T", "C"))
        self.result: Optional[AnalysisResult] = None
        self.calibrations: Dict[str, Calibration] = {}
        self.refs: Dict[str, np.ndarray] = {}
        self._load_calibrations()

    # ---- ROI / analysis ----------------------------------------------------------
    def auto_roi(self) -> Optional[Roi]:
        if not self.images:
            return None
        src = self.images.get("W", next(iter(self.images.values())))
        self.roi = find_strip(cv2.cvtColor(src, cv2.COLOR_BGR2GRAY), self.params.invert)
        return self.roi

    def analyze(self) -> AnalysisResult:
        if not self.images:
            raise ValueError("No images loaded")
        self.result = analyze_sequence(self.images, self.darks, self.roi, self.params, self.refs or None)
        self.roi = self.result.roi
        return self.result

    def lock_windows(self, on: bool):
        """Freeze the current band windows so faint/absent bands are still integrated."""
        if on and self.result:
            self.params = replace(self.params, fixed_windows=[(b.name, b.left, b.right) for b in self.result.bands])
        else:
            self.params = replace(self.params, fixed_windows=None)

    def set_blank_reference(self):
        """Use the current strip profiles as flat-field reference (use a BLANK strip or white card)."""
        if not self.result:
            raise ValueError("Analyze a blank strip first")
        self.refs = {led: c.mean(0) for led, c in self.result.crops.items()}

    def signal(self, led, test, control, metric) -> float:
        return band_signal(self.result, led, test, control, metric) if self.result else float("nan")

    # ---- standards & calibration ---------------------------------------------------
    @property
    def standards_path(self):
        return os.path.join(self.workdir, "standards.csv")

    def add_standard(self, hormone, conc, signal, signal_def):
        new = not os.path.exists(self.standards_path)
        with open(self.standards_path, "a", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["timestamp", "hormone", "conc", "signal", "signal_def"])
            w.writerow([dt.datetime.now().isoformat(timespec="seconds"), hormone, conc, signal, signal_def])

    def standards(self, hormone, signal_def=None):
        xs, ys = [], []
        if os.path.exists(self.standards_path):
            with open(self.standards_path) as f:
                for r in csv.DictReader(f):
                    if r["hormone"] == hormone and (signal_def is None or r["signal_def"] == signal_def):
                        xs.append(float(r["conc"]))
                        ys.append(float(r["signal"]))
        return xs, ys

    def fit(self, hormone, signal_def, model="auto", units="") -> Calibration:
        x, y = self.standards(hormone, signal_def)
        cal = fit_calibration(hormone, x, y, model, signal_def, units)
        self.calibrations[hormone] = cal
        cal.save(os.path.join(self.workdir, f"calibration_{hormone}.json"))
        return cal

    def _load_calibrations(self):
        for fn in os.listdir(self.workdir):
            if fn.startswith("calibration_") and fn.endswith(".json"):
                try:
                    c = Calibration.load(os.path.join(self.workdir, fn))
                    self.calibrations[c.hormone] = c
                except Exception:
                    pass

    def predict(self, hormone, signal) -> float:
        cal = self.calibrations.get(hormone)
        if cal is None or not np.isfinite(signal):
            return float("nan")
        return float(cal.predict(signal))

    # ---- results log -----------------------------------------------------------------
    def log_result(self, sample_id, hormone, conc, signal_def, signal, predicted):
        path = os.path.join(self.workdir, "measurements.csv")
        new = not os.path.exists(path)
        with open(path, "a", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["timestamp", "sample_id", "hormone", "known_conc", "led", "band", "pos_px",
                            "height_A", "area_A_px", "snr", "signal_def", "signal", "predicted_conc"])
            for led, bands in self.result.per_led.items():
                for b in bands:
                    w.writerow([dt.datetime.now().isoformat(timespec="seconds"), sample_id, hormone, conc,
                                led, b.name, f"{b.pos_px:.1f}", f"{b.height:.4f}", f"{b.area:.4f}",
                                f"{b.snr:.1f}", signal_def, f"{signal:.5g}", f"{predicted:.5g}"])
        return path


# =============================================================================
#  GUI
# =============================================================================
class App(tk.Tk if tk else object):
    def __init__(self, workdir="lfa_data"):
        super().__init__()
        self.title("LFA strip reader")
        self.geometry("1350x860")
        self.S = Session(workdir)
        self.reader = None
        self.q: "queue.Queue" = queue.Queue()
        self.selector = None
        self._build()
        self.after(100, self._poll)

    # ---- layout --------------------------------------------------------------------
    def _build(self):
        left = ttk.Frame(self, padding=6)
        left.pack(side="left", fill="y")
        right = ttk.Frame(self, padding=4)
        right.pack(side="left", fill="both", expand=True)

        def box(title):
            lf = ttk.LabelFrame(left, text=title, padding=5)
            lf.pack(fill="x", pady=3)
            return lf

        # camera / connection
        b = box("Instrument")
        self.port = tk.StringVar()
        self.port_cb = ttk.Combobox(b, textvariable=self.port, width=16)
        self.port_cb.grid(row=0, column=0, columnspan=2)
        ttk.Button(b, text="Refresh", command=self._refresh_ports).grid(row=0, column=2)
        ttk.Button(b, text="Connect", command=self.connect).grid(row=0, column=3)
        self.res = tk.StringVar(value="SXGA")
        ttk.Label(b, text="Resolution").grid(row=1, column=0, sticky="w")
        ttk.Combobox(b, textvariable=self.res, values=["VGA", "SVGA", "XGA", "SXGA", "UXGA"],
                     width=7).grid(row=1, column=1)
        ttk.Button(b, text="Apply", command=self.apply_res).grid(row=1, column=2)
        self.led_use, self.led_exp = {}, {}
        for i, led in enumerate(LEDS):
            self.led_use[led] = tk.BooleanVar(value=True)
            self.led_exp[led] = tk.StringVar(value=str(DEFAULT_EXPOSURE[led]))
            ttk.Checkbutton(b, text=f"LED {led}  exp", variable=self.led_use[led]).grid(row=2 + i, column=0, columnspan=2, sticky="w")
            ttk.Entry(b, textvariable=self.led_exp[led], width=6).grid(row=2 + i, column=2)
        self.dark_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(b, text="dark frame per LED", variable=self.dark_var).grid(row=6, column=0, columnspan=3, sticky="w")
        ttk.Button(b, text="Capture sequence", command=self.capture_sequence).grid(row=7, column=0, columnspan=2, sticky="ew")
        ttk.Button(b, text="Live W frame", command=self.capture_one).grid(row=7, column=2, columnspan=2, sticky="ew")
        ttk.Button(b, text="Open session folder", command=self.open_folder).grid(row=8, column=0, columnspan=2, sticky="ew")
        ttk.Button(b, text="Save session", command=self.save_folder).grid(row=8, column=2, columnspan=2, sticky="ew")

        # analysis
        b = box("Analysis")
        self.invert = tk.BooleanVar(value=False)
        ttk.Checkbutton(b, text="strip darker than background", variable=self.invert).grid(row=0, column=0, columnspan=3, sticky="w")
        ttk.Button(b, text="Auto ROI", command=self.auto_roi).grid(row=1, column=0, sticky="ew")
        ttk.Label(b, text="(or drag a box on the image)").grid(row=1, column=1, columnspan=2)
        self.detect_led = tk.StringVar(value="G")
        ttk.Label(b, text="Detect on LED").grid(row=2, column=0, sticky="w")
        ttk.Combobox(b, textvariable=self.detect_led, values=LEDS, width=4).grid(row=2, column=1)
        self.names = tk.StringVar(value="T,C")
        ttk.Label(b, text="Band names").grid(row=3, column=0, sticky="w")
        ttk.Entry(b, textvariable=self.names, width=14).grid(row=3, column=1, columnspan=2)
        self.snr = tk.StringVar(value="5")
        ttk.Label(b, text="Min SNR").grid(row=4, column=0, sticky="w")
        ttk.Entry(b, textvariable=self.snr, width=6).grid(row=4, column=1)
        self.lock = tk.BooleanVar(value=False)
        ttk.Checkbutton(b, text="lock band windows", variable=self.lock, command=self.toggle_lock).grid(row=5, column=0, columnspan=3, sticky="w")
        ttk.Button(b, text="Analyze", command=self.analyze).grid(row=6, column=0, sticky="ew")
        ttk.Button(b, text="Use as blank (flat-field)", command=self.set_blank).grid(row=6, column=1, columnspan=2, sticky="ew")

        # assay
        b = box("Assay / calibration")
        self.hormone = tk.StringVar(value="LH")
        ttk.Label(b, text="Hormone").grid(row=0, column=0, sticky="w")
        ttk.Combobox(b, textvariable=self.hormone, values=HORMONES, width=7).grid(row=0, column=1)
        self.sig_led = tk.StringVar(value="G")
        ttk.Label(b, text="Signal LED").grid(row=1, column=0, sticky="w")
        ttk.Combobox(b, textvariable=self.sig_led, values=LEDS, width=4).grid(row=1, column=1)
        self.metric = tk.StringVar(value="area")
        ttk.Combobox(b, textvariable=self.metric, values=["area", "height"], width=7).grid(row=1, column=2)
        self.test_i, self.ctrl_i = tk.StringVar(value="0"), tk.StringVar(value="1")
        ttk.Label(b, text="Test band #").grid(row=2, column=0, sticky="w")
        ttk.Entry(b, textvariable=self.test_i, width=4).grid(row=2, column=1)
        ttk.Label(b, text="Control # (blank=none)").grid(row=3, column=0, columnspan=2, sticky="w")
        ttk.Entry(b, textvariable=self.ctrl_i, width=4).grid(row=3, column=2)
        self.conc = tk.StringVar()
        ttk.Label(b, text="Known conc").grid(row=4, column=0, sticky="w")
        ttk.Entry(b, textvariable=self.conc, width=8).grid(row=4, column=1)
        self.units = tk.StringVar(value="mIU/mL")
        ttk.Entry(b, textvariable=self.units, width=8).grid(row=4, column=2)
        ttk.Button(b, text="Add as standard", command=self.add_standard).grid(row=5, column=0, columnspan=2, sticky="ew")
        ttk.Button(b, text="Fit calibration", command=self.fit).grid(row=5, column=2, columnspan=2, sticky="ew")
        self.sample = tk.StringVar(value="sample1")
        ttk.Label(b, text="Sample ID").grid(row=6, column=0, sticky="w")
        ttk.Entry(b, textvariable=self.sample, width=10).grid(row=6, column=1, columnspan=2)
        ttk.Button(b, text="Log result to CSV", command=self.log).grid(row=7, column=0, columnspan=3, sticky="ew")
        self.out = tk.StringVar(value="-")
        ttk.Label(left, textvariable=self.out, wraplength=260, font=("TkDefaultFont", 10, "bold")).pack(pady=8)
        self.status = tk.StringVar(value="Ready")
        ttk.Label(left, textvariable=self.status, wraplength=260, foreground="#555").pack()

        # plots + table
        self.fig = Figure(figsize=(9, 6), dpi=100, layout="constrained")
        gs = self.fig.add_gridspec(2, 2, height_ratios=[1.1, 1])
        self.ax_img = self.fig.add_subplot(gs[0, 0])
        self.ax_crop = self.fig.add_subplot(gs[0, 1])
        self.ax_prof = self.fig.add_subplot(gs[1, :])
        self.canvas = FigureCanvasTkAgg(self.fig, master=right)
        self.canvas.get_tk_widget().pack(fill="both", expand=True)
        NavigationToolbar2Tk(self.canvas, right)
        cols = ("led", "band", "pos_px", "height_A", "area", "snr")
        self.tree = ttk.Treeview(right, columns=cols, show="headings", height=7)
        for c in cols:
            self.tree.heading(c, text=c)
            self.tree.column(c, width=90, anchor="center")
        self.tree.pack(fill="x")
        self._refresh_ports()
        self.selector = RectangleSelector(self.ax_img, self._on_rect, useblit=True, button=[1],
                                          interactive=True, minspanx=5, minspany=5)

    # ---- helpers ---------------------------------------------------------------------
    def _msg(self, s):
        self.status.set(s)
        self.update_idletasks()

    def _refresh_ports(self):
        try:
            from lfa_capture import list_ports
            ports = list_ports()
        except Exception:
            ports = []
        self.port_cb["values"] = ports
        if ports and not self.port.get():
            self.port.set(ports[-1])

    def _sync_params(self):
        names = tuple(n.strip() for n in self.names.get().split(",") if n.strip())
        self.S.params = replace(self.S.params, detect_led=self.detect_led.get(), band_names=names,
                                snr_min=float(self.snr.get() or 5), invert=self.invert.get())

    def _ctrl(self):
        s = self.ctrl_i.get().strip()
        return int(s) if s else None

    def _signal_def(self):
        c = self._ctrl()
        return f"{self.sig_led.get()}:{self.metric.get()}:T{self.test_i.get()}" + (f"/C{c}" if c is not None else "")

    # ---- instrument ------------------------------------------------------------------
    def connect(self):
        try:
            from lfa_capture import Reader
            if self.reader:
                self.reader.close()
            self.reader = Reader(self.port.get())
            self._msg("Connected: " + ("board OK" if self.reader.ping() else "no answer"))
        except Exception as e:
            self.reader = None
            messagebox.showerror("Connect", str(e))

    def apply_res(self):
        if self.reader:
            try:
                self.reader.set("res", self.res.get())
                self._msg("Resolution set")
            except Exception as e:
                messagebox.showerror("Resolution", str(e))

    def _run_bg(self, fn, done):
        def work():
            try:
                self.q.put(("ok", done, fn()))
            except Exception as e:
                self.q.put(("err", None, e))
        threading.Thread(target=work, daemon=True).start()

    def _poll(self):
        try:
            while True:
                kind, done, val = self.q.get_nowait()
                if kind == "ok":
                    done(val)
                else:
                    self._msg("Error")
                    messagebox.showerror("Error", str(val))
        except queue.Empty:
            pass
        self.after(100, self._poll)

    def capture_sequence(self):
        if not self.reader:
            return messagebox.showinfo("Capture", "Connect to the board first")
        leds = [l for l in LEDS if self.led_use[l].get()]
        exps = {l: int(self.led_exp[l].get()) for l in leds}
        dark = self.dark_var.get()
        self._msg("Capturing...")

        def done(res):
            self.S.images, self.S.darks = res
            self.S.roi = None
            self._msg("Captured " + ", ".join(res[0]))
            self.auto_roi()

        self._run_bg(lambda: self.reader.capture_sequence(leds, exps, with_dark=dark), done)

    def capture_one(self):
        if not self.reader:
            return messagebox.showinfo("Capture", "Connect to the board first")
        led = "W" if self.led_use["W"].get() else next(l for l in LEDS if self.led_use[l].get())
        exp = int(self.led_exp[led].get())

        def done(img):
            self.S.images, self.S.darks = {led: img}, {}
            self._draw()
            self._msg(f"Live frame ({led})")

        self._run_bg(lambda: self.reader.capture(led, exp, 0), done)

    def open_folder(self):
        d = filedialog.askdirectory(title="Session folder (G.png, W.png, B.png, dark_G.png ...)")
        if d:
            from lfa_capture import load_session
            self.S.images, self.S.darks = load_session(d)
            self.S.roi = None
            self.load_dir = d
            self._msg(f"Loaded {list(self.S.images)} from {os.path.basename(d)}")
            self.auto_roi()

    def save_folder(self):
        d = filedialog.askdirectory(title="Save session to folder")
        if d and self.S.images:
            from lfa_capture import save_session
            save_session(d, self.S.images, self.S.darks)
            self._msg("Saved")

    # ---- analysis --------------------------------------------------------------------
    def auto_roi(self):
        self._sync_params()
        if self.S.auto_roi() is None:
            self._msg("Strip not found - drag a box on the image")
        self._draw()

    def _on_rect(self, eclick, erelease):
        if eclick.xdata is None or erelease.xdata is None:
            return
        self.S.roi = Roi.from_rect(eclick.xdata, eclick.ydata, erelease.xdata, erelease.ydata)
        self._msg("Manual ROI set")

    def toggle_lock(self):
        self.S.lock_windows(self.lock.get())

    def set_blank(self):
        try:
            self.S.set_blank_reference()
            self._msg("Flat-field reference stored (this session)")
        except Exception as e:
            messagebox.showerror("Blank", str(e))

    def analyze(self):
        try:
            self._sync_params()
            if self.lock.get() is False:
                self.S.params = replace(self.S.params, fixed_windows=None)
            res = self.S.analyze()
        except Exception as e:
            return messagebox.showerror("Analyze", str(e))
        self._draw()
        self._fill_table(res)
        try:
            sig = self.S.signal(self.sig_led.get(), int(self.test_i.get()), self._ctrl(), self.metric.get())
        except ValueError:
            sig = float("nan")
        pred = self.S.predict(self.hormone.get(), sig)
        txt = f"signal [{self._signal_def()}] = {sig:.4g}"
        if np.isfinite(pred):
            txt += f"\n{self.hormone.get()} ~ {pred:.3g} {self.units.get()}"
        elif self.hormone.get() in self.S.calibrations:
            txt += "\n(outside calibration range)"
        self.out.set(txt)
        self._last_signal, self._last_pred = sig, pred

    def _fill_table(self, res: AnalysisResult):
        self.tree.delete(*self.tree.get_children())
        for led, bands in res.per_led.items():
            for b in bands:
                self.tree.insert("", "end", values=(led, b.name, f"{b.pos_px:.0f}", f"{b.height:.3f}",
                                                    f"{b.area:.2f}", f"{b.snr:.0f}"))

    def _draw(self):
        S = self.S
        for ax in (self.ax_img, self.ax_crop, self.ax_prof):
            ax.clear()
        if S.images:
            led = "W" if "W" in S.images else next(iter(S.images))
            self.ax_img.imshow(cv2.cvtColor(S.images[led], cv2.COLOR_BGR2RGB))
            self.ax_img.set_title(f"LED {led}  (drag = manual ROI)", fontsize=9)
            if S.roi:
                c = S.roi.corners()
                self.ax_img.plot(*np.vstack([c, c[:1]]).T, "c-", lw=1)
        r = S.result
        if r:
            stack = [np.clip(c.mean(0, keepdims=True).repeat(max(3, c.shape[0] // 4), 0), 0, 255) for c in r.crops.values()]
            self.ax_crop.imshow(np.vstack(stack), cmap="gray", aspect="auto", vmin=0, vmax=255)
            self.ax_crop.set_yticks([(i + 0.5) * stack[0].shape[0] for i in range(len(stack))])
            self.ax_crop.set_yticklabels(list(r.crops.keys()))
            self.ax_crop.set_title("strip crops (one per LED)", fontsize=9)
            colors = {"G": "tab:green", "W": "0.4", "B": "tab:blue", "R": "tab:red"}
            for led, a in r.A.items():
                self.ax_prof.plot(a, color=colors.get(led, "k"), label=f"LED {led}", lw=1.2)
            for b in r.bands:
                self.ax_prof.axvspan(b.left, b.right, color="orange", alpha=0.15)
                self.ax_prof.text(b.pos_px, self.ax_prof.get_ylim()[1] * 0.92, b.name, ha="center", fontsize=9)
            self.ax_prof.set_xlabel("position along strip (px)")
            self.ax_prof.set_ylabel("absorbance (baseline-corrected)")
            self.ax_prof.legend(fontsize=8)
        self.canvas.draw_idle()
        self.selector = RectangleSelector(self.ax_img, self._on_rect, useblit=True, button=[1],
                                          interactive=True, minspanx=5, minspany=5)

    # ---- calibration -----------------------------------------------------------------
    def add_standard(self):
        if not self.S.result:
            return messagebox.showinfo("Standard", "Analyze a strip first")
        try:
            c = float(self.conc.get())
        except ValueError:
            return messagebox.showinfo("Standard", "Enter the known concentration")
        self.analyze()
        self.S.add_standard(self.hormone.get(), c, self._last_signal, self._signal_def())
        x, _ = self.S.standards(self.hormone.get(), self._signal_def())
        self._msg(f"Standard added ({len(x)} for {self.hormone.get()} / {self._signal_def()})")

    def fit(self):
        try:
            cal = self.S.fit(self.hormone.get(), self._signal_def(), units=self.units.get())
        except Exception as e:
            return messagebox.showerror("Fit", str(e))
        self.out.set(f"{cal.hormone}: {cal.model} fit, n={cal.n}, R^2={cal.r2:.4f}\nparams={['%.4g' % p for p in cal.params]}")

    def log(self):
        if not self.S.result:
            return
        self.analyze()
        p = self.S.log_result(self.sample.get(), self.hormone.get(), self.conc.get(), self._signal_def(),
                              self._last_signal, self._last_pred)
        self._msg("Logged to " + p)


def main():
    if tk is None:
        sys.exit("tkinter/matplotlib not available - install them (see README)")
    App().mainloop()


if __name__ == "__main__":
    if "--demo" in sys.argv:           # write a synthetic session folder you can open in the GUI
        from make_synthetic import synth_sequence
        from lfa_capture import save_session
        ims, dks = synth_sequence()
        save_session("demo_session", ims, dks)
        print("wrote demo_session/ - open it with 'Open session folder'")
    else:
        main()
