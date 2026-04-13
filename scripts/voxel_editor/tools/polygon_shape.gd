class_name PolygonShape
extends ShapeTool

## Regular N-gon rasterized on the projection plane.
## Click 1 = center, Click 2 = radius point.
## Configurable number of sides.

var _center := Vector3i.ZERO
var _radius_pos := Vector3i.ZERO
var _plane_u: int
var _plane_v: int
var _plane_axis: int


func _init() -> void:
	requires_drag = true
	supports_height = true


func _on_begin(pos: Vector3i) -> void:
	_center = pos
	_radius_pos = pos
	_plane_axis = _dominant_axis(face_normal)
	match _plane_axis:
		0: _plane_u = 2; _plane_v = 1
		1: _plane_u = 0; _plane_v = 2
		_: _plane_u = 0; _plane_v = 1


func _on_update(pos: Vector3i) -> void:
	_radius_pos = pos


func _on_get_preview() -> Array[Vector3i]:
	return _polygon_positions()


func _on_commit() -> Array[Vector3i]:
	return _polygon_positions()


func _polygon_positions() -> Array[Vector3i]:
	var cu: int = _center[_plane_u]
	var cv: int = _center[_plane_v]
	var ru: int = _radius_pos[_plane_u]
	var rv: int = _radius_pos[_plane_v]
	var radius := Vector2(ru - cu, rv - cv).length()
	if radius < 0.5:
		return [_center]

	var fixed_val: int = _center[_plane_axis]

	# Build polygon vertices
	var verts: Array[Vector2] = []
	for i in sides:
		var angle := TAU * i / sides
		verts.append(Vector2(cu + radius * cos(angle), cv + radius * sin(angle)))

	if hollow:
		return _rasterize_outline(verts, fixed_val)
	else:
		return _rasterize_filled(verts, fixed_val)


func _rasterize_filled(verts: Array[Vector2], fixed: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	# Bounding box
	var min_u := int(floorf(verts[0].x))
	var max_u := int(ceilf(verts[0].x))
	var min_v := int(floorf(verts[0].y))
	var max_v := int(ceilf(verts[0].y))
	for v in verts:
		min_u = mini(min_u, int(floorf(v.x)))
		max_u = maxi(max_u, int(ceilf(v.x)))
		min_v = mini(min_v, int(floorf(v.y)))
		max_v = maxi(max_v, int(ceilf(v.y)))

	for u in range(min_u, max_u + 1):
		for v in range(min_v, max_v + 1):
			if _point_in_polygon(Vector2(u + 0.5, v + 0.5), verts):
				var pos := Vector3i.ZERO
				pos[_plane_u] = u
				pos[_plane_v] = v
				pos[_plane_axis] = fixed
				result.append(pos)

	return result


func _rasterize_outline(verts: Array[Vector2], fixed: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var seen := {}
	for i in verts.size():
		var a := verts[i]
		var b := verts[(i + 1) % verts.size()]
		# Rasterize edge using Bresenham in 2D
		var au := int(roundf(a.x))
		var av := int(roundf(a.y))
		var bu := int(roundf(b.x))
		var bv := int(roundf(b.y))
		var line := _bresenham_2d(au, av, bu, bv)
		for pt in line:
			if not seen.has(pt):
				seen[pt] = true
				var pos := Vector3i.ZERO
				pos[_plane_u] = pt.x
				pos[_plane_v] = pt.y
				pos[_plane_axis] = fixed
				result.append(pos)
	return result


static func _point_in_polygon(point: Vector2, verts: Array[Vector2]) -> bool:
	# Ray casting algorithm
	var inside := false
	var n := verts.size()
	var j := n - 1
	for i in n:
		var vi := verts[i]
		var vj := verts[j]
		if (vi.y > point.y) != (vj.y > point.y):
			var x_intersect := vi.x + (point.y - vi.y) / (vj.y - vi.y) * (vj.x - vi.x)
			if point.x < x_intersect:
				inside = not inside
		j = i
	return inside


static func _bresenham_2d(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x1 > x0 else -1
	var sy := 1 if y1 > y0 else -1
	var err := dx - dy
	var x := x0
	var y := y0
	while true:
		result.append(Vector2i(x, y))
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return result


static func _dominant_axis(normal: Vector3i) -> int:
	if absi(normal.x) >= absi(normal.y) and absi(normal.x) >= absi(normal.z):
		return 0
	elif absi(normal.y) >= absi(normal.z):
		return 1
	else:
		return 2
