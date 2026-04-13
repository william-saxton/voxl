class_name WFCTileEditor
extends Node

## In-engine tile editing mode. Activates boundary markers and constrains
## editing tools to a tile-sized region. Works with the existing VoxelInteraction
## dig/place tools.

signal editing_started(origin: Vector3i, size_in_tiles: Vector2i)
signal editing_finished(tile: Resource)

var _terrain: Object
var _active: bool = false
var _origin := Vector3i.ZERO
var _size_in_tiles := Vector2i(1, 1)
var _boundary_markers: Array[Node3D] = []


func initialize(terrain: Object) -> void:
	_terrain = terrain


func start_editing(origin: Vector3i, size_in_tiles: Vector2i = Vector2i(1, 1)) -> void:
	_origin = origin
	_size_in_tiles = size_in_tiles
	_active = true
	_create_boundary_markers()
	editing_started.emit(origin, size_in_tiles)
	print("[WFCTileEditor] Editing started at %s (%dx%d tiles)" % [
		str(origin), size_in_tiles.x, size_in_tiles.y])


func stop_editing() -> void:
	_active = false
	_clear_boundary_markers()


func is_editing() -> bool:
	return _active


func get_origin() -> Vector3i:
	return _origin


func get_size_in_tiles() -> Vector2i:
	return _size_in_tiles


## Check if a world-voxel position is within the editing region.
func is_within_bounds(voxel_pos: Vector3i) -> bool:
	if not _active:
		return true  # No restriction when not editing
	var max_x := _origin.x + _size_in_tiles.x * WFCTileDef.TILE_X
	var max_y := _origin.y + WFCTileDef.TILE_Y
	var max_z := _origin.z + _size_in_tiles.y * WFCTileDef.TILE_Z
	return (voxel_pos.x >= _origin.x and voxel_pos.x < max_x
		and voxel_pos.y >= _origin.y and voxel_pos.y < max_y
		and voxel_pos.z >= _origin.z and voxel_pos.z < max_z)


## Export the current editing region as a tile or structure.
func export_current() -> Resource:
	if not _terrain:
		push_error("[WFCTileEditor] No terrain set")
		return null

	var result: Resource
	if _size_in_tiles == Vector2i(1, 1):
		result = WFCTileExporter.export_tile(_terrain, _origin)
	else:
		result = WFCTileExporter.export_structure(_terrain, _origin, _size_in_tiles)

	editing_finished.emit(result)
	return result


func _create_boundary_markers() -> void:
	_clear_boundary_markers()
	if not _terrain or not _terrain is Node3D:
		return

	var voxel_scale := MaterialRegistry.VOXEL_SCALE
	var world_origin := Vector3(_origin) * voxel_scale
	var region_w := float(_size_in_tiles.x * WFCTileDef.TILE_X) * voxel_scale
	var region_h := float(WFCTileDef.TILE_Y) * voxel_scale
	var region_d := float(_size_in_tiles.y * WFCTileDef.TILE_Z) * voxel_scale

	# Create 4 corner pillars using simple meshes
	var corners := [
		world_origin,
		world_origin + Vector3(region_w, 0, 0),
		world_origin + Vector3(region_w, 0, region_d),
		world_origin + Vector3(0, 0, region_d),
	]

	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.6)
	pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for corner in corners:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, region_h, 0.5)
		box.material = pillar_mat
		mesh_instance.mesh = box
		mesh_instance.position = corner + Vector3(0, region_h * 0.5, 0)
		(_terrain as Node3D).get_parent().add_child(mesh_instance)
		_boundary_markers.append(mesh_instance)


func _clear_boundary_markers() -> void:
	for marker in _boundary_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_boundary_markers.clear()
