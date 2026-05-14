# Nimbus North Star

**Date:** 2026-05-14
**Status:** Draft
**Type:** Strategic / Phase 0
**Scope:** Defines vision, pillars, anti-goals, phased roadmap, and Tauri sunset for the effort to make Nimbus "the best rclone app for the Mac." This is a strategic doc, not an implementation spec. Each subsequent phase gets its own brainstorm → design → implementation cycle.

---

## Vision

**Nimbus is the cloud storage app Apple would have shipped.** A native macOS utility that turns rclone's 50+ cloud providers into something that feels indistinguishable from Finder and Disk Utility working together — buttery, opinionated, and free of cross-platform smell.

The wedge isn't features. It's *feel*. Mountain Duck has more polish than ExpanDrive; ExpanDrive is faster than Cyberduck; none of them feel native enough that a Mac fan would recommend them without an apology. Nimbus's apology is zero.

### Pitch (for ourselves, for the README, for the App Store)

> Nimbus brings every cloud you use into a single native Mac app. No web view. No cross-platform shell. It feels like Apple made it because we held ourselves to that standard on every screen.

### Audience

Mac users who already love Finder and would rather have *one* native app for cloud storage than a folder full of vendor-specific clients and a Cyberduck install from 2019. Power users welcome, but the app does not require them.

---

## Design Pillars

Four non-negotiable principles every decision must satisfy. If a feature can't ship with all four green, it doesn't ship.

### 1. Native or nothing

- SwiftUI-first for every screen
- AppKit bridge only where SwiftUI gives genuinely worse UX (likely candidates: outline-view-heavy interactions, advanced drag-and-drop, Quick Look host integration)
- Zero third-party UI dependencies; zero third-party for anything Apple already provides (`URLSession`, `AVKit`, `AsyncImage`, `Combine`/Observation, etc.)
- HIG is canon — when in doubt, copy Apple

### 2. Finder-grade file interaction

The Browser must clear Finder's interaction bar for everything it supports:

- Multi-select (single, range, ⌘-additive) with Finder semantics
- Drag-and-drop within a remote, across remotes (enqueues a Copy transfer), and to/from Finder
- Quick Look on every selectable item via the system Quick Look host
- Type-to-select with prefix matching
- Sort indicators, column resize/reorder, list/grid view toggle, view preferences per remote
- Right-click contextual menus consistent with Finder's verb set
- All standard ⌘-shortcuts (open, info, rename, duplicate, move to trash, etc.)

Finder is the floor; we are allowed to exceed it (e.g., cross-remote copy via drag).

### 3. Utility-app rigor

Disk Utility and System Settings (Ventura+) aesthetic:

- Dense, useful information density — no wasted vertical real estate
- Status badges that answer "what is the state of this thing right now?" at a glance (mounted / unmounted / error / syncing)
- Destructive actions earn their keep: confirmation, undo where possible, no surprise side effects
- Sidebar source list patterns; section headers with proper HIG styling
- Forms (Add Remote, Edit Mount, Settings panes) feel like Apple's, not like a web form

### 4. Performance is a feature

Hard numbers, enforced in CI where possible:

| Metric | Target |
|--------|--------|
| Cold launch (M1 baseline) | ≤ 1.0s to first interactive frame |
| Directory load (10k items) | ≤ 200ms with virtualized rows, skeleton placeholders during fetch |
| Mount → visible in Finder | ≤ 2.0s |
| Animation duration (normal flow) | ≤ 250ms, snappy curves |
| Scroll | 120fps where ProMotion is available; never drops a frame in normal use |

If a feature can't meet this bar, it doesn't ship in the phase that introduced it.

---

## Anti-Goals

What Nimbus is explicitly **not**:

- **Not a media-first app.** Music/Photos aesthetic is wrong for Nimbus. When a media gallery ships (Phase 5), it lives *inside* the utility frame, not the other way around.
- **Not a comms/social tool.** No collab UI, no presence, no chat overlays, no commenting.
- **Not a power-user-only tool.** rclone CLI exists for that. Nimbus meets power users where they are but never requires them.
- **Not cross-platform.** macOS only. iOS/iPadOS/visionOS are not on the roadmap.
- **Not a subscription SaaS shell.** Nimbus is a Mac app. Local-first, no Nimbus-owned server, no account required.
- **Not a Tauri app.** See [Tauri Sunset](#tauri-sunset).

---

## Reference Apps

These set the aesthetic floor. When a design decision is unclear, look at how these apps handle it.

| App | What we borrow |
|-----|----------------|
| **Finder** | File browser interaction floor — selection, drag-and-drop, Quick Look, sort/view modes, keyboard, contextual menus |
| **Disk Utility** | Status-heavy utility UI, sidebar source list, destructive-action affordances, dense status badges |
| **System Settings (Ventura+)** | Settings pane layout, dense forms, sectioned content, navigation pattern |

Explicitly **not** referenced: Mail, Messages, Music, Photos, TV. Those apps' aesthetics solve different problems than Nimbus solves.

---

## Phased Roadmap

Solo developer. No multi-tracking. Each phase ships before the next begins. Each phase has its own brainstorm → design → implementation cycle.

| Phase | Theme | Output | Rough scope |
|-------|-------|--------|-------------|
| **0 — North Star** | This document | Vision, pillars, roadmap | (now) |
| **1 — Foundation + Browser** | Design system, interaction primitives, perf baseline, Browser becomes Finder-grade | First implementation spec | ~3–4 weeks |
| **2 — Radiate polish** | Apply foundation to Remotes, Mounts, Transfers, CopySync, Settings, Onboarding | One spec or split per screen | ~3–4 weeks |
| **3 — System integration depth** | Quick Look provider, Spotlight, Shortcuts, Services menu, Share Sheet, menubar polish, notifications | One spec, possibly split | ~3 weeks |
| **4 — Tier 2 features** | Encryption wizard, scheduled syncs, public links | Spec per feature | ~4–6 weeks |
| **5 — Tier 3 features** | Media gallery, advanced browser modes | Spec per feature | as needed |

**Sequencing rules:**

- No phase begins until the previous phase ships.
- Within each phase, every screen in scope must clear all four pillars before the phase ships.
- The original Enter Space Tier 4 (OS integration) folds into Phase 3 — it *is* system integration depth.

### Phase 1 preview (next brainstorm)

Phase 1 produces a foundation layer that every later phase inherits. Detailed in its own design doc, but the bounds are:

**Foundation layer** (`Nimbus/Nimbus/DesignSystem/`, `Nimbus/Nimbus/Components/`):

- **Design tokens** — semantic colors, spacing scale, radius scale, animation curves. All HIG-derived; no magic numbers in views.
- **Typography ramp** — strictly semantic (`.largeTitle`, `.headline`, `.body`, `.callout`). Zero `.system(size:)`. Dynamic Type tested through XXXL.
- **Component primitives** — `StatusBadge`, `InspectorPanel`, `SourceListSection`, `EmptyState`, toolbar patterns, sheet chrome, confirmation dialogs with destructive-action affordances.
- **Interaction primitives** — `Selection` model (single + range + ⌘-additive), `DragDropCoordinator` (within-remote, cross-remote, to-Finder), `QuickLookHost`, keyboard handler with `KeyEquivalent` registration, focus management.
- **Performance harness** — a `BenchScene` target that runs scripted scenarios (load 10k items, mount, switch remote) and dumps timings. Pillar 4 enforced by `swift test` + this harness.

**Browser as proving ground** (`Views/Browser/`):

- `FileTable` rebuilt against the foundation: virtualized rows, sort indicators, column resize/reorder persistence, type-to-select, multi-select with Finder semantics, drag-and-drop including cross-remote drops that enqueue a Copy transfer.
- `FileGrid` rebuilt similarly with Finder-icon-view feel.
- Quick Look integration via the new `QuickLookHost`.
- Browser toolbar using the new primitives.
- Empty states + error states using `EmptyState` primitive.
- Browser perf: 10k-item dir cold-load ≤ 200ms with skeleton placeholders during fetch.

**Explicitly out of scope for Phase 1:**
- Other screens (Phase 2)
- Encryption wizard, scheduled syncs, public links (Phase 4)
- Spotlight/Shortcuts/Services (Phase 3)
- Media gallery (Phase 5)

---

## Tauri Sunset

Today the repo contains both a Tauri app (~7,380 LOC TypeScript + ~780 LOC Rust + a Swift File Provider extension) and a SwiftUI app (~3,653 LOC Swift). Recent history shows features being shipped twice (e.g., launch-at-login landed in both apps over ten commits). This stops in Phase 1.

### Step 1 — Mark deprecated immediately

- Add `DEPRECATED.md` at repo root linking to the SwiftUI app
- Add a one-line banner to the Tauri app's About dialog: "Nimbus is moving to native Swift. This build is end-of-life."
- Bump the Tauri app's version to a `-eol` suffix

### Step 2 — Freeze at last working state

- Cut a `tauri-eol` branch pinning the Tauri tree at its current commit
- No new feature commits to `src/`, `src-tauri/`, or `src-tauri/FileProviderExtension/`
- Security fixes only, and only if anyone yells

### Step 3 — Move out of the way

- Relocate Tauri sources to `legacy/tauri/` on `main` so the SwiftUI app is the obvious primary citizen of the repo
- Update `CLAUDE.md`, `README.md`, and the scripts in `scripts/` to default to SwiftUI builds
- Delete `src-tauri/FileProviderExtension/` once the Nimbus SwiftUI File Provider extension reaches parity (already very close — both extensions read from the same `group.app.casavargas.nimbus` app group)

### Deletion (later)

Outright deletion of `legacy/tauri/` happens after the SwiftUI app fully replaces it for shipped users (~end of Phase 2 or Phase 3). Until then, the legacy tree is a useful reference for "how did we solve X over there?" but explicitly not a build target.

---

## Risks

Naming these up front so future-me doesn't pretend they weren't predictable.

### Finder-grade file interaction is hard in SwiftUI

`Table` is good but not Finder. Drag-and-drop across remotes is a custom UX problem. Selection semantics under SwiftUI's data-driven model are awkward at the edges. Budget for `NSViewRepresentable` bridges in at least one place during Phase 1. The interaction primitives in the foundation layer must be designed assuming we may need to swap out the underlying view for AppKit later without rewriting consumers.

### Performance pillar bites at scale

10k-item directories require virtualized rows + cached thumbnails + async metadata fetch. Phase 1 must establish the perf harness; otherwise pillar 4 silently degrades feature-by-feature with no one noticing until users complain. The `BenchScene` target is non-optional.

### Polish-first costs visible momentum

Phases 1 and 2 combined are ~6–8 weeks before any user-facing *new feature* ships. This is the right bet for the wedge, but easy to flinch on. If we blink mid-Phase 2 and start shipping Tier 2 features early, the foundation deteriorates and the wedge dulls. Phase 2 must complete before Tier 2 work begins.

### Solo-dev sequencing

No parallel feature tracks. This means features that would be easy to delegate in a team setting take their full sequential time here. Schedule estimates reflect serial execution.

---

## Success Metrics

The wedge is *feel*, which is hard to measure. Mix of objective and subjective gates per phase.

### Objective (CI-enforceable)

- Cold launch ≤ 1.0s on M1 baseline
- 10k-item directory load ≤ 200ms (perf harness)
- Mount-to-Finder-visible ≤ 2.0s
- No animation > 250ms in normal flow
- VoiceOver: every interactive element labeled; in-scope screens fully usable VoiceOver-only
- Dynamic Type XXXL doesn't break any in-scope layout
- Zero `.system(size:)` calls (lint check)
- Zero third-party UI dependency added (Package.resolved diff check)

### Subjective (self-graded per phase exit)

- Two-minute walkthrough of the app. Count moments where it feels non-native. Phase exit gate: zero of those moments within the phase's scope.
- Side-by-side comparison against Finder (for Browser) or Disk Utility (for status-heavy screens). List every interaction where Apple's app wins. Phase exit gate: list empty within scope.
- Hand the build to a Mac-fan friend who hasn't seen it. Ask: "Does this feel like an Apple app?" Track yes/no over time.

### Per-phase gate

A phase ships only when:
1. All objective metrics pass in CI
2. All subjective lists are empty within scope
3. All four design pillars hold for every screen in scope

If any of those fail, the phase doesn't ship — work continues until they pass. No silent compromises.

---

## What's next

This is the strategic frame. The Phase 1 implementation spec is a separate brainstorm session that turns the foundation + Browser preview above into a concrete, task-by-task plan with TDD steps. That session happens after this doc is reviewed and approved.

After Phase 1 ships, Phase 2 gets its own brainstorm. And so on.

The terminal state of *this* doc is: a fixed reference for what "best rclone app for the Mac" means in concrete, testable terms, so every future spec can be checked against it.
