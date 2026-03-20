class_name RiftVoxelGenerator
extends VoxelGeneratorScript


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, _lod: int) -> void:
	var size := out_buffer.get_size()
	var oy := origin_in_voxels.y
	var top_y := oy + size.y - 1
	var ch := VoxelBuffer.CHANNEL_TYPE

	# Fast path: entire block is one material
	if top_y <= 0:
		out_buffer.fill(MaterialRegistry.BEDROCK, ch)
		return
	if oy >= 16:
		# Air is the default, but fill explicitly to be safe
		return
	if oy >= 1 and top_y <= 14:
		out_buffer.fill(MaterialRegistry.STONE, ch)
		return

	# Mixed block — fill slabs instead of per-voxel loop
	# Bedrock: world_y <= 0
	if oy <= 0:
		var bedrock_end := mini(size.y, 1 - oy)
		out_buffer.fill_area(MaterialRegistry.BEDROCK,
			Vector3i(0, 0, 0), Vector3i(size.x, bedrock_end, size.z), ch)

	# Stone: world_y 1..14
	var stone_start := maxi(0, 1 - oy)
	var stone_end := mini(size.y, 15 - oy)
	if stone_start < stone_end:
		out_buffer.fill_area(MaterialRegistry.STONE,
			Vector3i(0, stone_start, 0), Vector3i(size.x, stone_end, size.z), ch)

	# Dirt: world_y == 15
	var dirt_local := 15 - oy
	if dirt_local >= 0 and dirt_local < size.y:
		out_buffer.fill_area(MaterialRegistry.DIRT,
			Vector3i(0, dirt_local, 0), Vector3i(size.x, dirt_local + 1, size.z), ch)


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE
