"""Self-test on synthetic strips: python test_analysis.py"""
import numpy as np
from make_synthetic import synth_sequence
from lfa_analysis import (AnalysisParams, analyze_sequence, band_signal,
                          fit_calibration)

prm = AnalysisParams(band_names=("T", "C"))

# 1) geometry + peak positions on a tilted strip
imgs, darks = synth_sequence(angle_deg=3.0, noise=1.0)
res = analyze_sequence(imgs, darks, params=prm)
print(f"ROI: len={res.roi.length:.0f} width={res.roi.width:.0f} angle={res.roi.angle_deg:.2f} deg")
for b in res.bands:
    print(f"  {b.name}: pos={b.pos_px:.1f}px  height={b.height:.3f}  area={b.area:.3f}  snr={b.snr:.0f}")
assert len(res.bands) == 2
assert abs(res.bands[0].pos_px - 150) < 4 and abs(res.bands[1].pos_px - 250) < 4
for led in res.per_led:
    print(f"  {led}: heights", [round(b.height, 3) for b in res.per_led[led]])

# 2) dose-response: area should be linear in true band height
true_h = np.array([0.0, 0.02, 0.05, 0.1, 0.2, 0.35, 0.5])
sig = []
fixed = None
for i, h in enumerate(true_h):
    imgs, darks = synth_sequence(heights=(h, 0.4), seed=i + 10, noise=1.5)
    p = AnalysisParams(band_names=("T", "C"),
                       fixed_windows=[("T", 135, 165), ("C", 235, 265)])
    r = analyze_sequence(imgs, darks, params=p)
    sig.append(band_signal(r, "G", 0, 1))
sig = np.array(sig)
print("T/C ratio:", np.round(sig, 3))
r2 = np.corrcoef(true_h, sig)[0, 1] ** 2
print(f"linearity r^2 (T/C vs true height) = {r2:.4f}")
assert r2 > 0.99

# 3) calibration round trip (sandwich-style, saturating)
conc = np.array([0, 5, 10, 25, 50, 100, 250], float)
resp = 0.02 + 1.4 * conc ** 1.3 / (60 ** 1.3 + conc ** 1.3)
cal = fit_calibration("LH", conc, resp, "4pl")
back = cal.predict(resp[1:])
print("4PL recovered conc:", np.round(back, 1), " r2=%.4f" % cal.r2)
assert np.allclose(back, conc[1:], rtol=0.02)
print("ALL TESTS PASSED")
