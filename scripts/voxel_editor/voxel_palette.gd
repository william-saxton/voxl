class_name VoxelPalette
extends Resource

## A palette for the voxel editor. Each entry defines a color AND a base material.
## The entry's index in the array IS the visual variant:
##   make_voxel_id(base_material, index) → uint16 = (index << 8) | base_material

@export var palette_name: String = "default"
@export var entries: Array[PaletteEntry] = []


func _init() -> void:
	if entries.is_empty():
		# Entry 0 is always AIR (reserved)
		var air := PaletteEntry.new()
		air.entry_name = "Air"
		air.color = Color(0.0, 0.0, 0.0, 0.0)
		air.base_material = MaterialRegistry.AIR
		entries.append(air)


## Get the full uint16 voxel ID for a palette index.
func get_voxel_id(index: int) -> int:
	if index < 0 or index >= entries.size():
		return 0
	return MaterialRegistry.make_voxel_id(entries[index].base_material, index)


## Get the color for a palette index.
func get_color(index: int) -> Color:
	if index < 0 or index >= entries.size():
		return Color.MAGENTA
	return entries[index].color


## Find the palette index for a given uint16 voxel ID.
## Returns -1 if not found.
func find_entry(voxel_id: int) -> int:
	var base := MaterialRegistry.base_material(voxel_id)
	var visual := MaterialRegistry.visual_variant(voxel_id)
	if visual >= 0 and visual < entries.size():
		if entries[visual].base_material == base:
			return visual
	# Fallback: linear search
	for i in entries.size():
		if entries[i].base_material == base:
			return i
	return -1


## Resolve a uint16 voxel ID to its display color.
## Falls back to material-based defaults if not in palette.
func resolve_color(voxel_id: int) -> Color:
	if voxel_id == 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var visual := MaterialRegistry.visual_variant(voxel_id)
	if visual >= 0 and visual < entries.size():
		return entries[visual].color
	# Fallback based on base material
	return _default_color(MaterialRegistry.base_material(voxel_id))


static func _default_color(base: int) -> Color:
	match base:
		MaterialRegistry.STONE: return Color(0.6, 0.58, 0.55)
		MaterialRegistry.BEDROCK: return Color(0.25, 0.23, 0.22)
		MaterialRegistry.WATER: return Color(0.2, 0.4, 0.8, 0.6)
		MaterialRegistry.DIRT: return Color(0.55, 0.35, 0.18)
		MaterialRegistry.MUD: return Color(0.18, 0.12, 0.08)
		MaterialRegistry.LAVA: return Color(1.0, 0.3, 0.0, 0.9)
		MaterialRegistry.ACID: return Color(0.3, 0.9, 0.1, 0.6)
		MaterialRegistry.GAS: return Color(0.5, 0.7, 0.3, 0.3)
	return Color.MAGENTA


## Create a default palette with basic material entries.
static func create_default() -> VoxelPalette:
	var pal := VoxelPalette.new()
	pal.palette_name = "default"

	# Index 0 = AIR (already added in _init)
	# Index 1 = Stone
	pal.add_entry("Stone", Color(0.6, 0.58, 0.55), MaterialRegistry.STONE)
	# Index 2 = Bedrock
	pal.add_entry("Bedrock", Color(0.25, 0.23, 0.22), MaterialRegistry.BEDROCK)
	# Index 3 = Dirt
	pal.add_entry("Dirt", Color(0.55, 0.35, 0.18), MaterialRegistry.DIRT)
	# Index 4 = Dark Stone
	pal.add_entry("Dark Stone", Color(0.4, 0.38, 0.35), MaterialRegistry.STONE)
	# Index 5 = Mossy Stone
	pal.add_entry("Mossy Stone", Color(0.45, 0.55, 0.4), MaterialRegistry.STONE)
	# Index 6 = Light Dirt
	pal.add_entry("Light Dirt", Color(0.7, 0.5, 0.3), MaterialRegistry.DIRT)
	# Index 7 = Mud
	pal.add_entry("Mud", Color(0.18, 0.12, 0.08), MaterialRegistry.MUD)

	return pal


## Build a PackedColorArray indexed by palette entry index (visual variant).
## Used by the C++ native mesher for fast color lookup.
func get_color_table() -> PackedColorArray:
	var table := PackedColorArray()
	table.resize(entries.size())
	for i in entries.size():
		table[i] = entries[i].color
	return table


func add_entry(entry_name: String, color: Color, base_material: int) -> int:
	var entry := PaletteEntry.new()
	entry.entry_name = entry_name
	entry.color = color
	entry.base_material = base_material
	entries.append(entry)
	return entries.size() - 1


## Resolve a uint16 voxel ID to a deterministic color based on base_material.
## Used by the Material debug view mode.
func resolve_material_color(voxel_id: int) -> Color:
	if voxel_id == 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var base := MaterialRegistry.base_material(voxel_id)
	match base:
		MaterialRegistry.STONE: return Color(0.7, 0.7, 0.7)
		MaterialRegistry.BEDROCK: return Color(0.2, 0.2, 0.2)
		MaterialRegistry.WATER: return Color(0.2, 0.5, 0.9)
		MaterialRegistry.DIRT: return Color(0.6, 0.4, 0.2)
		MaterialRegistry.MUD: return Color(0.3, 0.2, 0.1)
		MaterialRegistry.LAVA: return Color(1.0, 0.3, 0.0)
		MaterialRegistry.ACID: return Color(0.3, 0.9, 0.1)
		MaterialRegistry.GAS: return Color(0.5, 0.7, 0.3)
	# Unknown — use golden ratio hash for a unique hue
	var h := fmod(float(base) * 0.618033988749895, 1.0)
	return Color.from_hsv(h, 0.7, 0.9)


## Get the shader_material for a palette entry by voxel ID.
## Returns null if no custom material is assigned.
func get_entry_material(voxel_id: int) -> Material:
	if voxel_id == 0:
		return null
	var visual := MaterialRegistry.visual_variant(voxel_id)
	if visual >= 0 and visual < entries.size():
		return entries[visual].shader_material
	return null


## Check if any palette entry has a custom shader_material assigned.
func has_any_custom_materials() -> bool:
	for entry in entries:
		if entry.shader_material != null:
			return true
	return false
