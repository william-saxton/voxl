class_name RiftVoxelGenerator
extends VoxelGeneratorScript

## WFC tile layout — set by VoxelWorldManager before terrain starts streaming.
## Once set, this data is read-only from background threads.
var _wfc_layout: PackedInt32Array  # grid_w * grid_h tile IDs
var _wfc_grid_w: int = 0
var _wfc_grid_h: int = 0
var _wfc_tiles: Dictionary = {}  # tile_id → WFCTileDef
var _wfc_active: bool = false


## Called from main thread before terrain streams. Thread-safe after this call.
func set_wfc_layout(layout: PackedInt32Array, grid_w: int, grid_h: int,
		tiles: Dictionary) -> void:
	_wfc_layout = layout
	_wfc_grid_w = grid_w
	_wfc_grid_h = grid_h
	_wfc_tiles = tiles
	_wfc_active = true


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, _lod: int) -> void:
	if _wfc_active:
		_generate_block_wfc(out_buffer, origin_in_voxels)
	else:
		_generate_block_flat(out_buffer, origin_in_voxels)


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE


# ── WFC-driven generation ──

func _generate_block_wfc(out_buffer: VoxelBuffer, origin: Vector3i) -> void:
	var size := out_buffer.get_size()
	var ch := VoxelBuffer.CHANNEL_TYPE

	for lz in size.z:
		for lx in size.x:
			var wx := origin.x + lx
			var wz := origin.z + lz

			# Tile coordinates (128 voxels per tile)
			var tile_gx := wx >> 7  # wx / 128
			var tile_gz := wz >> 7  # wz / 128

			# Out of grid → bedrock below y=16, air above
			if tile_gx < 0 or tile_gx >= _wfc_grid_w \
					or tile_gz < 0 or tile_gz >= _wfc_grid_h:
				for ly in size.y:
					var wy := origin.y + ly
					if wy <= 0:
						out_buffer.set_voxel(MaterialRegistry.BEDROCK, lx, ly, lz, ch)
				continue

			var tile_idx := tile_gx + tile_gz * _wfc_grid_w
			var tile_id: int = _wfc_layout[tile_idx]
			var tile: WFCTileDef = _wfc_tiles.get(tile_id)

			if not tile:
				# Unknown tile — fallback to bedrock/air
				for ly in size.y:
					var wy := origin.y + ly
					if wy <= 0:
						out_buffer.set_voxel(MaterialRegistry.BEDROCK, lx, ly, lz, ch)
				continue

			# Local position within tile
			var local_x := wx - (tile_gx << 7)  # wx % 128
			var local_z := wz - (tile_gz << 7)  # wz % 128

			for ly in size.y:
				var wy := origin.y + ly
				if wy < 0 or wy >= WFCTileDef.TILE_Y:
					if wy < 0:
						out_buffer.set_voxel(MaterialRegistry.BEDROCK, lx, ly, lz, ch)
					continue

				var voxel_id := tile.get_voxel(local_x, wy, local_z)

				# Border blending (surface layer only, within 8 voxels of edge)
				if wy == 15 and voxel_id != MaterialRegistry.AIR:
					voxel_id = _blend_border(voxel_id, tile, tile_gx, tile_gz,
						local_x, local_z)

				if voxel_id != 0:
					out_buffer.set_voxel(voxel_id, lx, ly, lz, ch)


func _blend_border(voxel_id: int, tile: WFCTileDef, tile_gx: int, tile_gz: int,
		local_x: int, local_z: int) -> int:
	const BLEND_DIST := 8

	# Distance to each edge
	var dist_n := local_z
	var dist_s := WFCTileDef.TILE_Z - 1 - local_z
	var dist_e := WFCTileDef.TILE_X - 1 - local_x
	var dist_w := local_x

	var min_dist := mini(mini(dist_n, dist_s), mini(dist_e, dist_w))
	if min_dist >= BLEND_DIST:
		return voxel_id

	# Find which neighbor we're closest to
	var neighbor_gx := tile_gx
	var neighbor_gz := tile_gz
	if min_dist == dist_n:
		neighbor_gz -= 1
	elif min_dist == dist_s:
		neighbor_gz += 1
	elif min_dist == dist_e:
		neighbor_gx += 1
	else:
		neighbor_gx -= 1

	# Look up neighbor tile
	if neighbor_gx < 0 or neighbor_gx >= _wfc_grid_w \
			or neighbor_gz < 0 or neighbor_gz >= _wfc_grid_h:
		return voxel_id

	var n_idx := neighbor_gx + neighbor_gz * _wfc_grid_w
	var n_tile_id: int = _wfc_layout[n_idx]
	var n_tile: WFCTileDef = _wfc_tiles.get(n_tile_id)
	if not n_tile or n_tile.surface_material == tile.surface_material:
		return voxel_id

	# Hash dithering
	var t := float(min_dist) / float(BLEND_DIST)
	var h := ((local_x * 374761393 + local_z * 668265263) & 0x7FFFFFFF) % 1000
	if h > int(t * 1000.0):
		return n_tile.surface_material

	return voxel_id


# ── Flat terrain fallback (original) ──

func _generate_block_flat(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i) -> void:
	var size := out_buffer.get_size()
	var oy := origin_in_voxels.y
	var top_y := oy + size.y - 1
	var ch := VoxelBuffer.CHANNEL_TYPE

	# Fast path: entire block is one material
	if top_y <= 0:
		out_buffer.fill(MaterialRegistry.BEDROCK, ch)
		return
	if oy >= 16:
		return
	if oy >= 1 and top_y <= 14:
		out_buffer.fill(MaterialRegistry.STONE, ch)
		return

	# Mixed block — fill slabs
	if oy <= 0:
		var bedrock_end := mini(size.y, 1 - oy)
		out_buffer.fill_area(MaterialRegistry.BEDROCK,
			Vector3i(0, 0, 0), Vector3i(size.x, bedrock_end, size.z), ch)

	var stone_start := maxi(0, 1 - oy)
	var stone_end := mini(size.y, 15 - oy)
	if stone_start < stone_end:
		out_buffer.fill_area(MaterialRegistry.STONE,
			Vector3i(0, stone_start, 0), Vector3i(size.x, stone_end, size.z), ch)

	var dirt_local := 15 - oy
	if dirt_local >= 0 and dirt_local < size.y:
		out_buffer.fill_area(MaterialRegistry.DIRT,
			Vector3i(0, dirt_local, 0), Vector3i(size.x, dirt_local + 1, size.z), ch)
