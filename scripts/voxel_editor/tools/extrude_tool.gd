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

## Ray-projection state — the clicked face defines a 3D line along face_dir
## that the mouse cursor is projected onto each frame.
var _line_corners: Array[Vector3] = []  ## AABB corners of the source face (world space)
var _line_dir: Vector3 = Vector3.ZERO   ## Unit vector along face_dir


## Begin an extrude gesture. Finds the connected surface at pos.
func begin(tile: WFCTileDef, pos: Vector3i, face: Vector3i,
		_camera: Camera3D, _mouse_y: float) -> bool:
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

	_recompute_line_state()
	layers = 1
	active = true
	return true


## Rebuild the projection line state from the current `surface`. Call this
## after the caller filters the surface (e.g. to a selection) so the
## drag projection anchors on the actual extrusion source.
func _recompute_line_state() -> void:
	_line_dir = Vector3(face_dir).normalized()
	if surface.is_empty():
		_line_corners = []
		return
	var face_offset := Vector3(face_dir) * 0.5
	var min_p := Vector3(surface[0])
	var max_p := min_p
	for spos in surface:
		var v := Vector3(spos)
		min_p.x = minf(min_p.x, v.x)
		min_p.y = minf(min_p.y, v.y)
		min_p.z = minf(min_p.z, v.z)
		max_p.x = maxf(max_p.x, v.x)
		max_p.y = maxf(max_p.y, v.y)
		max_p.z = maxf(max_p.z, v.z)
	min_p += Vector3(0.5, 0.5, 0.5) + face_offset
	max_p += Vector3(0.5, 0.5, 0.5) + face_offset
	_line_corners = [
		Vector3(min_p.x, min_p.y, min_p.z),
		Vector3(max_p.x, min_p.y, min_p.z),
		Vector3(min_p.x, max_p.y, min_p.z),
		Vector3(max_p.x, max_p.y, min_p.z),
		Vector3(min_p.x, min_p.y, max_p.z),
		Vector3(max_p.x, min_p.y, max_p.z),
		Vector3(min_p.x, max_p.y, max_p.z),
		Vector3(max_p.x, max_p.y, max_p.z),
	]


## Update layer count by projecting the mouse ray onto the extrusion line.
## Finds the closest point on the line through the face-AABB corner nearest the camera.
func update_drag_from_ray(camera: Camera3D, ray_origin: Vector3, ray_dir: Vector3,
		mouse_pos: Vector2) -> void:
	if not active or _line_corners.is_empty():
		return

	var cam_pos := camera.global_position
	var line_origin := _line_corners[0]
	var best_dist := cam_pos.distance_squared_to(line_origin)
	for i in range(1, _line_corners.size()):
		var d := cam_pos.distance_squared_to(_line_corners[i])
		if d < best_dist:
			best_dist = d
			line_origin = _line_corners[i]

	var w := line_origin - ray_origin
	var b := _line_dir.dot(ray_dir)
	var d_val := _line_dir.dot(w)
	var e := ray_dir.dot(w)
	var denom := 1.0 - b * b
	var t: float
	if absf(denom) < 0.0001:
		# Lines nearly parallel — fall back to screen-space projection
		var screen_base := camera.unproject_position(line_origin)
		var screen_tip := camera.unproject_position(line_origin + _line_dir)
		var screen_dir := screen_tip - screen_base
		var ppu := screen_dir.length()
		if ppu < 1.0:
			return
		var delta := mouse_pos - screen_base
		t = delta.dot(screen_dir / ppu) / ppu
	else:
		t = (b * e - d_val) / denom

	layers = maxi(1, int(roundf(t)))


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
