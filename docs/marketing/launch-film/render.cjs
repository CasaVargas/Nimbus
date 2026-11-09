// Renders film.html frame by frame in headless Chromium and pipes PNG
// frames into ffmpeg. Deterministic: frame n is film.seek(n / fps).
//
//   NODE_PATH=<node_modules with playwright> node render.cjs [--vertical] [--fps 60] [--scale 2] [--from 0] [--to 61] [--out out/nimbus-launch.mp4]
//
// --vertical renders the 9:16 cut (1080x1920) from the same film (film.html?v).
//
// --scale 2 renders at 3840x2160 and ffmpeg downsamples to 1080p (sharper text).
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : fallback;
};
const fps = Number(arg('fps', 60));
const scale = Number(arg('scale', 2));
const from = Number(arg('from', 0));
const vertical = process.argv.includes('--vertical');
const out = path.resolve(__dirname, arg('out', vertical ? 'out/nimbus-launch-vertical.mp4' : 'out/nimbus-launch.mp4'));

(async () => {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const browser = await chromium.launch();
  const size = vertical ? { width: 1080, height: 1920 } : { width: 1920, height: 1080 };
  const page = await browser.newPage({ viewport: size, deviceScaleFactor: scale });
  await page.goto('file://' + path.join(__dirname, 'film.html') + (vertical ? '?render&v' : '?render'));
  await page.evaluate(() => window.ready);
  await page.evaluate(() => document.fonts.ready);
  const duration = await page.evaluate(() => window.DURATION);
  const to = Number(arg('to', duration));
  const frames = Math.round((to - from) * fps);

  const ffmpeg = spawn('ffmpeg', [
    '-y', '-loglevel', 'error',
    '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
    '-vf', `scale=${size.width}:${size.height}:flags=lanczos,format=yuv420p`,
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-tune', 'film',
    '-movflags', '+faststart', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
    out,
  ], { stdio: ['pipe', 'inherit', 'inherit'] });

  const started = Date.now();
  for (let n = 0; n < frames; n++) {
    const t = from + n / fps;
    await page.evaluate(time => window.seek(time), t);
    const png = await page.screenshot({ type: 'png' });
    if (!ffmpeg.stdin.write(png)) await new Promise(r => ffmpeg.stdin.once('drain', r));
    if (n % (fps * 5) === 0) {
      const rate = (n + 1) / ((Date.now() - started) / 1000);
      process.stdout.write(`frame ${n}/${frames}  t=${t.toFixed(1)}s  ${rate.toFixed(1)} fps\n`);
    }
  }
  ffmpeg.stdin.end();
  await new Promise(r => ffmpeg.on('close', r));
  await browser.close();
  console.log(`wrote ${out}`);
})();
