class_name BrushShape
extends ShapeTool

## Brush tool that paints voxels by click-and-drag.
## Size controls the radius: 1 = single voxel, larger = sphere.
## Flat mode draws a circle (disk) instead of a sphere.

## Brush radius in voxels. 1 = single voxel, 2+ = sphere/circle of that radius.
var brush_size := 1

## When true, draws a flat circle on the clicked face plane instead of a sphere.
var flat := false

var _pos := Vector3i.ZERO


func _on_begin(pos: Vector3i) -> void:
	_pos = pos


func _on_update(pos: Vector3i) -> void:
	_pos = pos


func _on_commit() -> Array[Vector3i]:
	return _generate_brush(_pos)


func _on_get_preview() -> Array[Vector3i]:
	return _generate_brush(_pos)


func _generate_brush(center: Vector3i) -> Array[Vector3i]:
	if brush_size <= 1:
		return [center]

	var positions: Array[Vector3i] = []
	var r := brush_size - 1  # radius in voxels (size 2 = radius 1)
	var r_sq := r * r

	if flat:
		# Flat circle on the plane perpendicular to face_normal
		var abs_n := Vector3i(absi(face_normal.x), absi(face_normal.y), absi(face_normal.z))
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dz in range(-r, r + 1):
					# Only allow offsets perpendicular to face_normal
					var along_normal := dx * abs_n.x + dy * abs_n.y + dz * abs_n.z
					if along_normal != 0:
						continue
					if dx * dx + dy * dy + dz * dz <= r_sq:
						positions.append(center + Vector3i(dx, dy, dz))
	else:
		# Sphere
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if dx * dx + dy * dy + dz * dz <= r_sq:
						positions.append(center + Vector3i(dx, dy, dz))

	return positions
