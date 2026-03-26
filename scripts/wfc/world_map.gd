class_name WorldMap
extends Resource

@export var grid_width: int = 8
@export var grid_height: int = 8
## One byte per cell — biome ID (index into biome_palette). 0 = unassigned.
@export var cell_data: PackedByteArray = []
## Vector2i grid coord → String path to fixed tile/structure .res
@export var fixed_chunks: Dictionary = {}
@export var biome_palette: Array[BiomeDef] = []


func _init() -> void:
	if cell_data.size() == 0:
		_resize(grid_width, grid_height)


func resize(new_width: int, new_height: int) -> void:
	_resize(new_width, new_height)


func _resize(w: int, h: int) -> void:
	var old_data := cell_data.duplicate()
	var old_w := grid_width
	var old_h := grid_height
	grid_width = w
	grid_height = h
	cell_data.resize(w * h)
	cell_data.fill(0)
	# Preserve existing data where possible
	var copy_w := mini(old_w, w)
	var copy_h := mini(old_h, h)
	for y in copy_h:
		for x in copy_w:
			cell_data[x + y * w] = old_data[x + y * old_w]


func get_cell(gx: int, gz: int) -> int:
	if gx < 0 or gx >= grid_width or gz < 0 or gz >= grid_height:
		return 0
	return cell_data[gx + gz * grid_width]


func set_cell(gx: int, gz: int, biome_id: int) -> void:
	if gx < 0 or gx >= grid_width or gz < 0 or gz >= grid_height:
		return
	cell_data[gx + gz * grid_width] = biome_id


func set_fixed_chunk(gx: int, gz: int, res_path: String) -> void:
	fixed_chunks[Vector2i(gx, gz)] = res_path


func clear_fixed_chunk(gx: int, gz: int) -> void:
	fixed_chunks.erase(Vector2i(gx, gz))


func get_fixed_chunk(gx: int, gz: int) -> String:
	return fixed_chunks.get(Vector2i(gx, gz), "")


func is_fixed(gx: int, gz: int) -> bool:
	return fixed_chunks.has(Vector2i(gx, gz))


func get_biome(biome_id: int) -> BiomeDef:
	if biome_id <= 0 or biome_id > biome_palette.size():
		return null
	return biome_palette[biome_id - 1]
