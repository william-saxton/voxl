---
title: Palette & Tiles
layout: default
nav_order: 4
---

# Palette & Tiles

Two of the editor's most important non-viewport surfaces: the **palette editor** on the right (which decides what colours you can paint with) and the **tile properties dialog** behind the cog icon (which decides what kind of tile you're editing).

---

## The palette panel

The right-hand panel hosts the palette editor. It shows the current palette as a grid of colour swatches grouped by **material type**, with the active entry highlighted. Clicking a swatch makes it the active colour for Add and Paint.

### What is a palette entry?

A palette entry is more than just a colour — it bundles three things:

| Field | What it controls |
|---|---|
| **Name** | A label, shown on hover. Useful for "moss-stone-light" vs "moss-stone-dark" |
| **Colour** | The RGB tint applied in the Lit and Unshaded view modes. This is what you pick |
| **Material type** | The base substance — Stone, Bedrock, Water, Dirt, Mud, Lava, Acid, Gas, Steam. Drives the **Material** view mode and is what your host game reads when deciding physics, sound, particle behaviour, etc. |

Two entries can share a colour but differ in material — and vice versa. The editor uses the entry's index, not its colour, as the canonical voxel ID.

### Palette controls

At the top of the palette panel:

| Control | Effect |
|---|---|
| **Palette dropdown** | Switch between palettes when more than one is loaded. A tile can use exactly one palette at a time |
| **Duplicate** | Copy the current palette under a new name. The active tile re-binds to the duplicate |
| **Delete** | Remove the current palette. Disabled when only one palette exists |

At the bottom of the panel:

| Control | Effect |
|---|---|
| **Add Entry** | Append a new entry to the palette. Defaults to white / Stone |
| **Delete Entry** | Remove the highlighted entry. Voxels referencing the deleted entry become air |

### Editing an entry

Click a swatch to select it; the **Entry Editor** at the bottom of the panel exposes the entry's three fields:

- **Name** — text input
- **Colour** — colour-picker button (opens Godot's standard picker)
- **Material type** — dropdown with the nine base material types

Changes propagate immediately to the viewport — repainting all voxels referencing that entry.

### The eyedropper

In Add, Subtract, or Paint mode, hold <kbd>Alt</kbd> and click an existing voxel. The clicked voxel's palette index becomes the active entry. This is the fastest way to colour-match without scrolling the palette.

In Select mode, <kbd>Alt</kbd>+click does something different — it deselects the clicked voxel.

### Importing and exporting palettes

The File menu has two palette-only commands:

- **Import Palette…** — load a `.tres` palette file. Replaces the current palette
- **Export Palette…** — save the current palette to a `.tres` file. Useful for sharing a colour scheme across multiple tiles

Tiles store a *reference* to their palette, not a copy — editing a palette changes every tile that uses it.

---

## The gradient panel

Just below the palette swatches sits the **Gradient Selection Panel**. Each palette entry can be assigned a weight; when more than one entry is selected, Add and Paint pick from the selected entries randomly, biased by the weights.

| Operation | How |
|---|---|
| Multi-select entries | <kbd>Ctrl</kbd>+click to add/remove individual entries from the selection |
| Adjust weight | Each selected entry shows a small numeric spinner — set 1.0–10.0 |
| Clear selection | Click any single swatch to drop the multi-select |

When multi-select is active, the active-colour indicator shows the *blend* — and shape tools place a mix of the selected colours rather than one solid tone.

{: .tip }
> Gradient selection is the right tool for stone walls, rocky ground, mossy patches — anywhere "this material has variation" reads better than a single flat colour.

---

## The tile properties dialog

Click the <img src="assets/icons/settings.svg" class="tool-icon"> cog icon at the bottom of the left sidebar to open the tile properties dialog. These are the *metadata* fields of the tile — they don't affect what voxels exist, but they do affect how the host game reads, places, and connects the tile.

| Field | Type | Default | Notes |
|---|---|---|---|
| **Name** | text | `untitled` | Display name. Distinct from the file name |
| **Tile Size** | preset + custom | 128 × 112 × 128 | See [Size presets](#size-presets) below |
| **Edge North/South/East/West** | dropdown | Solid Wall | What kind of connection each side is. See [Edge types](#edge-types) |
| **Biome** | text | empty | Free-text label — e.g. `stone_cavern`, `crystal_forest`. Used by the host game to filter compatible tiles |
| **Weight** | slider | 1.0 | Probability weight for random tile selection at runtime. Range 0.1–10.0 |
| **Surface Material** | dropdown | (registry) | The default material applied to the tile's top surface — fed to footstep / particle systems |
| **Tags** | comma-separated text | empty | Free-form tags. Host games can filter by tag |
| **Marker Scale** | float | 1.0 | Display size of metadata markers (spawn points, etc.) in the viewport |

### Size presets {#size-presets}

The Tile Size field has six presets plus a custom option:

| Preset | Dimensions | Typical use |
|---|---|---|
| Default | 128 × 112 × 128 | Standard play tile |
| Small Prop | 32 × 32 × 32 | A statue, a chest, a small decoration |
| Medium Prop | 64 × 64 × 64 | A tree, a pillar, a doorway segment |
| Tall | 128 × 224 × 128 | Multi-storey rooms, towers |
| Wide | 256 × 112 × 256 | Plazas, large halls |
| Custom | any (1–512 per axis) | Anything else |

Resizing a tile that already has voxels does not delete them — voxels outside the new bounds stay in memory but are simply not rendered or saved.

### Edge types {#edge-types}

Each of the four cardinal edges (North, South, East, West) carries a flag describing what's at that edge. The host game uses these flags during world-generation to decide which tiles can sit next to each other.

| Edge type | Meaning |
|---|---|
| **Solid Wall** | Closed off — a wall blocks passage |
| **Open Ground** | Walkable open ground continues across the edge |
| **Corridor** | A 1-tile-wide passage crosses the edge |
| **Door** | A doorway / portal sits at this edge |
| **Bedrock Wall** | Indestructible wall — used at world boundaries |
| **Structure Internal** | Inside a multi-tile structure — only matches other Structure Internal edges |

Two tiles can be placed adjacent only if their facing edges are compatible — Open Ground next to Open Ground, Door next to Door, etc. Solid Wall is the safe default and matches anything (since "wall + wall" is always a wall).

---

## Tile vs palette: where each lives

A common point of confusion when you first open the editor:

| Asset | Stored in | Owned by |
|---|---|---|
| **Voxel grid** (geometry + colour indices) | The `.tres` tile file | The tile |
| **Palette** (colour, material, name per entry) | A separate `.tres` palette file | Shared across tiles |
| **Tile properties** (size, edges, biome, …) | Inside the tile `.tres` | The tile |
| **Metadata points** (spawns, particles, …) | Inside the tile `.tres` | The tile |

So changing a colour in the palette changes every tile that references it. Resizing a tile only affects that tile. This is intentional — it means a 100-tile dungeon can re-tone everything by editing one palette file.

---

## Saving palettes alongside tiles

When you save a tile (<kbd>Ctrl</kbd>+<kbd>S</kbd>), the editor writes only the tile file — *not* the palette. Palettes are saved separately via **File → Export Palette…**, or implicitly when you edit them in the editor and save the project.

A typical workflow:

1. Pick or duplicate a palette before starting a tile
2. Author the tile (this guide's chapters 2–3)
3. <kbd>Ctrl</kbd>+<kbd>S</kbd> the tile
4. If you tweaked the palette, **File → Export Palette…** to commit those changes

Forgetting step 4 is the most common cause of "the tile looks fine in the editor but renders wrong in the game".

---

## Next

Continue to the [Advanced](advanced.html) chapter for selection, transforms, symmetry, the procedural shader tool, and spawn-point metadata.
