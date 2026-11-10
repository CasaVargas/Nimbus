# Nimbus marketing site

A single static page: `index.html`, `styles.css` and the images in `assets/`. No
build step, no dependencies, no script, no tracking.

App screenshots are rendered from demo data, never from a real configuration:
the previews in `Nimbus/Nimbus/Views/Debug/SiteScreenshots.swift` draw the real
views at 2x, one preview per file name. Render each in Xcode, save the PNG to
`docs/screenshots/`, and convert it for the site with
`cwebp -q 90 -alpha_q 100 name.png -o site/assets/name.webp`.

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
