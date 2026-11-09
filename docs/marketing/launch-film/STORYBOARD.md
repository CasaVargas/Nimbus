# Nimbus launch film: "Where do you even start?"

**Length:** about 60 s. **Format:** 1920 × 1080 and a 9:16 cut at 1080 × 1920, both 60 fps H.264 MP4 with the same timeline. In 9:16, captions stack on two lines (the dimmed half on its own line), windows span the frame width, and all type stays inside the social safe area. **Look:** a keynote product film. Black stage, SF Pro Display, large tight type, slow eased motion, one idea per beat, generous silence.
**Sound:** none in this cut. A licensed music bed goes on in editing (see "Music" below).
**Source:** `film.html` is a deterministic animation: every frame is a pure function of `t`. `render.mjs` steps it frame by frame in headless Chromium and pipes the frames to ffmpeg. App screens come from Nimbus's own SwiftUI views with fixture data (no personal data), rendered at 2× by a temporary capture test.

## Claims (each one checked against the README and the code)

- Works with 70+ services. rclone reports 72 backends in the Add Cloud picker; the film says "70+".
- Clouds show up in Finder. This is the File Provider extension.
- Backups preview every change before they run, and keep replaced and deleted files. Backups phase 1, PR #25.
- Native Mac app. Open source (GPL-3.0). No subscription. The README says prebuilt binaries will be a one-time purchase and the source is free.
- **Not claimed:** prices, scheduling (that's phase 2), Keychain storage (tokens live in `rclone.conf`), or "syncs everything".

## Beats

| # | Time | Picture | Words on screen |
|---|---|---|---|
| 1 | 0.0–4.5 | Black. A single line fades up, holds, fades. | "You have files." |
| 2 | 4.5–8.0 | The words return and shift up. A second line. | "Everywhere." |
| 3 | 8.0–15.5 | Service names arrive one at a time, then faster and smaller, until about 70 names and logos fill the frame in a drifting, overlapping cloud. A slow push-in. | Google Drive. Dropbox. OneDrive. iCloud Drive. Box. Amazon S3. Backblaze B2. Proton Drive. MEGA. pCloud. Your NAS… |
| 4 | 15.5–20.0 | Everything freezes, blurs and dims. Centred, white: | "Where do you even start?" |
| 5 | 20.0–24.5 | The cloud of names collapses into one point. The Nimbus icon blooms out of it. | "Nimbus" |
| 6 | 24.5–32.0 | A Mac window rises into frame: Home, all clouds ready, one storage bar. Slow drift. | "Every cloud. One place." |
| 7 | 32.0–37.5 | The window steps back. The menu bar companion drops down beside it. | "Always a click away." |
| 8 | 37.5–45.5 | The Backups list, then the preview sheet slides over it: "12 files will be copied, 2 replaced and 1 removed." | "Back up anything." / "See every change before it happens." |
| 9 | 45.5–51.0 | The Add Cloud picker. The grid of services. | "70+ services. Sign in once." |
| 10 | 51.0–56.0 | Three words, one at a time, large. | "Native." "Open source." "No subscription." |
| 11 | 56.0–61.0 | End card: the icon, the wordmark, the tagline, the URL. Hold, then fade to black. | "Nimbus" / "Every cloud. One Mac." / github.com/CasaVargas/Nimbus |

## Motion rules

- Easing is `cubic-bezier(0.22, 1, 0.36, 1)` (expo-out) for entrances and `cubic-bezier(0.65, 0, 0.35, 1)` for moves. Nothing linear except the slow camera drift.
- Type enters with an 18–24 px rise and opacity from 0, over 0.7–0.9 s, and leaves with opacity only.
- App windows have 18 px corners and a soft shadow (0 40px 120px rgba(0,0,0,.6)), plus a 1 px inner highlight. They never spin, bounce or pop.
- Never two ideas on screen at once.

## Music (for the edit)

Use a minimal piano or synth pulse at about 90 BPM: sparse in beats 1–2, building through 3, cut to silence on 4 ("Where do you even start?"), then a warm resolve when the icon blooms on 5. Use only a licensed or royalty-free track.
