"""
lfa_analysis.py - quantify gold-nanoparticle lateral-flow strips from
single-colour-LED images.

Pipeline (per LED image):
    dark-subtract -> linearise gamma -> sample a strip-aligned ROI ->
    average across strip width -> 1-D profile -> absorbance A = -log10(I/I_baseline)
    -> peak finding / integration (band "intensity")

Why absorbance, and why the 530 nm LED matters:
    Colloidal gold (typically 20-40 nm particles) has its plasmon absorption at
    ~520-540 nm, so a green 530 nm LED gives the largest contrast between a red
    band and the white membrane. Blue is absorbed less; red hardly at all, so a
    red LED makes a good non-absorbing *reference* channel.

Signal definition used for calibration (your choice in the GUI):
    area of the test band  (or  test area / control area  to cancel out
    illumination / membrane / camera-distance variations).
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np
from scipy import sparse
from scipy.optimize import curve_fit
from scipy.signal import find_peaks, peak_widths, savgol_filter
from scipy.sparse.linalg import spsolve

_trapz = getattr(np, "trapezoid", None) or np.trapz

# Which colour channel of the (BGR) camera image to use for each LED.
BGR_INDEX = {"B": 0, "G": 1, "R": 2}
LED_CHANNEL = {"G": "G", "W": "G", "B": "B", "R": "R", "X": "R"}


# =============================================================================
#  Geometry
# =============================================================================
@dataclass
class Roi:
    """Rotated rectangle. `length` runs along the strip (direction angle_deg from
    the +x axis, image coords with y pointing down), `width` across it."""
    cx: float
    cy: float
    length: float
    width: float
    angle_deg: float = 0.0

    def corners(self) -> np.ndarray:
        t = math.radians(self.angle_deg)
        e1 = np.array([math.cos(t), math.sin(t)])
        e2 = np.array([-math.sin(t), math.cos(t)])
        c = np.array([self.cx, self.cy])
        hl, hw = self.length / 2, self.width / 2
        return np.array([c - e1 * hl - e2 * hw, c + e1 * hl - e2 * hw,
                         c + e1 * hl + e2 * hw, c - e1 * hl + e2 * hw])

    @staticmethod
    def from_rect(x0, y0, x1, y1) -> "Roi":
        """Axis-aligned rectangle (e.g. dragged with the mouse)."""
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        w, h = x1 - x0, y1 - y0
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        return Roi(cx, cy, w, h, 0.0) if w >= h else Roi(cx, cy, h, w, 90.0)

    def to_dict(self):
        return asdict(self)

    @staticmethod
    def from_dict(d) -> "Roi":
        return Roi(**d)


def find_strip(gray: np.ndarray, invert: bool = False, min_area: int = 300) -> Optional[Roi]:
    """Locate the strip as the largest bright blob (Otsu) and fit a rotated box
    using PCA. Set invert=True if the strip is darker than its surroundings."""
    g = cv2.GaussianBlur(gray.astype(np.float32), (0, 0), 2)
    g8 = cv2.normalize(g, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    flag = (cv2.THRESH_BINARY_INV if invert else cv2.THRESH_BINARY) | cv2.THRESH_OTSU
    _, mask = cv2.threshold(g8, 0, 255, flag)
    k = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, k)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if n < 2:
        return None
    best = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    if stats[best, cv2.CC_STAT_AREA] < min_area:
        return None
    ys, xs = np.nonzero(labels == best)
    pts = np.column_stack([xs, ys]).astype(np.float64)
    c = pts.mean(0)
    evals, evecs = np.linalg.eigh(np.cov((pts - c).T))
    e1 = evecs[:, 1]
    if e1[0] < 0 or (abs(e1[0]) < 1e-9 and e1[1] < 0):
        e1 = -e1                      # strip start = left/top
    e2 = np.array([-e1[1], e1[0]])
    p1, p2 = (pts - c) @ e1, (pts - c) @ e2
    a1, b1 = np.percentile(p1, [0.5, 99.5])
    a2, b2 = np.percentile(p2, [0.5, 99.5])
    center = c + e1 * (a1 + b1) / 2 + e2 * (a2 + b2) / 2
    return Roi(float(center[0]), float(center[1]), float(b1 - a1), float(b2 - a2),
               math.degrees(math.atan2(e1[1], e1[0])))


def warp_roi(img: np.ndarray, roi: Roi) -> np.ndarray:
    """Resample the ROI to an upright rectangle: x = along strip, y = across."""
    L, W = max(2, int(round(roi.length))), max(2, int(round(roi.width)))
    t = math.radians(roi.angle_deg)
    c, s = math.cos(t), math.sin(t)
    tx = roi.cx - (L / 2) * c + (W / 2) * s
    ty = roi.cy - (L / 2) * s - (W / 2) * c
    M = np.array([[c, -s, tx], [s, c, ty]], dtype=np.float64)
    return cv2.warpAffine(img, M, (L, W), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_REPLICATE)


def channel_image(bgr: np.ndarray, led: str) -> np.ndarray:
    ch = BGR_INDEX[LED_CHANNEL.get(led, "G")]
    if bgr.ndim == 2:
        return bgr.astype(np.float32)
    return bgr[:, :, ch].astype(np.float32)


def _inner_rows(crop: np.ndarray, width_frac: float) -> np.ndarray:
    h = crop.shape[0]
    r0 = int(h * (1 - width_frac) / 2)
    return crop[r0:max(r0 + 1, h - r0)]


# =============================================================================
#  1-D signal processing
# =============================================================================
def als_baseline(y: np.ndarray, lam: float = 1e5, p: float = 0.01, niter: int = 10) -> np.ndarray:
    """Asymmetric least squares baseline (Eilers & Boelens 2005). Peaks above the
    baseline get weight p, so the baseline hugs the bottom of the signal."""
    L = len(y)
    D = sparse.diags([1.0, -2.0, 1.0], [0, -1, -2], shape=(L, L - 2))
    H = lam * D.dot(D.T)
    w = np.ones(L)
    z = y
    for _ in range(niter):
        W = sparse.spdiags(w, 0, L, L)
        z = spsolve(sparse.csc_matrix(W + H), w * y)
        w = p * (y > z) + (1 - p) * (y < z)
    return z


@dataclass
class AnalysisParams:
    detect_led: str = "G"            # LED whose image is used to locate bands
    band_names: Sequence[str] = ()   # names assigned in order from strip start
    width_frac: float = 0.5          # use the central 50 % across the strip width
    gamma: float = 2.2               # camera gamma to undo (1.0 = leave as is)
    lam: float = 1e5                 # baseline stiffness
    p: float = 0.01                  # baseline asymmetry
    smooth_px: int = 9               # Savitzky-Golay window for peak detection
    snr_min: float = 5.0             # a band must be >= snr_min * noise
    min_abs_prom: float = 0.01       # ... and at least this much absorbance
    min_dist_px: int = 15            # min spacing between bands
    invert: bool = False             # strip darker than background?
    px_per_mm: Optional[float] = None
    # If given, skip detection and integrate fixed windows: [(name, left_px, right_px), ...]
    fixed_windows: Optional[List[Tuple[str, int, int]]] = None


def absorbance_profile(prof: np.ndarray, dark: Optional[np.ndarray], gamma: float,
                       lam: float, p: float, ref: Optional[np.ndarray] = None) -> np.ndarray:
    """prof/dark in 0..255 camera counts -> baseline-corrected absorbance profile.
    `ref` is an optional profile from a blank strip/white card (flat-field)."""
    def lin(v, d=None):
        x = v.astype(np.float64) / 255.0
        if d is not None:
            x = x - d.astype(np.float64) / 255.0
        return np.clip(x, 1e-4, None) ** gamma

    I = lin(prof, dark)
    if ref is not None:
        I = I / np.clip(lin(ref, dark), 1e-6, None)
    a = -np.log10(I / np.percentile(I, 95))
    return a - als_baseline(a, lam, p)


@dataclass
class Band:
    name: str
    left: int
    right: int
    pos_px: float
    pos_mm: Optional[float]
    height: float
    area: float
    fwhm_px: float
    snr: float


def _noise(As: np.ndarray) -> float:
    return float(1.4826 * np.median(np.abs(As - np.median(As)))) + 1e-9


def detect_bands(A: np.ndarray, prm: AnalysisParams) -> Tuple[List[Band], float]:
    win = prm.smooth_px | 1
    As = savgol_filter(A, win, 2) if len(A) > win else A
    sigma = _noise(As)
    prom = max(prm.snr_min * sigma, prm.min_abs_prom)
    peaks, _ = find_peaks(As, prominence=prom, distance=prm.min_dist_px)
    bands: List[Band] = []
    if len(peaks):
        w = peak_widths(As, peaks, rel_height=0.5)
        wb = peak_widths(As, peaks, rel_height=0.9)
    for i, pk in enumerate(peaks):
        ext = 0.15 * (wb[3][i] - wb[2][i])
        l = max(0, int(math.floor(wb[2][i] - ext)))
        r = min(len(A) - 1, int(math.ceil(wb[3][i] + ext)))
        name = prm.band_names[i] if i < len(prm.band_names) else f"band{i + 1}"
        bands.append(Band(name, l, r, float(pk),
                          pk / prm.px_per_mm if prm.px_per_mm else None,
                          float(As[pk]), float(_trapz(A[l:r + 1])),
                          float(w[0][i]), float(As[pk] / sigma)))
    return bands, sigma


def windows_to_bands(A: np.ndarray, windows, prm: AnalysisParams) -> List[Band]:
    out = []
    sigma = _noise(A)
    for name, l, r in windows:
        l, r = max(0, int(l)), min(len(A) - 1, int(r))
        seg = A[l:r + 1]
        k = int(np.argmax(seg))
        out.append(Band(name, l, r, float(l + k), (l + k) / prm.px_per_mm if prm.px_per_mm else None,
                        float(seg[k]), float(_trapz(seg)), float(r - l) / 2, float(seg[k] / sigma)))
    return out


@dataclass
class AnalysisResult:
    roi: Roi
    params: AnalysisParams
    crops: Dict[str, np.ndarray]           # inner strip crop per LED (counts)
    A: Dict[str, np.ndarray]               # absorbance profile per LED
    bands: List[Band]                      # as measured on detect_led
    per_led: Dict[str, List[Band]]         # same windows measured on every LED
    noise: Dict[str, float]


def analyze_sequence(images: Dict[str, np.ndarray],
                     darks: Optional[Dict[str, np.ndarray]] = None,
                     roi: Optional[Roi] = None,
                     params: Optional[AnalysisParams] = None,
                     refs: Optional[Dict[str, np.ndarray]] = None) -> AnalysisResult:
    """images/darks: {led_name: BGR uint8 image}. refs: {led_name: 1-D reference profile}."""
    prm = params or AnalysisParams()
    darks = darks or {}
    refs = refs or {}

    if roi is None:
        src = images["W"] if "W" in images else next(iter(images.values()))
        gray = cv2.cvtColor(src, cv2.COLOR_BGR2GRAY) if src.ndim == 3 else src
        roi = find_strip(gray, prm.invert)
        if roi is None:
            raise ValueError("Strip not found - pass a manual ROI or check illumination")

    crops, A = {}, {}
    for led, img in images.items():
        crop = _inner_rows(warp_roi(channel_image(img, led), roi), prm.width_frac)
        crops[led] = crop
        dprof = None
        if led in darks:
            dprof = _inner_rows(warp_roi(channel_image(darks[led], led), roi), prm.width_frac).mean(0)
        A[led] = absorbance_profile(crop.mean(0), dprof, prm.gamma, prm.lam, prm.p, refs.get(led))

    det = prm.detect_led if prm.detect_led in A else next(iter(A))
    if prm.fixed_windows:
        bands = windows_to_bands(A[det], prm.fixed_windows, prm)
        noise = {led: _noise(a) for led, a in A.items()}
    else:
        bands, sig = detect_bands(A[det], prm)
        noise = {led: _noise(a) for led, a in A.items()}
        noise[det] = sig
    windows = [(b.name, b.left, b.right) for b in bands]
    per_led = {led: windows_to_bands(a, windows, prm) for led, a in A.items()}
    return AnalysisResult(roi, prm, crops, A, bands, per_led, noise)


def band_signal(res: AnalysisResult, led: str, test: int, control: Optional[int] = None,
                metric: str = "area") -> float:
    """Calibration signal: test band metric, optionally divided by the control band's."""
    bl = res.per_led.get(led, [])
    if test >= len(bl):
        return float("nan")
    t = getattr(bl[test], metric)
    if control is None:
        return float(t)
    if control >= len(bl):
        return float("nan")
    c = getattr(bl[control], metric)
    return float(t / c) if c else float("nan")


# =============================================================================
#  Calibration (signal -> concentration)
# =============================================================================
def four_pl(x, a, b, c, d):
    """a = response at zero conc, d = response at infinite conc, c = EC50, b = slope."""
    x = np.asarray(x, float)
    return d + (a - d) / (1.0 + (x / c) ** b)


def inv_four_pl(y, a, b, c, d):
    y = np.asarray(y, float)
    with np.errstate(divide="ignore", invalid="ignore"):
        r = (a - d) / (y - d) - 1.0
        return np.where(r > 0, c * np.power(np.where(r > 0, r, np.nan), 1.0 / b), np.nan)


@dataclass
class Calibration:
    hormone: str
    model: str                    # "4pl" or "linear"
    params: List[float]
    n: int = 0
    r2: float = float("nan")
    signal_def: str = ""
    units: str = ""

    def predict(self, signal):
        s = np.asarray(signal, float)
        if self.model == "4pl":
            return inv_four_pl(s, *self.params)
        m, q = self.params
        x = (s - q) / m
        return np.where(x >= 0, x, np.nan)       # negative -> below zero-conc signal

    def save(self, path):
        with open(path, "w") as f:
            json.dump(asdict(self), f, indent=2)

    @staticmethod
    def load(path) -> "Calibration":
        with open(path) as f:
            return Calibration(**json.load(f))


def fit_calibration(hormone: str, conc: Sequence[float], signal: Sequence[float],
                    model: str = "auto", signal_def: str = "", units: str = "") -> Calibration:
    x, y = np.asarray(conc, float), np.asarray(signal, float)
    ok = np.isfinite(x) & np.isfinite(y)
    x, y = x[ok], y[ok]
    if len(x) < 2:
        raise ValueError("Need at least 2 standards")
    if model == "auto":
        model = "4pl" if len(np.unique(x)) >= 5 else "linear"

    if model == "linear":
        m, q = np.polyfit(x, y, 1)
        pred = m * x + q
        params = [float(m), float(q)]
    else:
        pos = x[x > 0]
        if len(pos) == 0:
            raise ValueError("4PL needs non-zero concentrations")
        p0 = [y[np.argmin(x)], 1.0, float(np.median(pos)), y[np.argmax(x)]]
        lo = [-np.inf, 0.2, pos.min() / 10, -np.inf]
        hi = [np.inf, 8.0, pos.max() * 10, np.inf]
        popt, _ = curve_fit(four_pl, x, y, p0=p0, bounds=(lo, hi), maxfev=50000)
        pred = four_pl(x, *popt)
        params = [float(v) for v in popt]
    ss_res = float(np.sum((y - pred) ** 2))
    ss_tot = float(np.sum((y - y.mean()) ** 2)) or 1e-12
    return Calibration(hormone, model, params, int(len(x)), 1 - ss_res / ss_tot, signal_def, units)


def lod_signal(blank_signals: Sequence[float], k: float = 3.0) -> Tuple[float, float]:
    """Blank mean and k-sigma threshold on the signal axis; convert to
    concentration with Calibration.predict (mind the assay direction:
    sandwich -> mean + k*sd, competitive -> mean - k*sd)."""
    b = np.asarray(blank_signals, float)
    return float(b.mean()), float(k * b.std(ddof=1))
