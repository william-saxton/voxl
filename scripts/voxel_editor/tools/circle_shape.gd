class_name CircleShape
extends ShapeTool

## Midpoint circle on the projection plane defined by the first click's face normal.
## Click 1 = center, Click 2 = radius point.
## Shift = (no-op, circle is already circular).

var _center := Vector3i.ZERO
var _radius_pos := Vector3i.ZERO
var _plane_u: int  # First drawing axis index (0=X, 1=Y, 2=Z)
var _plane_v: int  # Second drawing axis index
var _plane_axis: int  # Normal axis index


func _init() -> void:
	requires_drag = true
	supports_height = true


func _on_begin(pos: Vector3i) -> void:
	_center = pos
	_radius_pos = pos
	# Determine drawing plane from face_normal
	_plane_axis = _dominant_axis(face_normal)
	match _plane_axis:
		0: _plane_u = 2; _plane_v = 1  # X normal → draw in ZY
		1: _plane_u = 0; _plane_v = 2  # Y normal → draw in XZ
		_: _plane_u = 0; _plane_v = 1  # Z normal → draw in XY


func _on_update(pos: Vector3i) -> void:
	_radius_pos = pos


func _on_get_preview() -> Array[Vector3i]:
	return _circle_positions()


func _on_commit() -> Array[Vector3i]:
	return _circle_positions()


func _circle_positions() -> Array[Vector3i]:
	var cu: int = _center[_plane_u]
	var cv: int = _center[_plane_v]
	var ru: int = _radius_pos[_plane_u]
	var rv: int = _radius_pos[_plane_v]
	var radius := int(roundf(Vector2(ru - cu, rv - cv).length()))
	if radius == 0:
		return [_center]

	var fixed_val: int = _center[_plane_axis]
	var result: Array[Vector3i] = []

	if hollow:
		_rasterize_circle_outline(cu, cv, radius, fixed_val, result)
	else:
		_rasterize_circle_filled(cu, cv, radius, fixed_val, result)

	return result


func _rasterize_circle_filled(cx: int, cy: int, r: int, fixed: int,
		out: Array[Vector3i]) -> void:
	var r_sq := r * r
	for du in range(-r, r + 1):
		for dv in range(-r, r + 1):
			if du * du + dv * dv <= r_sq:
				out.append(_make_pos(cx + du, cy + dv, fixed))


func _rasterize_circle_outline(cx: int, cy: int, r: int, fixed: int,
		out: Array[Vector3i]) -> void:
	# Midpoint circle algorithm
	var x := r
	var y := 0
	var err := 1 - r

	while x >= y:
		_add_octants(cx, cy, x, y, fixed, out)
		y += 1
		if err < 0:
			err += 2 * y + 1
		else:
			x -= 1
			err += 2 * (y - x) + 1


func _add_octants(cx: int, cy: int, x: int, y: int, fixed: int,
		out: Array[Vector3i]) -> void:
	var pts: Array[Vector2i] = [
		Vector2i(cx + x, cy + y), Vector2i(cx - x, cy + y),
		Vector2i(cx + x, cy - y), Vector2i(cx - x, cy - y),
		Vector2i(cx + y, cy + x), Vector2i(cx - y, cy + x),
		Vector2i(cx + y, cy - x), Vector2i(cx - y, cy - x),
	]
	# Deduplicate using a simple check
	var seen := {}
	for pt in pts:
		if not seen.has(pt):
			seen[pt] = true
			out.append(_make_pos(pt.x, pt.y, fixed))


func get_guide_markers() -> Dictionary:
	var center := Vector3(_center) + Vector3(0.5, 0.5, 0.5)
	return { "center": center }


func _make_pos(u_val: int, v_val: int, fixed_val: int) -> Vector3i:
	var pos := Vector3i.ZERO
	pos[_plane_u] = u_val
	pos[_plane_v] = v_val
	pos[_plane_axis] = fixed_val
	return pos


static func _dominant_axis(normal: Vector3i) -> int:
	if absi(normal.x) >= absi(normal.y) and absi(normal.x) >= absi(normal.z):
		return 0
	elif absi(normal.y) >= absi(normal.z):
		return 1
	else:
		return 2
