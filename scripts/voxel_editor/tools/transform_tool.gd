class_name TransformTool
extends RefCounted

## Interactive Move/Rotate/Scale for selected voxels.
## Move: click-drag or arrow keys to translate selection.
## Rotate: click-drag ring to rotate by arbitrary degrees. Shift snaps to 45°.
## Scale: click-drag cube handle to scale by integer factor.

enum TransformMode { MOVE, ROTATE, SCALE }
enum Constraint { FREE, AXIS_X, AXIS_Y, AXIS_Z, PLANE_XY, PLANE_XZ, PLANE_YZ }

var mode: TransformMode = TransformMode.MOVE
var active := false  ## Move drag active
var constraint: Constraint = Constraint.FREE

## Move state
var _drag_start := Vector3i.ZERO
var _drag_offset := Vector3i.ZERO
var _original_positions: Array[Vector3i] = []
var _original_voxels: Dictionary = {}  # Vector3i → int (voxel ID at original pos)
var _tile: WFCTileDef  # Reference to current tile for bounds/wrap

## Wrap mode: positions wrap around tile boundaries with posmod
var wrap := false

## Rotate state
var rotating := false
var _rotate_axis: int = 1  # 0=X, 1=Y, 2=Z
var _rotate_start_angle := 0.0
var _rotate_degrees := 0.0

## Scale state
var scaling := false
var _scale_start_dist := 1.0
var _scale_factor := 1.0


# ── Shared ──

func _capture_original(tile: WFCTileDef, sel: VoxelSelection) -> void:
	_tile = tile
	_original_positions = sel.get_positions().duplicate()
	_original_voxels.clear()
	for pos in _original_positions:
		_original_voxels[pos] = tile.get_voxel(pos.x, pos.y, pos.z)


func _get_center() -> Vector3:
	if _original_positions.is_empty():
		return Vector3.ZERO
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for pos in _original_positions:
		min_v = min_v.min(Vector3(pos))
		max_v = max_v.max(Vector3(pos) + Vector3.ONE)
	return (min_v + max_v) * 0.5


func cancel() -> void:
	active = false
	rotating = false
	scaling = false
	_original_positions.clear()
	_original_voxels.clear()


func is_any_active() -> bool:
	return active or rotating or scaling


# ── Move ──

func begin_move(tile: WFCTileDef, sel: VoxelSelection, start_pos: Vector3i) -> void:
	active = true
	_drag_start = start_pos
	_drag_offset = Vector3i.ZERO
	_capture_original(tile, sel)


func update_move(current_pos: Vector3i) -> void:
	if not active:
		return
	var raw := current_pos - _drag_start
	_drag_offset = _apply_constraint(raw)


func _apply_constraint(offset: Vector3i) -> Vector3i:
	match constraint:
		Constraint.AXIS_X:
			return Vector3i(offset.x, 0, 0)
		Constraint.AXIS_Y:
			return Vector3i(0, offset.y, 0)
		Constraint.AXIS_Z:
			return Vector3i(0, 0, offset.z)
		Constraint.PLANE_XY:
			return Vector3i(offset.x, offset.y, 0)
		Constraint.PLANE_XZ:
			return Vector3i(offset.x, 0, offset.z)
		Constraint.PLANE_YZ:
			return Vector3i(0, offset.y, offset.z)
	return offset  # FREE


func nudge(offset: Vector3i) -> void:
	_drag_offset += offset


func get_move_preview() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for pos in _original_positions:
		var new_pos := pos + _drag_offset
		if wrap:
			new_pos = _wrap_pos(new_pos)
		if _tile_in_bounds(new_pos):
			result.append(new_pos)
	return result


func commit_move(tile: WFCTileDef) -> Dictionary:
	active = false
	_tile = tile
	if _drag_offset == Vector3i.ZERO:
		return { "old_data": {}, "new_data": {} }

	var old_data: Dictionary = {}
	var new_data: Dictionary = {}
	var new_positions: Array[Vector3i] = []

	for pos in _original_positions:
		var new_pos := pos + _drag_offset
		if wrap:
			new_pos = _wrap_pos(new_pos)
		if _tile_in_bounds(new_pos):
			new_positions.append(new_pos)
			new_data[new_pos] = _original_voxels[pos]

	for pos in new_data:
		old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)
	for pos in _original_positions:
		if not old_data.has(pos):
			old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	return { "old_data": old_data, "new_data": new_data,
			"new_positions": new_positions,
			"clear_positions": _original_positions.duplicate() }


# ── Rotate ──

func begin_rotate(tile: WFCTileDef, sel: VoxelSelection, axis: int,
		start_angle: float) -> void:
	rotating = true
	_rotate_axis = axis
	_rotate_start_angle = start_angle
	_rotate_degrees = 0.0
	_capture_original(tile, sel)


func update_rotate(current_angle: float, snap: bool) -> void:
	if not rotating:
		return
	var delta := current_angle - _rotate_start_angle
	# Normalize to -180..180
	while delta > 180.0:
		delta -= 360.0
	while delta < -180.0:
		delta += 360.0
	if snap:
		delta = snapped(delta, 45.0)
	_rotate_degrees = delta


func get_rotate_preview() -> Array[Vector3i]:
	if _original_positions.is_empty() or absf(_rotate_degrees) < 0.01:
		return _original_positions.duplicate()

	var center := _get_center()
	var angle := deg_to_rad(_rotate_degrees)
	var ca := cos(angle)
	var sa := sin(angle)
	var result: Array[Vector3i] = []

	for pos in _original_positions:
		var rel := Vector3(pos) + Vector3(0.5, 0.5, 0.5) - center
		var rotated: Vector3
		match _rotate_axis:
			0:  # X axis
				rotated = Vector3(rel.x, rel.y * ca - rel.z * sa, rel.y * sa + rel.z * ca)
			1:  # Y axis
				rotated = Vector3(rel.x * ca + rel.z * sa, rel.y, -rel.x * sa + rel.z * ca)
			_:  # Z axis
				rotated = Vector3(rel.x * ca - rel.y * sa, rel.x * sa + rel.y * ca, rel.z)
		var new_pos := Vector3i(
			int(floorf(rotated.x + center.x)),
			int(floorf(rotated.y + center.y)),
			int(floorf(rotated.z + center.z)))
		if _tile_in_bounds(new_pos):
			result.append(new_pos)
	return result


func get_rotate_degrees() -> float:
	return _rotate_degrees


func get_rotate_axis() -> int:
	return _rotate_axis


# ── Scale ──

func begin_scale(tile: WFCTileDef, sel: VoxelSelection, start_dist: float) -> void:
	scaling = true
	_scale_start_dist = maxf(start_dist, 0.1)
	_scale_factor = 1.0
	_capture_original(tile, sel)


func update_scale(current_dist: float, snap: bool = true) -> void:
	if not scaling:
		return
	var raw := current_dist / _scale_start_dist
	if snap:
		# Snap to 0.25 increments (0.25, 0.5, 0.75, 1.0, 1.25, ..., 4.0)
		_scale_factor = maxf(0.25, snapped(raw, 0.25))
	else:
		_scale_factor = maxf(0.25, raw)


func get_scale_preview() -> Array[Vector3i]:
	if _original_positions.is_empty() or _scale_factor < 0.25:
		return []
	if is_equal_approx(_scale_factor, 1.0):
		return _original_positions.duplicate()

	var center := _get_center()
	var factor := _scale_factor
	var result: Array[Vector3i] = []
	var seen: Dictionary = {}

	# Compute the bounding box of original positions
	var bb_min := Vector3(INF, INF, INF)
	var bb_max := Vector3(-INF, -INF, -INF)
	for pos in _original_positions:
		bb_min = bb_min.min(Vector3(pos))
		bb_max = bb_max.max(Vector3(pos) + Vector3.ONE)

	# Scaled bounding box
	var scaled_size := (bb_max - bb_min) * factor
	var scaled_min := center - scaled_size * 0.5
	var scaled_max := center + scaled_size * 0.5

	# For each destination voxel, sample from source
	var sx := int(ceilf(scaled_max.x)) - int(floorf(scaled_min.x))
	var sy := int(ceilf(scaled_max.y)) - int(floorf(scaled_min.y))
	var sz := int(ceilf(scaled_max.z)) - int(floorf(scaled_min.z))
	for dx in sx:
		for dy in sy:
			for dz in sz:
				var dest := Vector3i(
					int(floorf(scaled_min.x)) + dx,
					int(floorf(scaled_min.y)) + dy,
					int(floorf(scaled_min.z)) + dz)
				if not _tile_in_bounds(dest):
					continue
				# Inverse map to source
				var src_f := (Vector3(dest) + Vector3(0.5, 0.5, 0.5) - center) / factor + center
				var src := Vector3i(int(floorf(src_f.x)), int(floorf(src_f.y)), int(floorf(src_f.z)))
				var vid: int = _original_voxels.get(src, 0)
				if vid != 0 and not seen.has(dest):
					seen[dest] = true
					result.append(dest)
	return result


func get_scale_factor() -> float:
	return _scale_factor


# ── Helpers ──

func _wrap_pos(pos: Vector3i) -> Vector3i:
	var sx: int = _tile.tile_size_x if _tile else WFCTileDef.TILE_X
	var sy: int = _tile.tile_size_y if _tile else WFCTileDef.TILE_Y
	var sz: int = _tile.tile_size_z if _tile else WFCTileDef.TILE_Z
	return Vector3i(posmod(pos.x, sx), posmod(pos.y, sy), posmod(pos.z, sz))


func _tile_in_bounds(pos: Vector3i) -> bool:
	if _tile:
		return pos.x >= 0 and pos.x < _tile.tile_size_x and \
				pos.y >= 0 and pos.y < _tile.tile_size_y and \
				pos.z >= 0 and pos.z < _tile.tile_size_z
	return VoxelQuery._in_bounds(pos)
