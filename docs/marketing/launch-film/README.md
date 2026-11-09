# Nimbus launch film

A 61-second keynote-style product film, in 16:9 and 9:16: "You have files. Everywhere. Where do you even start? Nimbus." The beats, the claims and the motion rules are in [STORYBOARD.md](STORYBOARD.md).

| File | What it is |
|---|---|
| `film.html` | The film. Open it in a browser to watch it in real time, add `?t=24` to start at 24 s, or add `?v` for the 9:16 layout. Every frame is a pure function of time (`window.seek(t)`), and both cuts share the same timeline. Positions that differ by orientation live in one `L` table. |
| `render.cjs` | Frame-exact renderer: headless Chromium (Playwright) → PNG frames → ffmpeg H.264. |
| `assets/screens/` | Real Nimbus SwiftUI views with fixture data, rendered at 2× by `capture/FilmCaptureTests.swift`. |
| `assets/logos/`, `assets/icon.png` | Copied from the app's asset catalogs. |

## Render

```bash
NODE_PATH=<a node_modules folder that contains playwright 1.64> node render.cjs --fps 60 --scale 2 --out out/nimbus-launch.mp4
```

Add `--vertical` for the 9:16 cut (1080 × 1920; type wraps inside the social safe area, which keeps it clear of the top and bottom ~250 px where Reels and TikTok draw their controls). `--scale 2` renders at twice the size and downsamples, which gives sharper type. `--from` and `--to` render one section. Four parallel segments joined with `ffmpeg -f concat -c copy` cut a render to about 8 minutes. Output goes to `out/`, which is gitignored.

## Re-capture the app screens

Copy `capture/FilmCaptureTests.swift` into `Nimbus/NimbusTests/` on a branch that has Backups (#25), run `xcodegen generate`, then:

```bash
TEST_RUNNER_FILM_OUT="$PWD/docs/marketing/launch-film/assets/screens" xcodebuild test -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:NimbusTests/FilmCaptureTests
```

Then delete the copy.

## Not in this cut

- **Music.** The storyboard describes the bed; add a licensed track in the edit.
