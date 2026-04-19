class_name VoxelWorldManager
extends Node

@export var voxel_world_path: NodePath
@export var player_path: NodePath
## Optional: path to a WorldMap .res file. Disabled in Phase 3 — re-wired in a later phase.
@export_file("*.tres", "*.res") var world_map_path: String = ""

var _world: VoxelWorld
var _player: Node3D
var _material_sim: MaterialSimulatorNative
var _interaction: VoxelInteraction
var _hud: StressTestHUD
var _stress_test: StressTest
var _measure_tool: MeasureTool


var _terrain_ready_timer: float = 0.0
var _player_unfrozen: bool = false

func _ready() -> void:
	_world = get_node(voxel_world_path) as VoxelWorld
	_player = get_node(player_path) as Node3D

	_setup_material_simulator()
	_setup_hud()
	_setup_stress_test()
	_setup_interaction()
	_setup_measure_tool()


func _setup_material_simulator() -> void:
	if not _world:
		return
	_material_sim = MaterialSimulatorNative.new()
	_material_sim.name = "MaterialSimulator"
	add_child(_material_sim)
	_material_sim.initialize(_world.get_store(), _player)


func _process(delta: float) -> void:
	if _player_unfrozen:
		set_process(false)
		return

	_terrain_ready_timer += delta
	if _terrain_ready_timer < 2.0:
		return

	if _world and _player:
		var voxel_pos := MaterialRegistry.world_to_voxel(_player.global_position)
		var below := _world.get_voxel(Vector3i(voxel_pos.x, 15, voxel_pos.z))
		if below != MaterialRegistry.AIR:
			(_player as VoxelPlayer).terrain_ready = true
			_player_unfrozen = true
			set_process(false)


func _setup_hud() -> void:
	_hud = StressTestHUD.new()
	_hud.name = "StressTestHUD"
	var canvas := CanvasLayer.new()
	canvas.name = "HUDLayer"
	canvas.layer = 10
	add_child(canvas)
	canvas.add_child(_hud)
	if _material_sim:
		_hud.initialize(_material_sim)


func _setup_stress_test() -> void:
	_stress_test = StressTest.new()
	_stress_test.name = "StressTest"
	add_child(_stress_test)
	if _material_sim and _world:
		_stress_test.initialize(_material_sim, _world, _player)


func _setup_interaction() -> void:
	_interaction = get_node_or_null("VoxelInteraction") as VoxelInteraction
	if not _interaction:
		_interaction = VoxelInteraction.new()
		_interaction.name = "VoxelInteraction"
		add_child(_interaction)
	if _world:
		_interaction.initialize(_world, _material_sim, _player, _hud)


func _setup_measure_tool() -> void:
	_measure_tool = load("res://scripts/measure_tool.gd").new()
	_measure_tool.name = "MeasureTool"
	add_child(_measure_tool)
	if _world:
		_measure_tool.initialize(_world)


func get_material_simulator() -> MaterialSimulatorNative:
	return _material_sim
