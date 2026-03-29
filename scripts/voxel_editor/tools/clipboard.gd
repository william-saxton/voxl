class_name VoxelClipboard
extends RefCounted

## Copy/cut/paste buffer for voxel selections.
## Stores voxel IDs at positions relative to the selection's minimum corner.

var _data: Dictionary = {}  # Vector3i (relative) → int (voxel_id)
var _size := Vector3i.ZERO  # Bounding box size


func is_empty() -> bool:
	return _data.is_empty()


func get_size() -> Vector3i:
	return _size


func get_data() -> Dictionary:
	return _data


## Copy the selected voxels from tile into the clipboard.
func copy(tile: WFCTileDef, selection: VoxelSelection) -> void:
	_data.clear()
	if selection.is_empty():
		_size = Vector3i.ZERO
		return

	var bb := selection.get_bounding_box()
	var origin := Vector3i(int(bb.position.x), int(bb.position.y), int(bb.position.z))
	_size = Vector3i(int(bb.size.x), int(bb.size.y), int(bb.size.z))

	for pos in selection.get_positions():
		var vid := tile.get_voxel(pos.x, pos.y, pos.z)
		if vid != 0:
			_data[pos - origin] = vid


## Paste clipboard contents at the given anchor position.
## Returns a dictionary of { positions: Array[Vector3i], voxel_ids: Dictionary }
## for the undo system to apply.
func get_paste_data(anchor: Vector3i, tile: WFCTileDef = null) -> Dictionary:
	var positions: Array[Vector3i] = []
	var voxel_ids: Dictionary = {}  # Vector3i → int

	for rel_pos in _data:
		var world_pos: Vector3i = (rel_pos as Vector3i) + anchor
		var in_bounds := VoxelQuery._in_bounds_tile(world_pos, tile) if tile else VoxelQuery._in_bounds(world_pos)
		if in_bounds:
			positions.append(world_pos)
			voxel_ids[world_pos] = _data[rel_pos]

	return { "positions": positions, "voxel_ids": voxel_ids }


## Get preview positions for paste at the given anchor (for rendering).
func get_paste_preview(anchor: Vector3i, tile: WFCTileDef = null) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for rel_pos in _data:
		var world_pos: Vector3i = (rel_pos as Vector3i) + anchor
		var in_bounds := VoxelQuery._in_bounds_tile(world_pos, tile) if tile else VoxelQuery._in_bounds(world_pos)
		if in_bounds:
			result.append(world_pos)
	return result
