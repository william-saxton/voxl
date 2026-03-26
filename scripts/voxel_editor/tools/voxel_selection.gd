class_name VoxelSelection
extends RefCounted

## Selection storage using Dictionary[Vector3i, bool] for O(1) membership.
## Provides iteration, bounding box, and set operations.

signal selection_changed()

var _selected: Dictionary = {}  # Vector3i → true


func add(pos: Vector3i) -> void:
	if not _selected.has(pos):
		_selected[pos] = true
		selection_changed.emit()


func add_array(positions: Array[Vector3i]) -> void:
	var changed := false
	for pos in positions:
		if not _selected.has(pos):
			_selected[pos] = true
			changed = true
	if changed:
		selection_changed.emit()


func remove(pos: Vector3i) -> void:
	if _selected.erase(pos):
		selection_changed.emit()


func remove_array(positions: Array[Vector3i]) -> void:
	var changed := false
	for pos in positions:
		if _selected.erase(pos):
			changed = true
	if changed:
		selection_changed.emit()


func toggle(pos: Vector3i) -> void:
	if _selected.has(pos):
		_selected.erase(pos)
	else:
		_selected[pos] = true
	selection_changed.emit()


func contains(pos: Vector3i) -> bool:
	return _selected.has(pos)


func clear() -> void:
	if not _selected.is_empty():
		_selected.clear()
		selection_changed.emit()


func is_empty() -> bool:
	return _selected.is_empty()


func size() -> int:
	return _selected.size()


func get_positions() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for pos in _selected:
		result.append(pos as Vector3i)
	return result


func get_bounding_box() -> AABB:
	if _selected.is_empty():
		return AABB()
	var first := true
	var min_pos := Vector3i.ZERO
	var max_pos := Vector3i.ZERO
	for pos in _selected:
		var p: Vector3i = pos
		if first:
			min_pos = p
			max_pos = p
			first = false
		else:
			min_pos.x = mini(min_pos.x, p.x)
			min_pos.y = mini(min_pos.y, p.y)
			min_pos.z = mini(min_pos.z, p.z)
			max_pos.x = maxi(max_pos.x, p.x)
			max_pos.y = maxi(max_pos.y, p.y)
			max_pos.z = maxi(max_pos.z, p.z)
	return AABB(Vector3(min_pos), Vector3(max_pos - min_pos + Vector3i.ONE))


## Replace entire selection with new positions.
func set_positions(positions: Array[Vector3i]) -> void:
	_selected.clear()
	for pos in positions:
		_selected[pos] = true
	selection_changed.emit()


## Invert selection within a bounding box (select unselected, deselect selected).
func invert(tile: WFCTileDef) -> void:
	var bb := get_bounding_box()
	if bb.size == Vector3.ZERO:
		return
	var min_p := Vector3i(int(bb.position.x), int(bb.position.y), int(bb.position.z))
	var max_p := min_p + Vector3i(int(bb.size.x), int(bb.size.y), int(bb.size.z))
	var new_sel: Dictionary = {}
	for x in range(min_p.x, max_p.x):
		for y in range(min_p.y, max_p.y):
			for z in range(min_p.z, max_p.z):
				var pos := Vector3i(x, y, z)
				if not _selected.has(pos) and tile.get_voxel(x, y, z) != 0:
					new_sel[pos] = true
	_selected = new_sel
	selection_changed.emit()
