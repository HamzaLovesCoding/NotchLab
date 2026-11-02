# NotchLab landing page

A dependency-free, responsive landing page using the product's real logo and screenshots. The screenshots are rendered from the real app UI filled with demo data, so no personal reminders, clipboard items, or usage show up.

From this directory, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Open http://127.0.0.1:4173. No build step is needed. Pushing changes to `website/` on `main` publishes the site to GitHub Pages (see `.github/workflows/pages.yml`).

The main download links point to the public v1.0.0 DMG on GitHub. Update those links and version labels when a new release ships. Source installation is also available in an expandable section. The interactive preview switches between screenshots; it does not run the macOS app.
