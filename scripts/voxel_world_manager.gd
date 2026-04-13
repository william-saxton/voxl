class_name VoxelWorldManager
extends Node

@export var voxel_terrain_path: NodePath
@export var player_path: NodePath
## Optional: path to a WorldMap .res file. If set, enables WFC generation.
@export_file("*.tres", "*.res") var world_map_path: String = ""

var _terrain: VoxelTerrain
var _player: Node3D
var _material_sim: MaterialSimulatorNative
var _interaction: VoxelInteraction
var _hud: StressTestHUD
var _stress_test: StressTest
var _measure_tool: MeasureTool
var _world_map: WorldMap
var _wfc_tiles: Dictionary = {}  # tile_id → WFCTileDef


var _terrain_ready_timer: float = 0.0
var _player_unfrozen: bool = false

func _ready() -> void:
	_terrain = get_node(voxel_terrain_path) as VoxelTerrain
	_player = get_node(player_path) as Node3D

	# Scale terrain so each voxel is 0.25 world units
	if _terrain:
		_terrain.transform = _terrain.transform.scaled_local(
			Vector3(MaterialRegistry.VOXEL_SCALE, MaterialRegistry.VOXEL_SCALE, MaterialRegistry.VOXEL_SCALE))

	_build_voxel_library()
	_setup_wfc()
	_setup_material_simulator()
	_setup_hud()
	_setup_stress_test()
	_setup_interaction()
	_setup_measure_tool()


func _process(delta: float) -> void:
	if _player_unfrozen:
		set_process(false)
		return

	# Poll until terrain has a solid block under the player
	_terrain_ready_timer += delta
	# Wait at least 2 seconds for meshes/collision to build
	if _terrain_ready_timer < 2.0:
		return

	if _terrain and _player:
		var tool := _terrain.get_voxel_tool()
		var voxel_pos := MaterialRegistry.world_to_voxel(_player.global_position)
		var below := tool.get_voxel(Vector3i(voxel_pos.x, 15, voxel_pos.z))
		if below != MaterialRegistry.AIR:
			(_player as VoxelPlayer).terrain_ready = true
			_player_unfrozen = true
			set_process(false)


func _build_voxel_library() -> void:
	if not _terrain:
		return
	var mesher := _terrain.mesher as VoxelMesherBlocky
	if not mesher:
		return

	var cube_mat := StandardMaterial3D.new()
	cube_mat.vertex_color_use_as_albedo = true

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.2, 0.4, 0.8, 0.6)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var lava_mat := StandardMaterial3D.new()
	lava_mat.albedo_color = Color(1.0, 0.3, 0.0, 0.9)
	lava_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lava_mat.emission_enabled = true
	lava_mat.emission = Color(1.0, 0.3, 0.0)
	lava_mat.emission_energy_multiplier = 2.0

	var acid_mat := StandardMaterial3D.new()
	acid_mat.albedo_color = Color(0.3, 0.9, 0.1, 0.6)
	acid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var gas_mat := StandardMaterial3D.new()
	gas_mat.albedo_color = Color(0.5, 0.7, 0.3, 0.3)
	gas_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

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

	# Index 3: WATER
	var water := VoxelBlockyModelCube.new()
	water.color = Color(0.2, 0.4, 0.8, 0.6)
	water.set_material_override(0, water_mat)
	water.transparency_index = 1
	models.append(water)

	# Index 4: DIRT
	var dirt := VoxelBlockyModelCube.new()
	dirt.color = Color(0.55, 0.35, 0.18)
	dirt.set_material_override(0, cube_mat)
	models.append(dirt)

	# Index 5: MUD
	var mud := VoxelBlockyModelCube.new()
	mud.color = Color(0.18, 0.12, 0.08)
	mud.set_material_override(0, cube_mat)
	models.append(mud)

	# Index 6: LAVA
	var lava := VoxelBlockyModelCube.new()
	lava.color = Color(1.0, 0.3, 0.0, 0.9)
	lava.set_material_override(0, lava_mat)
	lava.transparency_index = 2
	models.append(lava)

	# Index 7: ACID
	var acid := VoxelBlockyModelCube.new()
	acid.color = Color(0.3, 0.9, 0.1, 0.6)
	acid.set_material_override(0, acid_mat)
	acid.transparency_index = 3
	models.append(acid)

	# Index 8: GAS
	var gas := VoxelBlockyModelCube.new()
	gas.color = Color(0.5, 0.7, 0.3, 0.3)
	gas.set_material_override(0, gas_mat)
	gas.transparency_index = 4
	models.append(gas)

	var library := VoxelBlockyLibrary.new()
	library.models = models
	library.bake()
	mesher.library = library


func _setup_wfc() -> void:
	if not _terrain:
		return
	var generator: RiftVoxelGenerator = _terrain.generator as RiftVoxelGenerator
	if not generator:
		return

	# Load world map if a path is set, otherwise use starter tiles for testing
	if world_map_path != "":
		var loaded := ResourceLoader.load(world_map_path)
		if loaded is WorldMap:
			_world_map = loaded
		else:
			push_error("[VoxelWorldManager] Failed to load WorldMap: %s" % world_map_path)
			return
	else:
		# No world map — use starter tiles on a small test grid
		_world_map = WorldMap.new()
		_world_map.grid_width = 4
		_world_map.grid_height = 4

	var StarterTilesScript: Script = load("res://scripts/wfc/starter_tiles.gd")
	var tiles: Array[WFCTileDef] = StarterTilesScript.generate_all()

	# Register tiles with the solver and build lookup dict
	var solver: RefCounted = ClassDB.instantiate(&"WFCSolver")
	if not solver:
		push_warning("[VoxelWorldManager] WFCSolver not available (native not compiled), skipping WFC")
		return
	solver.call("set_grid_size", _world_map.grid_width, _world_map.grid_height)
	solver.call("set_biome_map", _world_map.cell_data, _world_map.grid_width)
	solver.call("set_seed", 42)

	if not _world_map.fixed_chunks.is_empty():
		solver.call("set_fixed_cells", _world_map.fixed_chunks)

	_wfc_tiles.clear()
	for i in tiles.size():
		var tile: WFCTileDef = tiles[i]
		var tile_id: int = i + 1  # 0 reserved for "no tile"
		solver.call("add_tile", tile_id, tile.edge_north, tile.edge_south,
			tile.edge_east, tile.edge_west, tile.weight, tile.biome)
		_wfc_tiles[tile_id] = tile

	var solved: bool = solver.call("solve")
	if solved:
		var layout: PackedInt32Array = solver.call("get_layout")
		generator.set_wfc_layout(layout, _world_map.grid_width,
			_world_map.grid_height, _wfc_tiles)
		print("[VoxelWorldManager] WFC solve succeeded (%dx%d)" % [
			_world_map.grid_width, _world_map.grid_height])
	else:
		push_warning("[VoxelWorldManager] WFC solve failed, using flat terrain")


func _setup_material_simulator() -> void:
	_material_sim = MaterialSimulatorNative.new()
	_material_sim.name = "MaterialSimulator"
	_material_sim.sim_radius = 7
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


func _setup_measure_tool() -> void:
	_measure_tool = load("res://scripts/measure_tool.gd").new()
	_measure_tool.name = "MeasureTool"
	add_child(_measure_tool)
	if _terrain:
		_measure_tool.initialize(_terrain)


func get_material_simulator() -> MaterialSimulatorNative:
	return _material_sim
