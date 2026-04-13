class_name VoxImporter
extends RefCounted

## Import a MagicaVoxel .vox file and produce a WFCTileDef (or WFCStructureDef
## if the model exceeds one tile in size).
##
## .vox format reference: https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt
## RIFF-like: "VOX " header, then chunks (MAIN → SIZE, XYZI, RGBA, etc.)


static func import_file(path: String, palette_map: VoxelPaletteMap) -> Resource:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[VoxImporter] Cannot open: %s" % path)
		return null

	# Header: "VOX " + version (4 bytes)
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != "VOX ":
		push_error("[VoxImporter] Not a valid .vox file: %s" % path)
		return null
	var _version := file.get_32()

	# MAIN chunk
	var main_id := file.get_buffer(4).get_string_from_ascii()
	if main_id != "MAIN":
		push_error("[VoxImporter] Expected MAIN chunk, got: %s" % main_id)
		return null
	var _main_content_size := file.get_32()
	var _main_children_size := file.get_32()

	# Parse child chunks
	var size_x := 0
	var size_y := 0  # MV Y = our Z
	var size_z := 0  # MV Z = our Y
	var voxels: Array[Vector3i] = []
	var color_indices: PackedByteArray = []

	while file.get_position() < file.get_length():
		var chunk_id := file.get_buffer(4).get_string_from_ascii()
		var content_size := file.get_32()
		var children_size := file.get_32()
		var chunk_start := file.get_position()

		if chunk_id == "SIZE":
			size_x = file.get_32()
			size_y = file.get_32()
			size_z = file.get_32()

		elif chunk_id == "XYZI":
			var num_voxels := file.get_32()
			for i in num_voxels:
				var vx := file.get_8()  # MV X → our X
				var vy := file.get_8()  # MV Y → our Z
				var vz := file.get_8()  # MV Z → our Y
				var ci := file.get_8()  # color index (1-255, 0 = not used)
				voxels.append(Vector3i(vx, vz, vy))
				color_indices.append(ci)

		# Skip to end of chunk content + children
		file.seek(chunk_start + content_size + children_size)

	file.close()

	if voxels.is_empty():
		push_warning("[VoxImporter] No voxels found in: %s" % path)

	# Determine if this fits in one tile or needs a structure
	var tiles_x := ceili(float(size_x) / WFCTileDef.TILE_X)
	var tiles_z := ceili(float(size_y) / WFCTileDef.TILE_Z)  # MV Y → our Z

	if tiles_x <= 1 and tiles_z <= 1:
		return _build_single_tile(path, voxels, color_indices, palette_map)
	else:
		return _build_structure(path, voxels, color_indices, palette_map,
			tiles_x, tiles_z, size_x, size_y, size_z)


static func _build_single_tile(
	path: String,
	voxels: Array[Vector3i],
	color_indices: PackedByteArray,
	palette_map: VoxelPaletteMap
) -> WFCTileDef:
	var tile := WFCTileDef.new()
	tile.tile_name = path.get_file().get_basename()
	tile._ensure_data()

	for i in voxels.size():
		var pos := voxels[i]
		var voxel_id := palette_map.get_voxel_id(color_indices[i])
		tile.set_voxel(pos.x, pos.y, pos.z, voxel_id)

	print("[VoxImporter] Imported tile '%s': %d voxels" % [tile.tile_name, voxels.size()])
	return tile


static func _build_structure(
	path: String,
	voxels: Array[Vector3i],
	color_indices: PackedByteArray,
	palette_map: VoxelPaletteMap,
	tiles_x: int,
	tiles_z: int,
	_size_x: int,
	_size_y: int,
	_size_z: int
) -> WFCStructureDef:
	var structure := WFCStructureDef.new()
	structure.structure_name = path.get_file().get_basename()
	structure.size = Vector2i(tiles_x, tiles_z)

	var full_w := tiles_x * WFCTileDef.TILE_X
	var full_h := WFCTileDef.TILE_Y
	var full_d := tiles_z * WFCTileDef.TILE_Z
	var byte_size := full_w * full_h * full_d * 2
	structure.full_voxel_data.resize(byte_size)
	structure.full_voxel_data.fill(0)

	for i in voxels.size():
		var pos := voxels[i]
		if pos.x < 0 or pos.x >= full_w or pos.y < 0 or pos.y >= full_h or pos.z < 0 or pos.z >= full_d:
			continue
		var voxel_id := palette_map.get_voxel_id(color_indices[i])
		var idx := (pos.x + pos.y * full_w + pos.z * full_w * full_h) * 2
		structure.full_voxel_data.encode_u16(idx, voxel_id)

	print("[VoxImporter] Imported structure '%s': %dx%d tiles, %d voxels" % [
		structure.structure_name, tiles_x, tiles_z, voxels.size()])
	return structure
