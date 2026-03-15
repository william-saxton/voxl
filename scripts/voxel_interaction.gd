class_name VoxelInteraction
extends Node

@export var raycast_distance: float = 200.0

var _voxel_tool: VoxelTool
var _material_sim: MaterialSimulator
var _camera: Camera3D

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


func initialize(terrain: VoxelTerrain, material_sim: MaterialSimulator) -> void:
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_material_sim = material_sim


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
			_material_sim._wake_region(place_pos, 2)
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
