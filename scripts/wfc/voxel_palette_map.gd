class_name VoxelPaletteMap
extends Resource

@export var palette_name: String = "default"
## Maps MagicaVoxel palette index (int, 0-255) → full uint16 voxel ID.
## Unmapped indices default to AIR (0).
@export var mappings: Dictionary = {}


## Look up the voxel ID for a MagicaVoxel palette index.
func get_voxel_id(palette_index: int) -> int:
	return mappings.get(palette_index, 0)


## Set a mapping from palette index to voxel ID.
func set_mapping(palette_index: int, voxel_id: int) -> void:
	mappings[palette_index] = voxel_id


## Create a simple default palette that maps low indices to base materials.
static func create_default() -> VoxelPaletteMap:
	var pal := VoxelPaletteMap.new()
	pal.palette_name = "default"
	pal.mappings = {
		0: MaterialRegistry.AIR,
		1: MaterialRegistry.STONE,
		2: MaterialRegistry.BEDROCK,
		3: MaterialRegistry.WATER,
		4: MaterialRegistry.DIRT,
		5: MaterialRegistry.MUD,
		6: MaterialRegistry.LAVA,
		7: MaterialRegistry.ACID,
		8: MaterialRegistry.STEAM,
	}
	return pal
