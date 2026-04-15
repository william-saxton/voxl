class_name EditorGrid
extends Node3D

## Renders a floor grid at y=0 and tile boundary wireframe.
## Supports variable tile dimensions and snap point overlays.

var _grid_mesh: MeshInstance3D
var _boundary_mesh: MeshInstance3D
var _snap_mesh: MeshInstance3D
var _ref_capsule: MeshInstance3D
var _floor_mesh: MeshInstance3D
var _tile_x: int = WFCTileDef.DEFAULT_TILE_X
var _tile_y: int = WFCTileDef.DEFAULT_TILE_Y
var _tile_z: int = WFCTileDef.DEFAULT_TILE_Z
var _snap_grid: int = 0
var _snap_center: bool = false
var _ref_visible := true
var _ref_height := 32.0  # Capsule total height in voxels
var _ref_radius := 8.0   # Capsule radius in voxels
var _ref_pos_x := 0.0    # Capsule position offset along X (voxels)
var _ref_pos_z := 0.0    # Capsule position offset along Z (voxels)
var _floor_visible := false
var _floor_depth := 32.0  # Depth below Y=0 in voxels (default: one player height)


func _ready() -> void:
	_build_floor_grid()
	_build_boundary()
	_build_ref_capsule()
	_build_floor_ghost()


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
	_build_snap_overlay()
	_build_floor_ghost()


## Update the snap point overlay. Call when snap settings change.
func set_snap(grid: int, center: bool) -> void:
	_snap_grid = grid
	_snap_center = center
	_build_snap_overlay()


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


## Toggle reference capsule visibility.
func set_ref_visible(vis: bool) -> void:
	_ref_visible = vis
	if _ref_capsule:
		_ref_capsule.visible = vis


## Update reference capsule dimensions and rebuild.
func set_ref_size(height: float, radius: float) -> void:
	_ref_height = height
	_ref_radius = radius
	_build_ref_capsule()


## Update reference capsule X/Z position (voxel coords, relative to tile origin).
func set_ref_position(x: float, z: float) -> void:
	_ref_pos_x = x
	_ref_pos_z = z
	if _ref_capsule:
		_ref_capsule.position = Vector3(x, _ref_height * 0.5, z)


## World-space AABB for hit-testing the capsule as a drag gizmo.
## Returns AABB() (empty) when the capsule is hidden.
func get_ref_aabb() -> AABB:
	if not _ref_visible or _ref_capsule == null:
		return AABB()
	var size := Vector3(_ref_radius * 2.0, _ref_height, _ref_radius * 2.0)
	var origin := Vector3(_ref_pos_x - _ref_radius, 0.0, _ref_pos_z - _ref_radius)
	return AABB(origin, size)


## Highlight the capsule while being dragged / hovered.
func set_ref_highlight(highlight: bool) -> void:
	if _ref_capsule == null:
		return
	var mesh := _ref_capsule.mesh as CapsuleMesh
	if mesh == null:
		return
	var mat := mesh.material as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = Color(0.4, 1.0, 0.6, 0.55) if highlight else Color(0.2, 0.9, 0.4, 0.35)


## Toggle Rift Delver floor ghost visibility.
func set_floor_visible(vis: bool) -> void:
	_floor_visible = vis
	_build_floor_ghost()


## Set floor ghost depth below Y=0, in voxels, and rebuild.
func set_floor_depth(d: float) -> void:
	_floor_depth = d
	_build_floor_ghost()


func _build_ref_capsule() -> void:
	if _ref_capsule:
		_ref_capsule.queue_free()
		_ref_capsule = null

	if not _ref_visible:
		return

	var capsule := CapsuleMesh.new()
	capsule.height = _ref_height
	capsule.radius = _ref_radius

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.4, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	capsule.material = mat

	_ref_capsule = MeshInstance3D.new()
	_ref_capsule.mesh = capsule
	_ref_capsule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Default offset: origin corner. User can move it via set_ref_position().
	if _ref_pos_x == 0.0 and _ref_pos_z == 0.0:
		_ref_pos_x = _ref_radius + 0.5
		_ref_pos_z = _ref_radius + 0.5
	_ref_capsule.position = Vector3(_ref_pos_x, _ref_height * 0.5, _ref_pos_z)
	add_child(_ref_capsule)


func _build_floor_ghost() -> void:
	if _floor_mesh:
		_floor_mesh.queue_free()
		_floor_mesh = null

	if not _floor_visible:
		return

	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.7, 0.2, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false

	# Show above the floor grid so the user can see the "fill to" height.
	var y := _floor_depth
	var w := float(_tile_x)
	var d := float(_tile_z)

	# Filled quad for the floor plane
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var face_color := Color(0.9, 0.7, 0.2, 0.15)
	for v in [
		Vector3(0, y, 0), Vector3(w, y, 0), Vector3(w, y, d),
		Vector3(0, y, 0), Vector3(w, y, d), Vector3(0, y, d),
	]:
		im.surface_set_color(face_color)
		im.surface_add_vertex(v)
	im.surface_end()

	# Outline + grid lines every 16 voxels so depth is readable
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.9, 0.7, 0.2, 0.6)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	im.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	var line_color := Color(0.9, 0.7, 0.2, 0.6)
	var sub_color := Color(0.9, 0.7, 0.2, 0.25)
	var step := 16
	var x := 0
	while x <= int(_tile_x):
		var c := line_color if (x == 0 or x == int(_tile_x)) else sub_color
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(float(x), y, 0.0))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(float(x), y, d))
		x += step
	var z := 0
	while z <= int(_tile_z):
		var c := line_color if (z == 0 or z == int(_tile_z)) else sub_color
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(0.0, y, float(z)))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(w, y, float(z)))
		z += step
	im.surface_end()

	_floor_mesh = MeshInstance3D.new()
	_floor_mesh.mesh = im
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_mesh)


func _build_snap_overlay() -> void:
	if _snap_mesh:
		_snap_mesh.queue_free()
		_snap_mesh = null

	if _snap_grid < 2:
		return

	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false

	var g := _snap_grid
	var half := g / 2
	var cross_size := 0.3
	var y_offset := 0.01  # Slight raise above floor grid

	# Snap grid lines — dashed appearance via shorter segments at snap intervals
	var edge_color := Color(0.2, 0.8, 1.0, 0.2)
	var center_color := Color(1.0, 0.6, 0.2, 0.2)
	var point_color := Color(0.2, 0.8, 1.0, 0.5) if not _snap_center else Color(1.0, 0.6, 0.2, 0.5)
	var line_color := edge_color if not _snap_center else center_color

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)

	# Draw grid lines at snap intervals
	var offset := half if _snap_center else 0
	var x := offset
	while x <= _tile_x:
		im.surface_set_color(line_color)
		im.surface_add_vertex(Vector3(float(x), y_offset, 0.0))
		im.surface_set_color(line_color)
		im.surface_add_vertex(Vector3(float(x), y_offset, float(_tile_z)))
		x += g

	var z := offset
	while z <= _tile_z:
		im.surface_set_color(line_color)
		im.surface_add_vertex(Vector3(0.0, y_offset, float(z)))
		im.surface_set_color(line_color)
		im.surface_add_vertex(Vector3(float(_tile_x), y_offset, float(z)))
		z += g

	# Draw cross markers at each snap intersection
	x = offset
	while x <= _tile_x:
		z = offset
		while z <= _tile_z:
			var px := float(x)
			var pz := float(z)
			# X-axis cross arm
			im.surface_set_color(point_color)
			im.surface_add_vertex(Vector3(px - cross_size, y_offset, pz))
			im.surface_set_color(point_color)
			im.surface_add_vertex(Vector3(px + cross_size, y_offset, pz))
			# Z-axis cross arm
			im.surface_set_color(point_color)
			im.surface_add_vertex(Vector3(px, y_offset, pz - cross_size))
			im.surface_set_color(point_color)
			im.surface_add_vertex(Vector3(px, y_offset, pz + cross_size))
			z += g
		x += g

	im.surface_end()

	_snap_mesh = MeshInstance3D.new()
	_snap_mesh.mesh = im
	_snap_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snap_mesh)
