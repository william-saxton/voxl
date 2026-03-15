# Voxel World & Material Simulation — Implementation Plan

## Context

This plan is for adding a godot_voxel-based destructible terrain layer and Noita-inspired
material simulation to Rift Delver. Work is split into two stages:

1. A **standalone prototype project** to validate the technology in isolation.
2. **Integration into Rift Delver** once the prototype is proven.

---

## Rift Delver — Relevant Existing Systems

| System | Location | Notes |
|---|---|---|
| WorldChunkManager | `scripts/systems/world_chunk_manager.gd` | GridMap-based, emits `chunk_loaded` / `chunk_unloaded` signals |
| WorldChunkInstance | `scripts/systems/world_chunk_instance.gd` | Per-chunk entity spawning |
| AmmoType resource | `scripts/resources/ammo_type/ammo_type.gd` | Will need a `material_interaction` field added |
| combat_system | `scripts/systems/combat_system.gd` | Projectile impact hook goes here |
| status component | `scenes/components/gameplay/status/status.gd` | Receives entity staining effects |
| sprite_effects | `scenes/components/visual/sprite_effects/sprite_effects.gd` | Visual tint for stained entities |
| LimboAI GDExtension | `addons/limboai/` | Reference for how GDExtensions are installed |

---

## Core Decisions

- **Voxel size:** 0.0625m (1/16 of the 1m player character)
- **Max dig depth:** 16 voxels = 1.0m below surface, enforced by indestructible BEDROCK voxel type
- **Camera:** Static isometric — no change to camera type
- **Occlusion:** Shader-based fade for voxels above the player's Y position
- **Structural geometry:** Existing GridMap stays for walls/room structure; voxel layer is the floor surface only
- **godot_voxel install:** GDExtension, same pattern as LimboAI — drop into `addons/`, enable in Project Settings
- **Material simulation:** Runs entirely on the GPU via a compute shader. GDScript only manages setup, dispatching, and reading back geometry changes. This avoids any CPU threading bottleneck and means simulation scales to the full voxel density for free.

---

## Architecture Overview

```
GPU                                          CPU
─────────────────────────────────────────    ─────────────────────────────────────────
Material state textures (ping-pong 3D)       godot_voxel voxel geometry (CPU RAM)
  tex_current → compute shader → tex_next    VoxelWorldManager
                                               reads geometry_change_buffer every N frames
Geometry change buffer (GPU storage)    →      calls VoxelTool to carve/place voxels
  compute shader writes destroy/create
  events here when geometry must change   →  MaterialSimulator (thin GDScript autoload)
                                               dispatches compute shader each tick
Voxel terrain shader                           writes wake_mask_texture on impact
  reads tex_current for staining/colour        reads geometry_change_buffer
  reads fade_above_y uniform for occlusion
```

### Why This Split

- Simulation state (what material is where) lives entirely on the GPU in a 3D texture.
  No CPU readback needed for visuals — the voxel shader reads the texture directly.
- Geometry (which voxels exist as solid collision+mesh) lives in godot_voxel on the CPU.
  This only needs to change when a material physically destroys or creates a voxel —
  a sparse event compared to simulation ticks. The compute shader flags these changes
  in a small GPU buffer; the CPU reads it every few frames and applies them via VoxelTool.

---

## Phase 0 — Create Prototype Project

1. Create a new minimal Godot 4 project (suggested name: `rift-voxel-prototype`).
2. Check your Godot version: **Help > About**. Download the matching godot_voxel
   GDExtension from https://github.com/Zylann/godot_voxel/releases.
   The latest release (v1.6) targets Godot 4.6. Match your minor version exactly.
3. Install: drop the extension folder into `addons/`, enable in Project Settings > Plugins.
4. Create a test scene with:
   - Static isometric `Camera3D` (match Rift Delver's angle)
   - `CharacterBody3D` player capsule (1m tall)
   - `VoxelTerrain` node

---

## Phase 1 — Voxel World Foundation (Prototype)

**Goal:** Flat voxel terrain at 1/16 scale the player can walk on.

### RiftVoxelGenerator

```gdscript
# voxel_generator.gd
class_name RiftVoxelGenerator
extends VoxelGeneratorScript

const VOXEL_AIR := 0
const VOXEL_STONE := 1
const VOXEL_BEDROCK := 2

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, _lod: int) -> void:
    for z in out_buffer.get_size().z:
        for x in out_buffer.get_size().x:
            for y in out_buffer.get_size().y:
                var world_y := origin_in_voxels.y + y
                if world_y <= -16:
                    out_buffer.set_voxel(VOXEL_BEDROCK, x, y, z, VoxelBuffer.CHANNEL_TYPE)
                elif world_y <= 0:
                    out_buffer.set_voxel(VOXEL_STONE, x, y, z, VoxelBuffer.CHANNEL_TYPE)
                else:
                    out_buffer.set_voxel(VOXEL_AIR, x, y, z, VoxelBuffer.CHANNEL_TYPE)
```

### VoxelLibrary Setup

Create a `VoxelBlockyLibrary` resource with entries:
- Index 0: AIR (transparent, no collision)
- Index 1: STONE (opaque, full collision)
- Index 2: BEDROCK (opaque, full collision, treated as indestructible in the compute shader)

---

## Phase 2 — Camera and Occlusion (Prototype)

**Goal:** Static isometric camera that cuts away geometry above the player.

Pass player Y to the voxel terrain shader each frame:

```gdscript
# In your world manager script
func _process(_delta: float) -> void:
    voxel_terrain.material_override.set_shader_parameter(
        "fade_above_y", player.global_position.y + 0.5
    )
```

In the voxel terrain's shader override, discard or alpha-fade any fragment whose
world Y exceeds `fade_above_y`. godot_voxel's `VoxelMesherBlocky` accepts a custom
material — add a `shader_parameter` uniform for this threshold.

---

## Phase 3 — GPU Material Simulation (Prototype)

**Goal:** Cellular automaton running entirely on the GPU via a compute shader.
No per-cell GDScript; no CPU threading concerns. Scales to full voxel density.

### Data Layout

| Resource | Type | Purpose |
|---|---|---|
| `tex_current` | `RDTextureFormat` 3D, R8_UINT | Current material state per voxel |
| `tex_next` | `RDTextureFormat` 3D, R8_UINT | Next material state (written by compute) |
| `geometry_change_buffer` | `RDStorageBuffer` | Compact list of voxel positions where geometry must be added/removed; written by compute, read by CPU |
| `wake_mask_texture` | `RDTextureFormat` 3D, R8_UINT | CPU writes here to wake regions on impact; compute reads to activate cells |

Material types are stored as uint8 values matching the enum below.

### MaterialType Enum (shared between GDScript and GLSL via constants)

```gdscript
# material_types.gd — shared constants, included by MaterialSimulator
const MAT_NONE     := 0
const MAT_STONE    := 1
const MAT_DIRT     := 2
const MAT_WOOD     := 3
const MAT_WATER    := 4
const MAT_FIRE     := 5
const MAT_ACID     := 6
const MAT_SCORCHED := 7
const MAT_SAND     := 8
const MAT_BEDROCK  := 9
```

### Checkerboard Update Pattern

All GPU cells update in parallel, which causes race conditions if two adjacent cells
both try to write to the same neighbour in the same pass. The fix is a checkerboard
dispatch — on even ticks update cells where `(x + y + z) % 2 == 0`, on odd ticks
update the rest. The compute shader receives a `tick_parity` uniform (0 or 1).

```glsl
// material_sim.glsl (compute shader)
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r8ui) uniform uimage3D tex_current;
layout(set = 0, binding = 1, r8ui) uniform uimage3D tex_next;
layout(set = 0, binding = 2, r8ui) uniform uimage3D wake_mask;

// Geometry change buffer: each entry is a packed uvec2 (position, action)
// action 0 = remove voxel, action 1 = place voxel
layout(set = 0, binding = 3) buffer GeometryChanges {
    uint change_count;
    uvec2 changes[4096];
} geo_buf;

layout(push_constant) uniform Params {
    ivec3 sim_size;
    uint tick_parity;
    float fire_spread_chance;
    float fire_die_chance;
} params;

#define MAT_NONE     0u
#define MAT_STONE    1u
#define MAT_DIRT     2u
#define MAT_WOOD     3u
#define MAT_WATER    4u
#define MAT_FIRE     5u
#define MAT_ACID     6u
#define MAT_SCORCHED 7u
#define MAT_SAND     8u
#define MAT_BEDROCK  9u

uint read(ivec3 pos) {
    if (any(lessThan(pos, ivec3(0))) || any(greaterThanEqual(pos, params.sim_size)))
        return MAT_BEDROCK;
    return imageLoad(tex_current, pos).r;
}

void write_next(ivec3 pos, uint mat) {
    imageStore(tex_next, pos, uvec4(mat, 0u, 0u, 0u));
}

void queue_geometry_remove(ivec3 pos) {
    uint idx = atomicAdd(geo_buf.change_count, 1u);
    if (idx < 4096u)
        geo_buf.changes[idx] = uvec2(
            uint(pos.x) | (uint(pos.y) << 10u) | (uint(pos.z) << 20u),
            0u  // 0 = remove
        );
}

void simulate_fire(ivec3 pos) {
    ivec3 neighbours[4] = {
        pos + ivec3(1,0,0), pos + ivec3(-1,0,0),
        pos + ivec3(0,0,1), pos + ivec3(0,0,-1)
    };
    // Spread to flammable neighbours
    for (int i = 0; i < 4; i++) {
        uint n = read(neighbours[i]);
        if (n == MAT_WOOD || n == MAT_DIRT) {
            // Use position-derived pseudo-random for spread chance
            float r = fract(sin(float(pos.x * 127 + pos.z * 311 + neighbours[i].x)) * 43758.5);
            if (r < params.fire_spread_chance)
                write_next(neighbours[i], MAT_FIRE);
        }
    }
    // Self-extinguish
    float r2 = fract(sin(float(pos.x * 73 + pos.y * 157 + pos.z * 239)) * 43758.5);
    if (r2 < params.fire_die_chance) {
        write_next(pos, MAT_SCORCHED);
        queue_geometry_remove(pos);
    } else {
        write_next(pos, MAT_FIRE);
    }
}

void simulate_water(ivec3 pos) {
    ivec3 below = pos + ivec3(0, -1, 0);
    uint below_mat = read(below);
    if (below_mat == MAT_NONE) {
        write_next(below, MAT_WATER);
        write_next(pos, MAT_NONE);
        return;
    }
    if (below_mat == MAT_FIRE) {
        write_next(below, MAT_NONE);
        write_next(pos, MAT_NONE);
        return;
    }
    write_next(pos, MAT_WATER);
}

void simulate_acid(ivec3 pos) {
    ivec3 neighbours[5] = {
        pos + ivec3(1,0,0), pos + ivec3(-1,0,0),
        pos + ivec3(0,-1,0), pos + ivec3(0,0,1), pos + ivec3(0,0,-1)
    };
    for (int i = 0; i < 5; i++) {
        uint n = read(neighbours[i]);
        if (n == MAT_STONE || n == MAT_DIRT) {
            write_next(neighbours[i], MAT_NONE);
            write_next(pos, MAT_NONE);
            queue_geometry_remove(neighbours[i]);
            return;
        }
    }
    write_next(pos, MAT_ACID);
}

void main() {
    ivec3 pos = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(pos, params.sim_size))) return;

    // Checkerboard: skip cells that don't belong to this tick's parity
    uint parity = uint((pos.x + pos.y + pos.z) % 2);
    if (parity != params.tick_parity) {
        write_next(pos, read(pos));
        return;
    }

    // Only simulate if this cell is awake
    uint awake = imageLoad(wake_mask, pos).r;
    if (awake == 0u) {
        write_next(pos, read(pos));
        return;
    }

    uint mat = read(pos);
    switch (mat) {
        case MAT_FIRE:  simulate_fire(pos);  break;
        case MAT_WATER: simulate_water(pos); break;
        case MAT_ACID:  simulate_acid(pos);  break;
        default:        write_next(pos, mat); break;
    }
}
```

### MaterialSimulator GDScript Autoload (thin wrapper)

The GDScript side only manages GPU resources and handles the CPU-side geometry sync.
All simulation logic lives in the shader above.

```gdscript
# material_simulator.gd
class_name MaterialSimulator
extends Node

const VOXEL_SCALE := 0.0625
const SIM_WIDTH  := 512   # voxels — covers ~32m (adjust to loaded area size)
const SIM_DEPTH  := 512
const SIM_HEIGHT := 32    # 2m total vertical range

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _tex_current: RID
var _tex_next: RID
var _wake_mask: RID
var _geo_buffer: RID
var _uniform_set: RID

var _tick := 0
var _geo_readback_interval := 5  # frames between geometry syncs

var voxel_tool: VoxelTool = null
signal entity_entered_material(entity: Node3D, material_type: int)


func _ready() -> void:
    _rd = RenderingServer.get_rendering_device()
    _setup_compute()


func _setup_compute() -> void:
    var shader_file := load("res://shaders/material_sim.glsl") as RDShaderFile
    _shader = _rd.shader_create_from_spirv(shader_file.get_spirv())
    _pipeline = _rd.compute_pipeline_create(_shader)

    var fmt := RDTextureFormat.new()
    fmt.format = RenderingDevice.DATA_FORMAT_R8_UINT
    fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
    fmt.width = SIM_WIDTH
    fmt.height = SIM_HEIGHT
    fmt.depth = SIM_DEPTH
    fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
        | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
        | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)

    _tex_current = _rd.texture_create(fmt, RDTextureView.new(), [])
    _tex_next    = _rd.texture_create(fmt, RDTextureView.new(), [])
    _wake_mask   = _rd.texture_create(fmt, RDTextureView.new(), [])

    # Geometry change buffer: 4 bytes count + 4096 * 8 bytes entries
    _geo_buffer = _rd.storage_buffer_create(4 + 4096 * 8)

    _rebuild_uniform_set()


func _rebuild_uniform_set() -> void:
    # Build uniforms for all four bindings and create the uniform set
    # (implementation detail — bind tex_current, tex_next, wake_mask, geo_buffer)
    pass


func wake_region(world_pos: Vector3, radius_m: float) -> void:
    # Convert world position to voxel coordinates and write 1s into wake_mask texture
    # in a sphere of the given radius. This activates the compute shader for those cells.
    var centre := _world_to_sim(world_pos)
    var radius_v := int(ceil(radius_m / VOXEL_SCALE))
    # Write to a staging buffer then upload to wake_mask texture
    # (omitted for brevity — use rd.texture_update with a byte array)
    pass


func apply_impact(world_pos: Vector3, material_type: int) -> void:
    # Write the material type into tex_current at the impact position,
    # then wake the surrounding region so the compute shader picks it up.
    var voxel_pos := _world_to_sim(world_pos)
    # Upload single voxel change to tex_current
    wake_region(world_pos, 0.5)


func _physics_process(_delta: float) -> void:
    _dispatch_simulation()
    _tick += 1
    if _tick % _geo_readback_interval == 0:
        _apply_geometry_changes()


func _dispatch_simulation() -> void:
    # Reset change counter to 0 at start of each dispatch
    _rd.buffer_update(_geo_buffer, 0, 4, PackedByteArray([0, 0, 0, 0]))

    var push_constant := PackedByteArray()
    push_constant.resize(32)
    # Pack sim_size (ivec3), tick_parity (uint), fire_spread_chance, fire_die_chance
    # into push_constant bytes

    var compute_list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
    _rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
    _rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
    _rd.compute_list_dispatch(
        compute_list,
        int(ceil(SIM_WIDTH  / 8.0)),
        int(ceil(SIM_DEPTH  / 8.0)),
        int(ceil(SIM_HEIGHT / 1.0))
    )
    _rd.compute_list_end()

    # Swap ping-pong textures
    var tmp := _tex_current
    _tex_current = _tex_next
    _tex_next = tmp


func _apply_geometry_changes() -> void:
    if not voxel_tool:
        return
    # Read the change count from the buffer
    var count_bytes := _rd.buffer_get_data(_geo_buffer, 0, 4)
    var count := count_bytes.decode_u32(0)
    if count == 0:
        return
    count = min(count, 4096)
    # Read the change entries
    var entries := _rd.buffer_get_data(_geo_buffer, 4, count * 8)
    for i in count:
        var packed_pos := entries.decode_u32(i * 8)
        var action     := entries.decode_u32(i * 8 + 4)
        var vx := int(packed_pos & 0x3FF)
        var vy := int((packed_pos >> 10) & 0x3FF)
        var vz := int((packed_pos >> 20) & 0x3FF)
        var world_voxel := Vector3i(vx, vy, vz)
        if action == 0:  # remove geometry
            voxel_tool.set_voxel(world_voxel, 0, VoxelBuffer.CHANNEL_TYPE)
        else:            # place geometry
            voxel_tool.set_voxel(world_voxel, 1, VoxelBuffer.CHANNEL_TYPE)


func _world_to_sim(world_pos: Vector3) -> Vector3i:
    return Vector3i(
        int(floor(world_pos.x / VOXEL_SCALE)),
        int(floor(world_pos.y / VOXEL_SCALE)),
        int(floor(world_pos.z / VOXEL_SCALE))
    )
```

### Initial Material Interactions

| Source | Target | Result | Where defined |
|---|---|---|---|
| FIRE | adjacent WOOD / DIRT | Target becomes FIRE (probabilistic) | `simulate_fire()` in GLSL |
| FIRE | self | Becomes SCORCHED after random ticks | `simulate_fire()` in GLSL |
| WATER | FIRE below/adjacent | Both become NONE (steam) | `simulate_water()` in GLSL |
| WATER | AIR below | Water falls (gravity) | `simulate_water()` in GLSL |
| ACID | adjacent STONE / DIRT | Geometry removed, ACID consumed | `simulate_acid()` in GLSL |

---

## Phase 4 — Staining (Prototype)

**Goal:** Voxels and entities show visual material state.

Because the material simulation texture (`tex_current`) is already on the GPU, the
voxel terrain shader can sample it directly for staining with no extra work. There is
no separate stain channel needed.

In the voxel terrain shader, sample `tex_current` at the fragment's world position
and blend a stain colour on top of the base voxel colour:

```glsl
// In voxel_material.gdshader (fragment section)
uniform usampler3D material_state;  // tex_current bound here
uniform float voxel_scale;

vec3 apply_stain(vec3 base_colour, vec3 world_pos) {
    ivec3 voxel_coord = ivec3(floor(world_pos / voxel_scale));
    uint mat = texelFetch(material_state, voxel_coord, 0).r;
    if (mat == 7u) return mix(base_colour, vec3(0.1, 0.08, 0.06), 0.6); // SCORCHED
    if (mat == 4u) return mix(base_colour, vec3(0.2, 0.4, 0.8),  0.4); // WET
    if (mat == 6u) return mix(base_colour, vec3(0.2, 0.8, 0.2),  0.5); // ACID
    return base_colour;
}
```

Entity staining: `MaterialSimulator` reads the simulation texture at each entity's
position (via a small CPU-side sample of `tex_current`) and emits
`entity_entered_material(entity, material_type)`. Connect this signal to:
- `status.gd` — apply a status effect (on_fire, wet, acid_burned)
- `sprite_effects.gd` — apply a colour tint matching the material

```gdscript
# Add to MaterialSimulator
signal entity_entered_material(entity: Node3D, material_type: int)

func check_entity_overlap(entity: Node3D) -> void:
    var sim_pos := _world_to_sim(entity.global_position)
    # Sample a single texel from tex_current via a small buffer readback
    # This is acceptable because it's a single pixel per entity per frame,
    # not a large readback.
    var bytes := _rd.texture_get_data(_tex_current, 0)
    var idx := sim_pos.x + sim_pos.z * SIM_WIDTH + sim_pos.y * SIM_WIDTH * SIM_DEPTH
    if idx >= 0 and idx < bytes.size():
        var mat := bytes[idx]
        if mat != 0:
            entity_entered_material.emit(entity, mat)
```

---

## Phase 5 — Integration into Rift Delver

Once the prototype is stable and performing acceptably:

### Step 1: Install godot_voxel GDExtension

Drop the extension folder into `addons/godot_voxel/` alongside `addons/limboai/`.
Enable in Project Settings > Plugins.

### Step 2: Create VoxelWorldManager

New file: `scripts/systems/voxel_world_manager.gd`

- On `WorldChunkManager.chunk_loaded(chunk_pos, chunk_instance)`, generate the voxel
  surface for that chunk's region.
- Each game chunk (16×16 tiles at 1m scale) = 256×256 voxels at 1/16 scale.
- Use the same `RiftVoxelGenerator` from the prototype, parameterised by biome/depth.

```gdscript
# scripts/systems/voxel_world_manager.gd
class_name VoxelWorldManager
extends Node

@export var chunk_manager_path: NodePath
@export var voxel_terrain: VoxelTerrain

const TILE_TO_VOXEL := 16  # 1 tile = 16 voxels

func _ready() -> void:
    var chunk_manager := get_node(chunk_manager_path) as WorldChunkManager
    chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
    chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)

func _on_chunk_loaded(chunk_pos: Vector2i, _instance: WorldChunkInstance) -> void:
    # VoxelTerrain streams automatically.
    # Apply biome-specific overrides or pre-carve rooms here if needed.
    pass

func _on_chunk_unloaded(_chunk_pos: Vector2i) -> void:
    pass  # godot_voxel handles unloading its own chunks
```

### Step 3: Add material_interaction to AmmoType

In `scripts/resources/ammo_type/ammo_type.gd`, add:

```gdscript
@export var material_interaction: int = MaterialSimulator.MAT_NONE
```

### Step 4: Hook into combat_system

In `scripts/systems/combat_system.gd`, on projectile impact with terrain:

```gdscript
var material_sim := get_tree().get_first_node_in_group("material_simulator") as MaterialSimulator
if material_sim and ammo_type.material_interaction != MaterialSimulator.MAT_NONE:
    material_sim.apply_impact(impact_world_position, ammo_type.material_interaction)
```

### Step 5: Connect entity staining

In the player and enemy base scripts, call `MaterialSimulator.check_entity_overlap(self)`
on a timer (every 0.1s is sufficient). Connect the `entity_entered_material` signal to:
- `status.gd` — apply a status effect (on_fire, wet, acid_burned)
- `sprite_effects.gd` — apply a colour tint matching the material

---

## Key Things to Validate in the Prototype

| Question | How to test |
|---|---|
| Does godot_voxel GDExtension version match your Godot build? | Install + open editor, check Output for errors |
| Is 1/16 scale meshing performant with a large view radius? | Godot profiler, walk around, watch draw calls and mesh build time |
| Does the compute shader compile and dispatch without errors? | Check RenderingDevice validation errors in Output |
| Is the checkerboard pattern producing correct spread behaviour? | Watch fire spread — should expand outward without visual artefacts |
| Is geometry_change_buffer overflow happening? | Add a print when `change_count > 4096`; increase buffer if needed |
| Does the geometry sync (CPU readback every N frames) cause hitches? | Profile `_apply_geometry_changes()` with many simultaneous changes |
| Does the Y-cutoff occlusion shader feel natural? | Playtest — adjust fade softness and threshold |
| Does BEDROCK correctly prevent digging below 1m? | Trigger acid near bedrock, confirm no geometry changes are queued |

---

## File Checklist

### Prototype Project (new)
- [ ] `voxel_generator.gd` — RiftVoxelGenerator
- [ ] `material_types.gd` — shared MaterialType constants
- [ ] `material_simulator.gd` — Autoload, GPU compute wrapper + geometry sync
- [ ] `shaders/material_sim.glsl` — compute shader, all cellular automaton rules
- [ ] `shaders/voxel_material.gdshader` — voxel terrain shader, fade_above_y + stain from tex_current
- [ ] `voxel_world.tscn` — VoxelTerrain + camera + player test scene
- [ ] `voxel_blocky_library.tres` — VoxelBlockyLibrary resource (AIR, STONE, BEDROCK)

### Rift Delver Integration (existing project)
- [ ] `addons/godot_voxel/` — GDExtension files
- [ ] `scripts/systems/voxel_world_manager.gd` — new
- [ ] `scripts/systems/material_simulator.gd` — ported from prototype (Autoload)
- [ ] `scripts/resources/material_types.gd` — shared constants
- [ ] `assets/shaders/material_sim.glsl` — compute shader
- [ ] `assets/shaders/voxel_material.gdshader` — voxel terrain shader
- [ ] `scripts/resources/ammo_type/ammo_type.gd` — add material_interaction field
- [ ] `scripts/systems/combat_system.gd` — add apply_impact call on terrain hit
