class_name VoxelInteraction
extends Node

@export var raycast_distance: float = 200.0

var _world: VoxelWorld
var _material_sim: MaterialSimulatorNative
var _camera: Camera3D
var _player: Node3D
var _hud: StressTestHUD

const SLOT_WATER := 0
const SLOT_LAVA := 1
const SLOT_ACID := 2
const SLOT_DIRT := 3
const SLOT_SAND := 4

var _placeable_ids: Array[int] = [
	MaterialRegistry.WATER,
	MaterialRegistry.LAVA,
	MaterialRegistry.ACID,
	MaterialRegistry.DIRT,
	MaterialRegistry.SAND,
]
var _selected_slot: int = SLOT_WATER

const SLOT_NAMES: Array[String] = ["Water", "Lava", "Acid", "Dirt", "Sand"]


func initialize(world: VoxelWorld, material_sim: MaterialSimulatorNative, player: Node3D = null, hud: StressTestHUD = null) -> void:
	_world = world
	_material_sim = material_sim
	_player = player
	_hud = hud


func _process(delta: float) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_3d()
	_run_stress_tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _world or not _camera:
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
	elif event.is_action_pressed("debug_spawn_sand"):
		_spawn_sand_cluster()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_reaction_stress"):
		_spawn_reaction_stress()
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
	if not _world or not _player:
		return
	var center_v := MaterialRegistry.world_to_voxel(_player.global_position) + offset
	center_v.y = 16
	var count := 0
	for x in range(-8, 9):
		for z in range(-8, 9):
			var pos := center_v + Vector3i(x, 0, z)
			var below := _world.get_voxel(pos + Vector3i.DOWN)
			if _world.get_voxel(pos) == MaterialRegistry.AIR and MaterialRegistry.is_solid(below):
				_world.set_voxel(pos, fluid_id)
				count += 1
	print("Spawned %d %s blocks" % [count, _fluid_name(fluid_id)])


var _stress_running := false
var _stress_phase := 0
var _stress_timer := 0.0
var _stress_total_spawned := 0
var _stress_base_offset := Vector3i.ZERO
const STRESS_PHASE_DURATION := 5.0
const STRESS_FPS_FLOOR := 20


func _run_stress_tick(delta: float) -> void:
	if not _stress_running:
		return
	_stress_timer += delta
	if _stress_timer < STRESS_PHASE_DURATION:
		return
	_stress_timer -= STRESS_PHASE_DURATION
	_stress_phase += 1
	_run_stress_phase(_stress_phase)

	var fps := Engine.get_frames_per_second()
	var tick_ms := 0.0
	if _material_sim:
		tick_ms = _material_sim.get_last_tick_ms()
	var changes := 0
	if _material_sim:
		changes = _material_sim.get_last_changes_count()
	var active := 0
	var store_node := _world.find_child("Store", false, false)
	if store_node:
		active = store_node.loaded_chunk_count()

	print("[STRESS P%d] fps=%d tick=%.1fms changes=%d spawned_total=%d active_chunks=%d"
			% [_stress_phase, fps, tick_ms, changes, _stress_total_spawned, active])

	if fps < STRESS_FPS_FLOOR and _stress_phase > 2:
		print("[STRESS] === HIT FLOOR at phase %d (fps=%d) — stopping ===" % [_stress_phase, fps])
		_stress_running = false


func _run_stress_phase(phase: int) -> void:
	var center := _stress_base_offset
	var positions := PackedInt32Array()
	var values := PackedInt32Array()

	# Each phase adds a new batch in a tight spiral around the base offset.
	var angle := phase * 2.39996  # golden angle in radians
	var radius := 20 + phase * 8
	var px := int(cos(angle) * radius)
	var pz := int(sin(angle) * radius)
	var origin := center + Vector3i(px, 16, pz)

	# Escalating sizes: phase 1 = 10x10, phase 2 = 15x15, etc.
	var half := mini(5 + phase * 3, 25)
	var height := mini(2 + phase, 10)

	# Alternate: even phases spawn water, odd spawn lava. Adjacent = reactions at borders.
	var mat_id: int
	if phase % 3 == 0:
		mat_id = MaterialRegistry.WATER
	elif phase % 3 == 1:
		mat_id = MaterialRegistry.LAVA
	else:
		mat_id = MaterialRegistry.SAND

	for x in range(-half, half + 1):
		for z in range(-half, half + 1):
			for y in range(0, height):
				var pos := origin + Vector3i(x, y, z)
				if _world.get_voxel(pos) != MaterialRegistry.AIR:
					continue
				positions.append(pos.x); positions.append(pos.y); positions.append(pos.z)
				values.append(mat_id)

	var placed := _world.set_voxels(positions, values)
	_stress_total_spawned += placed


func _spawn_reaction_stress() -> void:
	if _stress_running:
		print("[STRESS] === STOPPED (manual) at phase %d, total spawned: %d ===" % [_stress_phase, _stress_total_spawned])
		_stress_running = false
		return
	if not _world or not _player:
		return
	_stress_running = true
	_stress_phase = 0
	_stress_timer = STRESS_PHASE_DURATION  # trigger first phase immediately
	_stress_total_spawned = 0
	var player_v := MaterialRegistry.world_to_voxel(_player.global_position)
	_stress_base_offset = Vector3i(player_v.x + 30, 0, player_v.z + 30)
	print("[STRESS] === STARTED — press T again to stop ===")


func _spawn_sand_cluster() -> void:
	if not _world or not _player:
		return
	var center_v := MaterialRegistry.world_to_voxel(_player.global_position)
	center_v.y = 24
	var count := 0
	for i in range(8):
		var offset := Vector3i(randi_range(-3, 3), randi_range(0, 4), randi_range(-3, 3))
		var pos := center_v + offset
		if _world.get_voxel(pos) == MaterialRegistry.AIR:
			_world.set_voxel(pos, MaterialRegistry.SAND)
			count += 1
	print("Spawned %d sand blocks above player" % count)


func _clear_fluids_around_player() -> void:
	if not _world or not _player:
		return
	var center := MaterialRegistry.world_to_voxel(_player.global_position)
	var radius := 120
	var count := 0
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			for y in range(-20, 20):
				var pos := center + Vector3i(x, y, z)
				var voxel := _world.get_voxel(pos)
				if MaterialRegistry.is_simulatable(voxel):
					_world.set_voxel(pos, MaterialRegistry.AIR)
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
	if not _player or not _camera or not _world:
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
	projectile.initialize(_world, _material_sim, dir)
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
	var result: Variant = _do_raycast()
	if result == null:
		return

	var hit_pos: Vector3i = result.position
	var voxel: int = _world.get_voxel(hit_pos)
	if voxel == MaterialRegistry.BEDROCK:
		return

	_world.set_voxel(hit_pos, MaterialRegistry.AIR)


func _try_place() -> void:
	var result: Variant = _do_raycast()
	if result == null:
		return

	var place_pos: Vector3i = result.previous_position
	var existing: int = _world.get_voxel(place_pos)
	if existing != MaterialRegistry.AIR:
		return

	var mat_id: int = _placeable_ids[_selected_slot]
	_world.set_voxel(place_pos, mat_id)


func _do_raycast() -> Variant:
	if not _world:
		return null
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)

	return _world.raycast(ray_origin, ray_dir, raycast_distance)
