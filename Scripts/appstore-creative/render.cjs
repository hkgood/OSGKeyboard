#!/usr/bin/env node
// Renders a deterministic canvas scene (window.render(t)) to PNG stills or
// a looping video piped straight into ffmpeg.
//
//   NODE_PATH=<dir with playwright-core> node render.cjs \
//     --page header.html --query "w=3840&h=1646&lang=zh" \
//     --still 7.0 --out poster.png [--debug-safe]
//   ... --video --fps 30 --out frames.mov   (ProRes 4444 intermediate)
//
// Chromium comes from the Playwright cache; override with CHROMIUM_PATH.

const { chromium } = require('playwright-core');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const v = process.argv[i + 1];
  return v === undefined || v.startsWith('--') ? true : v;
}

function chromiumPath() {
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  const cache = path.join(os.homedir(), 'Library/Caches/ms-playwright');
  const dirs = fs.readdirSync(cache).filter((d) => /^chromium-\d+$/.test(d)).sort().reverse();
  for (const d of dirs) {
    const p = path.join(cache, d,
      'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing');
    if (fs.existsSync(p)) return p;
  }
  throw new Error('No Playwright Chromium found; set CHROMIUM_PATH');
}

(async () => {
  const page = path.resolve(__dirname, arg('page', 'header.html'));
  const query = arg('query', '');
  const out = path.resolve(arg('out'));
  const params = new URLSearchParams(query);
  const W = +params.get('w');
  const H = +params.get('h');

  const browser = await chromium.launch({
    executablePath: chromiumPath(),
    args: ['--force-color-profile=srgb', '--disable-gpu-vsync'],
  });
  const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  const tab = await ctx.newPage();
  tab.on('console', (m) => console.log('[page]', m.text()));
  tab.on('pageerror', (e) => { console.error('[page error]', e); process.exit(1); });
  await tab.goto(`file://${page}?${query}`);
  await tab.evaluate(() => window.READY);

  const grab = async (t, debugSafe) => {
    const b64 = await tab.evaluate(async ({ t, debugSafe }) => {
      await window.render(t);
      if (debugSafe) window.SAFE_DEBUG();
      const c = document.getElementById('c');
      return c.toDataURL('image/png').split(',')[1];
    }, { t, debugSafe });
    return Buffer.from(b64, 'base64');
  };

  if (arg('layout')) {
    const layout = await tab.evaluate(() => window.LAYOUT);
    fs.writeFileSync(path.resolve(arg('layout')), JSON.stringify(layout, null, 2));
  }

  if (arg('still') !== undefined) {
    const t = parseFloat(arg('still'));
    fs.writeFileSync(out, await grab(t, !!arg('debug-safe')));
    console.log(`wrote ${out}`);
  } else if (arg('video')) {
    const fps = +arg('fps', 30);
    const duration = await tab.evaluate(() => window.DURATION);
    const frames = Math.round(duration * fps);
    // Lossless-ish intermediate; delivery encodes happen in a second pass.
    const ff = spawn('ffmpeg', [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'png', '-i', '-',
      // Same matrix + tags as the simulator footage it gets composited with.
      '-vf', 'scale=out_color_matrix=bt709:out_range=tv',
      '-c:v', 'prores_ks', '-profile:v', '4', '-pix_fmt', 'yuva444p10le',
      '-colorspace', 'bt709', '-color_primaries', 'bt709',
      '-color_trc', 'iec61966-2-1', '-color_range', 'tv',
      '-vendor', 'apl0', out,
    ], { stdio: ['pipe', 'inherit', 'inherit'] });
    const started = Date.now();
    for (let i = 0; i < frames; i++) {
      const buf = await grab(i / fps, false);
      if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
      if (i % 30 === 0) {
        const s = ((Date.now() - started) / 1000).toFixed(0);
        console.log(`frame ${i}/${frames} (${s}s)`);
      }
    }
    ff.stdin.end();
    await new Promise((r, j) => ff.on('close', (c) => (c === 0 ? r() : j(new Error(`ffmpeg ${c}`)))));
    console.log(`wrote ${out}`);
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
