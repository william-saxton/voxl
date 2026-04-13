class_name ExtrudeTool
extends RefCounted

## Click-and-drag extrude tool. Click a face to find connected surface voxels,
## then drag along the face normal to control how many layers to extrude.
##   ADD: duplicate the surface N layers outward
##   SUBTRACT: remove N layers from the surface inward
##   PAINT: repaint N layers of surface

var query := VoxelQuery.new()

## Extrude gesture state
var active := false
var surface: Array[Vector3i] = []
var face_dir := Vector3i.ZERO
var source_ids: Dictionary = {}  ## Vector3i surface pos → int voxel_id
var layers: int = 1
var _start_mouse_y: float = 0.0
var _face_screen_dir: float = 1.0  ## +1 or -1: whether dragging up = more layers

const PIXELS_PER_LAYER := 20


## Begin an extrude gesture. Finds the connected surface at pos.
## camera is needed to determine screen-space direction of face_dir.
func begin(tile: WFCTileDef, pos: Vector3i, face: Vector3i,
		camera: Camera3D, mouse_y: float) -> bool:
	var vid := tile.get_voxel(pos.x, pos.y, pos.z)
	if vid == 0:
		return false

	face_dir = face
	surface = query.find_surface(tile, pos, face)
	if surface.is_empty():
		return false

	# Cache source voxel IDs for duplication
	source_ids.clear()
	for spos in surface:
		source_ids[spos] = tile.get_voxel(spos.x, spos.y, spos.z)

	# Determine screen-space direction: does moving mouse up increase or decrease layers?
	var world_pos := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	var screen_start := camera.unproject_position(world_pos)
	var screen_end := camera.unproject_position(world_pos + Vector3(face))
	# Map screen-space face direction to mouse Y drag:
	# If face points up on screen (screen_end.y < screen_start.y, diff negative),
	# dragging mouse up (negative delta) should add layers → need negative × negative = positive
	_face_screen_dir = signf(screen_end.y - screen_start.y)
	if absf(screen_end.y - screen_start.y) < 2.0:
		# Face is nearly horizontal on screen — use X instead
		_face_screen_dir = signf(screen_end.x - screen_start.x)

	_start_mouse_y = mouse_y
	layers = 1
	active = true
	return true


## Update layer count from mouse drag.
func update_drag(mouse_y: float) -> void:
	if not active:
		return
	var delta := (mouse_y - _start_mouse_y) * _face_screen_dir
	layers = maxi(1, int(delta / PIXELS_PER_LAYER) + 1)


## Get preview positions for the current layer count and mode.
func get_preview(mode: int) -> Array[Vector3i]:
	if not active:
		return []
	match mode:
		0:  # ADD — show new layers outward
			return _get_add_targets()
		1:  # SUBTRACT — show layers to remove inward
			return _get_subtract_targets()
		2:  # PAINT — show surface layers to repaint
			return _get_subtract_targets()  # Same positions, different operation
	return []


## Commit and return results.
func commit(_tile: WFCTileDef, mode: int) -> Dictionary:
	active = false
	var result := {
		"targets": [] as Array[Vector3i],
		"voxel_ids": {},  # Vector3i → int (what to write at each target)
	}

	match mode:
		0:  # ADD
			var targets := _get_add_targets()
			result.targets = targets
			# Map each target back to its source surface voxel by layer
			for layer_i in layers:
				var offset := face_dir * (layer_i + 1)
				for spos in surface:
					var target := spos + offset
					if VoxelQuery._in_bounds(target) and source_ids.has(spos):
						result.voxel_ids[target] = source_ids[spos]
		1:  # SUBTRACT
			result.targets = _get_subtract_targets()
		2:  # PAINT
			result.targets = _get_subtract_targets()

	return result


func cancel() -> void:
	active = false
	surface.clear()
	source_ids.clear()


func _get_add_targets() -> Array[Vector3i]:
	var targets: Array[Vector3i] = []
	for layer_i in layers:
		var offset := face_dir * (layer_i + 1)
		for spos in surface:
			var target := spos + offset
			if VoxelQuery._in_bounds(target):
				targets.append(target)
	return targets


func _get_subtract_targets() -> Array[Vector3i]:
	## Remove N layers inward from the surface. Layer 0 = the surface itself,
	## layer 1 = one step opposite face_dir, etc.
	var targets: Array[Vector3i] = []
	for layer_i in layers:
		var offset := face_dir * -layer_i  # Inward
		for spos in surface:
			var target := spos + offset
			if VoxelQuery._in_bounds(target):
				targets.append(target)
	return targets
