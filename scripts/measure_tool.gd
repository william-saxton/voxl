class_name MeasureTool
extends Node

var _camera: Camera3D
var _voxel_tool: VoxelTool
var _label: Label
var _line_instance: MeshInstance3D

var _point_a: Vector3i
var _has_point_a: bool = false


func initialize(terrain: VoxelTerrain) -> void:
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE


func _ready() -> void:
	_setup_hud()
	_setup_line_mesh()


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 11
	add_child(canvas)

	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 0.0
	_label.anchor_bottom = 0.0
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.text = "[M] Measure: aim at a voxel and press M to set Point A"
	canvas.add_child(_label)


func _setup_line_mesh() -> void:
	_line_instance = MeshInstance3D.new()
	_line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(_line_instance)


func _process(_delta: float) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_3d()


func _unhandled_input(event: InputEvent) -> void:
	if not _camera or not _voxel_tool:
		return
	if event.is_action_pressed("measure_tool"):
		_on_measure_pressed()
		get_viewport().set_input_as_handled()


func _on_measure_pressed() -> void:
	var result := _do_raycast()
	if not result:
		print("Measure: no voxel hit")
		return

	if not _has_point_a:
		_point_a = result.position
		_has_point_a = true
		_clear_line()
		_label.text = "[ MEASURE ]  Point A set: %s\n\nAim at Point B and press M" % [_point_a]
		print("Measure: Point A = voxel %s" % [_point_a])
	else:
		var point_b := result.position
		_has_point_a = false
		_draw_line(
			MaterialRegistry.voxel_to_world(_point_a),
			MaterialRegistry.voxel_to_world(point_b)
		)
		_show_measurement(_point_a, point_b)


func _show_measurement(a: Vector3i, b: Vector3i) -> void:
	var diff := b - a
	var voxel_dist := Vector3(diff).length()
	var world_diff := Vector3(diff) * MaterialRegistry.VOXEL_SCALE
	var world_dist := world_diff.length()

	var msg := "[ MEASURE ]  A: %s  →  B: %s\n" % [a, b]
	msg += "\n"
	msg += "  X axis:  %d voxels  (%.2f world units)\n" % [diff.x, world_diff.x]
	msg += "  Y axis:  %d voxels  (%.2f world units)\n" % [diff.y, world_diff.y]
	msg += "  Z axis:  %d voxels  (%.2f world units)\n" % [diff.z, world_diff.z]
	msg += "\n"
	msg += "  3D distance:  %.1f voxels  (%.2f world units)\n" % [voxel_dist, world_dist]
	msg += "\n"
	msg += "  Press M to start a new measurement"
	_label.text = msg
	print(msg)


func _draw_line(world_a: Vector3, world_b: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 0.0)
	mat.no_depth_test = true

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	mesh.surface_add_vertex(world_a)
	mesh.surface_add_vertex(world_b)
	mesh.surface_end()

	_line_instance.mesh = mesh


func _clear_line() -> void:
	_line_instance.mesh = null


func _do_raycast() -> VoxelRaycastResult:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)
	return _voxel_tool.raycast(ray_origin, ray_dir, 200.0)
