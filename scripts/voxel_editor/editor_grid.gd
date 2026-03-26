class_name EditorGrid
extends Node3D

## Renders a floor grid at y=0 and tile boundary wireframe.
## Supports variable tile dimensions.

var _grid_mesh: MeshInstance3D
var _boundary_mesh: MeshInstance3D
var _tile_x: int = WFCTileDef.DEFAULT_TILE_X
var _tile_y: int = WFCTileDef.DEFAULT_TILE_Y
var _tile_z: int = WFCTileDef.DEFAULT_TILE_Z


func _ready() -> void:
	_build_floor_grid()
	_build_boundary()


## Rebuild grid and boundary for new tile dimensions.
func set_tile_size(sx: int, sy: int, sz: int) -> void:
	if sx == _tile_x and sy == _tile_y and sz == _tile_z:
		return
	_tile_x = sx
	_tile_y = sy
	_tile_z = sz
	if _grid_mesh:
		_grid_mesh.queue_free()
	if _boundary_mesh:
		_boundary_mesh.queue_free()
	_build_floor_grid()
	_build_boundary()


func _build_floor_grid() -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)

	var grid_color := Color(0.5, 0.5, 0.5, 0.3)
	var sub_color := Color(0.4, 0.4, 0.4, 0.15)

	# Grid lines every 16 voxels
	var steps_x := _tile_x / 16 + 1
	var steps_z := _tile_z / 16 + 1

	for i in steps_x:
		var pos := float(i * 16)
		if pos > _tile_x:
			pos = float(_tile_x)
		var c := grid_color if (i == 0 or i == steps_x - 1) else sub_color

		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(pos, 0.0, 0.0))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(pos, 0.0, float(_tile_z)))

	for i in steps_z:
		var pos := float(i * 16)
		if pos > _tile_z:
			pos = float(_tile_z)
		var c := grid_color if (i == 0 or i == steps_z - 1) else sub_color

		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(0.0, 0.0, pos))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(float(_tile_x), 0.0, pos))

	im.surface_end()

	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.mesh = im
	_grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_mesh)


func _build_boundary() -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)

	var c := Color(1.0, 0.4, 0.2, 0.5)
	var w := float(_tile_x)
	var h := float(_tile_y)
	var d := float(_tile_z)

	var corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d),
		Vector3(0, h, 0), Vector3(w, h, 0), Vector3(w, h, d), Vector3(0, h, d),
	]

	var edges: Array[Vector2i] = [
		Vector2i(0,1), Vector2i(1,2), Vector2i(2,3), Vector2i(3,0),
		Vector2i(4,5), Vector2i(5,6), Vector2i(6,7), Vector2i(7,4),
		Vector2i(0,4), Vector2i(1,5), Vector2i(2,6), Vector2i(3,7),
	]

	for edge in edges:
		im.surface_set_color(c)
		im.surface_add_vertex(corners[edge.x])
		im.surface_set_color(c)
		im.surface_add_vertex(corners[edge.y])

	im.surface_end()

	_boundary_mesh = MeshInstance3D.new()
	_boundary_mesh.mesh = im
	_boundary_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_boundary_mesh)
