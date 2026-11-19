#!/usr/bin/env node
// npm install && npx playwright install chromium && node render.mjs
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { access, mkdir, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
function value(flag, fallback) {
  const index = args.indexOf(flag);
  if (index < 0) return fallback;
  if (!args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`${flag} needs a value`);
  return args[index + 1];
}
const allowed = new Set(['--portrait', '--stills-only', '--output', '--browser', '--ffmpeg', '--help']);
for (let i = 0; i < args.length; i++) {
  if (!allowed.has(args[i])) throw new Error(`Unknown argument: ${args[i]}`);
  if (['--output', '--browser', '--ffmpeg'].includes(args[i])) i++;
}
if (args.includes('--help')) {
  console.log('node render.mjs [--portrait] [--stills-only] [--output FILE] [--browser CHROME] [--ffmpeg FFMPEG]');
  process.exit(0);
}
const portrait = args.includes('--portrait');
const width = portrait ? 1080 : 1920, height = portrait ? 1920 : 1080;
const output = resolve(value('--output', join(root, `blossom-intro${portrait ? '-portrait' : ''}.mp4`)));
const stills = join(dirname(output), portrait ? 'stills-portrait' : 'stills');
const ffmpeg = value('--ffmpeg', process.env.FFMPEG_PATH || 'ffmpeg');
const hash = buffer => createHash('sha256').update(buffer).digest('hex');
const { chromium } = process.env.PLAYWRIGHT_MODULE
  ? await import(pathToFileURL(resolve(process.env.PLAYWRIGHT_MODULE)).href)
  : await import('playwright');
let executablePath = value('--browser', process.env.CHROME_PATH);
if (!executablePath) {
  const candidates = [chromium.executablePath(),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome'];
  for (const path of candidates) {
    try { await access(path, constants.X_OK); executablePath = path; break; } catch {}
  }
}
await mkdir(stills, { recursive: true });
const errors = [], requests = [];
let browser, encoder;
try {
  browser = await chromium.launch({ headless: true, ...(executablePath ? {executablePath} : {}),
    args: ['--disable-gpu', '--disable-lcd-text', '--font-render-hinting=none', '--hide-scrollbars'] });
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1,
    colorScheme: 'dark', reducedMotion: 'reduce' });
  page.on('pageerror', error => errors.push(error.message));
  await page.route(/^https?:\/\//, route => { requests.push(route.request().url()); return route.abort(); });
  await page.goto(`${pathToFileURL(join(root, 'index.html')).href}?capture=1`);
  await page.evaluate(() => window.ready);
  const config = await page.evaluate(() => ({duration: CONFIG.duration, fps: CONFIG.fps,
    brand: CONFIG.brand, tagline: CONFIG.tagline, flowers: CONFIG.flowerCount,
    fontLoaded: document.fonts.check(`${CONFIG.fontWeight} 100px "Blossom Serif"`),
    layout: window.layoutMetrics}));
  if (config.brand !== 'Blossom' || config.tagline !== 'for her') throw new Error('Brand spelling check failed');
  if (!config.fontLoaded) throw new Error('Embedded font did not load');
  if (config.layout.wordWidth > width * .9) throw new Error('Wordmark exceeds safe margins');
  const screenshot = async t => {
    await page.evaluate(t => window.renderFrame(t), t);
    return page.screenshot({ type: 'png', animations: 'disabled', caret: 'hide' });
  };
  console.log(`${width}×${height}; ${config.duration}s at ${config.fps} fps; embedded font loaded.`);
  const samples = [1.5, 3, 4.5, 5.5, 6.5, 8];
  const checks = [];
  for (const t of samples) {
    const first = await screenshot(t);
    // Exercise out-of-order seeking, not just repeated screenshots of an untouched DOM.
    await screenshot((t + 2.173) % config.duration);
    const second = await screenshot(t);
    if (!first.equals(second)) throw new Error(`Pixel determinism failed at ${t}s`);
    const name = `t-${t.toFixed(1).padStart(4, '0')}.png`;
    await writeFile(join(stills, name), first);
    checks.push({time: t, file: name, sha256: hash(first), deterministic: true});
    console.log(`Still ${t.toFixed(1)}s: identical after an out-of-order seek.`);
  }
  const holdA = await screenshot(7), holdB = await screenshot(8);
  if (!holdA.equals(holdB)) throw new Error('Final hold is not stationary');
  // Verify every entry is cream rain except the separately constructed flower slot.
  const structure = await page.evaluate(() => ({
    letters: [...document.querySelectorAll('#letters text')].map(g=>g.textContent),
    tagline: document.querySelector('#tagline').textContent,
    rain: document.querySelector('#rain').children.length,
    petals: document.querySelector('#frangipani-pink').querySelectorAll('[data-unfurl]').length
  }));
  if (structure.letters.join('') !== 'Blossm' || structure.tagline !== 'for her' || structure.petals !== 5)
    throw new Error('Letter/flower construction check failed');
  if (structure.rain !== config.flowers) throw new Error('Rain count check failed');
  const frames = Math.round(config.duration * config.fps);
  const frameHashes = [];
  if (!args.includes('--stills-only')) {
    await mkdir(dirname(output), {recursive: true});
    const encoderArgs = ['-y', '-hide_banner', '-loglevel', 'warning', '-f', 'image2pipe',
      '-framerate', String(config.fps), '-vcodec', 'png', '-i', 'pipe:0', '-an',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
      '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
      '-movflags', '+faststart', '-frames:v', String(frames), output];
    encoder = spawn(ffmpeg, encoderArgs, {stdio: ['pipe', 'ignore', 'pipe']});
    let encoderError, encoderLog='';
    encoder.on('error', error => {encoderError=error;});
    encoder.stdin.on('error', error => {encoderError=error;});
    encoder.stderr.on('data', data => {encoderLog+=data;});
    const completed = new Promise((resolve,reject) => {
      encoder.once('error', reject);
      encoder.once('close', code => code===0 ? resolve() : reject(new Error(`ffmpeg exited ${code}: ${encoderLog}`)));
    });
    // Keep rejection handled while screenshots are in flight.
    completed.catch(()=>{});
    console.log(`Rendering ${frames} frames to ${output}`);
    for (let frame=0; frame<frames; frame++) {
      if(encoderError) throw encoderError;
      const png = await screenshot(frame/config.fps);
      frameHashes.push(hash(png));
      if(!encoder.stdin.write(png)) await Promise.race([once(encoder.stdin,'drain'),completed]);
      if(frame % config.fps === 0) console.log(`  ${frame}/${frames}`);
    }
    encoder.stdin.end();
    await completed;
    console.log(`Encoded ${frames} frames. H.264 / yuv420p / CRF 16 / faststart.`);
    console.log(`Checking all ${frames} frames again in reverse order…`);
    for(let frame=frames-1;frame>=0;frame--) {
      const png=await screenshot(frame/config.fps);
      if(hash(png)!==frameHashes[frame]) throw new Error(`Reverse-seek determinism failed at frame ${frame} (${frame/config.fps}s)`);
      if(frame%config.fps===0) console.log(`  verified through frame ${frame}`);
    }
  }
  if (errors.length) throw new Error(`Browser errors: ${errors.join('; ')}`);
  if (requests.length) throw new Error(`Unexpected runtime network requests: ${requests.join('; ')}`);
  await writeFile(join(stills, 'verification.json'), JSON.stringify({
    viewport: {width,height}, ...config, frames, samples:checks, finalHoldIdentical:true,
    browserErrors:errors, runtimeNetworkRequests:requests, structure,
    allVideoFramesReverseSeekIdentical: frameHashes.length===frames,
    frameHashes,
    output:args.includes('--stills-only') ? null : output
  },null,2)+'\n');
  console.log(`Passed: deterministic pixels, spelling, five-petal flower, final hold, zero runtime network requests.`);
} catch (error) {
  if(encoder && encoder.exitCode===null) encoder.kill('SIGTERM');
  console.error(error.stack || error);
  process.exitCode=1;
} finally {
  if(browser) await browser.close();
}
