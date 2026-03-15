class_name VoxelWorldManager
extends Node

@export var voxel_terrain_path: NodePath
@export var player_path: NodePath

var _terrain: VoxelTerrain
var _player: Node3D
var _material_sim: MaterialSimulator
var _interaction: VoxelInteraction


func _ready() -> void:
	_terrain = get_node(voxel_terrain_path) as VoxelTerrain
	_player = get_node(player_path) as Node3D

	_setup_cube_materials()
	_setup_material_simulator()
	_setup_interaction()


func _setup_cube_materials() -> void:
	if not _terrain:
		return
	var mesher := _terrain.mesher as VoxelMesherBlocky
	if not mesher:
		return
	var library := mesher.library as VoxelBlockyLibrary
	if not library:
		return

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true

	var cube_ids: Array[int] = [
		MaterialRegistry.STONE,
		MaterialRegistry.BEDROCK,
		MaterialRegistry.DIRT,
		MaterialRegistry.MUD,
	]
	for voxel_id: int in cube_ids:
		var model := library.get_model(voxel_id)
		if model:
			model.set_material_override(0, mat)
	library.bake()


func _setup_material_simulator() -> void:
	_material_sim = MaterialSimulator.new()
	_material_sim.name = "MaterialSimulator"
	add_child(_material_sim)
	if _terrain:
		_material_sim.initialize(_terrain)


func _setup_interaction() -> void:
	_interaction = get_node_or_null("VoxelInteraction") as VoxelInteraction
	if not _interaction:
		_interaction = VoxelInteraction.new()
		_interaction.name = "VoxelInteraction"
		add_child(_interaction)
	if _terrain and _material_sim:
		_interaction.initialize(_terrain, _material_sim)


func get_material_simulator() -> MaterialSimulator:
	return _material_sim
