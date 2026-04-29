# VOXL docs site

This folder is the source for the VOXL user guide hosted on GitHub Pages.

## Local preview (optional)

GitHub Pages will build the site automatically once enabled. To preview locally first, you'll need Ruby + Bundler:

```bash
cd docs
bundle init
bundle add jekyll just-the-docs jekyll-remote-theme jekyll-seo-tag
bundle exec jekyll serve
```

The site appears at <http://127.0.0.1:4000/voxl/>.

## Enabling GitHub Pages (one-time setup)

1. Go to <https://github.com/william-saxton/voxl/settings/pages>
2. Under **Source**, choose **Deploy from a branch**
3. Set the branch to **main** and the folder to **/docs**
4. Click **Save**
5. Wait ~1 minute. The site goes live at <https://william-saxton.github.io/voxl/>

The first build can take 2–5 minutes; subsequent updates after a push usually take under a minute.

## Files in this folder

| File | Purpose |
|---|---|
| `_config.yml` | Jekyll + Just-the-Docs configuration |
| `_sass/custom/custom.scss` | Inline icon styling and `<kbd>` key-cap styling |
| `index.md` | Getting Started (page 1) |
| `editing-basics.md` | Editing Basics (page 2) |
| `shapes-and-tools.md` | Shapes & Tools (page 3) |
| `palette-and-tiles.md` | Palette & Tiles (page 4) |
| `advanced.md` | Selection, Transform, Symmetry, Procedural, Spawns (page 5) |
| `reference.md` | Shortcuts, menus, glossary (page 6) |
| `assets/icons/*.svg` | Tool icons embedded inline in the guide |
| `voxel_editor_reference.md` | (Legacy) — predates this guide; excluded from the Pages build via `_config.yml` |
| `agentic_llm_asset_creation.md` | (Legacy) — also excluded |

## Updating the docs

Just edit the markdown and push to `main`. The Pages site rebuilds automatically.

If you add a new page, give it Just-the-Docs front-matter:

```yaml
---
title: My New Page
layout: default
nav_order: 7
---
```

If you reference a tool icon that isn't already in `assets/icons/`, copy the SVG from `themes/icons/` and replace `fill="white"` with `fill="currentColor"` so it renders correctly in both light and dark modes.
