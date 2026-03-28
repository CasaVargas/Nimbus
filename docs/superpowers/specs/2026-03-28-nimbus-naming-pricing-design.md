# Nimbus — Naming & Pricing Design

## Name

**Name:** Nimbus

**Tagline:** "Your cloud, one app."

**Positioning:** A polished desktop app for managing cloud storage across 40+ providers. Powered by rclone under the hood, branded as its own product. Targets developers and power users who want a real GUI without the jank.

**App identifier:** `com.nimbus.app` (fallback: `com.nimbusapp.cloud`)

**Naming rationale:** "Nimbus" is a cloud type — immediately evokes cloud storage without being generic. Short, one word, memorable. Subtle enough that power users get the connection, approachable enough for everyone else.

## Pricing

**Model:** One-time purchase, single tier

**Price:** $14

**What's included:** Full app, all features, no restrictions

**Update policy:** Free updates within v1.x. Major versions (v2, v3) are paid upgrades (~$9 for existing users, $14 for new customers).

**Distribution:** Direct download from website. Payments via Gumroad or Lemonsqueezy. Mac App Store considered for later, not at launch (avoids 30% cut and App Review friction).

**No free tier. No trial at launch.** If conversion becomes a problem, add a 7-day trial later.

## Rename Scope

Renaming from "StreamCloned" to "Nimbus" touches:
- `package.json` (name field)
- `src-tauri/Cargo.toml` (package name, description)
- `src-tauri/tauri.conf.json` (app identifier, window title, product name)
- Any hardcoded strings referencing "StreamCloned" in UI copy
- GitHub repo name/description (when ready)
