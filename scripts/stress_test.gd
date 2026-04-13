class_name StressTest
extends Node

const PHASE_DURATION := 5.0
const ESCALATION_INTERVAL := 2.0
const TICK_BUDGET_MS := 16.0
const MAX_DURATION := 120.0

var _material_sim: MaterialSimulatorNative
var _voxel_tool: VoxelTool
var _player: Node3D
var _running := false
var _elapsed := 0.0
var _phase := 0
var _escalation_timer := 0.0
var _spawn_origin := Vector3i.ZERO


func initialize(material_sim: MaterialSimulatorNative, terrain: VoxelTerrain, player: Node3D) -> void:
	_material_sim = material_sim
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_player = player


func toggle() -> void:
	_running = not _running
	if _running:
		_elapsed = 0.0
		_phase = 0
		_escalation_timer = 0.0
		if _player:
			var p := MaterialRegistry.world_to_voxel(_player.global_position)
			_spawn_origin = Vector3i(p.x + 80, 16, p.z + 80)
		print("[StressTest] STARTED - spawning around %s" % str(_spawn_origin))
	else:
		print("[StressTest] STOPPED")


func _physics_process(delta: float) -> void:
	if not _running or not _material_sim:
		return

	_elapsed += delta

	if _elapsed > MAX_DURATION:
		print("[StressTest] Time limit reached (%.0fs), stopping." % MAX_DURATION)
		_running = false
		return

	var tick_ms := _material_sim.get_last_tick_ms()
	if tick_ms > TICK_BUDGET_MS and _phase > 0:
		print("[StressTest] Tick budget exceeded (%.2f ms > %.0f ms) at phase %d, stopping." % [tick_ms, TICK_BUDGET_MS, _phase])
		_running = false
		return

	var target_phase := int(_elapsed / PHASE_DURATION)
	if target_phase > _phase:
		_phase = target_phase
		_run_phase(_phase)


func _run_phase(phase: int) -> void:
	match phase:
		1:
			_spawn_line(MaterialRegistry.WATER, _spawn_origin, Vector3i(2, 0, 0), 10)
			_log_phase("Phase 1: 10 water blocks in a line")
		2:
			_spawn_line(MaterialRegistry.ACID, _spawn_origin + Vector3i(0, 0, 60), Vector3i(2, 0, 0), 10)
			_log_phase("Phase 2: 10 acid blocks (parallel line, reactions)")
		3:
			_spawn_grid_at(MaterialRegistry.WATER, _spawn_origin + Vector3i(160, 0, 0), 5)
			_log_phase("Phase 3: 25 water blocks (5x5 grid)")
		4:
			_spawn_grid_at(MaterialRegistry.LAVA, _spawn_origin + Vector3i(160, 0, 60), 5)
			_log_phase("Phase 4: 25 lava blocks (5x5 grid, reactions)")
		_:
			_escalation_timer += PHASE_DURATION
			_run_escalation()


func _process(delta: float) -> void:
	if not _running or _phase < 5 or not _material_sim:
		return

	_escalation_timer += delta
	if _escalation_timer >= ESCALATION_INTERVAL:
		_escalation_timer -= ESCALATION_INTERVAL
		_run_escalation()


func _run_escalation() -> void:
	var batch := _phase - 4
	var fluid_ids: Array[int] = [MaterialRegistry.WATER, MaterialRegistry.ACID, MaterialRegistry.LAVA]
	var chosen: int = fluid_ids[batch % fluid_ids.size()]
	var origin := _spawn_origin + Vector3i(batch * 80, 0, 240)
	_spawn_random(chosen, origin, 10)
	_log_phase("Phase 5+: escalation batch %d, +10 blocks" % batch)


func _spawn_line(fluid_id: int, origin: Vector3i, step: Vector3i, count: int) -> void:
	for i in count:
		var pos := origin + step * i
		if _can_place(pos):
			_material_sim.place_fluid(pos, fluid_id)


func _spawn_grid_at(fluid_id: int, origin: Vector3i, size: int) -> void:
	for x in size:
		for z in size:
			var pos := origin + Vector3i(x * 3, 0, z * 3)
			if _can_place(pos):
				_material_sim.place_fluid(pos, fluid_id)


func _spawn_random(fluid_id: int, origin: Vector3i, count: int) -> void:
	for i in count:
		var pos := origin + Vector3i(randi_range(-60, 60), 0, randi_range(-60, 60))
		if _can_place(pos):
			_material_sim.place_fluid(pos, fluid_id)


func _can_place(pos: Vector3i) -> bool:
	var here := _voxel_tool.get_voxel(pos)
	var below := _voxel_tool.get_voxel(pos + Vector3i.DOWN)
	return here == MaterialRegistry.AIR and MaterialRegistry.is_solid(below)


func _log_phase(desc: String) -> void:
	var active := _material_sim.get_active_cell_count()
	var tick_ms := _material_sim.get_last_tick_ms()
	print("[StressTest] %s | Active: %d | Tick: %.2f ms" % [desc, active, tick_ms])
