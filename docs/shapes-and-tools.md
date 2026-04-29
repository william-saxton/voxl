---
title: Shapes & Tools
layout: default
nav_order: 3
---

# Shapes & Tools

When Add, Subtract, or Paint is the active mode, the left sidebar shows seven sub-tools: five **shapes** and two **stamps** (Fill, Extrude). Plus a third special sub-tool — the procedural **Shader** — which is covered on the [Advanced page](advanced.html#procedural-shader).

This page documents each shape and tool: which icon it has, the keyboard shortcut, the click pattern, what modifier keys do, and which options apply.

| | Tool | Key | Click pattern | Notes |
|---|---|---|---|---|
| <img src="assets/icons/brush.svg" class="tool-icon"> | [Brush](#brush) | <kbd>1</kbd> | Click or hold-drag | Sized 1–16, optional Flat |
| <img src="assets/icons/timeline.svg" class="tool-icon"> | [Line](#line) | <kbd>2</kbd> | Click start → click end | <kbd>Shift</kbd> snaps to axis |
| <img src="assets/icons/check_box_outline_blank.svg" class="tool-icon"> | [Box](#box) | <kbd>3</kbd> | Click → click → height | Hollow, Square (<kbd>Shift</kbd>) |
| <img src="assets/icons/circle.svg" class="tool-icon"> | [Circle](#circle) | <kbd>4</kbd> | Click centre → drag radius → height | Hollow |
| <img src="assets/icons/polygon.svg" class="tool-icon"> | [Polygon](#polygon) | <kbd>5</kbd> | Click centre → drag radius → height | Hollow, Sides 3–32 |
| <img src="assets/icons/fill.svg" class="tool-icon"> | [Fill](#fill) | <kbd>F</kbd> | One click | Behaviour depends on mode |
| <img src="assets/icons/extrude.svg" class="tool-icon"> | [Extrude](#extrude) | <kbd>G</kbd> | Click face → drag depth | Pulls or pushes faces |

All seven tools live under all three of Add / Subtract / Paint — the **mode** decides whether the tool adds, removes, or recolours; the **tool** decides the volume.

---

## The height phase

Three shapes — Box, Circle, Polygon — have a final **height phase**. After your two clicks define the footprint on the working plane, the shape becomes a flat outline floating in 3D. Move the mouse to extrude that outline along the face normal: forward to make it taller, backward to make it shorter (or even invert past zero). A third click commits the shape; <kbd>Esc</kbd> cancels.

The height preview is rendered as a translucent wireframe in mode-coloured tint:

| Mode | Preview tint |
|---|---|
| Add | Blue |
| Subtract | Red |
| Paint | Yellow |

If you skip the height phase by clicking immediately on the second click, the shape is one voxel thick.

---

## <img src="assets/icons/brush.svg" class="tool-icon"> Brush {#brush}

**Shortcut**: <kbd>1</kbd>

The simplest tool — places (or removes / recolours) a single voxel under the cursor on click, or a continuous trail on hold-and-drag.

### Options (context bar)

| Option | Range | Effect |
|---|---|---|
| **Brush Size** | 1–16 | Diameter of the brush sphere. At size 1 you place one voxel per click; at size 16 you stamp a 16-voxel ball |
| **Flat** | toggle | When on, the brush is flattened against the working plane — gives you a circular disc instead of a sphere |

{: .tip }
> A size-3 Flat brush is the right tool for sketching organic surfaces — fast enough to drag continuously, large enough to feel like a paintbrush rather than a pixel.

---

## <img src="assets/icons/timeline.svg" class="tool-icon"> Line {#line}

**Shortcut**: <kbd>2</kbd>

Two-click straight line between two voxels. The line is drawn with Bresenham-style rasterisation in 3D, so it stays 1 voxel thick along its length regardless of orientation.

### Click pattern

1. Click the start voxel
2. Move the cursor — a translucent preview line tracks the cursor
3. Click the end voxel to commit

### Modifiers

| Hold | Effect |
|---|---|
| <kbd>Shift</kbd> | Snap to the nearest cardinal axis (X / Y / Z) — produces a perfectly straight line along one axis |

Cancel an in-progress line with <kbd>Esc</kbd>.

---

## <img src="assets/icons/check_box_outline_blank.svg" class="tool-icon"> Box {#box}

**Shortcut**: <kbd>3</kbd>

A 3D rectangular cuboid defined by three clicks: two corners on the working plane, then a height.

### Click pattern

1. Click corner A — anchors one edge of the footprint
2. Click corner B — completes the footprint rectangle. The preview now floats; move the mouse vertically to set height
3. Click again to commit the cuboid

### Options

| Option | Effect |
|---|---|
| **Hollow** (<kbd>H</kbd>) | Build only the shell of the cuboid (six faces, no interior). Combine with Subtract to carve a window |
| **Wrap at Tile Edges** | When on, voxels that fall outside the tile bounds wrap around using `posmod` instead of being clipped. Off by default |

### Modifiers

| Hold | Effect |
|---|---|
| <kbd>Shift</kbd> | Constrain the footprint to a square — both dimensions move together |

---

## <img src="assets/icons/circle.svg" class="tool-icon"> Circle {#circle}

**Shortcut**: <kbd>4</kbd>

A vertical or horizontal disc, swept into a cylinder during the height phase.

### Click pattern

1. Click the centre point
2. Drag outward to set the radius — the preview disc grows. Click to commit the radius
3. Move the mouse to set the height (sweep direction depends on which face the centre was placed on)
4. Click to commit

### Options

| Option | Effect |
|---|---|
| **Hollow** (<kbd>H</kbd>) | Build only the rim — gives you a hoop instead of a disc, or a tube instead of a cylinder |

The disc is rasterised with a midpoint-circle algorithm, so radii from 1 to ~64 produce visually clean circles.

---

## <img src="assets/icons/polygon.svg" class="tool-icon"> Polygon {#polygon}

**Shortcut**: <kbd>5</kbd>

A regular N-gon. Behaves identically to Circle but with discrete sides instead of a smooth curve. With Sides = 32 it is indistinguishable from Circle; with Sides = 3 it is a triangle.

### Click pattern

Same as Circle: centre → radius → height.

### Options

| Option | Range | Effect |
|---|---|---|
| **Hollow** (<kbd>H</kbd>) | toggle | Outline only — useful for polygonal arches and rims |
| **Sides** | 3–32 (default 6) | Number of corners in the polygon |

{: .tip }
> Sides = 6 (a hexagon) is the default for a reason — it tessellates well at small radii and reads as "polygon" rather than "low-resolution circle".

---

## <img src="assets/icons/fill.svg" class="tool-icon"> Fill {#fill}

**Shortcut**: <kbd>F</kbd>

A flood-fill that propagates from the clicked voxel outwards. Behaviour depends on the active **primary mode**:

| Mode | Behaviour |
|---|---|
| **Add** | Pour fill — fills connected air voxels like water rising to fill an enclosed cavity |
| **Subtract** | Removes the entire connected blob you click on |
| **Paint** | Recolours every voxel connected to the clicked one |

Click a voxel (or empty space, in Add mode) to start the fill. There is no preview — the fill commits immediately.

### Connectivity options (context bar)

When Fill (or Extrude, or Face-select) is the active tool, the context bar shows a set of filters that restrict which neighbours count as "connected":

| Toggle | Effect |
|---|---|
| **Face** (<kbd>Q</kbd>) | Toggle between **Geometry** connectivity (any 6-connected non-air voxel) and **Face** connectivity (only voxels sharing the *exposed* face you clicked) |
| **Color** | Restrict the flood to voxels with the same palette colour as the seed |
| **Material** | Restrict the flood to voxels with the same base material type (stone, water, lava, etc.) as the seed |
| **Range** | Slider 4–128 (default 64). Maximum search distance from the seed in voxels — caps runaway fills |

The combination of `Color` + `Face` is what you want when recolouring a single visible surface (a wall) without bleeding into adjacent surfaces.

---

## <img src="assets/icons/extrude.svg" class="tool-icon"> Extrude {#extrude}

**Shortcut**: <kbd>G</kbd>

Pull a face outward (Add), push it inward (Subtract), or repaint a layer (Paint). Extrude operates on a *connected face region* — first it finds all voxels on the face you clicked that share connectivity with each other, then it extrudes that region as a single block along the face normal.

### Click pattern

1. Click a face — the connected face region highlights
2. Drag the mouse along the face normal — the preview shows N layers
3. Release (or click again) to commit

The same connectivity options as Fill (Face / Color / Material / Range) apply during selection of the face region.

{: .note }
> Extrude is the right tool for "thicken this wall by 2 voxels" or "carve back this ledge by 1". It's selection + transform in a single click-drag.

---

## Working plane and depth

When you click in the viewport, the editor decides which Y level your shape lives on. Three rules, in priority:

1. **Click on a voxel** → the new shape is placed on the face you clicked
2. **Click on the floor grid** → the new shape sits at Y = 0
3. **Click in empty space** → the working plane is the closest grid plane perpendicular to the camera's view direction

Once a shape's first click lands, the working plane is locked for the duration of that shape's drawing — you can move the mouse anywhere in 3D space and the shape stays anchored to the original plane until you commit.

---

## Locking guide points

Two refinements help with very precise placement:

| Shortcut | Effect |
|---|---|
| <kbd>L</kbd> | Lock or unlock highlight points on the face under the cursor — locked faces show a permanent visual marker, useful as a reference while sketching |
| <kbd>Shift</kbd> + <kbd>L</kbd> | Clear all locked faces |

Locked faces persist across mode and tool changes; they live on the tile until cleared or the tile is closed.

---

## Cancelling

At any point during a multi-click shape, press <kbd>Esc</kbd> to cancel the in-progress action. The shape is discarded; no voxels are placed or removed.

---

## Next

Move on to [Palette & Tiles](palette-and-tiles.html) for the colour palette workflow and the tile-properties dialog.
