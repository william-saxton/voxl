class_name BoxShape
extends ShapeTool

## AABB box between two clicks, with optional third click for height.
## Supports fill/hollow toggle. Shift = force square on the projection plane.

var _start := Vector3i.ZERO
var _end := Vector3i.ZERO


func _init() -> void:
	requires_drag = true
	supports_height = true


func _on_begin(pos: Vector3i) -> void:
	_start = pos
	_end = pos


func _on_update(pos: Vector3i) -> void:
	_end = _apply_shift(pos)


func _on_get_preview() -> Array[Vector3i]:
	return _box_positions(_start, _end, hollow)


func _on_commit() -> Array[Vector3i]:
	return _box_positions(_start, _end, hollow)


func _apply_shift(pos: Vector3i) -> Vector3i:
	if not Input.is_key_pressed(KEY_SHIFT):
		return pos
	# Force square on the projection plane (equal side lengths in the two drawing axes)
	var delta := pos - _start
	var max_d := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z)))
	return Vector3i(
		_start.x + max_d * signi(delta.x) if delta.x != 0 else _start.x,
		_start.y + max_d * signi(delta.y) if delta.y != 0 else _start.y,
		_start.z + max_d * signi(delta.z) if delta.z != 0 else _start.z,
	)


func get_guide_markers() -> Dictionary:
	var min_v := Vector3(
		mini(_start.x, _end.x), mini(_start.y, _end.y), mini(_start.z, _end.z))
	var max_v := Vector3(
		maxi(_start.x, _end.x), maxi(_start.y, _end.y), maxi(_start.z, _end.z))

	# If in height phase, extend along face_normal
	if in_height_phase():
		var offset := Vector3(face_normal) * _height
		var ext_min := Vector3(
			minf(min_v.x, min_v.x + offset.x),
			minf(min_v.y, min_v.y + offset.y),
			minf(min_v.z, min_v.z + offset.z))
		var ext_max := Vector3(
			maxf(max_v.x, max_v.x + offset.x),
			maxf(max_v.y, max_v.y + offset.y),
			maxf(max_v.z, max_v.z + offset.z))
		min_v = ext_min
		max_v = ext_max

	# Center point (offset by 0.5 to be in voxel center space)
	var center := (min_v + max_v) * 0.5 + Vector3(0.5, 0.5, 0.5)

	# Edge midpoints — midpoint of each of the 12 edges of the AABB
	var a0 := min_v + Vector3(0.5, 0.5, 0.5)
	var b0 := max_v + Vector3(0.5, 0.5, 0.5)
	var edge_mids: Array[Vector3] = []
	# Bottom face edges (y = a0.y)
	edge_mids.append(Vector3((a0.x + b0.x) * 0.5, a0.y, a0.z))  # bottom front
	edge_mids.append(Vector3((a0.x + b0.x) * 0.5, a0.y, b0.z))  # bottom back
	edge_mids.append(Vector3(a0.x, a0.y, (a0.z + b0.z) * 0.5))  # bottom left
	edge_mids.append(Vector3(b0.x, a0.y, (a0.z + b0.z) * 0.5))  # bottom right
	# Top face edges (y = b0.y)
	edge_mids.append(Vector3((a0.x + b0.x) * 0.5, b0.y, a0.z))
	edge_mids.append(Vector3((a0.x + b0.x) * 0.5, b0.y, b0.z))
	edge_mids.append(Vector3(a0.x, b0.y, (a0.z + b0.z) * 0.5))
	edge_mids.append(Vector3(b0.x, b0.y, (a0.z + b0.z) * 0.5))
	# Vertical edges
	edge_mids.append(Vector3(a0.x, (a0.y + b0.y) * 0.5, a0.z))
	edge_mids.append(Vector3(b0.x, (a0.y + b0.y) * 0.5, a0.z))
	edge_mids.append(Vector3(a0.x, (a0.y + b0.y) * 0.5, b0.z))
	edge_mids.append(Vector3(b0.x, (a0.y + b0.y) * 0.5, b0.z))

	# Remove duplicates (degenerate edges on flat boxes)
	var unique_mids: Array[Vector3] = []
	for m in edge_mids:
		var is_dup := false
		for u in unique_mids:
			if m.is_equal_approx(u) or m.is_equal_approx(center):
				is_dup = true
				break
		if not is_dup:
			unique_mids.append(m)

	return { "center": center, "edge_midpoints": unique_mids }


static func _box_positions(a: Vector3i, b: Vector3i, is_hollow: bool) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var min_x := mini(a.x, b.x)
	var max_x := maxi(a.x, b.x)
	var min_y := mini(a.y, b.y)
	var max_y := maxi(a.y, b.y)
	var min_z := mini(a.z, b.z)
	var max_z := maxi(a.z, b.z)

	# For hollow check, only consider axes that have extent > 0.
	# A flat box (e.g. min_y == max_y) should only check the 2 non-flat axes.
	var x_has_extent := max_x > min_x
	var y_has_extent := max_y > min_y
	var z_has_extent := max_z > min_z

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				if is_hollow:
					var on_edge := false
					if x_has_extent and (x == min_x or x == max_x):
						on_edge = true
					if y_has_extent and (y == min_y or y == max_y):
						on_edge = true
					if z_has_extent and (z == min_z or z == max_z):
						on_edge = true
					if on_edge:
						result.append(Vector3i(x, y, z))
				else:
					result.append(Vector3i(x, y, z))

	return result
