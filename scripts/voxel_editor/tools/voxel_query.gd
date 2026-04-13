class_name VoxelQuery
extends RefCounted

## Shared query mechanism for finding connected voxels.
## Used by Fill, Extrude, and Select tools.
##
## Two orthogonal settings:
##   connectivity: GEOMETRY (3D flood fill) or FACE (only voxels sharing an exposed face)
##   filter_color / filter_material: additional filters layered on top

enum Connectivity {
	GEOMETRY,  ## Any non-air, 6-connected
	FACE,      ## Must share an exposed face in a specific direction
}

const DEFAULT_RANGE := 64
const MAX_FILL_VOXELS := 100000
const NEIGHBORS_6: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Native backend (set by TileRenderer at startup)
static var native: RefCounted  # VoxelEditorNative when available

var connectivity: Connectivity = Connectivity.GEOMETRY
var filter_color := false    ## When true, must match full voxel_id
var filter_material := false ## When true, must match base_material (id & 0xFF)
var search_range: int = DEFAULT_RANGE


## Check if a voxel at pos matches the reference voxel_id based on active filters.
## With no filters enabled, any non-air voxel matches.
func matches(tile: WFCTileDef, pos: Vector3i, ref_id: int) -> bool:
	var vid := tile.get_voxel(pos.x, pos.y, pos.z)
	if vid == 0:
		return false
	if filter_color and vid != ref_id:
		return false
	if filter_material and (vid & 0xFF) != (ref_id & 0xFF):
		return false
	return true


## Check if a position matches "air" (for fill-air mode).
static func is_air(tile: WFCTileDef, pos: Vector3i) -> bool:
	return tile.get_voxel(pos.x, pos.y, pos.z) == 0


## Flood fill from start, finding all connected voxels that match.
## Uses connectivity mode: GEOMETRY does simple 6-connected BFS,
## FACE requires each voxel to have an exposed face in face_dir.
func flood_fill(tile: WFCTileDef, start: Vector3i,
		face_dir := Vector3i.ZERO) -> Array[Vector3i]:
	var ref_id := tile.get_voxel(start.x, start.y, start.z)
	if ref_id == 0:
		return []

	# FACE mode requires a face direction
	if connectivity == Connectivity.FACE and face_dir == Vector3i.ZERO:
		return []

	# For FACE mode, verify start has an exposed face
	if connectivity == Connectivity.FACE:
		var check := start + face_dir
		if _in_bounds_tile(check, tile) and not is_air(tile, check):
			return []

	# Use C++ native backend if available
	if native:
		var criteria := _get_native_criteria()
		var packed: PackedVector3Array
		if connectivity == Connectivity.FACE:
			packed = native.find_surface(tile.voxel_data, start, face_dir,
					criteria, search_range, MAX_FILL_VOXELS,
					tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
		else:
			packed = native.flood_fill(tile.voxel_data, start,
					criteria, search_range, MAX_FILL_VOXELS,
					tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
		var typed: Array[Vector3i] = []
		typed.resize(packed.size())
		for i in packed.size():
			typed[i] = Vector3i(packed[i])
		return typed

	var result: Array[Vector3i] = []
	var visited := {}
	var queue: Array[Vector3i] = [start]
	visited[start] = true

	while not queue.is_empty():
		var pos: Vector3i = queue.pop_front()
		result.append(pos)

		if result.size() >= MAX_FILL_VOXELS:
			break

		for offset in NEIGHBORS_6:
			var neighbor := pos + offset
			if visited.has(neighbor):
				continue
			if not _in_bounds_tile(neighbor, tile):
				continue
			if not _in_range(start, neighbor):
				continue
			if not matches(tile, neighbor, ref_id):
				continue
			# FACE mode: neighbor must also have an exposed face in face_dir
			if connectivity == Connectivity.FACE:
				var neighbor_check := neighbor + face_dir
				if _in_bounds_tile(neighbor_check, tile) and not is_air(tile, neighbor_check):
					continue
			visited[neighbor] = true
			queue.append(neighbor)

	return result


## Pour fill — fills air like pouring water into a container.
## 1. Scans down from start to find the floor.
## 2. At each Y level going up, does a 2D (XZ) flood fill.
## 3. If a level is enclosed (bounded by walls / tile boundary), fills it.
## 4. If a level overflows (air extends beyond range), stops — that's the rim.
## Tile boundaries count as solid walls.
func pour_fill(tile: WFCTileDef, start: Vector3i) -> Array[Vector3i]:
	if not _in_bounds_tile(start, tile):
		return []

	var start_xz := Vector2i(start.x, start.z)

	# Scan down to find the floor (first solid below start, or tile bottom)
	var floor_y := start.y
	while floor_y > 0 and is_air(tile, Vector3i(start.x, floor_y - 1, start.z)):
		floor_y -= 1

	# Fill level by level from floor upward
	var result: Array[Vector3i] = []
	for y in range(floor_y, tile.tile_size_y):
		var level := _flood_fill_2d_enclosed(tile, start_xz, y)
		if level.is_empty():
			break  # This level is open or solid at start — stop (rim reached)
		for p in level:
			result.append(Vector3i(p.x, y, p.y))
		if result.size() >= MAX_FILL_VOXELS:
			break

	return result


## 2D flood fill at a specific Y level in the XZ plane.
## Returns the enclosed air positions, or empty if the region overflows
## (air extends beyond search_range from start — means no wall on that side).
## Tile boundaries are treated as solid walls.
func _flood_fill_2d_enclosed(tile: WFCTileDef, start_xz: Vector2i,
		y: int) -> Array[Vector2i]:
	# Start position must be air at this level
	if not is_air(tile, Vector3i(start_xz.x, y, start_xz.y)):
		return []

	var result: Array[Vector2i] = []
	var visited := {}
	var queue: Array[Vector2i] = [start_xz]
	visited[start_xz] = true

	const DIRS_4: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]

	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		result.append(p)

		if result.size() >= MAX_FILL_VOXELS:
			return []  # Too large — treat as open

		for dir in DIRS_4:
			var np := p + dir
			if visited.has(np):
				continue
			visited[np] = true
			# Tile boundary = wall
			if np.x < 0 or np.x >= tile.tile_size_x or \
					np.y < 0 or np.y >= tile.tile_size_z:
				continue
			# Range check — if air extends beyond range, this level is open
			if absi(np.x - start_xz.x) > search_range or \
					absi(np.y - start_xz.y) > search_range:
				return []  # Overflow — rim reached
			if is_air(tile, Vector3i(np.x, y, np.y)):
				queue.append(np)

	return result


## Find connected surface voxels that share an exposed face in the given direction.
## This is a convenience wrapper that temporarily sets FACE connectivity.
func find_surface(tile: WFCTileDef, start: Vector3i, face_dir: Vector3i) -> Array[Vector3i]:
	var old_conn := connectivity
	connectivity = Connectivity.FACE
	var result := flood_fill(tile, start, face_dir)
	connectivity = old_conn
	return result


## Chebyshev distance range check (cube-shaped, not diamond-shaped).
func _in_range(start: Vector3i, pos: Vector3i) -> bool:
	return absi(pos.x - start.x) <= search_range and \
			absi(pos.y - start.y) <= search_range and \
			absi(pos.z - start.z) <= search_range


static func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < WFCTileDef.TILE_X and \
			pos.y >= 0 and pos.y < WFCTileDef.TILE_Y and \
			pos.z >= 0 and pos.z < WFCTileDef.TILE_Z


static func _in_bounds_tile(pos: Vector3i, tile: WFCTileDef) -> bool:
	return pos.x >= 0 and pos.x < tile.tile_size_x and \
			pos.y >= 0 and pos.y < tile.tile_size_y and \
			pos.z >= 0 and pos.z < tile.tile_size_z


## Map filter_color/filter_material to native criteria int.
## 0 = geometry (any non-air), 1 = color (exact match), 2 = material (base match)
func _get_native_criteria() -> int:
	if filter_color:
		return 1
	if filter_material:
		return 2
	return 0
