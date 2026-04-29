---
title: Editing Basics
layout: default
nav_order: 2
---

# Editing Basics

Five primary modes drive everything you do in the editor. They live on the left sidebar and are mutually exclusive — exactly one is active at a time. The mode you pick decides what clicking in the viewport will do; the **shape** or **sub-tool** under it decides *how*.

| | Mode | Shortcut | What clicking does |
|---|---|---|---|
| <img src="assets/icons/add_box.svg" class="tool-icon" alt="Add"> | **Add** | <kbd>B</kbd> | Place voxels using the current shape, painted with the current palette colour |
| <img src="assets/icons/indeterminate_check_box.svg" class="tool-icon" alt="Subtract"> | **Subtract** | <kbd>E</kbd> | Remove voxels using the current shape |
| <img src="assets/icons/brush.svg" class="tool-icon" alt="Paint"> | **Paint** | <kbd>P</kbd> | Repaint existing voxels with the current palette colour — geometry is unchanged |
| <img src="assets/icons/select_all.svg" class="tool-icon" alt="Select"> | **Select** | <kbd>S</kbd> | Build a selection that you can copy, transform, or delete |
| <img src="assets/icons/category.svg" class="tool-icon" alt="Spawns"> | **Spawns** | <kbd>K</kbd> | Place metadata points (enemy, item, particle, etc.) at the clicked voxel |

Switching modes is non-destructive — your selection, your palette choice, and the camera position all carry across.

---

## Add — placing voxels

Add is the default mode and the one you'll spend the most time in. Every shape in the [Shapes & Tools](shapes-and-tools.html) chapter is available in Add — pick the shape, click in the viewport, and voxels appear coloured by the active palette entry.

**Working plane** — when you click on existing geometry, the new voxels sit on the face you clicked. When you click on empty space, the editor projects to the closest grid plane based on camera angle. If you've never placed a voxel yet, clicks fall on Y = 0 (the floor).

**Stroke = one undo step.** Holding the mouse button and dragging is treated as a single action: <kbd>Ctrl</kbd>+<kbd>Z</kbd> rolls the whole stroke back, not one voxel at a time.

---

## Subtract — removing voxels

Subtract uses the same shape tools as Add, but inverts the operation. Hold and drag to carve a tunnel; click once with the Box shape to delete a cuboid region.

{: .tip }
> Subtract respects the **hollow** modifier. With <kbd>H</kbd> active and the Box shape selected, Subtract carves only the *shell* of a cuboid — leaving the interior intact. Useful for cutting windows.

---

## Paint — recolouring without changing geometry

Paint takes whatever shape you have active and applies the current palette colour to every voxel inside the shape's volume. Air voxels are skipped — you can't paint into nothing.

Paint is the one mode where the **Fill** sub-tool changes character: instead of pouring paint like water, it recolours all voxels connected to the clicked one (see Fill, below).

---

## Select — building a selection

Select replaces the shape sub-tools with four selection methods. See the [Advanced page](advanced.html#selection) for the full breakdown — the short version is:

- **Face** — click a voxel to flood-select all connected voxels along that exposed face
- **Rect** — click two corners of a 3D box; everything inside is selected
- **Brush** — click-drag to paint the selection voxel by voxel
- **Object** — click any voxel to grab the entire 6-connected blob it belongs to

Selected voxels are drawn with a cyan wireframe overlay. Once you have a selection, the **Transform bar** (right of the viewport) lights up with Move / Rotate / Scale / Flip / Mirror / Hollow / Flood / Dilate / Erode buttons.

---

## Spawns — placing metadata

Spawns mode lets you mark voxels with non-geometric data — enemy spawn points, loot chest locations, particle emitters, shader planes, navigation waypoints. The sub-tools list is dynamic and pulled from the editor's metadata-type registry, grouped by category. Selecting a type and clicking a voxel opens a property dialog where you set position, custom key-value pairs, and type-specific fields.

See the [Spawn Points section](advanced.html#spawn-points) for the complete list of types and their properties.

---

## The eyedropper

In any mode **except Select**, hold <kbd>Alt</kbd> and click an existing voxel to copy its colour into the active palette slot. This is the fastest way to match an existing colour without hunting through the palette.

In Select mode, <kbd>Alt</kbd>+click instead **deselects** the clicked voxel — useful for pruning a selection.

---

## Undo and redo

| Action | Shortcut |
|---|---|
| Undo | <kbd>Ctrl</kbd>+<kbd>Z</kbd> |
| Redo | <kbd>Ctrl</kbd>+<kbd>Y</kbd> or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> |

The undo stack holds up to **50 actions** per session. Each shape stroke, each fill, each transform commit is one entry. Switching tools clears any in-progress action but leaves the stack alone.

{: .warning }
> Undo history does not survive **closing the editor**. Save before quitting if you might want to roll back later.

---

## The Y-slice slider

The Y-slice slider lives at the right end of the status bar. It clips the rendered tile above a chosen Y coordinate, letting you see (and edit) the interior of tall structures without obstruction.

| Slider value | Effect |
|---|---|
| `0` | No clipping — the full tile is visible |
| `1` to tile height | Hide everything above that Y level |

Voxels above the slice are hidden but **not deleted** — sliding back up reveals them again. The slice is a view setting, not an edit.

---

## View modes

The Viewport menu contains five rendering modes that change how the tile is shaded. They have no effect on the tile data itself.

| Mode | What you see | When to use |
|---|---|---|
| **Unshaded** | Flat vertex colours, no lighting | Reading exact palette colours |
| **Lit** (default) | Per-pixel shaded with half-lambert wrapping | Everyday editing |
| **Normals** | Face normals visualised as RGB | Debugging mesh orientation |
| **Material** | Voxels coloured by base material type (stone / water / lava / …) | Verifying material assignments |
| **Textured** | Custom shader materials per palette entry | Previewing in-game appearance |

Press <kbd>V</kbd> to cycle through these. Press <kbd>W</kbd> to toggle a wireframe overlay on top of any mode.

The Viewport menu also offers two quick toggles useful for scale-checking your tile:

- **Player Reference** — shows a 1.8 m capsule at the tile centre. Configurable height, radius, and position via *Player Ref Size / Position…*
- **Rift Delver Floor** — drops a flat floor plane at a chosen Y depth, useful when authoring tiles that sit below the play surface

---

## Saving and loading

| Action | Shortcut | What happens |
|---|---|---|
| New Tile | <kbd>Ctrl</kbd>+<kbd>N</kbd> | Creates a blank tile at the configured size; prompts for a name |
| Open Tile… | <kbd>Ctrl</kbd>+<kbd>O</kbd> | File dialog filtered to `.tres` / `.res` |
| Save Tile | <kbd>Ctrl</kbd>+<kbd>S</kbd> | Writes to the current path. If the tile has no path yet, falls through to Save As |
| Save Tile As… | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> | File picker, choose a new path |
| Export Tile… | — | Opens the export dialog (Full / Smallest / Selected — see below) |

### Export modes

The **File → Export Tile…** dialog gives you three flavours:

- **Full Tile** — the entire tile at its declared dimensions, padding included
- **Smallest Possible** — auto-cropped to the tight bounding box of all non-air voxels
- **Selected Only** — exports just the active selection, cropped tight; useful for chopping pieces out of a larger tile

Palettes can also be imported and exported separately (`File → Import Palette… / Export Palette…`) — handy when you want to share a colour scheme across multiple tiles.

---

## Snap and numeric input

Two refinements help with precision:

**Snap modes** (context bar, when a shape is active):

| Mode | Behaviour |
|---|---|
| **Off** | No snapping — clicks land on the voxel under the cursor |
| **Edge** | Hold <kbd>Ctrl</kbd> while clicking to snap to grid-line midpoints |
| **Center** | Hold <kbd>Ctrl</kbd> while clicking to snap to grid-cell centres (odd positions) |

**Numeric input** (during multi-click shape drawing):

While dragging a Line, Box, Circle, or Polygon, type digits to lock the dimension to a specific value instead of relying on cursor position. <kbd>Tab</kbd> cycles between axes when more than one is being adjusted. The current numeric value is shown next to the cursor.

---

## Status bar at a glance

The bottom strip carries six pieces of information:

1. **Status text** — what just happened (e.g. *Saved tile to res://resources/tiles/cave_a.tres*)
2. **Stats label** — voxel count, chunk count, last meshing time
3. **C++ indicator** — `C++: Loaded` (green) or `C++: GDScript fallback` (orange)
4. **Remote indicator** — connection state to the asset sync server
5. **Y-slice label and slider** — current Y clip threshold

The C++ indicator is the most useful one to glance at — if it's orange you'll see slower response on procedural tools and large fills, and you should check the native build.

---

## Next

Move on to [Shapes & Tools](shapes-and-tools.html) for the precise click patterns and modifier keys for every drawing tool.
