class_name VoxelInteraction
extends Node

@export var raycast_distance: float = 200.0

var _voxel_tool: VoxelTool
var _terrain: VoxelTerrain
var _material_sim: MaterialSimulatorNative
var _camera: Camera3D
var _player: Node3D
var _hud: StressTestHUD

const SLOT_WATER := 0
const SLOT_LAVA := 1
const SLOT_ACID := 2
const SLOT_DIRT := 3

var _fluid_ids: Array[int] = [
	MaterialRegistry.WATER,
	MaterialRegistry.LAVA,
	MaterialRegistry.ACID,
]
var _selected_slot: int = SLOT_WATER

const SLOT_NAMES: Array[String] = ["Water", "Lava", "Acid", "Dirt"]


func initialize(terrain: VoxelTerrain, material_sim: MaterialSimulatorNative, player: Node3D = null, hud: StressTestHUD = null) -> void:
	_terrain = terrain
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
		_spawn_grid(MaterialRegistry.WATER, Vector3i(0, 0, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_acid"):
		_spawn_grid(MaterialRegistry.ACID, Vector3i(80, 0, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_spawn_lava"):
		_spawn_grid(MaterialRegistry.LAVA, Vector3i(0, 0, 80))
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


func _spawn_grid(fluid_id: int, offset: Vector3i) -> void:
	if not _material_sim or not _player:
		return
	var center_v := MaterialRegistry.world_to_voxel(_player.global_position) + offset
	center_v.y = 16
	var count := 0
	for x in range(-8, 9):
		for z in range(-8, 9):
			var pos := center_v + Vector3i(x, 0, z)
			var below := _voxel_tool.get_voxel(pos + Vector3i.DOWN)
			if _voxel_tool.get_voxel(pos) == MaterialRegistry.AIR and MaterialRegistry.is_solid(below):
				_material_sim.place_fluid(pos, fluid_id)
				count += 1
	print("Spawned %d %s blocks" % [count, _fluid_name(fluid_id)])


func _clear_fluids_around_player() -> void:
	if not _material_sim or not _player:
		return
	var center := MaterialRegistry.world_to_voxel(_player.global_position)
	var radius := 120
	var count := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			for y in range(-20, 20):
				var pos := center + Vector3i(x, y, z)
				var voxel := _voxel_tool.get_voxel(pos)
				if MaterialRegistry.is_simulatable(voxel):
					_material_sim.remove_voxel(pos)
					count += 1
	print("Cleared %d fluid blocks" % count)


static func _fluid_name(id: int) -> String:
	if id == MaterialRegistry.WATER:
		return "Water"
	if id == MaterialRegistry.LAVA:
		return "Lava"
	if id == MaterialRegistry.ACID:
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
		var fluid_id: int = _fluid_ids[_selected_slot]
		if _material_sim:
			_material_sim.place_fluid(place_pos, fluid_id)
		else:
			_voxel_tool.set_voxel(place_pos, fluid_id)


func _do_raycast() -> VoxelRaycastResult:
	if not _terrain:
		return null
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)

	return _voxel_tool.raycast(ray_origin, ray_dir, raycast_distance)
