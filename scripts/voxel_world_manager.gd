class_name VoxelWorldManager
extends Node

@export var voxel_terrain_path: NodePath
@export var player_path: NodePath

var _terrain: VoxelTerrain
var _player: Node3D
var _material_sim: MaterialSimulatorNative
var _interaction: VoxelInteraction
var _hud: StressTestHUD
var _stress_test: StressTest


func _ready() -> void:
	_terrain = get_node(voxel_terrain_path) as VoxelTerrain
	_player = get_node(player_path) as Node3D

	_build_voxel_library()
	_setup_material_simulator()
	_setup_hud()
	_setup_stress_test()
	_setup_interaction()


func _build_voxel_library() -> void:
	if not _terrain:
		return
	var mesher := _terrain.mesher as VoxelMesherBlocky
	if not mesher:
		return

	var cube_mat := StandardMaterial3D.new()
	cube_mat.vertex_color_use_as_albedo = true

	var water_fluid: VoxelBlockyFluid = load("res://resources/water_fluid.tres")
	var lava_fluid: VoxelBlockyFluid = load("res://resources/lava_fluid.tres")
	var acid_fluid: VoxelBlockyFluid = load("res://resources/acid_fluid.tres")
	var gas_fluid: VoxelBlockyFluid = load("res://resources/toxic_gas_fluid.tres")

	var models: Array[VoxelBlockyModel] = []

	# Index 0: AIR
	models.append(VoxelBlockyModelEmpty.new())

	# Index 1: STONE
	var stone := VoxelBlockyModelCube.new()
	stone.color = Color(0.6, 0.58, 0.55)
	stone.set_material_override(0, cube_mat)
	models.append(stone)

	# Index 2: BEDROCK
	var bedrock := VoxelBlockyModelCube.new()
	bedrock.color = Color(0.25, 0.23, 0.22)
	bedrock.set_material_override(0, cube_mat)
	models.append(bedrock)

	# WATER levels (indices WATER_BASE .. WATER_BASE + FLUID_LEVELS - 1)
	for i in MaterialRegistry.FLUID_LEVELS:
		var m := VoxelBlockyModelFluid.new()
		m.fluid = water_fluid
		m.level = i
		m.transparency_index = 1
		models.append(m)

	# Index DIRT
	var dirt := VoxelBlockyModelCube.new()
	dirt.color = Color(0.55, 0.35, 0.18)
	dirt.set_material_override(0, cube_mat)
	models.append(dirt)

	# Index MUD
	var mud := VoxelBlockyModelCube.new()
	mud.color = Color(0.18, 0.12, 0.08)
	mud.set_material_override(0, cube_mat)
	models.append(mud)

	# LAVA levels
	for i in MaterialRegistry.FLUID_LEVELS:
		var m := VoxelBlockyModelFluid.new()
		m.fluid = lava_fluid
		m.level = i
		m.transparency_index = 2
		models.append(m)

	# ACID levels
	for i in MaterialRegistry.FLUID_LEVELS:
		var m := VoxelBlockyModelFluid.new()
		m.fluid = acid_fluid
		m.level = i
		m.transparency_index = 3
		models.append(m)

	# GAS levels (always full visual height)
	for i in MaterialRegistry.FLUID_LEVELS:
		var m := VoxelBlockyModelFluid.new()
		m.fluid = gas_fluid
		m.level = MaterialRegistry.FLUID_LEVELS - 1
		m.transparency_index = 4
		models.append(m)

	var library := VoxelBlockyLibrary.new()
	library.models = models
	library.bake()
	mesher.library = library


func _setup_material_simulator() -> void:
	_material_sim = MaterialSimulatorNative.new()
	_material_sim.name = "MaterialSimulator"
	add_child(_material_sim)
	if _terrain:
		_material_sim.initialize(_terrain, _player)


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
	if _material_sim and _terrain:
		_stress_test.initialize(_material_sim, _terrain, _player)


func _setup_interaction() -> void:
	_interaction = get_node_or_null("VoxelInteraction") as VoxelInteraction
	if not _interaction:
		_interaction = VoxelInteraction.new()
		_interaction.name = "VoxelInteraction"
		add_child(_interaction)
	if _terrain and _material_sim:
		_interaction.initialize(_terrain, _material_sim, _player, _hud)


func get_material_simulator() -> MaterialSimulatorNative:
	return _material_sim
