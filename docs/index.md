---
title: Getting Started
layout: default
nav_order: 1
---

# VOXL Voxel Editor — User Guide

VOXL is a standalone voxel tile editor built in Godot 4.6. It is purpose-built for authoring small chunks of voxel geometry — "tiles" — that can be assembled at runtime to form larger worlds. A tile is a compact 3D grid of coloured voxels with optional metadata (spawn points, particle emitters, shader planes) and edge flags that describe how it connects to its neighbours.

This guide covers the editor itself: every mode, tool, panel, and shortcut. It does not cover engine setup, the native C++ extension build, or how tiles are loaded by a host game.

---

## What you'll learn

| Page | What's covered |
|---|---|
| [Getting Started](./) | The application layout, your first edit, saving, and navigation |
| [Editing Basics](editing-basics.html) | Add / Subtract / Paint / Select / Spawn modes, undo, view modes, the Y-slice slider |
| [Shapes & Tools](shapes-and-tools.html) | Brush, Line, Box, Circle, Polygon, Fill, Extrude — including click patterns and modifier keys |
| [Palette & Tiles](palette-and-tiles.html) | The colour palette, material types, the tile properties dialog |
| [Advanced](advanced.html) | Selection, Transform, Symmetry, Procedural Shader, Spawn Points, Custom Mirror Planes |
| [Reference](reference.html) | Complete keyboard shortcut table, menu reference, glossary |

---

## Application layout

When the editor opens you'll see six regions arranged around a central 3D viewport.

```
 ┌─────────────────────────────────────────────────────────────┐
 │  Menu bar  (File · Edit · Viewport · Selection · Remote)    │
 ├─────────────────────────────────────────────────────────────┤
 │  Context bar  (tool-specific spinners, toggles, snap mode)  │
 ├──────┬──────────────────────────────────────┬───────┬───────┤
 │      │                                      │       │       │
 │ Left │                                      │ Trans │ Right │
 │ side │           3D viewport                │ -form │ panel │
 │ bar  │                                      │ bar   │       │
 │      │                                      │       │       │
 ├──────┴──────────────────────────────────────┴───────┴───────┤
 │  Status bar  (status text · stats · C++ indicator · Y-slice)│
 └─────────────────────────────────────────────────────────────┘
```

| Region | Contains |
|---|---|
| **Menu bar** | File · Edit · Viewport · Selection · Remote drop-downs |
| **Context bar** | Spinners and toggles relevant to the current tool — brush size, hollow flag, polygon sides, snap mode, query filters |
| **Left sidebar** | Five primary mode buttons (Add / Subtract / Paint / Select / Spawns), a sub-tools area that changes with the active mode, and the symmetry controls |
| **3D viewport** | The voxel canvas — click to place, drag to orbit, scroll to zoom |
| **Transform bar** | Move / Rotate / Scale / Flip / Mirror / Hollow / Flood buttons (active when a selection exists) |
| **Right panel** | Palette editor, gradient panel, and the list of custom mirror planes |
| **Status bar** | Current action text · performance stats · `C++: Loaded` or `C++: GDScript fallback` · `Remote: Connected/Disconnected` · Y-slice slider |

{: .note }
> The "C++: Loaded" indicator on the right of the status bar tells you whether the native extension was loaded successfully. If it shows `GDScript fallback`, the editor still works but procedural shape preview, greedy meshing, and other hot-path operations run in pure GDScript instead of the native module.

---

## Your first edit

1. **Launch the editor.** A blank tile of the default size (128 × 112 × 128 voxels) is created automatically.
2. **Confirm Add mode is active.** The <img src="assets/icons/add_box.svg" class="tool-icon" alt="Add"> Add button on the left sidebar should be highlighted. If not, press <kbd>B</kbd>.
3. **Confirm Brush is the active shape.** The <img src="assets/icons/brush.svg" class="tool-icon" alt="Brush"> Brush button under it should be selected. If not, press <kbd>1</kbd>.
4. **Click anywhere in the viewport.** A single voxel appears at the cursor, coloured by the currently selected palette entry.
5. **Hold and drag.** Each voxel under the cursor is added — useful for sketching surfaces.
6. **Press <kbd>Ctrl</kbd>+<kbd>Z</kbd>** to undo the entire stroke as a single action.
7. **Save.** Press <kbd>Ctrl</kbd>+<kbd>S</kbd>, choose a path inside `res://`, and the tile is written as a `.tres` resource.

That's the whole loop. Everything else in this guide is a refinement of those steps.

---

## Camera controls

| Action | How |
|---|---|
| **Orbit** | Middle-mouse drag |
| **Pan** | <kbd>Shift</kbd> + middle-mouse drag |
| **Zoom** | Scroll wheel (clamped between 5 and 400 units of distance) |
| **Reset to default** | Viewport menu → Reset Camera |
| **Focus the tile centre** | Viewport menu → Focus Center |
| **Switch to Rift Delver isometric** | Viewport menu → Rift Delver View — orbits to a fixed isometric angle and switches to the lit shader, matching the in-game camera |

---

## Where files go

| Asset | Format | Default location |
|---|---|---|
| Tiles | `.tres` (Godot resource) | `res://resources/tiles/` |
| Palettes | `.tres` | `res://resources/palettes/` |
| Imported scenes | `.tscn` / `.scn` | anywhere under `res://` |

The file dialogs use Godot's resource browser, so all paths must live inside the project's `res://` tree.

---

## Next

Continue to [Editing Basics](editing-basics.html) for the five primary modes and the everyday actions you'll use to shape a tile.
