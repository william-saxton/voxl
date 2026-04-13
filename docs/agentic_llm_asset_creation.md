# Agentic LLM Asset Creation — Design & Implementation Guide

## Overview

This document describes a planned feature to add an agentic LLM interface to the VOXL editor, allowing language models (e.g. Claude) to create and refine voxel assets through tool-use and visual feedback. The goal is to let users describe assets in natural language ("a twisted tree with thick roots", "a dungeon room with pillars and a loot chest") and have an LLM iteratively build them using the editor's existing tool infrastructure.

No custom model training is required. Modern foundation models with tool-use and multimodal (vision) capabilities are sufficient.

---

## Why This Is Feasible Without Training

VOXL's assets are structured, discrete data (uint16 voxel grids) edited through composable operations (box, fill, extrude, SDF expressions). This maps cleanly to LLM tool-use:

- **Voxel tiles** are 128x112x128 grids — large but highly structured
- **The editor already has a procedural tool** that accepts math expressions (SDFs, noise) and fills voxels programmatically
- **All editor operations** (shape placement, fill, extrude, select, transform, metadata) are callable from GDScript
- **The palette/material system** is a finite, enumerable set (~100 materials) that fits easily in a system prompt
- **Tile metadata** (spawns, triggers, edge types) is structured key-value data

The LLM doesn't output raw voxel arrays. It orchestrates existing tools — the same way a human uses the editor, but via function calls instead of mouse clicks.

---

## Architecture

```
User prompt (natural language)
    |
    v
LLM (Claude API with tool-use + vision)
    |
    v
Tool calls (place_box, run_sdf, fill, add_spawn, etc.)
    |
    v
Editor operations (GDScript adapter layer)
    |
    v
TileRenderer renders updated tile
    |
    v
Visual feedback (screenshots, slices) sent back to LLM
    |
    v
LLM refines or confirms
```

### Components to Build

1. **Tool adapter layer** — GDScript functions bridging LLM tool-call JSON to editor operations
2. **API integration** — HTTP client (Godot `HTTPRequest` or sidecar process) calling Claude API
3. **Visual feedback pipeline** — capture rendered views and send back to LLM as images
4. **Session manager** — manages the conversation loop, undo checkpoints, and user approval

---

## Tool Definitions for the LLM

These map directly to existing editor capabilities:

| LLM Tool | Editor Component | Purpose |
|---|---|---|
| `place_box(pos, size, material, hollow)` | BoxShape + Add/Subtract | Place or carve rectangular regions |
| `place_sphere(center, radius, material)` | ProceduralTool sphere | Place spherical shapes |
| `run_sdf(expression, origin, region_size, material)` | ProceduralTool.execute() | Run arbitrary SDF/math for organic shapes |
| `fill(start_pos, material, connectivity)` | FillTool | Flood-fill connected regions |
| `extrude(pos, normal, depth)` | ExtrudeTool | Extend or carve faces |
| `select_region(min, max)` | SelectTool | Select a box region |
| `transform(operation, axis)` | TransformTool | Rotate, flip, mirror selection |
| `paint(positions, material)` | Paint mode | Repaint existing voxels |
| `add_spawn(pos, type, properties)` | MetadataTool | Place spawn points, triggers |
| `set_edge_type(face, type)` | WFCTileDef | Configure WFC edge constraints |
| `read_voxel(pos)` | WFCTileDef.get_voxel() | Inspect what's at a position |
| `get_tile_info()` | WFCTileDef properties | Read tile dimensions, palette, stats |
| `capture_views(angles, y_slices)` | Feedback pipeline | Request visual feedback |
| `undo(steps)` | VoxelUndoManager | Roll back recent operations |

### Tool Adapter Implementation

Each tool function lives in a new script (e.g. `scripts/voxel_editor/llm/llm_tool_adapter.gd`) and translates structured arguments into editor calls. Example:

```gdscript
func place_box(args: Dictionary) -> Dictionary:
    var pos := Vector3i(args.x, args.y, args.z)
    var size := Vector3i(args.sx, args.sy, args.sz)
    var vid: int = _palette.find_material(args.material)
    var voxels_changed := 0
    for x in range(pos.x, pos.x + size.x):
        for y in range(pos.y, pos.y + size.y):
            for z in range(pos.z, pos.z + size.z):
                if args.get("hollow", false):
                    var on_edge = (x == pos.x or x == pos.x + size.x - 1
                        or y == pos.y or y == pos.y + size.y - 1
                        or z == pos.z or z == pos.z + size.z - 1)
                    if not on_edge:
                        continue
                _tile.set_voxel(x, y, z, vid)
                voxels_changed += 1
    _tile_renderer.mark_all_dirty()
    return {"voxels_changed": voxels_changed}
```

---

## Visual Feedback Strategies

The LLM needs to "see" what it has built in order to refine it. Four complementary approaches, ordered by priority:

### 1. SDF Expressions via ProceduralTool (highest priority)

For organic shapes, the LLM writes math expressions rather than placing individual voxels. This sidesteps spatial precision issues entirely.

`ProceduralTool.execute()` already supports this — it evaluates a GDScript expression for every voxel in a region with built-in variables (`x, y, z, cx, cy, cz, nx, ny, nz, sx, sy, sz`).

LLMs are good at SDF math: unions, intersections, smooth blends, noise perturbation. Example mushroom:

```gdscript
var stem_d = sqrt((x-cx)*(x-cx) + (z-cz)*(z-cz)) - 6.0
var cap_d = sqrt((x-cx)*(x-cx) + (y-70)*(y-70) + (z-cz)*(z-cz)) - 20.0
var shape = stem_d if y < 60 else cap_d
return vid if shape <= 0.0 else -1
```

**Key advantage:** continuous math produces smooth organic forms. The voxel grid discretizes it automatically.

### 2. Multi-Angle Rendered Screenshots (high priority)

Capture the SubViewport from 4-6 camera angles and send as images in the LLM request:

```gdscript
func capture_views(angles: Array[float] = [0, 90, 180, 270]) -> Array[PackedByteArray]:
    var images: Array[PackedByteArray] = []
    for angle in angles:
        _camera_pivot.set_orbit_angle(angle)
        await RenderingServer.frame_post_draw
        var img := _viewport.get_texture().get_image()
        images.append(img.save_png_to_buffer())
    return images
```

Use different view modes for different information:
- `LIT` — general appearance
- `MATERIAL` — material type distribution (color-coded by base material)
- `NORMALS` — surface geometry detail

### 3. Y-Slice Cross-Section Sprite Sheet (medium priority)

Render top-down views at regular Y intervals, composited into a single image grid. This gives the LLM a precise "CT scan" of the voxel volume.

For a 128x112x128 tile, capture every 8th layer (14 slices) as small colored 2D grids and tile them into one image. Each pixel = one voxel column at that Y level, colored by palette.

```gdscript
func capture_y_slices(interval: int = 8) -> Image:
    var slices: Array[Image] = []
    for y in range(0, _tile.tile_size_y, interval):
        var slice := Image.create(_tile.tile_size_x, _tile.tile_size_z, false, Image.FORMAT_RGB8)
        for x in _tile.tile_size_x:
            for z in _tile.tile_size_z:
                var vid := _tile.get_voxel(x, y, z)
                var color := _palette.get_color(vid) if vid > 0 else Color.BLACK
                slice.set_pixel(x, z, color)
        slices.append(slice)
    return _composite_grid(slices)  # arrange into rows/columns
```

### 4. Sparse Text Dump (low priority, small regions only)

For targeted edits in small areas (up to ~32x32x32), a compact text grid per Y-layer:

```
Y=10: ....####....
      ...######...
      ..########..
```

Token-efficient for debugging specific areas, but doesn't scale to full tiles.

---

## Conversation Flow

### Initial System Prompt

Provide the LLM with:
- Tile dimensions and coordinate system (X-right, Y-up, Z-forward)
- Full material registry (name -> ID mapping, ~100 entries)
- Current palette (variant ID -> color + base material)
- Available tools with schemas
- Spatial reference: character height ~32 voxels, tile is 128x112x128

### Iterative Refinement Loop

```
1. User describes desired asset
2. LLM plans approach, makes tool calls (SDF + structural)
3. Editor executes, captures views
4. Images sent back to LLM
5. LLM evaluates result, refines or asks user for guidance
6. Repeat until user approves
```

### Undo Checkpoints

Before each LLM operation batch, save an undo checkpoint. If the user or LLM rejects a result, roll back cleanly. The existing `VoxelUndoManager` supports this (50-item history).

---

## Implementation Plan

### Phase 1: Tool Adapter Layer
- New directory: `scripts/voxel_editor/llm/`
- `llm_tool_adapter.gd` — maps tool-call JSON to editor operations
- `llm_tool_defs.gd` — tool schemas (name, parameters, descriptions) for the API
- Wire up to existing editor components via signals/references
- Estimated scope: ~500-800 lines GDScript

### Phase 2: Visual Feedback Pipeline
- `llm_feedback.gd` — captures multi-angle screenshots and Y-slice composites
- Camera orbit automation (rotate to preset angles, capture, restore)
- Image encoding (PNG -> base64) for API payloads
- Estimated scope: ~300-500 lines GDScript

### Phase 3: API Integration
- `llm_session.gd` — manages conversation state, sends requests, parses responses
- HTTP client using Godot `HTTPRequest` node or external sidecar
- Tool-call response parsing and dispatch to adapter layer
- API key management (project settings or environment variable)
- Estimated scope: ~400-600 lines GDScript

### Phase 4: Editor UI Integration
- Chat panel in editor sidebar (text input + conversation history)
- "Generate" button that kicks off a session
- Progress indicators during LLM calls
- Approve/reject/refine controls
- Thumbnail previews in chat history
- Estimated scope: ~500-800 lines GDScript + scene

### Phase 5: Refinement & Presets
- Prompt templates for common asset types (rooms, terrain features, props, structures)
- WFC-aware generation (respect edge constraints, biome materials)
- Batch generation (create multiple tile variants from one description)
- Save/load prompt history for reproducibility

---

## Key Source Files Reference

| File | Relevance |
|---|---|
| `scripts/voxel_editor/voxel_editor_main.gd` | Top-level editor controller, viewport, camera |
| `scripts/voxel_editor/tile_renderer.gd` | Chunk-based rendering, view modes, Y-slice clip |
| `scripts/voxel_editor/tools/procedural_tool.gd` | SDF expression execution (GDScript eval) |
| `scripts/voxel_editor/tools/editor_tool_manager.gd` | Tool registry and mode switching |
| `scripts/voxel_editor/tools/fill_tool.gd` | Flood-fill with connectivity options |
| `scripts/voxel_editor/tools/extrude_tool.gd` | Face extrusion |
| `scripts/voxel_editor/tools/select_tool.gd` | Voxel selection |
| `scripts/voxel_editor/tools/transform_tool.gd` | Move/rotate/flip selected voxels |
| `scripts/voxel_editor/tools/voxel_undo_manager.gd` | Undo/redo (50-item history) |
| `scripts/voxel_editor/tools/voxel_query.gd` | Raycast, flood fill queries |
| `scripts/voxel_editor/ui/metadata_tool.gd` | Spawn point / trigger placement |
| `scripts/voxel_editor/voxel_palette.gd` | Palette colors and material mapping |
| `scripts/wfc/wfc_tile_def.gd` | Tile data structure (get/set voxel, metadata) |
| `scripts/material_registry.gd` | Material type enum (~100 types) |
| `native/src/voxel_editor_native.cpp` | C++ fast meshing, raycast, flood-fill |

---

## Constraints & Considerations

- **Token budget**: A full 128x112x128 tile has ~1.8M voxels. Never dump raw data. Use visual feedback (images) and targeted reads.
- **Latency**: Each LLM round-trip takes seconds. Batch operations where possible. Use SDF expressions to set large regions in one call rather than thousands of individual voxel placements.
- **API costs**: Multi-angle screenshots with vision are more expensive per request. Offer quality tiers (quick: 2 views, standard: 4 views, detailed: 6 views + slices).
- **Determinism**: SDF expressions are deterministic. Save the expression alongside the tile for reproducibility and parameterized variants.
- **Edge constraints**: When generating WFC tiles, the LLM must respect edge type rules (walls match walls, corridors match corridors). Include current edge configuration in context.
- **Coordinate system**: Document clearly in the system prompt. VOXL uses X-right, Y-up, Z-forward with integer coordinates. Origin is (0,0,0) at the bottom-left-front corner.
