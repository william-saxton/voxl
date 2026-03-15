class_name RiftVoxelGenerator
extends VoxelGeneratorScript


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, _lod: int) -> void:
	for z in out_buffer.get_size().z:
		for x in out_buffer.get_size().x:
			for y in out_buffer.get_size().y:
				var world_y := origin_in_voxels.y + y
				if world_y <= -16:
					out_buffer.set_voxel(MaterialRegistry.BEDROCK, x, y, z, VoxelBuffer.CHANNEL_TYPE)
				elif world_y == 0:
					out_buffer.set_voxel(MaterialRegistry.DIRT, x, y, z, VoxelBuffer.CHANNEL_TYPE)
				elif world_y < 0:
					out_buffer.set_voxel(MaterialRegistry.STONE, x, y, z, VoxelBuffer.CHANNEL_TYPE)
				else:
					out_buffer.set_voxel(MaterialRegistry.AIR, x, y, z, VoxelBuffer.CHANNEL_TYPE)


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE
