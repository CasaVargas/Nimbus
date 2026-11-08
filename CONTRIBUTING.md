# Contributing to Nimbus

Thanks for your interest. Nimbus is a small project with one maintainer, so
the process below is deliberately light. Read it once; it will save a round
trip on your first pull request.

## Prerequisites

- macOS 15 or later
- Xcode 27 or later, with the Command Line Tools installed (Xcode 16.4 through
  26.6 crash in IRGen while compiling this project)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [rclone](https://rclone.org/install/): `brew install rclone` (the app spawns
  it at runtime and the integration tests expect it on `PATH`)

## Set up a local build

```bash
git clone https://github.com/CasaVargas/Nimbus.git
cd Nimbus

# Optional: your Apple Developer team, for a signed local build.
cp Nimbus/Local.xcconfig.example Nimbus/Local.xcconfig
# edit Nimbus/Local.xcconfig and set DEVELOPMENT_TEAM

# Generate the Xcode project (run again after editing project.yml or adding files).
cd Nimbus && xcodegen generate && cd ..

# xcodegen rewrites the extension's Info.plist with literal version numbers;
# restore the committed one before you commit anything.
git checkout -- Nimbus/FileProviderExtension/Info.plist
```

`Nimbus/Local.xcconfig` is gitignored. Without it the project still generates
and builds; you just need to disable signing on the command line:

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

A signed build (with a team) is required to actually register the File
Provider extension with Finder and to use the shared app group. Everything
else, including the browser, mounts and transfers, works unsigned.

## Run the tests

```bash
# App + File Provider tests
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# RcloneKit (plain Swift package)
cd RcloneKit && swift test
```

Snapshot fixtures under `Nimbus/NimbusTests/Fixtures` were recorded on a
Retina display. A non-Retina or headless machine can drift by a few bits on a
handful of them; see the skip list in `.github/workflows/ci.yml` for the ones
that are known to be environment-dependent. Do not re-record fixtures from a
non-Retina machine.

Two lint scripts run as pre-build phases and will fail the build on purpose:

- `scripts/lint-no-system-size.sh`: no `.system(size:)` fonts; use the
  semantic typography helpers in `DesignSystem`.
- `scripts/lint-package-resolved.sh`: no remote Swift package dependencies.
  Nimbus uses Apple frameworks and the local `RcloneKit` package only.

## How work gets planned

Significant work starts with a short design spec, not with code. Specs live
in `docs/superpowers/specs/` and follow the existing naming
(`YYYY-MM-DD-topic-design.md`). The strategic context is
`docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md`; read its
design pillars (native or nothing, Finder-grade interaction, utility-app
rigor, performance is a feature) before proposing UI changes. If you are
unsure whether something needs a spec, open an issue first and ask.

Bug fixes, test additions and small, self-contained improvements do not need
a spec. Just open the pull request.

## Pull requests

- Branch from `main`. Pull requests land through review; nothing is pushed to
  `main` directly.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit
  messages: `feat(browser): ...`, `fix(fileprovider): ...`, `docs: ...`,
  `chore: ...`, `test: ...`, `refactor: ...`.
- Keep commits small and focused. One logical change per commit.
- Run the tests before you push. CI runs the same commands as above on a
  GitHub-hosted `xcode-27` runner (Xcode 16.x and 26.x crash in IRGen on
  this codebase; use Xcode 27 or later locally too).
- Do not touch Swift UI code (`Views/`, `Components/`, `ViewModels/`) and
  unrelated files in the same pull request.
- Fill in the pull request template: a summary, how you tested it,
  screenshots for anything visible, and `Closes #N` for the issue it resolves.
- Do not commit `Nimbus/Local.xcconfig`, `xcuserdata`, or the regenerated
  `FileProviderExtension/Info.plist`.

## Project layout

| Path | What lives there |
|------|------------------|
| `Nimbus/Nimbus/` | SwiftUI app: `Views/`, `ViewModels/`, `Services/`, `State/`, `DesignSystem/`, `Components/` |
| `Nimbus/FileProviderExtension/` | `NSFileProviderReplicatedExtension` that exposes remotes in Finder |
| `Nimbus/NimbusTests/` | Swift Testing suites, snapshot fixtures and mocks |
| `RcloneKit/` | Local Swift package: typed HTTP client for the rclone RC API |
| `Nimbus/project.yml` | XcodeGen definition; the `.xcodeproj` is generated from it |
| `scripts/` | Build, lint and packaging scripts |
| `docs/superpowers/specs/` | Design specs and phase exit-gate records |
| `legacy/tauri/` | Frozen Tauri sources, reference only, not built |

## Reporting problems

Use the issue templates. For security problems, do not open a public issue;
see [SECURITY.md](SECURITY.md).

By contributing you agree that your contributions are licensed under the
GPL-3.0-or-later, the same license as the project.
