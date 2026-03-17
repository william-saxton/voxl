class_name VoxelInteraction
extends Node

@export var raycast_distance: float = 200.0

var _voxel_tool: VoxelTool
var _material_sim: MaterialSimulatorNative
var _camera: Camera3D
var _player: Node3D
var _hud: StressTestHUD

const SLOT_WATER := 0
const SLOT_LAVA := 1
const SLOT_ACID := 2
const SLOT_DIRT := 3

var _fluid_bases: Array[int] = [
	MaterialRegistry.WATER_BASE,
	MaterialRegistry.LAVA_BASE,
	MaterialRegistry.ACID_BASE,
]
var _selected_slot: int = SLOT_WATER

const SLOT_NAMES: Array[String] = ["Water", "Lava", "Acid", "Dirt"]


func initialize(terrain: VoxelTerrain, material_sim: MaterialSimulatorNative, player: Node3D = null, hud: StressTestHUD = null) -> void:
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_material_sim = material_sim
	_player = player
	_hud = hud


func _process(_delta: float) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_3d()


func _unhandled_input(event: InputEvent) -> void:
	if not _voxel_tool or not _camera:
		return

	if event.is_action_pressed("interact_primary"):
		_try_dig()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact_secondary"):
		_try_place()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_fluid_1"):
		_selected_slot = SLOT_WATER
		print("Selected: Water")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_fluid_2"):
		_selected_slot = SLOT_LAVA
		print("Selected: Lava")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_fluid_3"):
		_selected_slot = SLOT_ACID
		print("Selected: Acid")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_fluid_4"):
		_selected_slot = SLOT_DIRT
		print("Selected: Dirt")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_water"):
		_spawn_grid(MaterialRegistry.WATER_BASE, Vector3i(0, 0, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_acid"):
		_spawn_grid(MaterialRegistry.ACID_BASE, Vector3i(20, 0, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_lava"):
		_spawn_grid(MaterialRegistry.LAVA_BASE, Vector3i(0, 0, 20))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_clear"):
		_clear_fluids_around_player()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fire_projectile"):
		_fire_projectile()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_toggle_hud"):
		if _hud:
			_hud.visible = not _hud.visible
		get_viewport().set_input_as_handled()


func _spawn_grid(fluid_base: int, offset: Vector3i) -> void:
	if not _material_sim or not _player:
		return
	var center := Vector3i(_player.global_position) + offset
	center.y = 1
	var count := 0
	for x in range(-2, 3):
		for z in range(-2, 3):
			var pos := center + Vector3i(x * 3, 0, z * 3)
			var below := _voxel_tool.get_voxel(pos + Vector3i.DOWN)
			if _voxel_tool.get_voxel(pos) == MaterialRegistry.AIR and MaterialRegistry.is_solid(below):
				_material_sim.place_fluid(pos, fluid_base)
				count += 1
	print("Spawned %d %s sources" % [count, _fluid_name(fluid_base)])


func _clear_fluids_around_player() -> void:
	if not _material_sim or not _player:
		return
	var center := Vector3i(_player.global_position)
	var radius := 30
	var count := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			for y in range(-5, 5):
				var pos := center + Vector3i(x, y, z)
				var voxel := _voxel_tool.get_voxel(pos)
				if MaterialRegistry.is_simulatable(voxel):
					_material_sim.remove_voxel(pos)
					count += 1
	print("Cleared %d fluid blocks" % count)


static func _fluid_name(base: int) -> String:
	if base == MaterialRegistry.WATER_BASE:
		return "Water"
	if base == MaterialRegistry.LAVA_BASE:
		return "Lava"
	if base == MaterialRegistry.ACID_BASE:
		return "Acid"
	return "Unknown"


func _fire_projectile() -> void:
	if not _player or not _camera or not _material_sim:
		return

	var ground_pos: Variant = _get_mouse_ground_position()
	if ground_pos == null:
		return

	var dir := (ground_pos as Vector3 - _player.global_position)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var projectile := BlackHoleProjectile.new()
	projectile.global_position = _player.global_position + Vector3(0, 2, 0)
	projectile.initialize(_voxel_tool, _material_sim, dir)
	get_tree().current_scene.add_child(projectile)


func _get_mouse_ground_position() -> Variant:
	var mouse_pos := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse_pos)
	var direction := _camera.project_ray_normal(mouse_pos)
	if abs(direction.y) < 0.001:
		return null
	var t := (_player.global_position.y - origin.y) / direction.y
	if t < 0.0:
		return null
	return origin + direction * t


func _try_dig() -> void:
	var result := _do_raycast()
	if not result:
		return

	var voxel := _voxel_tool.get_voxel(result.position)
	if voxel == MaterialRegistry.BEDROCK:
		return

	if _material_sim:
		_material_sim.remove_voxel(result.position)
	else:
		_voxel_tool.set_voxel(result.position, MaterialRegistry.AIR)


func _try_place() -> void:
	var result := _do_raycast()
	if not result:
		return

	var place_pos := result.previous_position
	var existing := _voxel_tool.get_voxel(place_pos)
	if existing != MaterialRegistry.AIR:
		return

	if _selected_slot == SLOT_DIRT:
		_voxel_tool.set_voxel(place_pos, MaterialRegistry.DIRT)
		if _material_sim:
			_material_sim.sync_voxel(place_pos, MaterialRegistry.DIRT)
	else:
		var base: int = _fluid_bases[_selected_slot]
		if _material_sim:
			_material_sim.place_fluid(place_pos, base)
		else:
			_voxel_tool.set_voxel(place_pos, MaterialRegistry.fluid_id(base, MaterialRegistry.FLUID_LEVELS - 1))


func _do_raycast() -> VoxelRaycastResult:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)
	return _voxel_tool.raycast(ray_origin, ray_dir, raycast_distance)
