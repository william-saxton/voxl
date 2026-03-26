# VOXL Voxel Editor — Complete Tool & UI Reference

## Application Layout

The editor is a standalone Godot application with:
- **Top**: Menu bar (File, Edit, View) and Context-sensitive properties panel (bellow)
- **Left**: tool bar with main tools and dynamic sub tools sections.
- **Center**: 3D viewport (voxel editing canvas)
- **Right**: Palette editor (middle) + Tile properties (bottom)
- **Bottom**: Status bar (single-line text feedback)

---

## main tools (toolbar toggle group — only one active)

| Mode | Shortcut | Description |
|------|----------|-------------|
| **Add** | B | Place voxels using selected shape/tool |
| **Subtract** | E | Remove voxels using selected shape/tool |
| **Paint** | P | Repaint existing voxels with selected palette color |
| **Select** | S | Select existing voxels to be manipulated with sub tools |
| **spawns** | K | create spawn points for various game entities |

**Eyedropper**: Alt+Click in any mode picks the clicked voxel's color into the palette.

---

## Spawn tools (buttons) | sub tools

Only available in spawns tool

- **Enemy** 
- **Item** 
- **Weapon** 
- **Puzzle** 
- **secret** 

---

## Shape Tools (buttons + keyboard 1-5) | sub tools

All shapes work within any primary mode (Add/Subtract/Paint).

| Shape | Key | Click Pattern | Options | Tools |
|-------|-----|---------------|---------|-------|
| **Single** | 1 | One click | None | Add, Subtract, Paint |
| **Line** | 2 | Click start → click end | Shift = axis snap | Add, Subtract, Paint |
| **Box** | 3 | Click corner → click corner | Hollow (H), Shift = square | Add, Subtract, Paint |
| **Circle** | 4 | Click center → click radius | Hollow (H) | Add, Subtract, Paint |
| **Polygon** | 5 | Click center → click radius | Hollow (H), Sides: 3-32 (default 6) | Add, Subtract, Paint |

Line, Box, Circle, and Polygon support a **height phase** — after the second click, move mouse to extrude the shape along the face normal (third click confirms).

---

## Tool Types (toolbar toggle buttons) | sub tools

| Tool | Key | Description | Tools |
|------|-----|-------------|--------|
| **Fill** | F | Flood-fill connected voxels. ADD=pour fill (fills air like water), SUBTRACT=remove connected, PAINT=repaint connected | Add |
| **Extrude** | G | Click a face, drag to extend/remove/paint N layers along face normal | Add, Subtract |
| **Transform** | T | Move selected voxels. Arrow keys nudge, Shift+Up/Down nudges Y, Enter confirms, Escape cancels | Select |
| **Metadata** | N | Click a voxel to place/edit spawn points, triggers, loot chests, and other markers. Opens a dialog with type selector and key-value properties. | — |

---

## Query Options (shared by Fill, Extrude, Select) | sub tool options

| Option | Default | Description |
|--------|---------|-------------|
| **Connectivity** (Q) | Geometry | Geometry = any non-air 6-connected. Face = only voxels sharing an exposed face in clicked direction |
| **Match Color** | Off | Only match voxels with exact same visual ID |
| **Match Material** | Off | Only match voxels with same base material type |
| **Range** | 64 | Search distance from click (4-128, step 4) |

---

## Selection Operations (Edit menu)

| Operation | Shortcut | Description |
|-----------|----------|-------------|
| Copy | Ctrl+C | Copy selection to clipboard |
| Cut | Ctrl+X | Copy + delete |
| Paste | Ctrl+V | Enter paste mode — click to place |
| Delete | Delete | Remove selected voxels |
| Select All | Ctrl+A | Select all non-air voxels |
| Undo | Ctrl+Z | Undo last action (50 max) |
| Redo | Ctrl+Shift+Z | Redo undone action |

---

## Transform Options (right panel, shown in Transform mode) | sub tools

| Option | Default | Description |
|--------|---------|-------------|
| **Wrap at Tile Edges** | Off | Voxels wrap around tile boundaries using posmod |
| Rotate X/Y/Z | — | 90° rotation around selection center |
| Flip X/Y/Z | — | Mirror within selection bounds |
| Mirror X/Y/Z | — | Duplicate + flip (keeps original) |
| Hollow | — | Remove interior voxels (keep surface) |
| Flood Interior | — | Fill enclosed air inside selection |
| Dilate | — | Grow outward 1 voxel |
| Erode | — | Shrink inward 1 voxel |
Gizmo handles: axis arrows = lock to single axis, plane squares = lock to plane, center = free move.

---

## Menus

### File Menu
- New Tile (Ctrl+N)
- Open Tile... (Ctrl+O)
- Save Tile (Ctrl+S)
- Save Tile As... (Ctrl+Shift+S)
- Export Tile... (opens export dialog)
- Import Palette...
- Export Palette...

### View Menu
- Reset Camera — orbits to default view
- Focus Center — centers on tile midpoint
- Wireframe (W) — toggle voxel edge wireframe overlay
- UI Scale: 75%, 100%, 125%, 150%, 200%

---

## Top Panel: Context-Sensitive Properties

**Always visible:**
- Tool info text (describes current mode/tool)
- Selection count ("Selection: N voxels")
- Y-Slice slider (0=off, 1-max_Y hides voxels above that level)

**Shown per tool type:**
- **Shape mode**: Hollow checkbox, Polygon sides spinner (3-32)
- **Fill/Extrude/Select**: Connectivity checkbox, Color/Material filter checkboxes, Range slider (4-128)
- **Transform**: Wrap checkbox, keyboard hint text

---

## Right Panel: Palette Editor

- Palette selector dropdown (shown when >1 palette)
- Duplicate Palette / Delete Palette buttons
- Entry name text field
- Color picker button
- Material type dropdown (Stone, Bedrock, Water, Dirt, Mud, Lava, Acid, Gas, Steam)
- Add Entry / Delete Entry buttons

---

## Right Panel: Tile Properties

- **Name** text field
- **Tile Size** presets dropdown: Default (128x112x128), Small Prop (32x32x32), Medium Prop (64x64x64), Tall (128x224x128), Wide (256x112x256), Custom
- **Edge Types** (North/South/East/West dropdowns): Solid Wall, Open Ground, Corridor, Door, Bedrock Wall, Structure Internal
- **Biome** text field
- **Weight** slider (0.1-10.0, default 1.0)
- **Tags** comma-separated text field

---

## Export Dialog

Three export modes:

| Mode | Description |
|------|-------------|
| **Full Tile** | Exports entire tile at current dimensions |
| **Smallest Possible** | Auto-crops to bounding box of all non-air voxels |
| **Selected Only** | Exports only selected voxels, cropped to selection bounds |

File path input with browse button, saves as .tres.

---

## Metadata Dialog

For annotating voxel positions with gameplay data. Opened by clicking a voxel in Metadata mode (N).

- **Position** display (read-only)
- **Type** dropdown (grouped by category, extensible):
  - **Spawns**: spawn_point, enemy_spawn, item_spawn, weapon_spawn
  - **Events**: trigger
  - **Items**: loot_chest
  - **Navigation**: waypoint
  - **Other**: custom
- **Properties** key-value rows (add/remove dynamically, pre-populated from type defaults)
- **Delete Point** button (when editing existing)

Types are extensible — new spawn/marker types can be registered at runtime via `MetadataTool.register_type()`. Each type has a name, category, display color (for 3D markers), and default properties template.

---

## Camera Controls

| Action | Input |
|--------|-------|
| Orbit | Middle mouse drag |
| Pan | Shift + Middle mouse drag |
| Zoom | Scroll wheel (min 5, max 400 distance) |

---

## Symmetry (toolbar toggle buttons)

| Button | Description |
|--------|-------------|
| **X** | Mirror all operations across the YZ plane at tile center X |
| **Y** | Mirror all operations across the XZ plane at tile center Y |
| **Z** | Mirror all operations across the XY plane at tile center Z |

Multiple axes can be enabled simultaneously (e.g., X+Z for 4-way symmetry, X+Y+Z for 8-way).

Symmetry applies to: Add, Subtract, Paint, Fill, Extrude, Select, and Paste operations. Mirrored positions are previewed in the viewport during hover and shape drawing.

**Custom mirror planes**: Users can place additional mirror planes at arbitrary positions along any axis, independent of tile center symmetry.

---

## Visual Features

- **Floor grid**: Lines every 16 voxels at Y=0
- **Boundary wireframe**: Orange box showing tile edges
- **Hover highlight**: White wireframe cube following cursor
- **Shape preview**: Translucent wireframe during shape drag
- **Selection overlay**: Cyan wireframe on selected voxels
- **Transform gizmo**: RGB axis arrows + plane handles at selection center
- **Symmetry planes**: Translucent colored planes (red=X, green=Y, blue=Z, yellow=custom) showing active mirror axes
