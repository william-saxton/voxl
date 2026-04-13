class_name WFCTileDef
extends Resource

enum EdgeType {
	SOLID_WALL = 0,
	OPEN_GROUND = 1,
	CORRIDOR = 2,
	DOOR = 3,
	BEDROCK_WALL = 4,
	STRUCTURE_INTERNAL = 5,
}

## Default tile dimensions in voxels (used by WFC grid tiles)
const DEFAULT_TILE_X := 128
const DEFAULT_TILE_Y := 112
const DEFAULT_TILE_Z := 128

## Legacy constants — point to defaults for backward compatibility
const TILE_X := DEFAULT_TILE_X
const TILE_Y := DEFAULT_TILE_Y
const TILE_Z := DEFAULT_TILE_Z
const TILE_VOL := TILE_X * TILE_Y * TILE_Z

## Instance tile dimensions — can differ from defaults for props/small assets
@export var tile_size_x: int = DEFAULT_TILE_X
@export var tile_size_y: int = DEFAULT_TILE_Y
@export var tile_size_z: int = DEFAULT_TILE_Z

@export var tile_name: String = ""
@export var edge_north: int = EdgeType.SOLID_WALL
@export var edge_south: int = EdgeType.SOLID_WALL
@export var edge_east: int = EdgeType.SOLID_WALL
@export var edge_west: int = EdgeType.SOLID_WALL
@export var weight: float = 1.0
@export var rotatable: bool = false
@export var tags: PackedStringArray = []
@export var surface_material: int = MaterialRegistry.STONE
@export var biome: String = ""
## uint16 LE — 2 bytes per voxel
@export var voxel_data: PackedByteArray = []
## Positional annotations for gameplay systems (spawn points, triggers, etc.)
@export var metadata_points: Dictionary = {}
## Embedded palette data — Array of Dictionaries, each with name, color, base_material.
## Saved alongside the tile so palette is preserved when reopening.
@export var palette_entries: Array[Dictionary] = []


## Get the tile volume based on instance dimensions.
func get_tile_vol() -> int:
	return tile_size_x * tile_size_y * tile_size_z


## Get instance tile size as Vector3i.
func get_tile_size() -> Vector3i:
	return Vector3i(tile_size_x, tile_size_y, tile_size_z)


## Set instance tile size. Resizes voxel_data if needed (preserves existing data).
func set_tile_size(sx: int, sy: int, sz: int) -> void:
	if sx == tile_size_x and sy == tile_size_y and sz == tile_size_z:
		return
	var old_sx := tile_size_x
	var old_sy := tile_size_y
	var old_sz := tile_size_z
	var old_data := voxel_data.duplicate()

	tile_size_x = sx
	tile_size_y = sy
	tile_size_z = sz

	# Allocate new buffer and copy overlapping region
	var new_vol := sx * sy * sz
	voxel_data = PackedByteArray()
	voxel_data.resize(new_vol * 2)
	voxel_data.fill(0)

	var copy_x := mini(old_sx, sx)
	var copy_y := mini(old_sy, sy)
	var copy_z := mini(old_sz, sz)
	for lz in copy_z:
		for ly in copy_y:
			for lx in copy_x:
				var old_idx := (lx + ly * old_sx + lz * old_sx * old_sy) * 2
				var new_idx := (lx + ly * sx + lz * sx * sy) * 2
				if old_idx + 1 < old_data.size():
					var v := old_data.decode_u16(old_idx)
					voxel_data.encode_u16(new_idx, v)


## Read a voxel ID (uint16) at local tile coordinates.
func get_voxel(lx: int, ly: int, lz: int) -> int:
	if lx < 0 or lx >= tile_size_x or ly < 0 or ly >= tile_size_y or lz < 0 or lz >= tile_size_z:
		return 0
	var idx := (lx + ly * tile_size_x + lz * tile_size_x * tile_size_y) * 2
	if idx + 1 >= voxel_data.size():
		return 0
	return voxel_data.decode_u16(idx)


## Write a voxel ID (uint16) at local tile coordinates.
func set_voxel(lx: int, ly: int, lz: int, voxel_id: int) -> void:
	if lx < 0 or lx >= tile_size_x or ly < 0 or ly >= tile_size_y or lz < 0 or lz >= tile_size_z:
		return
	_ensure_data()
	var idx := (lx + ly * tile_size_x + lz * tile_size_x * tile_size_y) * 2
	voxel_data.encode_u16(idx, voxel_id)


## Ensure voxel_data is allocated to full tile size.
func _ensure_data() -> void:
	var needed := get_tile_vol() * 2
	if voxel_data.size() < needed:
		voxel_data.resize(needed)


## Check if two edges are compatible for WFC adjacency.
static func edges_compatible(edge_a: int, edge_b: int) -> bool:
	# STRUCTURE_INTERNAL only matches itself (same structure)
	if edge_a == EdgeType.STRUCTURE_INTERNAL or edge_b == EdgeType.STRUCTURE_INTERNAL:
		return edge_a == edge_b
	return edge_a == edge_b
