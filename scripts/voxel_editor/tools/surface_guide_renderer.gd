class_name SurfaceGuideRenderer
extends MeshInstance3D

## Renders guide markers on hovered surfaces — a circle at the center
## and X marks at edge midpoints of the connected coplanar face region.

var _material: StandardMaterial3D
var _center_color := Color(1.0, 1.0, 0.2, 0.9)
var _midpoint_color := Color(1.0, 0.6, 0.2, 0.9)


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = true
	_material.render_priority = 11
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Update guide markers.
## markers: Dictionary with optional "center" (Vector3) and "edge_midpoints" (Array[Vector3]).
func update_guides(markers: Dictionary) -> void:
	if markers.is_empty():
		clear_guides()
		return

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _material)

	var center: Variant = markers.get("center")
	if center is Vector3:
		_draw_circle_marker(im, center, 0.45, _center_color)

	var midpoints: Variant = markers.get("edge_midpoints")
	if midpoints is Array:
		for point: Vector3 in midpoints:
			_draw_x_marker(im, point, 0.35, _midpoint_color)

	im.surface_end()
	mesh = im
	visible = true


func clear_guides() -> void:
	visible = false
	mesh = null


func _draw_circle_marker(im: ImmediateMesh, pos: Vector3, radius: float, col: Color) -> void:
	var segments := 16
	for plane in 3:
		for i in segments:
			var a0: float = TAU * i / segments
			var a1: float = TAU * (i + 1) / segments
			var p0 := pos
			var p1 := pos
			match plane:
				0:  # XY
					p0 += Vector3(cos(a0) * radius, sin(a0) * radius, 0)
					p1 += Vector3(cos(a1) * radius, sin(a1) * radius, 0)
				1:  # XZ
					p0 += Vector3(cos(a0) * radius, 0, sin(a0) * radius)
					p1 += Vector3(cos(a1) * radius, 0, sin(a1) * radius)
				2:  # YZ
					p0 += Vector3(0, cos(a0) * radius, sin(a0) * radius)
					p1 += Vector3(0, cos(a1) * radius, sin(a1) * radius)
			im.surface_set_color(col)
			im.surface_add_vertex(p0)
			im.surface_set_color(col)
			im.surface_add_vertex(p1)


func _draw_x_marker(im: ImmediateMesh, pos: Vector3, size: float, col: Color) -> void:
	for plane in 3:
		var d0 := Vector3.ZERO
		var d1 := Vector3.ZERO
		match plane:
			0:  # XY
				d0 = Vector3(size, size, 0)
				d1 = Vector3(size, -size, 0)
			1:  # XZ
				d0 = Vector3(size, 0, size)
				d1 = Vector3(size, 0, -size)
			2:  # YZ
				d0 = Vector3(0, size, size)
				d1 = Vector3(0, size, -size)
		im.surface_set_color(col)
		im.surface_add_vertex(pos - d0)
		im.surface_set_color(col)
		im.surface_add_vertex(pos + d0)
		im.surface_set_color(col)
		im.surface_add_vertex(pos - d1)
		im.surface_set_color(col)
		im.surface_add_vertex(pos + d1)
