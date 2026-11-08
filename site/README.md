# Nimbus marketing site

A single static page: `index.html`, `styles.css`, `site.js` and the screenshots in
`assets/` (copied from `docs/screenshots/`). No build step, no dependencies, no
tracking.

Preview locally:

```bash
python3 -m http.server 8080 --directory site
```

Deploy by copying the folder anywhere that serves static files (GitHub Pages,
Cloudflare Pages, the casavargas.github.io repo under `/nimbus/`).

Copy rules, carried over from the casavargas.app product page: no price (only the
model), no "sandboxed", no "bundles rclone", no performance numbers, no Mac App
Store, no roadmap item described as if it shipped, no em dashes. Bump the version
string in the hero, the download section, the JSON-LD and the DMG link together.
