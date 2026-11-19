"""Synthetic strip images for testing the analysis without hardware."""
import numpy as np


def synth_sequence(heights=(0.30, 0.45), positions=(150, 250), sigma_px=5.0,
                   angle_deg=3.0, noise=1.0, seed=0, size=(600, 800),
                   length=420, width=46, led_scale=None, gamma=2.2):
    """Returns (images, darks): dicts {'G','W','B'} -> BGR uint8.
    heights: peak absorbance (green LED) of each band, positions in px from strip start."""
    rng = np.random.default_rng(seed)
    H, W = size
    led_scale = led_scale or {"G": 1.0, "W": 0.6, "B": 0.35}
    led_level = {"G": 0.75, "W": 0.95, "B": 0.60}
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    cx, cy = W / 2, H / 2
    t = np.radians(angle_deg)
    u = (xx - cx) * np.cos(t) + (yy - cy) * np.sin(t) + length / 2      # along strip, 0..length
    v = -(xx - cx) * np.sin(t) + (yy - cy) * np.cos(t)                   # across strip
    strip = (u >= 0) & (u <= length) & (np.abs(v) <= width / 2)
    vign = 1.0 - 0.25 * (((xx - cx) / W) ** 2 + ((yy - cy) / H) ** 2) * 4 - 0.05 * (xx - cx) / W

    A0 = np.zeros_like(u)
    for h, p in zip(heights, positions):
        A0 += h * np.exp(-((u - p) ** 2) / (2 * sigma_px ** 2))

    images, darks = {}, {}
    for led in ("G", "W", "B"):
        refl = np.where(strip, 0.85 * 10 ** (-A0 * led_scale[led]), 0.02)
        lin = np.clip(led_level[led] * vign * refl, 0, 1)
        val = 255 * lin ** (1 / gamma) + rng.normal(0, noise, lin.shape)
        img = np.zeros((H, W, 3))
        if led == "G":
            img[..., 1], img[..., 0], img[..., 2] = val, 0.08 * val, 0.08 * val
        elif led == "B":
            img[..., 0], img[..., 1], img[..., 2] = val, 0.08 * val, 0.05 * val
        else:
            img[...] = val[..., None]
        images[led] = np.clip(img, 0, 255).astype(np.uint8)
        darks[led] = np.clip(rng.normal(2, noise * 0.5, (H, W, 3)), 0, 255).astype(np.uint8)
    return images, darks
