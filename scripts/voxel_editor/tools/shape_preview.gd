class_name ShapePreview
extends MultiMeshInstance3D

## Renders semi-transparent cubes at preview positions for shape tools.
## Uses MultiMesh for efficient instanced rendering.
## Also supports wireframe box mode for box selections.

const MAX_PREVIEW_VOXELS := 5000

var _material: StandardMaterial3D
var _current_positions: Array[Vector3i] = []
var _add_color := Color(0.3, 0.7, 1.0, 0.35)
var _subtract_color := Color(1.0, 0.3, 0.3, 0.35)
var _paint_color := Color(0.3, 1.0, 0.3, 0.35)

# Wireframe box rendering
var _wire_instance: MeshInstance3D
var _fill_instance: MeshInstance3D
var _wire_material: StandardMaterial3D
var _fill_material: StandardMaterial3D
var _wire_active := false


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true
	_material.albedo_color = _add_color

	# Create a unit cube mesh for instancing
	var cube := BoxMesh.new()
	cube.size = Vector3(0.98, 0.98, 0.98)  # Slightly inset to avoid z-fighting
	cube.material = _material

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cube
	multimesh.instance_count = 0

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

	# Wireframe box child — edges
	_wire_material = StandardMaterial3D.new()
	_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_material.albedo_color = Color(_add_color, 0.8)
	_wire_material.no_depth_test = true
	_wire_material.render_priority = 10
	_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_wire_instance = MeshInstance3D.new()
	_wire_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wire_instance.visible = false
	add_child(_wire_instance)

	# Wireframe box child — fill
	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.albedo_color = Color(_add_color, 0.3)
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_material.no_depth_test = true
	_fill_material.render_priority = 9
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_fill_instance = MeshInstance3D.new()
	_fill_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_instance.visible = false
	add_child(_fill_instance)



func set_preview_color(mode: int) -> void:
	# 0 = ADD, 1 = SUBTRACT, 2 = PAINT
	var col: Color
	match mode:
		0: col = _add_color
		1: col = _subtract_color
		2: col = _paint_color
		_: col = _add_color
	_material.albedo_color = col
	_wire_material.albedo_color = Color(col, 0.8)
	_fill_material.albedo_color = Color(col, 0.3)


func update_positions(positions: Array[Vector3i]) -> void:
	# Hide wireframe when using per-voxel mode
	_wire_active = false
	_wire_instance.visible = false
	_wire_instance.mesh = null
	_fill_instance.visible = false
	_fill_instance.mesh = null

	if positions.is_empty():
		visible = false
		multimesh.instance_count = 0
		_current_positions.clear()
		return

	var count := mini(positions.size(), MAX_PREVIEW_VOXELS)
	multimesh.instance_count = count
	for i in count:
		var pos := positions[i]
		# Offset by 0.5 so the cube is centered on the voxel
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY,
			Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5)))

	_current_positions = positions
	visible = true


## Show a wireframe box with translucent fill instead of per-voxel cubes.
## min_pos and max_pos are inclusive voxel coordinates.
func update_box_wireframe(min_pos: Vector3i, max_pos: Vector3i) -> void:
	# Hide per-voxel multimesh
	multimesh.instance_count = 0
	_wire_active = true

	var a := Vector3(min_pos)
	var b := Vector3(max_pos + Vector3i.ONE)

	var corners := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z),
		Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]

	# Edges
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]

	var edge_mesh := ImmediateMesh.new()
	edge_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	edge_mesh.surface_set_color(_wire_material.albedo_color)
	for edge in edges:
		edge_mesh.surface_add_vertex(corners[edge[0]])
		edge_mesh.surface_add_vertex(corners[edge[1]])
	edge_mesh.surface_end()
	edge_mesh.surface_set_material(0, _wire_material)
	_wire_instance.mesh = edge_mesh
	_wire_instance.visible = true

	# Filled faces
	var faces := [
		[0, 1, 2, 0, 2, 3],  # bottom
		[4, 6, 5, 4, 7, 6],  # top
		[0, 4, 5, 0, 5, 1],  # front
		[2, 6, 7, 2, 7, 3],  # back
		[0, 3, 7, 0, 7, 4],  # left
		[1, 5, 6, 1, 6, 2],  # right
	]

	var fill_mesh := ImmediateMesh.new()
	fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	fill_mesh.surface_set_color(_fill_material.albedo_color)
	for face in faces:
		for idx in face:
			fill_mesh.surface_add_vertex(corners[idx])
	fill_mesh.surface_end()
	fill_mesh.surface_set_material(0, _fill_material)
	_fill_instance.mesh = fill_mesh
	_fill_instance.visible = true

	visible = true


func clear() -> void:
	visible = false
	_wire_active = false
	_wire_instance.visible = false
	_wire_instance.mesh = null
	_fill_instance.visible = false
	_fill_instance.mesh = null
	multimesh.instance_count = 0
	_current_positions.clear()
