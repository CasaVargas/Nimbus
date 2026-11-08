# Nimbus launch film

A 61-second keynote-style product film: "You have files. Everywhere. Where do you even start? Nimbus." The beats, the claims and the motion rules are in [STORYBOARD.md](STORYBOARD.md).

| File | What it is |
|---|---|
| `film.html` | The film. Open it in a browser to watch it in real time, or add `?t=24` to start at 24 s. Every frame is a pure function of time (`window.seek(t)`). |
| `render.cjs` | Frame-exact renderer: headless Chromium (Playwright) → PNG frames → ffmpeg H.264. |
| `assets/screens/` | Real Nimbus SwiftUI views with fixture data, rendered at 2× by `capture/FilmCaptureTests.swift`. |
| `assets/logos/`, `assets/icon.png` | Copied from the app's asset catalogs. |

## Render

```bash
NODE_PATH=<a node_modules folder that contains playwright 1.64> node render.cjs --fps 60 --scale 2 --out out/nimbus-launch.mp4
```

`--scale 2` renders 3840 × 2160 and downsamples to 1080p, which gives sharper type. `--from` and `--to` render one section. Output goes to `out/`, which is gitignored.

## Re-capture the app screens

Copy `capture/FilmCaptureTests.swift` into `Nimbus/NimbusTests/` on a branch that has Backups (#25), run `xcodegen generate`, then:

```bash
TEST_RUNNER_FILM_OUT="$PWD/docs/marketing/launch-film/assets/screens" xcodebuild test -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:NimbusTests/FilmCaptureTests
```

Then delete the copy.

## Not in this cut

- **Music.** The storyboard describes the bed; add a licensed track in the edit.
- **A vertical (9:16) version.**
