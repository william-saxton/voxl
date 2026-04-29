---
title: Reference
layout: default
nav_order: 6
---

# Reference

Every keyboard shortcut, menu command, and term in one place. For workflow guidance, see the earlier chapters.

---

## Keyboard shortcuts

### Mode switching

| Key | Mode |
|---|---|
| <kbd>B</kbd> | Add |
| <kbd>E</kbd> | Subtract |
| <kbd>P</kbd> | Paint |
| <kbd>S</kbd> | Select |
| <kbd>K</kbd> | Spawns / Metadata |
| <kbd>T</kbd> | Transform (when selection exists) |

### Shape selection

Active when Add / Subtract / Paint is the current mode.

| Key | Shape |
|---|---|
| <kbd>1</kbd> | Brush |
| <kbd>2</kbd> | Line |
| <kbd>3</kbd> | Box |
| <kbd>4</kbd> | Circle |
| <kbd>5</kbd> | Polygon |
| <kbd>F</kbd> | Fill (toggle) |
| <kbd>G</kbd> | Extrude (toggle) |
| <kbd>P</kbd> | Procedural Shader (in Add mode; conflicts with Paint shortcut, context-dependent) |

### Shape modifiers

| Key | Effect |
|---|---|
| <kbd>H</kbd> | Toggle Hollow option for Box / Circle / Polygon |
| <kbd>Q</kbd> | Cycle connectivity: Geometry ↔ Face (for Fill / Extrude / Face-select) |
| <kbd>Shift</kbd> | (Held while drawing) Line: snap to axis · Box: square footprint |
| <kbd>Ctrl</kbd> | (Held while clicking) Apply current snap mode (Edge / Center) |
| <kbd>Alt</kbd> | (Held while clicking) Eyedropper — pick clicked voxel's colour. In Select mode: deselect |

### View

| Key | Effect |
|---|---|
| <kbd>V</kbd> | Cycle render mode (Unshaded → Lit → Normals → Material → Textured) |
| <kbd>W</kbd> | Toggle wireframe overlay |

### Editing

| Key | Effect |
|---|---|
| <kbd>Ctrl</kbd>+<kbd>Z</kbd> | Undo |
| <kbd>Ctrl</kbd>+<kbd>Y</kbd> or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> | Redo |
| <kbd>Ctrl</kbd>+<kbd>C</kbd> | Copy selection |
| <kbd>Ctrl</kbd>+<kbd>X</kbd> | Cut selection |
| <kbd>Ctrl</kbd>+<kbd>V</kbd> | Paste (enters paste mode) |
| <kbd>Del</kbd> | Delete selection |
| <kbd>Ctrl</kbd>+<kbd>A</kbd> | Select all non-air voxels |
| <kbd>Esc</kbd> | Cancel current operation (in-progress shape, paste, transform, selection) |
| <kbd>L</kbd> | Lock / unlock highlight points on current face |
| <kbd>Shift</kbd>+<kbd>L</kbd> | Clear all locked faces |

### File

| Key | Effect |
|---|---|
| <kbd>Ctrl</kbd>+<kbd>N</kbd> | New Tile |
| <kbd>Ctrl</kbd>+<kbd>O</kbd> | Open Tile… |
| <kbd>Ctrl</kbd>+<kbd>S</kbd> | Save Tile |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> | Save Tile As… |

### Transform (active during pending transform)

| Key | Effect |
|---|---|
| <kbd>←</kbd> / <kbd>→</kbd> | Nudge selection ±1 voxel on X |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Nudge selection ∓1 voxel on Z |
| <kbd>Shift</kbd>+<kbd>↑</kbd> / <kbd>Shift</kbd>+<kbd>↓</kbd> | Nudge selection ±1 voxel on Y |
| <kbd>Enter</kbd> | Commit transform |
| <kbd>Esc</kbd> | Cancel transform — voxels snap back |

### Camera (mouse only)

| Action | How |
|---|---|
| Orbit | Middle-mouse drag |
| Pan | <kbd>Shift</kbd> + middle-mouse drag |
| Zoom | Scroll wheel |

---

## Menu reference

### File menu

| Command | Shortcut | Effect |
|---|---|---|
| New Tile | <kbd>Ctrl</kbd>+<kbd>N</kbd> | Create a blank tile at the configured size |
| Open Tile… | <kbd>Ctrl</kbd>+<kbd>O</kbd> | Load a `.tres` / `.res` tile |
| Save Tile | <kbd>Ctrl</kbd>+<kbd>S</kbd> | Save to current path; falls through to Save As if no path |
| Save Tile As… | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd> | Save with a new name |
| Export Tile… | — | Open the export dialog (Full / Smallest / Selected) |
| Import Scene… | — | Voxelise a `.tscn` / `.scn` and pull it into the current tile |
| Import Palette… | — | Replace the current palette from a `.tres` file |
| Export Palette… | — | Save the current palette as a `.tres` file |

### Edit menu

| Command | Shortcut | Effect |
|---|---|---|
| Undo | <kbd>Ctrl</kbd>+<kbd>Z</kbd> | Roll back the last action |
| Redo | <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> or <kbd>Ctrl</kbd>+<kbd>Y</kbd> | Reapply an undone action |
| Procedural Shader… | — | Open the procedural shader dialog |

### Viewport menu

| Command | Shortcut | Effect |
|---|---|---|
| Reset Camera | — | Orbit to default angle |
| Focus Center | — | Centre camera on tile midpoint |
| Rift Delver View | — | Switch to fixed isometric + lit shading |
| Wireframe | <kbd>W</kbd> | Toggle wireframe overlay |
| Unshaded | — | Flat vertex colours |
| Lit | — | Per-pixel half-lambert shading (default) |
| Normals | — | Face normals as RGB debug |
| Material | — | Colour by base material type |
| Textured | — | Custom shader materials per palette entry |
| Player Reference | — | Toggle player capsule reference |
| Player Ref Size / Position… | — | Configure capsule height / radius / position |
| Rift Delver Floor | — | Toggle floor plane reference |
| Floor Depth… | — | Adjust floor Y position |
| UI Scale 75% / 100% / 125% / 150% / 200% | — | Scale all editor UI |

### Selection menu

| Command | Shortcut | Effect |
|---|---|---|
| Copy | <kbd>Ctrl</kbd>+<kbd>C</kbd> | Copy selection |
| Cut | <kbd>Ctrl</kbd>+<kbd>X</kbd> | Copy + delete |
| Paste | <kbd>Ctrl</kbd>+<kbd>V</kbd> | Enter paste mode |
| Delete | <kbd>Del</kbd> | Remove selected voxels |
| Select All | <kbd>Ctrl</kbd>+<kbd>A</kbd> | Select all non-air |
| Rotate X / Y / Z | — | 90° rotation around selection centre |
| Flip X / Y / Z | — | Mirror within selection bounds |
| Mirror X / Y / Z | — | Duplicate + flip; original kept |
| Scale 0.5× / 0.75× / 2× / 3× / 4× | — | Resample selection |
| Hollow | — | Strip interior voxels |
| Flood Interior | — | Fill enclosed air |
| Dilate | — | Grow selection +1 voxel |
| Erode | — | Shrink selection -1 voxel |

### Remote menu

| Command | Effect |
|---|---|
| Browse Remote Assets… | Open the remote browser dialog |
| Push Current Tile | Upload active tile |
| Push Current Palette | Upload active palette |
| Sync Settings… | Configure server connection |

---

## Glossary

**Air voxel** — A voxel with ID 0. Renders as transparent and counts as empty space for collisions and connectivity checks.

**Base material type** — A coarse classification of substance — Stone, Bedrock, Water, Dirt, Mud, Lava, Acid, Gas, or Steam — set on each palette entry. The host game uses this for footstep sounds, particle reactions, physics behaviour, and the **Material** view mode.

**Bedrock** — Indestructible voxel material. Used for tile boundaries that should never break under in-game destruction.

**Brush size** — The radius of the Brush shape and the Brush selection sub-tool. Range 1–16. Larger brushes are spheres in 3D unless **Flat** is on, in which case they're discs aligned to the working plane.

**Chunk** — Internal rendering unit. The editor groups voxels into 16-voxel chunks for performance — only chunks that change get re-meshed each frame, capped at 32 chunks per frame.

**Connectivity (Geometry vs Face)** — How Fill, Extrude, and Face-Select decide which voxels are "connected" to a starting point. **Geometry** treats any 6-connected non-air voxel as a neighbour (3D flood). **Face** only follows voxels along the *exposed* face you clicked, stopping at hidden faces.

**Custom mirror plane** — A user-placed mirror plane independent of the three axis-aligned planes. Drawn yellow in the viewport. Place via the Place button and click a face.

**Edge type** — Per-tile metadata describing what kind of connection each cardinal edge offers — Solid Wall, Open Ground, Corridor, Door, Bedrock Wall, Structure Internal. Used by the host game to decide which tiles can sit adjacent.

**Eyedropper** — <kbd>Alt</kbd>+click on an existing voxel to copy its palette index into the active palette slot. Available in Add / Subtract / Paint, but not Select.

**Fall back to GDScript** — If the native C++ extension fails to load, the editor still runs but uses pure-GDScript implementations for hot paths (procedural shape preview, greedy meshing, chunk generation). Slower but functionally identical. The status bar shows **C++: GDScript fallback** in orange when this happens.

**Gradient selection** — Multi-selecting palette entries with weights so Add and Paint pick from the set randomly. Useful for natural variation across surfaces.

**Greedy meshing** — Mesh-generation algorithm that merges adjacent voxel faces of the same colour into single quads. Reduces vertex count by ~10× for typical voxel scenes.

**Height phase** — The third click of a Box / Circle / Polygon shape, where you sweep the 2D footprint along the face normal to make it 3D.

**Hollow** — Modifier (<kbd>H</kbd>) for Box / Circle / Polygon that builds only the shell, omitting the interior.

**Locked face / locked highlight** — A face that stays visually marked across mode and tool changes, used as a placement reference. Toggle with <kbd>L</kbd>; clear all with <kbd>Shift</kbd>+<kbd>L</kbd>.

**Magic select** — The Face selection sub-tool (the <img src="assets/icons/voxel.svg" class="tool-icon"> icon). Flood-selects voxels along an exposed face from a clicked seed, stopping at hidden faces.

**Material view mode** — A debug render mode that colours every voxel by its base material type instead of its palette colour. Useful for verifying that "this looks like stone" voxels are actually classified as Stone.

**Metadata point** — A non-geometric marker placed at a voxel position. Spawn points, particle emitters, shader planes, and waypoints are all metadata points. Authored in Spawns mode.

**Mode** vs **Tool type** — The editor distinguishes between **primary mode** (Add / Subtract / Paint / Select / Spawns / Transform) and **tool type** (Shape / Fill / Extrude / Procedural / Select / Metadata). The mode decides *what* clicking does, the tool type decides *how*.

**Palette** — The set of available colours and material types. A `.tres` resource shared across multiple tiles. Editing a palette updates every tile that uses it.

**Palette entry** — One row in a palette: name + colour + material type. Voxels reference palette entries by index — entry 1 is the first non-air entry.

**Palette index** / **Voxel ID** — Same thing. The integer 0..N stored in each voxel cell, mapping to a palette entry. 0 is always air.

**Paste mode** — A floating preview of the clipboard following the cursor. Click to commit, <kbd>Esc</kbd> to cancel.

**Procedural shader** — The expression-based voxel generator. A region is defined by two clicks; an expression is evaluated at every voxel position to decide what to place. See the [Advanced page](advanced.html#procedural-shader).

**Remote sync** — Optional asset-server connection for sharing tiles and palettes across machines. Status is shown in the bottom right of the status bar.

**Selection** — A set of voxel positions. Drawn with a cyan wireframe overlay. Built via the Select sub-tools. Operated on by Edit menu commands and the Transform bar.

**Snap mode** (Off / Edge / Center) — Held-Ctrl behaviour during shape clicks: snap to grid-line midpoints (Edge) or grid-cell centres (Center). Set in the context bar.

**Spawn type** — A registered metadata category (Enemy Spawn, Loot Chest, Particle Effect, etc.) that defines what fields a metadata point exposes in the editor.

**Sub-tool** — The second-level button in the left sidebar that decides which specific shape, selection method, or spawn type is active under the current primary mode.

**Symmetry plane** — A mirror plane that automatically replicates each edit. Three axis-aligned planes (X / Y / Z) plus any number of custom planes.

**Tile** — A discrete voxel grid with a configurable size, edge metadata, biome, weight, and tags. The unit of work in the editor. Stored as a `.tres` file.

**Tile size** — The bounding dimensions of a tile in voxels. Set in the tile properties dialog. Six presets plus custom (1–512 per axis).

**Transform bar** — The vertical button strip on the right of the viewport. Active when a selection exists. Hosts Move / Rotate / Scale / Flip / Mirror / Hollow / Flood buttons.

**View mode** — A render style for the viewport: Unshaded / Lit / Normals / Material / Textured. Cycle with <kbd>V</kbd>. Has no effect on tile data.

**Working plane** — The Y level where new voxels are placed. Decided per-shape based on what was clicked: a voxel face → that face; the floor grid → Y = 0; empty space → closest grid plane perpendicular to the camera.

**Wrap at Tile Edges** — Box-shape option that uses `posmod` to wrap voxels off one side of the tile to the opposite side rather than clipping them.

**Y-slice slider** — The slider at the right of the status bar. Hides voxels above a chosen Y level for editing inside tall structures. View-only — does not delete.

---

## Useful URL fragments

Direct links into specific sections — handy for cross-referencing in commit messages or issue threads:

- [Application layout](./#application-layout)
- [Eyedropper](editing-basics.html#the-eyedropper)
- [Y-slice slider](editing-basics.html#the-y-slice-slider)
- [Height phase](shapes-and-tools.html#the-height-phase)
- [Fill connectivity](shapes-and-tools.html#fill)
- [Edge types](palette-and-tiles.html#edge-types)
- [Selection](advanced.html#selection)
- [Transform](advanced.html#transform)
- [Symmetry](advanced.html#symmetry)
- [Procedural shader](advanced.html#procedural-shader)
- [Spawn points](advanced.html#spawn-points)
