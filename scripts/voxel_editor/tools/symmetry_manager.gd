class_name SymmetryManager
extends RefCounted

## Generates mirrored copies of voxel positions across enabled symmetry axes
## and custom mirror planes. Injected into EditorToolManager to make all
## operations (add, subtract, paint, select) automatically symmetric.

signal symmetry_changed

## Axis symmetry toggles — mirror across the tile midpoint along each axis.
var mirror_x: bool = false
var mirror_y: bool = false
var mirror_z: bool = false

## Custom mirror planes defined by the user.
## Each entry: { axis: Vector3, point: float }
## axis is a unit vector (only axis-aligned supported for voxel snapping),
## point is the world-space coordinate of the plane along that axis.
var custom_planes: Array[Dictionary] = []

## Tile dimensions — needed to compute midpoints for axis symmetry.
var tile_size := Vector3i(128, 112, 128)


func set_tile_size(sx: int, sy: int, sz: int) -> void:
	tile_size = Vector3i(sx, sy, sz)


func has_any_symmetry() -> bool:
	return mirror_x or mirror_y or mirror_z or not custom_planes.is_empty()


func toggle_x() -> void:
	mirror_x = not mirror_x
	symmetry_changed.emit()


func toggle_y() -> void:
	mirror_y = not mirror_y
	symmetry_changed.emit()


func toggle_z() -> void:
	mirror_z = not mirror_z
	symmetry_changed.emit()


func add_custom_plane(axis: Vector3i, point: float) -> void:
	custom_planes.append({ "axis": axis, "point": point })
	symmetry_changed.emit()


func remove_custom_plane(index: int) -> void:
	if index >= 0 and index < custom_planes.size():
		custom_planes.remove_at(index)
		symmetry_changed.emit()


func clear_custom_planes() -> void:
	custom_planes.clear()
	symmetry_changed.emit()


## Given an array of original positions, return an expanded array that includes
## all mirrored copies. Duplicates (positions that land on top of originals or
## other mirrors) are deduplicated.
func apply_symmetry(positions: Array[Vector3i]) -> Array[Vector3i]:
	if not has_any_symmetry():
		return positions

	# Use a set for deduplication
	var result_set := {}
	for pos in positions:
		result_set[pos] = true

	# Build list of mirror operations to apply combinatorially.
	# Each op is a callable that reflects a single position.
	var ops: Array[Callable] = []

	if mirror_x:
		var mid_x: float = tile_size.x / 2.0
		ops.append(func(p: Vector3i) -> Vector3i:
			return Vector3i(int(floorf(2.0 * mid_x - 1.0 - p.x)), p.y, p.z))
	if mirror_y:
		var mid_y: float = tile_size.y / 2.0
		ops.append(func(p: Vector3i) -> Vector3i:
			return Vector3i(p.x, int(floorf(2.0 * mid_y - 1.0 - p.y)), p.z))
	if mirror_z:
		var mid_z: float = tile_size.z / 2.0
		ops.append(func(p: Vector3i) -> Vector3i:
			return Vector3i(p.x, p.y, int(floorf(2.0 * mid_z - 1.0 - p.z))))

	for plane in custom_planes:
		var axis: Vector3i = plane["axis"]
		var pt: float = plane["point"]
		if axis == Vector3i(1, 0, 0):
			ops.append(func(p: Vector3i) -> Vector3i:
				return Vector3i(int(floorf(2.0 * pt - 1.0 - p.x)), p.y, p.z))
		elif axis == Vector3i(0, 1, 0):
			ops.append(func(p: Vector3i) -> Vector3i:
				return Vector3i(p.x, int(floorf(2.0 * pt - 1.0 - p.y)), p.z))
		elif axis == Vector3i(0, 0, 1):
			ops.append(func(p: Vector3i) -> Vector3i:
				return Vector3i(p.x, p.y, int(floorf(2.0 * pt - 1.0 - p.z))))

	# Apply all combinations of ops (2^N combos for N ops).
	# For each combo, apply the selected ops in sequence to each position.
	var n := ops.size()
	var combo_count := 1 << n  # 2^n

	for combo in range(1, combo_count):  # Skip 0 = identity (already in set)
		for pos in positions:
			var p := pos
			for bit in n:
				if combo & (1 << bit):
					p = ops[bit].call(p)
			result_set[p] = true

	var result: Array[Vector3i] = []
	for key in result_set:
		result.append(key as Vector3i)
	return result


## Mirror a single position (used for preview/hover highlight).
func mirror_positions(pos: Vector3i) -> Array[Vector3i]:
	var input: Array[Vector3i] = [pos]
	return apply_symmetry(input)


## Get all symmetry plane definitions for rendering.
## Returns array of { axis: String, position: float, is_custom: bool }
func get_plane_visuals() -> Array[Dictionary]:
	var planes: Array[Dictionary] = []
	if mirror_x:
		planes.append({ "axis": "x", "position": tile_size.x / 2.0, "is_custom": false })
	if mirror_y:
		planes.append({ "axis": "y", "position": tile_size.y / 2.0, "is_custom": false })
	if mirror_z:
		planes.append({ "axis": "z", "position": tile_size.z / 2.0, "is_custom": false })
	for plane in custom_planes:
		var axis: Vector3i = plane["axis"]
		var axis_str := "x" if axis.x != 0 else ("y" if axis.y != 0 else "z")
		planes.append({ "axis": axis_str, "position": plane["point"], "is_custom": true })
	return planes
