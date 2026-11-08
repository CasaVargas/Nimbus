# Visual Identity & Browser Polish — Design

**Date:** 2026-11-07
**Status:** Approved (verbal: "just build me a beautiful interface first")
**Scope:** The visible polish pass before Nimbus goes public. No new features; every
change is something a first-time visitor sees in the README screenshots or in the
first five minutes of use.

## Why

The north-star doc says Nimbus should feel like "the cloud storage app Apple would
have shipped." The bones are there (design tokens, HIG forms, Finder-grade table),
but a screenshot today reads as a prototype:

- The app ships **no icon**. Dock, About pane, onboarding hero, and Finder all show
  the generic placeholder.
- The browser draws files with **SF Symbols** (`doc`, `photo`) instead of the real
  document icons Finder uses, and paints a loud green "Local" pill on every row.
- The table has **no column headers**, so sort state is invisible.
- The detail pane shows "No Remotes Yet" while four remotes sit in the sidebar,
  because the remote list is withheld until every status probe finishes.

## Goals

1. A real, reproducible **app icon** and brand mark used everywhere the app refers
   to itself (Dock, About, onboarding).
2. A browser that is **indistinguishable from Finder** at a glance: system file
   icons, Finder-style cloud status glyphs, column headers with sort indicators.
3. First-launch correctness: the first remote is selected as soon as the list is
   known.
4. Zero compiler warnings.

## Non-goals / anti-goals

- No new typefaces, colors, or layout language. Nimbus borrows Finder, Disk
  Utility, and System Settings; it does not invent.
- No feature work (search, Quick Look changes, new panes).
- No changes to the design-token files beyond what the above needs.
- No "AI-generated" tells: no gradient washes on cards, no eyebrow labels, no
  decorative motion.

## Decisions

### App icon

- **Drawn in code**, not Figma: `scripts/render-app-icon.swift` renders every size
  of `AppIcon.appiconset` with CoreGraphics. The script is the source of truth;
  the PNGs are build artifacts checked in so Xcode and contributors never need to
  run it.
- **Mark:** two overlapping cumulus clouds (a small translucent one behind, a solid
  white one in front) on a sky gradient inside the standard macOS squircle. The
  layered clouds are the "nimbus"; the depth is the one memorable thing.
- **Palette:** sky gradient `#5CB0FF` (top) → `#1A4FD6` (bottom); front cloud white
  with a faint `#DCE8FF` underside; back cloud white at 45% opacity.
- The onboarding hero and the About section use `NSApp.applicationIconImage`
  rather than a second asset, so there is one mark.
- The menu bar extra keeps an SF Symbol: menu bar glyphs must be template images.

### Browser

- **File icons:** `FileIcon` resolves `NSWorkspace.shared.icon(for: UTType)` from
  the filename extension (folders use `.folder`), cached per extension on the main
  actor. Used by the list row, the grid tile, and the drag preview.
- **Cloud status:** `StatusBadge` gains a `.compact` style that mirrors Finder's
  iCloud column: nothing for local items and folders, an outlined cloud for
  cloud-only files, the existing progress ring while downloading, `icloud.slash`
  for evicted, a red triangle for errors. The browser uses `.compact`; the default
  pill style is unchanged for every other caller and for the snapshot fixtures.
- **Column headers:** a SwiftUI header strip above the AppKit table (Name · Date
  Modified · Size) laid out on the same fixed column widths as `FileRowView`.
  Clicking a header sorts; the active column shows a chevron.
- **Breadcrumb:** the root crumb drops the trailing colon ("gdrive", not
  "gdrive:").

### First launch

- `RemotesSidebarSection.reload()` reports the remote list to the parent **before**
  probing statuses, so selection and the detail pane update immediately. Probes
  still run and still update the status dots as they land.

### Onboarding

- Hero shows the app icon at 96 pt instead of an SF cloud in a circle.

## Left to the builder

- Exact cloud geometry; iterate by rendering and looking.
- Whether the header strip needs a divider below it (match Finder's list view).
- Keep `FileGrid.Layout` constants unchanged; `FileGridLayoutTests` pins them.

## Verification

- Build with zero warnings.
- Full `NimbusTests` run green (snapshot tests use perceptual hashes; any fixture
  that must change is re-recorded deliberately and called out in the PR).
- Screenshots of onboarding, browser (list and grid), and the About pane captured
  from the running app and attached to the PR.
