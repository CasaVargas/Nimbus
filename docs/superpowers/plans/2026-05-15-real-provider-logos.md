# Real Provider Logos — Coverage Expansion + Key-Mapping Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every recognizable cloud brand in the Add Remote picker show its real logo (not a generic SF Symbol), and fix a pre-existing bug where multi-word backends (Google Cloud Storage, Google Photos) never render their bundled logo.

**Architecture:** Keep the existing approach — bundled Simple Icons single-path SVGs as template-rendering imagesets in `ProviderLogos.xcassets`, tinted by official brand hex, drawn by `ProviderIcon`/`ProviderBadge`. Add a `canonicalKey(_:)` normalizer so both call sites (`ProviderPicker` passing `Provider.prefix`, `RemoteRow` passing `remote.type`) resolve to the same catalog key. Add 6 new brand logos for the high-value backends that Simple Icons actually carries.

**Tech Stack:** SwiftUI, Xcode asset catalog (template imagesets), Simple Icons (jsDelivr CDN), XcodeBuildMCP for build, Apple Xcode MCP RenderPreview for visual verification.

---

## Background / Audit Results (already verified)

rclone exposes **69 backends**. Breakdown:

- **19 already have bundled logos:** b2, box, cloudinary, drive, dropbox, filen, gcs, gphotos, huaweidrive, iclouddrive, internetarchive, mega, netstorage(akamai), protondrive, seafile, sharefile(citrix), swift(openstack), yandex, zoho.
- **18 are protocol/virtual backends** where the SF Symbol is correct and NO logo is wanted: alias, archive, cache, chunker, combine, compress, crypt, hasher, memory, union, ftp, sftp, http, webdav, smb, hdfs, local, doi.
- **High-value brands missing a logo that Simple Icons DOES carry (verified via CDN, 200 OK):**
  - `s3` → `amazons3`
  - `onedrive` → `microsoftonedrive`
  - `azureblob` + `azurefiles` → `microsoftazure`
  - `oracleobjectstorage` (prefix `oos`) → `oracle`
  - `mailru` → `maildotru`
- **Niche backends genuinely NOT in Simple Icons (verified 404) — intentionally OUT OF SCOPE**, they keep the already-polished tinted SF-Symbol fallback: storj, tardigrade, pcloud, putio, jottacloud, koofr, pixeldrain, gofile, hidrive, opendrive, premiumizeme, sugarsync, qingstor, imagekit, internxt, drime, filescom, filefabric, filelu, linkbox, pikpak, quatrix, sia, shade, fichier, ulozto.

**Pre-existing bug:** `ProviderPicker.swift:53` passes `provider.name`. For GCS that string is `"google cloud storage"` and for Google Photos `"google photos"`, but the catalog keys are `gcs`/`gphotos` — so those logos never render in the picker. `RemoteRow.swift:50` passes `remote.type`, where rclone stores `"google cloud storage"` / `"google photos"` / `"oracleobjectstorage"`. The fix: switch the picker to pass `Provider.prefix` (stable: `gcs`, `gphotos`, `oos`, `s3`, …) and add a `canonicalKey` alias map so `RemoteRow`'s rclone-`type` spellings also resolve.

**No XcodeGen needed:** `project.yml` bundles `path: Nimbus` recursively and `ProviderLogos.xcassets` is already referenced in the pbxproj (verified). New imagesets dropped *inside* the existing `.xcassets` are picked up by the asset compiler on the next build — do **not** run `xcodegen generate` for this.

---

### Task 1: Add the 6 new brand logo imagesets

**Files:**
- Create: `Nimbus/Nimbus/Resources/ProviderLogos.xcassets/amazons3.imageset/{amazons3.svg,Contents.json}`
- Create: `Nimbus/Nimbus/Resources/ProviderLogos.xcassets/microsoftonedrive.imageset/{microsoftonedrive.svg,Contents.json}`
- Create: `Nimbus/Nimbus/Resources/ProviderLogos.xcassets/microsoftazure.imageset/{microsoftazure.svg,Contents.json}`
- Create: `Nimbus/Nimbus/Resources/ProviderLogos.xcassets/oracle.imageset/{oracle.svg,Contents.json}`
- Create: `Nimbus/Nimbus/Resources/ProviderLogos.xcassets/maildotru.imageset/{maildotru.svg,Contents.json}`

- [ ] **Step 1: Download the 5 SVGs from the Simple Icons CDN into the correct imageset folders**

Run (from repo root `/Volumes/DATA/CasaVargas/Nimbus`):

```bash
cd Nimbus/Nimbus/Resources/ProviderLogos.xcassets
for slug in amazons3 microsoftonedrive microsoftazure oracle maildotru; do
  mkdir -p "$slug.imageset"
  curl -fsSL "https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/$slug.svg" \
    -o "$slug.imageset/$slug.svg"
done
ls -1 */*.svg | grep -E 'amazons3|microsoftonedrive|microsoftazure|oracle|maildotru'
```

Expected: 5 lines listing the new `.svg` files; each file is a single-path `<svg ... viewBox="0 0 24 24"><title>…</title><path d="…"/></svg>`.

- [ ] **Step 2: Verify each SVG is a valid single-path Simple Icon**

Run:

```bash
cd /Volumes/DATA/CasaVargas/Nimbus/Nimbus/Nimbus/Resources/ProviderLogos.xcassets
for s in amazons3 microsoftonedrive microsoftazure oracle maildotru; do
  head -c 80 "$s.imageset/$s.svg"; echo " <-- $s"
done
```

Expected: each line starts with `<svg role="img" viewBox="0 0 24 24"` and contains `<title>`. If any file is HTML/empty (CDN miss), STOP and re-fetch that slug.

- [ ] **Step 3: Write the 5 `Contents.json` files (identical template-rendering format used by existing imagesets)**

Create each `<slug>.imageset/Contents.json` with this exact content (substitute the slug in `filename`):

```json
{
  "images" : [
    {
      "filename" : "SLUG.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
```

Concretely, write:
- `amazons3.imageset/Contents.json` with `"filename" : "amazons3.svg"`
- `microsoftonedrive.imageset/Contents.json` with `"filename" : "microsoftonedrive.svg"`
- `microsoftazure.imageset/Contents.json` with `"filename" : "microsoftazure.svg"`
- `oracle.imageset/Contents.json` with `"filename" : "oracle.svg"`
- `maildotru.imageset/Contents.json` with `"filename" : "maildotru.svg"`

- [ ] **Step 4: Sanity-check the asset catalog folder structure**

Run:

```bash
cd /Volumes/DATA/CasaVargas/Nimbus/Nimbus/Nimbus/Resources/ProviderLogos.xcassets
for s in amazons3 microsoftonedrive microsoftazure oracle maildotru; do
  test -f "$s.imageset/$s.svg" && test -f "$s.imageset/Contents.json" \
    && echo "OK $s" || echo "MISSING $s"
done
```

Expected: 5 `OK` lines.

- [ ] **Step 5: Commit**

```bash
cd /Volumes/DATA/CasaVargas/Nimbus
git add Nimbus/Nimbus/Resources/ProviderLogos.xcassets/amazons3.imageset \
        Nimbus/Nimbus/Resources/ProviderLogos.xcassets/microsoftonedrive.imageset \
        Nimbus/Nimbus/Resources/ProviderLogos.xcassets/microsoftazure.imageset \
        Nimbus/Nimbus/Resources/ProviderLogos.xcassets/oracle.imageset \
        Nimbus/Nimbus/Resources/ProviderLogos.xcassets/maildotru.imageset
git commit -m "feat(remotes): add Simple Icons logos for S3, OneDrive, Azure, Oracle, Mail.ru"
```

---

### Task 2: Wire the new logos into `ProviderCatalog.brand` and remove now-dead SF-Symbol special-cases

**Files:**
- Modify: `Nimbus/Nimbus/Components/ProviderIcon.swift` (the `brand` dictionary, lines 116-136; the `symbol(for:)` switch, lines 154-160)

- [ ] **Step 1: Add the 6 new brand entries to the `brand` dictionary**

In `ProviderIcon.swift`, the `static let brand: [String: Brand]` dictionary, add these entries (keep the dictionary alphabetically ordered by key, matching existing style). Brand hexes are the official Simple Icons colors:

```swift
        "azureblob": .init(asset: "microsoftazure", hex: 0x0078D4),
        "azurefiles": .init(asset: "microsoftazure", hex: 0x0078D4),
        "mailru": .init(asset: "maildotru", hex: 0x005FF9),
        "onedrive": .init(asset: "microsoftonedrive", hex: 0x0078D4),
        "oos": .init(asset: "oracle", hex: 0xF80000),
        "s3": .init(asset: "amazons3", hex: 0x569A31),
```

The dictionary after editing must contain all 19 originals plus these 6 (25 total). Do not remove any existing entry.

- [ ] **Step 2: Remove the now-shadowed SF-Symbol special cases (YAGNI — `brand[]` is checked first, so these are dead code)**

In `symbol(for name:)`, delete these three `case` blocks entirely (lines ~155-160):

```swift
        case "s3":
            return ("shippingbox.fill", Color(red: 1.0, green: 0.60, blue: 0.0)) // AWS orange
        case "onedrive", "sharepoint":
            return ("cloud.fill", Color(red: 0.0, green: 0.47, blue: 0.83)) // OneDrive blue
        case "azureblob", "azurefiles":
            return ("cloud.circle.fill", Color(red: 0.0, green: 0.62, blue: 0.93)) // Azure
```

Replace them with a single case that still covers the bare `sharepoint` string (no Simple Icon, and not a picker backend, but `remote.type` can carry it):

```swift
        case "sharepoint":
            return ("cloud.fill", Color(red: 0.0, green: 0.47, blue: 0.83))
```

Leave every other `case` in `symbol(for:)` untouched.

- [ ] **Step 3: Build to confirm it compiles**

Use XcodeBuildMCP `build_macos` (scheme `Nimbus`, project `Nimbus/Nimbus.xcodeproj`). If session defaults are unset, call `session_show_defaults` first.

Expected: BUILD SUCCEEDED, no errors in `ProviderIcon.swift`.

- [ ] **Step 4: Commit**

```bash
cd /Volumes/DATA/CasaVargas/Nimbus
git add Nimbus/Nimbus/Components/ProviderIcon.swift
git commit -m "feat(remotes): map S3/OneDrive/Azure/Oracle/Mail.ru to bundled logos"
```

---

### Task 3: Fix the name/prefix key-mapping bug (unblocks GCS + Google Photos + Oracle logos at both call sites)

**Files:**
- Modify: `Nimbus/Nimbus/Components/ProviderIcon.swift` (add `canonicalKey`, route `ProviderIcon` + `ProviderBadge` through it)
- Modify: `Nimbus/Nimbus/Views/Remotes/ProviderPicker.swift:53` (pass `provider.prefix` instead of `provider.name`)

- [ ] **Step 1: Add a `canonicalKey` normalizer to `ProviderCatalog`**

In `ProviderIcon.swift`, inside `enum ProviderCatalog`, add (place it directly above `static func tint(for:)`):

```swift
    /// Maps the various raw spellings that reach the icon views — rclone
    /// `Provider.prefix` from the picker and the stored `remote.type` from
    /// RemoteRow — onto a single catalog key. Most backends already agree
    /// (e.g. "s3", "dropbox"); only the multi-word ones diverge.
    static func canonicalKey(_ raw: String) -> String {
        let k = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch k {
        case "google cloud storage": return "gcs"
        case "google photos": return "gphotos"
        case "oracleobjectstorage": return "oos"
        default: return k
        }
    }
```

- [ ] **Step 2: Route `ProviderIcon.body` through `canonicalKey`**

In `struct ProviderIcon`, change:

```swift
        let key = provider.lowercased()
```

to:

```swift
        let key = ProviderCatalog.canonicalKey(provider)
```

- [ ] **Step 3: Route `ProviderBadge` through `canonicalKey`**

In `struct ProviderBadge.body`, change:

```swift
        let key = provider.lowercased()
```

to:

```swift
        let key = ProviderCatalog.canonicalKey(provider)
```

(The `glyph(key:)` helper already receives this `key`, so no further change there.)

- [ ] **Step 4: Make the picker pass the stable prefix**

In `Nimbus/Nimbus/Views/Remotes/ProviderPicker.swift`, line 53, change:

```swift
                ProviderBadge(provider: provider.name, size: 52)
```

to:

```swift
                ProviderBadge(provider: provider.prefix, size: 52)
```

(`Provider.prefix` is `gcs`, `gphotos`, `oos`, `s3`, `dropbox`, … — stable, unlike the human `name`.)

- [ ] **Step 5: Build**

Use XcodeBuildMCP `build_macos`. Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
cd /Volumes/DATA/CasaVargas/Nimbus
git add Nimbus/Nimbus/Components/ProviderIcon.swift Nimbus/Nimbus/Views/Remotes/ProviderPicker.swift
git commit -m "fix(remotes): resolve provider logo key for multi-word backends (GCS, Google Photos, Oracle)"
```

---

### Task 4: Visual verification

**Files:**
- Modify: `Nimbus/Nimbus/Components/ProviderIcon.swift` (`#Preview` name list, lines 210-213)

- [ ] **Step 1: Extend the preview grid to include every newly-covered + previously-broken key**

In the `#Preview` at the bottom of `ProviderIcon.swift`, replace the `names` array with:

```swift
    let names = ["drive", "gcs", "gphotos", "dropbox", "s3", "onedrive",
                 "azureblob", "azurefiles", "oos", "mailru", "b2", "box",
                 "mega", "protondrive", "iclouddrive", "swift", "yandex",
                 "zoho", "crypt", "ftp", "webdav", "local", "hdfs", "pcloud",
                 "storj", "koofr", "fichier", "doi"]
```

- [ ] **Step 2: Render the preview and visually confirm**

Use Apple Xcode MCP `RenderPreview` on `ProviderIcon.swift`'s `#Preview`.

Visually verify (do NOT ask the user — confirm yourself per CLAUDE.md UI rule):
- `s3`, `onedrive`, `azureblob`, `azurefiles`, `oos`, `mailru` show a recognizable **brand glyph** on a brand-colored tile (not a generic `cloud.fill`).
- `gcs` and `gphotos` now show the Google Cloud / Google Photos glyph (the pre-existing bug is fixed).
- `crypt`, `ftp`, `webdav`, `local`, `hdfs`, `doi` still show their distinct SF Symbols.
- `pcloud`, `storj`, `koofr`, `fichier` still show varied, distinct SF-Symbol fallback tiles (intentionally no logo).
- The grid still reads as a cohesive set of "app icons" (uniform rounded tiles, white knocked-out glyphs).

If any brand glyph is missing, clipped, or the wrong logo, iterate (re-check the slug→asset mapping in Task 2 Step 1 and the hex) until correct.

- [ ] **Step 3: Commit**

```bash
cd /Volumes/DATA/CasaVargas/Nimbus
git add Nimbus/Nimbus/Components/ProviderIcon.swift
git commit -m "test(remotes): expand provider icon preview to cover new + fixed logos"
```

---

## Self-Review Notes

- **Spec coverage:** "Real icons for all these remote services" → Task 1+2 add every recognizable brand Simple Icons actually carries; the audit explicitly documents which niche backends stay on the (already-polished) SF-Symbol fallback and *why* (not in Simple Icons), so expectations are honest. The Claude/Figma question was answered in conversation (limited value for asset sourcing) and is intentionally not a task.
- **Pre-existing bug:** Task 3 fixes GCS/Google Photos logos that never rendered in the picker — surfaced during the audit, in scope because it's the same "show the real logo" goal.
- **Type consistency:** `canonicalKey(_:)` defined in Task 3 Step 1 is the exact name used in Steps 2-3; brand keys `oos`/`s3`/`onedrive`/`azureblob`/`azurefiles`/`mailru` added in Task 2 Step 1 match the `canonicalKey` outputs and the `Provider.prefix` values from rclone.
- **No XcodeGen:** confirmed `.xcassets` is already in the pbxproj and bundled recursively; new imagesets need only a rebuild.
- **Out of scope (deliberate):** full-color official logos (licensing + grid-cohesion tradeoff, discussed and declined); Figma/Claude-design integration; niche backends absent from Simple Icons.
