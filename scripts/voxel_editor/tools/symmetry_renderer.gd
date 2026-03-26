class_name SymmetryRenderer
extends Node3D

## Renders translucent planes in the 3D viewport to visualize active
## symmetry axes and custom mirror planes.

var _planes: Array[MeshInstance3D] = []
var _tile_size := Vector3i(128, 112, 128)

const AXIS_COLOR_X := Color(1.0, 0.3, 0.3, 0.15)
const AXIS_COLOR_Y := Color(0.3, 1.0, 0.3, 0.15)
const AXIS_COLOR_Z := Color(0.3, 0.3, 1.0, 0.15)
const CUSTOM_COLOR := Color(1.0, 0.8, 0.2, 0.15)

const AXIS_LINE_X := Color(1.0, 0.3, 0.3, 0.6)
const AXIS_LINE_Y := Color(0.3, 1.0, 0.3, 0.6)
const AXIS_LINE_Z := Color(0.3, 0.3, 1.0, 0.6)
const CUSTOM_LINE := Color(1.0, 0.8, 0.2, 0.6)


func set_tile_size(sx: int, sy: int, sz: int) -> void:
	_tile_size = Vector3i(sx, sy, sz)


func update_planes(plane_visuals: Array[Dictionary]) -> void:
	# Clear existing
	for p in _planes:
		p.queue_free()
	_planes.clear()

	for data in plane_visuals:
		var axis: String = data["axis"]
		var pos: float = data["position"]
		var is_custom: bool = data["is_custom"]

		var fill_color: Color
		var line_color: Color
		match axis:
			"x":
				fill_color = CUSTOM_COLOR if is_custom else AXIS_COLOR_X
				line_color = CUSTOM_LINE if is_custom else AXIS_LINE_X
			"y":
				fill_color = CUSTOM_COLOR if is_custom else AXIS_COLOR_Y
				line_color = CUSTOM_LINE if is_custom else AXIS_LINE_Y
			"z":
				fill_color = CUSTOM_COLOR if is_custom else AXIS_COLOR_Z
				line_color = CUSTOM_LINE if is_custom else AXIS_LINE_Z
			_:
				continue

		_create_plane(axis, pos, fill_color, line_color)


func _create_plane(axis: String, pos: float, fill_color: Color, line_color: Color) -> void:
	# Create a quad mesh for the plane fill
	var mesh_inst := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh_inst.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = fill_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 1

	var sx := float(_tile_size.x)
	var sy := float(_tile_size.y)
	var sz := float(_tile_size.z)

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)

	match axis:
		"x":
			# YZ plane at x=pos
			_add_quad(im, Vector3(pos, 0, 0), Vector3(pos, sy, 0),
				Vector3(pos, sy, sz), Vector3(pos, 0, sz))
		"y":
			# XZ plane at y=pos
			_add_quad(im, Vector3(0, pos, 0), Vector3(sx, pos, 0),
				Vector3(sx, pos, sz), Vector3(0, pos, sz))
		"z":
			# XY plane at z=pos
			_add_quad(im, Vector3(0, 0, pos), Vector3(sx, 0, pos),
				Vector3(sx, sy, pos), Vector3(0, sy, pos))

	im.surface_end()

	# Add wireframe border
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = line_color
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.no_depth_test = true
	line_mat.render_priority = 2

	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, line_mat)

	match axis:
		"x":
			im.surface_add_vertex(Vector3(pos, 0, 0))
			im.surface_add_vertex(Vector3(pos, sy, 0))
			im.surface_add_vertex(Vector3(pos, sy, sz))
			im.surface_add_vertex(Vector3(pos, 0, sz))
			im.surface_add_vertex(Vector3(pos, 0, 0))
		"y":
			im.surface_add_vertex(Vector3(0, pos, 0))
			im.surface_add_vertex(Vector3(sx, pos, 0))
			im.surface_add_vertex(Vector3(sx, pos, sz))
			im.surface_add_vertex(Vector3(0, pos, sz))
			im.surface_add_vertex(Vector3(0, pos, 0))
		"z":
			im.surface_add_vertex(Vector3(0, 0, pos))
			im.surface_add_vertex(Vector3(sx, 0, pos))
			im.surface_add_vertex(Vector3(sx, sy, pos))
			im.surface_add_vertex(Vector3(0, sy, pos))
			im.surface_add_vertex(Vector3(0, 0, pos))

	im.surface_end()

	add_child(mesh_inst)
	_planes.append(mesh_inst)


func _add_quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Triangle 1: a, b, c
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_add_vertex(c)
	# Triangle 2: a, c, d
	im.surface_add_vertex(a)
	im.surface_add_vertex(c)
	im.surface_add_vertex(d)
