# Nimbus marketing site

A single static page: `index.html`, `styles.css` and the images in `assets/`. No
build step, no dependencies, no cookies, and one small inline script: the
download counter under the hero (`#stats`). It asks GitHub's public API for the
DMG download total and the star count, and shows the line only at
`data-min-downloads` (1,000) or more; stars are added at 100 or more. Without
scripts, or below the threshold, the line stays hidden and the page is unchanged.

The motion (the pinned paragraph whose sentences light in turn, windows that
grow into place, tiles that rise in) is CSS scroll timelines, in the last block
of `styles.css`. It sits inside `@supports (animation-timeline: view())` and
`prefers-reduced-motion: no-preference`, so a browser without scroll timelines,
or a reader who asked for less motion, gets the same page standing still. Keep
it that way: the page above that block must be complete on its own.

App screenshots are rendered from demo data, never from a real configuration:
the previews in `Nimbus/Nimbus/Views/Debug/SiteScreenshots.swift` draw the real
views at 2x, one preview per file name. Render each in Xcode, save the PNG to
`docs/screenshots/`, and convert it for the site with
`cwebp -q 90 -alpha_q 100 name.png -o site/assets/name.webp`.

Visits are counted by the self-hosted Plausible at `analytics.jonvargas.net`,
under the site `casavargas.app` (filter by page `/nimbus/`). It sets no cookies.
The three download links carry `plausible-event-name=Nimbus+Download` and a
`plausible-event-position` (nav, hero, footer), so a click shows as a
"Nimbus Download" event. Plausible ignores localhost, so this can only be checked
on the live page: a visit should `POST /api/event` and get a 202. The privacy
section says the page does this; keep the two in step.

Preview locally:

```bash
python3 -m http.server 8080 --directory site
```

Deploy by copying the folder anywhere that serves static files (GitHub Pages,
Cloudflare Pages, the casavargas.github.io repo under `/nimbus/`).

Copy rules, carried over from the casavargas.app product page: no price (only the
model), no "sandboxed", no "bundles rclone", no performance numbers, no Mac App
Store, no roadmap item described as if it shipped, no em dashes. The page names no
version: every download link goes to `releases/latest`, so publish the page only
once the latest release has what the page shows.
