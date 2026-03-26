class_name LineShape
extends ShapeTool

## 3D Bresenham line between two clicks.
## Shift = snap to nearest axis-aligned direction.

var _start := Vector3i.ZERO
var _end := Vector3i.ZERO


func _init() -> void:
	requires_drag = true


func _on_begin(pos: Vector3i) -> void:
	_start = pos
	_end = pos


func _on_update(pos: Vector3i) -> void:
	_end = _apply_shift(pos)


func _on_get_preview() -> Array[Vector3i]:
	return _bresenham_3d(_start, _end)


func _on_commit() -> Array[Vector3i]:
	return _bresenham_3d(_start, _end)


func _apply_shift(pos: Vector3i) -> Vector3i:
	if not Input.is_key_pressed(KEY_SHIFT):
		return pos
	# Snap to the axis with the largest delta
	var delta := pos - _start
	var ax := absi(delta.x)
	var ay := absi(delta.y)
	var az := absi(delta.z)
	if ax >= ay and ax >= az:
		return Vector3i(_start.x + delta.x, _start.y, _start.z)
	elif ay >= ax and ay >= az:
		return Vector3i(_start.x, _start.y + delta.y, _start.z)
	else:
		return Vector3i(_start.x, _start.y, _start.z + delta.z)


static func _bresenham_3d(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var dz := absi(to.z - from.z)
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var sz := 1 if to.z > from.z else -1

	var x := from.x
	var y := from.y
	var z := from.z

	# Dominant axis drives the loop
	if dx >= dy and dx >= dz:
		var ey := 2 * dy - dx
		var ez := 2 * dz - dx
		for _i in dx + 1:
			result.append(Vector3i(x, y, z))
			if ey > 0:
				y += sy
				ey -= 2 * dx
			if ez > 0:
				z += sz
				ez -= 2 * dx
			ey += 2 * dy
			ez += 2 * dz
			x += sx
	elif dy >= dx and dy >= dz:
		var ex := 2 * dx - dy
		var ez := 2 * dz - dy
		for _i in dy + 1:
			result.append(Vector3i(x, y, z))
			if ex > 0:
				x += sx
				ex -= 2 * dy
			if ez > 0:
				z += sz
				ez -= 2 * dy
			ex += 2 * dx
			ez += 2 * dz
			y += sy
	else:
		var ex := 2 * dx - dz
		var ey := 2 * dy - dz
		for _i in dz + 1:
			result.append(Vector3i(x, y, z))
			if ex > 0:
				x += sx
				ex -= 2 * dz
			if ey > 0:
				y += sy
				ey -= 2 * dz
			ex += 2 * dx
			ey += 2 * dy
			z += sz

	return result
