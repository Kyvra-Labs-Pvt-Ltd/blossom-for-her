# Blossom for her

An eight-second, offline SVG intro. Cormorant Garamond is embedded in `index.html`; its SIL Open Font License is in `vendor/OFL.txt`.

Open `index.html` in a browser to play, pause, or scrub. The top CONFIG block controls colors, timings, easing, flower count, and the optional cream flower centre. Edit `--brand-pink` to recolor the entire lockup; `--background` and `--glow-color` are independent.

## Render

Requires Node.js 20+, ffmpeg with `libx264`, and Playwright:

```sh
cd blossom-intro
npm install
npx playwright install chromium
node render.mjs
node render.mjs --portrait
```

The outputs are `blossom-intro.mp4` (1920×1080) and `blossom-intro-portrait.mp4` (1080×1920). Each has 240 frames at 30 fps, H.264, yuv420p, CRF 16, and faststart. The portrait layout recalculates type size, flower motion, glow, and spacing for the taller canvas.

```sh
# Inspect stills and determinism without encoding:
node render.mjs --stills-only

# Optional paths:
node render.mjs --ffmpeg /path/to/ffmpeg --browser /path/to/chromium --output /path/to/intro.mp4
```

`FFMPEG_PATH` and `CHROME_PATH` provide the same overrides. `PLAYWRIGHT_MODULE` can point to an existing Playwright `index.mjs` instead of a local installation.

The six requested stills and `verification.json` are saved in `stills/` or `stills-portrait/`. The renderer checks byte-identical pixels after seeking, then verifies all 240 video frames in reverse order. It also checks spelling, font loading, wordmark width, flower construction, the final hold, browser errors, and zero runtime network requests.

For custom capture, await `window.ready`, then call `window.renderFrame(t)` with seconds in [0, 8]. `?capture=1` hides controls. Frame logic uses absolute time and seeded randomness. The flower replaces the second “o”; placement uses the embedded font's measured advances, kerning, x-height, and baseline.
