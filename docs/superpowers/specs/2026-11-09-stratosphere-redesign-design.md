# Stratosphere Redesign — Design

**Date:** 2026-11-09
**Status:** Direction approved ("A, Stratosphere"). Details below are proposed and open to edits before Phase 1.
**Scope:** The look of every screen in the main app, the menu bar panel and first launch. No new features. No File Provider or RcloneKit changes.

**Mockups:** `docs/design/stratosphere/*.png` (static copies) and the editable canvas "Nimbus Redesign Directions" (https://claude.ai/artifact/HFYQATo9nUSBs8M3MDXjQd, private to the owner).

## Why

Feedback on 0.9.1: the app "is still looking vibe coded". Concretely:

- One flat grey (`windowBackgroundColor`) on sidebar, content and cards. No depth, no material.
- Every surface is the same 1 px outlined rounded rectangle: cards, banners, lists, settings groups.
- System blue does every job (selection, progress, buttons), so no screen has a visible primary action.
- No hero. Every screen opens with 13 pt text and thin bars; the state is never readable at a glance.
- rclone's option names reach the user (`config_change_team_drive`).

The ask: a native look that is also bold, in the spirit of MacPaw's apps.

## Decision

Build direction **A, Stratosphere**: a deep blue-to-violet backdrop, glass surfaces floating on it, one hero and one glowing primary action per screen, and a colour per cloud.

Rejected:

- **B, Daylight** (light, Finder-grade, colour only in accents): the most native, but not bold. It survives as the Light appearance of Stratosphere (see Appearance).
- **C, Midnight Cards** (pure black, solid colour cards): boldest and cheapest to build, but reads as a web dashboard, not a Mac app.

### What this supersedes

`2026-11-07-visual-identity-and-browser-polish-design.md` listed as anti-goals "no new typefaces, colors, or layout language" and "no gradient washes on cards". This spec reverses both, on purpose. What stays from that spec: real provider logos, system file icons in the browser, the Finder-grade table behaviour (sorting, selection, keyboard), and the app icon.

## Principles

1. **One hero per screen.** A large rounded headline states the situation in the user's words: "3.25 TB free", "2 of 3 backups are up to date".
2. **One primary action per screen.** It is the only filled, glowing control. Everything else is a glass capsule.
3. **Each cloud owns a colour.** The same colour appears in its ring segment, usage bar, card glow and page header.
4. **Glass over colour, never grey boxes.** Depth comes from the backdrop showing through, not from outlines.
5. **Mac conventions stay.** Traffic lights, sidebar, sheets, system fonts, standard keyboard behaviour, system file icons.
6. **Plain words.** No rclone option name is ever shown as a label.

## Visual language

### Backdrop

A fixed, non-scrolling window background behind everything, including the sidebar.

| Layer | Value |
|---|---|
| Base | linear, 160°: `#0B1640` → `#0A1030` (45%) → `#150C38` |
| Glow 1 | radial at 80% / −10%, `#488CFF` at 50% → clear |
| Glow 2 | radial at 6% / 110%, `#8854FF` at 60% → clear |
| Glow 3 | radial at 100% / 100%, `#FF5CA8` at 26% → clear |

Implementation: one `StratosphereBackdrop` view. `MeshGradient` (macOS 15) is the natural fit; layered `RadialGradient`s are an equally acceptable implementation if the mesh is hard to match.

### Surfaces

| Token | Use | Value (dark) |
|---|---|---|
| `glass` | cards, sidebar, table container | white 10% → 5% vertical, 1 px white 16% border, blur behind |
| `glassSheet` | sheets, menu bar panel | `#2E3C80` 94% → `#181E4C` 96%, 1 px white 20% border |
| `track` | bar and ring tracks | white 15% |
| `selection` | selected sidebar row, segmented choice | white 17% |
| `rowSelection` | selected file row | `#2459E0`, white text |

Glass is `glassEffect(_:in:)` on macOS 26 and later, and `.ultraThinMaterial` plus the gradient and border above on macOS 15 (the deployment target). One `GlassSurface` modifier hides the `#available` check. Keep glass effects few and grouped in a `GlassEffectContainer`; Apple's guidance is that many separate effects cost performance.

### Colour

| Token | Value | Use |
|---|---|---|
| `action` | `#2B6CF0` → `#1B48CC`, glow `#3680FF` at 60% | the primary pill |
| `ok` | `#45E3AA` | ready, done |
| `warning` | `#FFB84D` | needs sign-in, skipped |
| `muted` | `#A9B1C6` | unreachable |
| `error` | `#FF8080` | failed |
| text | white 100% / 80% / 72% | primary / secondary / tertiary |

These values were tuned in Phase 1. The first mockups used a 62% glow, 12% glass and 78% / 64% text, and the contrast tests failed with them: tertiary text on glass near the blue glow measured 3.4:1. With the values in these tables the worst case anywhere on the backdrop is 4.6:1. The tests sample the whole backdrop, so any later change to these numbers is checked.

**Cloud colours.** Each remote gets a two-stop colour, assigned by provider from a table next to `ProviderIcon.Brand`, with a fallback sequence for providers without an entry and for a second remote on the same provider (so two Google accounts differ).

| Example | Stops |
|---|---|
| Google Drive | `#4C9BFF` → `#2563FF` |
| OneDrive | `#2FD6F0` → `#0EA5E9` |
| Dropbox | `#9B8CFF` → `#6D4DFF` |
| Backblaze B2 | `#FFB340` → `#FF6A3D` |
| Unreachable / generic server | `#A3ACC2` → `#6B7388` |

### Type

System fonts only. Display text uses the rounded design; body text stays SF Pro. Fixed sizes are defined once, in the Stratosphere token file; `scripts/lint-no-system-size.sh` still rejects `.system(size:)` in views.

| Role | Size / weight | Design |
|---|---|---|
| Hero | 52 / heavy, tracking −2% | rounded |
| Page title | 30 / heavy | rounded |
| Sheet title | 22 / heavy | rounded |
| Section title, card title | 15 / bold | rounded |
| Body | 13 / regular or medium | default |
| Caption | 12 / regular | default |

Numbers that line up use `.monospacedDigit()`.

### Shape and spacing

| Token | Now | New |
|---|---|---|
| `Radius.card` | 10 | 20 |
| `Radius.sheet` | 14 | 26 |
| `Radius.pill` | 6 | capsule (height / 2) |
| new `Radius.row` | — | 10 |
| new `Radius.tile` | — | 12 (42 pt logo tile), 7 (24 pt) |

Spacing tokens are unchanged. Window corner radius is the system's.

### Motion

Existing `Motion` tokens. Additions, all disabled under Reduce Motion: the ring draws in once on first appearance (smooth); progress bars animate width; the primary pill has a hover lift. No ambient or looping animation.

## Components

New, in `Nimbus/Nimbus/Components/`:

| Component | Replaces / wraps | Notes |
|---|---|---|
| `StratosphereBackdrop` | window background | one instance per window |
| `GlassSurface` (modifier) | `surfaceSubtle` cards with borders | radius parameter; handles availability and accessibility fallbacks |
| `PrimaryPill` (button style) | `.borderedProminent` | large (46 pt) and small (32 pt) |
| `GlassCapsule` (button style) | `.bordered` | 32 pt; icon-only variant |
| `StorageRing` | the "All your clouds" bar | segments per cloud, centre label |
| `UsageBar` | thin `ProgressView` bars | cloud-coloured, 8 pt and 12 pt |
| `LogoTile` | `ProviderBadge` | white rounded tile holding the existing logo asset; 24 / 34 / 42 / 64 / 92 pt |
| `StatusDot`, `Chip` | `StatusBadge` pills | dot + text, never colour alone |
| `GlassSegmented` | `Picker(.segmented)` | Files / Transfers / Finder / Settings, Copy / Sync / Move |
| `HeroHeader` | page headers | headline, sentence, action slot |
| `ChoiceCard` | bool and enum config questions | radio-style cards with a title and a sentence |

`SheetChrome`, `FormSection`, `SetupSteps`, `EmptyState` keep their APIs and are restyled in place.

## Screens

Each references its mockup in `docs/design/stratosphere/`.

**Shell** (`ContentView`, `Sidebar`). The sidebar floats as a glass panel inset 10 pt, with the traffic lights inside it. Rows: logo tile, name, status dot. Home and the tools get coloured icon tiles. A footer shows total free space and the segment bar. The toolbar keeps its title and gains a global search capsule. Whether a floating sidebar is done with `NavigationSplitView` plus background customisation or a custom `HStack` is an implementation question for Phase 2; behaviour (collapse, resize, selection, keyboard) must match today's.

**Home** (`home.png`). Hero: "N free", one sentence, **Add Cloud**. Storage ring with legend. Attention banner keeps its content, gains the amber treatment and a small pill. "Your clouds" becomes a five-across grid of glass cards with a cloud-coloured glow. Recent activity and the tip card sit below.

**A cloud** (`cloud-files.png`). Header card washed in the cloud's colour: 64 pt logo, name, one status line, **Open in Finder**, a 12 pt usage bar. Tabs become a glass segmented control. The file table keeps `FileTableRepresentable` (AppKit) and its behaviour; only its drawing changes: transparent background inside a glass container, 35 pt rows, rounded full-row selection, and an "On this Mac" column using the existing cloud-status states.

**Add Cloud** (`add-cloud.png`, `sign-in.png`). The sheet becomes `glassSheet` over a dimmed, blurred window. Steps are three capsules. Service tiles are larger with a selected state. Sign-in gets a haloed logo and one pill.

Questions asked after sign-in (see the 2026-11-09 forward-only walk fix) are shown as `ChoiceCard`s with written copy. A small table maps option names to copy, starting with:

| rclone option | Title | Choices |
|---|---|---|
| `config_change_team_drive` | Which drive is this? | My Drive: "The files in your own Google account." / A shared drive: "A team space your organization owns. You pick which one next." |

Options without an entry fall back to rclone's own help text as the title, never the option name.

**Copy Between Clouds** (`copy-between-clouds.png`). Two cloud-coloured wells (From, To) with a path field each and an arrow between. Mode is a segmented control; options are switches. **Preview Copy** is the primary action. Running and earlier transfers list below.

**Backups** (`backups.png`). Hero states how many backups are current, with **New Backup**. Each backup is a row card: source, destination, schedule, last-run chips, next run, Preview and Run Now. A skipped backup uses the warning chip and says why.

**Settings** (`settings.png`). Same panes and options. Tabs become a glass segmented control with icons; groups become glass; Appearance becomes three thumbnails. Toggles stay standard `Toggle(.switch)`.

**Menu bar panel** (`menu-bar-panel.png`). `glassSheet` panel; the current transfer leads with a 10 pt bar; clouds list with logo tiles and a status glyph; **Open Nimbus** is the primary action.

**First launch** (`first-launch.png`). App icon in a halo with provider logos around it, the line "Every cloud, one window", three chips, **Add Your First Cloud**, and the rclone import link.

## Appearance

Stratosphere is the Dark appearance. In Light appearance the same components render with the Daylight palette (mockup `home-daylight.png`): a near-white backdrop with faint blue and violet glows, white cards with soft shadows, dark text, the same cloud colours and the same primary pill. This keeps the existing Appearance setting (System / Light / Dark) meaningful. Every token above therefore has a light value; the table of light values is produced in Phase 1 from the Daylight mockup.

## Accessibility

- **Reduce Transparency:** `GlassSurface` becomes an opaque fill (`#16204F` dark, white light) with the same border. The backdrop stays.
- **Increase Contrast:** borders go to white 40%, tertiary text is promoted to secondary, glows are removed.
- **Reduce Motion:** see Motion.
- **Contrast:** body and caption text ≥ 4.5:1 against the lightest and darkest area a surface can sit on. White on the primary pill is 4.6:1 at its lightest stop; do not lighten `action`.
- **Not colour alone:** every status has text or a glyph beside its dot; cloud colours never carry meaning by themselves.
- VoiceOver labels and keyboard behaviour are unchanged; the ring gets one label ("2.47 TB of 5.72 TB used") and its legend is the readable detail.

## Non-goals

- No new features, no information-architecture changes, no renamed concepts.
- No custom fonts, no bundled illustration assets beyond what exists.
- No user-chosen cloud colours yet.
- No File Provider, Finder or RcloneKit changes.
- No ambient animation.

## Phasing

Each phase is its own PR, builds and passes tests on its own, and is verified with RenderPreview plus a run of the real app.

1. **Foundation.** Tokens (dark and light), backdrop, `GlassSurface`, both button styles, `LogoTile`, `UsageBar`, `StorageRing`, `Chip`, cloud-colour table. A DEBUG gallery view shows them. No production screen changes.
2. **Shell.** Backdrop in the main window, floating sidebar, toolbar.
3. **Home.**
4. **A cloud:** header, tabs, table drawing.
5. **Add Cloud:** picker, naming, sign-in, `ChoiceCard` questions and their copy table.
6. **Copy Between Clouds and Backups.**
7. **Settings, menu bar panel, first launch.**

Between phases the app will mix old and new screens. Phases 2 and 3 land close together so the first thing a user sees is consistent.

## Testing

- Snapshot fixtures change in every phase from 2 on. Re-record only the fixtures for the screens that phase touches, on a Retina Mac, using `TEST_RUNNER_NIMBUS_SNAPSHOT_RECORD=1` (see the CLI test-loop notes). `ImageRenderer` cannot draw materials faithfully, so glass in fixtures is the opaque fallback; previews and the running app are the visual check.
- Unit tests for the cloud-colour assignment (stable per remote, distinct for two remotes on one provider) and the option-copy table (every entry has a title; unknown options fall back to help text).
- A contrast test over the token table for both appearances.
- Each phase's PR includes before and after screenshots, light and dark.

## Open questions

1. Is Light = Daylight acceptable, or should Light also be a coloured (pale sky) backdrop?
2. Should the menu bar panel follow the app's appearance or always be dark?
3. Does the floating sidebar justify a custom split view if `NavigationSplitView` cannot be styled that way on macOS 15?
