class_name EditOperations
extends RefCounted

## Static-style edit operations that work on selections or clipboard data.
## All operations return data compatible with the undo system.


## Rotate positions 90° around the selection centroid on the given axis.
## axis: 0=X, 1=Y, 2=Z
static func rotate(tile: WFCTileDef, selection: VoxelSelection,
		axis: int) -> Dictionary:
	var positions := selection.get_positions()
	if positions.is_empty():
		return { "old_data": {}, "new_data": {}, "new_positions": [] as Array[Vector3i] }

	var bb := selection.get_bounding_box()
	var center := bb.position + bb.size * 0.5

	var old_data: Dictionary = {}  # Vector3i → int (original voxel at that position)
	var new_data: Dictionary = {}  # Vector3i → int (what to write)
	var new_positions: Array[Vector3i] = []

	# Collect source voxels
	var src_voxels: Dictionary = {}  # Vector3i → int
	for pos in positions:
		src_voxels[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	# Compute rotated positions
	for pos in positions:
		var rel := Vector3(pos) + Vector3(0.5, 0.5, 0.5) - center
		var rotated: Vector3
		match axis:
			0:  # X axis: Y→Z, Z→-Y
				rotated = Vector3(rel.x, -rel.z, rel.y)
			1:  # Y axis: X→Z, Z→-X
				rotated = Vector3(rel.z, rel.y, -rel.x)
			_:  # Z axis: X→Y, Y→-X
				rotated = Vector3(-rel.y, rel.x, rel.z)
		var new_pos := Vector3i(
			int(floorf(rotated.x + center.x)),
			int(floorf(rotated.y + center.y)),
			int(floorf(rotated.z + center.z)))
		if VoxelQuery._in_bounds(new_pos):
			new_positions.append(new_pos)
			new_data[new_pos] = src_voxels[pos]

	# Collect old data at destination positions
	for pos in new_data:
		old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)
	# Also need old data at source positions (they'll be cleared)
	for pos in positions:
		if not old_data.has(pos):
			old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	return { "old_data": old_data, "new_data": new_data,
			"new_positions": new_positions, "clear_positions": positions }


## Rotate positions by arbitrary degrees around the selection centroid on the given axis.
## axis: 0=X, 1=Y, 2=Z
static func rotate_degrees(tile: WFCTileDef, selection: VoxelSelection,
		axis: int, degrees: float) -> Dictionary:
	var positions := selection.get_positions()
	if positions.is_empty():
		return { "old_data": {}, "new_data": {}, "new_positions": [] as Array[Vector3i] }

	var bb := selection.get_bounding_box()
	var center := bb.position + bb.size * 0.5
	var angle := deg_to_rad(degrees)
	var ca := cos(angle)
	var sa := sin(angle)

	var old_data: Dictionary = {}
	var new_data: Dictionary = {}
	var new_positions: Array[Vector3i] = []

	var src_voxels: Dictionary = {}
	for pos in positions:
		src_voxels[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	for pos in positions:
		var rel := Vector3(pos) + Vector3(0.5, 0.5, 0.5) - center
		var rotated: Vector3
		match axis:
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
		if VoxelQuery._in_bounds(new_pos):
			new_positions.append(new_pos)
			new_data[new_pos] = src_voxels[pos]

	for pos in new_data:
		old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)
	for pos in positions:
		if not old_data.has(pos):
			old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	return { "old_data": old_data, "new_data": new_data,
			"new_positions": new_positions, "clear_positions": positions }


## Flip positions along the given axis within the selection bounding box.
static func flip(tile: WFCTileDef, selection: VoxelSelection,
		axis: int) -> Dictionary:
	var positions := selection.get_positions()
	if positions.is_empty():
		return { "old_data": {}, "new_data": {}, "new_positions": [] as Array[Vector3i] }

	var bb := selection.get_bounding_box()
	var min_p := Vector3i(int(bb.position.x), int(bb.position.y), int(bb.position.z))
	var max_p := min_p + Vector3i(int(bb.size.x), int(bb.size.y), int(bb.size.z)) - Vector3i.ONE

	var old_data: Dictionary = {}
	var new_data: Dictionary = {}
	var new_positions: Array[Vector3i] = []

	var src_voxels: Dictionary = {}
	for pos in positions:
		src_voxels[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	for pos in positions:
		var new_pos := pos
		new_pos[axis] = max_p[axis] - (pos[axis] - min_p[axis])
		if VoxelQuery._in_bounds(new_pos):
			new_positions.append(new_pos)
			new_data[new_pos] = src_voxels[pos]

	for pos in new_data:
		old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)
	for pos in positions:
		if not old_data.has(pos):
			old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	return { "old_data": old_data, "new_data": new_data,
			"new_positions": new_positions, "clear_positions": positions }


## Mirror: duplicate + flip along axis. Keeps originals, adds mirrored copies.
static func mirror(tile: WFCTileDef, selection: VoxelSelection,
		axis: int) -> Dictionary:
	var positions := selection.get_positions()
	if positions.is_empty():
		return { "old_data": {}, "new_data": {} }

	var bb := selection.get_bounding_box()
	var min_p := Vector3i(int(bb.position.x), int(bb.position.y), int(bb.position.z))
	var max_p := min_p + Vector3i(int(bb.size.x), int(bb.size.y), int(bb.size.z)) - Vector3i.ONE
	# Mirror pivot is one beyond the max edge
	var pivot := max_p[axis] + 1

	var old_data: Dictionary = {}
	var new_data: Dictionary = {}

	for pos in positions:
		var vid := tile.get_voxel(pos.x, pos.y, pos.z)
		if vid == 0:
			continue
		var mirror_pos := pos
		mirror_pos[axis] = pivot + (max_p[axis] - pos[axis])
		if VoxelQuery._in_bounds(mirror_pos):
			old_data[mirror_pos] = tile.get_voxel(mirror_pos.x, mirror_pos.y, mirror_pos.z)
			new_data[mirror_pos] = vid

	return { "old_data": old_data, "new_data": new_data }


## Hollow: remove interior voxels (all 6 neighbors are solid).
static func hollow(tile: WFCTileDef, selection: VoxelSelection) -> Dictionary:
	var positions := selection.get_positions()
	var pos_set: Dictionary = {}
	for pos in positions:
		pos_set[pos] = true

	var old_data: Dictionary = {}
	var new_data: Dictionary = {}

	for pos in positions:
		var vid := tile.get_voxel(pos.x, pos.y, pos.z)
		if vid == 0:
			continue
		var all_solid := true
		for n in VoxelQuery.NEIGHBORS_6:
			var np := pos + n
			if not VoxelQuery._in_bounds(np) or tile.get_voxel(np.x, np.y, np.z) == 0:
				all_solid = false
				break
		if all_solid:
			old_data[pos] = vid
			new_data[pos] = 0  # Remove interior

	return { "old_data": old_data, "new_data": new_data }


## Flood interior: fill enclosed air inside selection bounding box.
static func flood_interior(tile: WFCTileDef, selection: VoxelSelection,
		fill_id: int) -> Dictionary:
	var bb := selection.get_bounding_box()
	if bb.size == Vector3.ZERO:
		return { "old_data": {}, "new_data": {} }

	var min_p := Vector3i(int(bb.position.x), int(bb.position.y), int(bb.position.z))
	var max_p := min_p + Vector3i(int(bb.size.x), int(bb.size.y), int(bb.size.z))

	# Find air voxels inside the bounding box that aren't reachable from the boundary
	var boundary_air: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array[Vector3i] = []

	# Seed with air voxels on the bounding box faces
	for x in range(min_p.x, max_p.x):
		for y in range(min_p.y, max_p.y):
			for z in range(min_p.z, max_p.z):
				if x == min_p.x or x == max_p.x - 1 or \
						y == min_p.y or y == max_p.y - 1 or \
						z == min_p.z or z == max_p.z - 1:
					var pos := Vector3i(x, y, z)
					if VoxelQuery._in_bounds(pos) and tile.get_voxel(x, y, z) == 0:
						boundary_air[pos] = true
						visited[pos] = true
						queue.append(pos)

	# BFS from boundary air — everything reachable is exterior
	while not queue.is_empty():
		var pos: Vector3i = queue.pop_front()
		for n in VoxelQuery.NEIGHBORS_6:
			var np := pos + n
			if visited.has(np):
				continue
			if np.x < min_p.x or np.x >= max_p.x or \
					np.y < min_p.y or np.y >= max_p.y or \
					np.z < min_p.z or np.z >= max_p.z:
				continue
			visited[np] = true
			if VoxelQuery._in_bounds(np) and tile.get_voxel(np.x, np.y, np.z) == 0:
				boundary_air[np] = true
				queue.append(np)

	# All air NOT reachable from boundary is interior — fill it
	var old_data: Dictionary = {}
	var new_data: Dictionary = {}
	for x in range(min_p.x, max_p.x):
		for y in range(min_p.y, max_p.y):
			for z in range(min_p.z, max_p.z):
				var pos := Vector3i(x, y, z)
				if VoxelQuery._in_bounds(pos) and tile.get_voxel(x, y, z) == 0 \
						and not boundary_air.has(pos):
					old_data[pos] = 0
					new_data[pos] = fill_id

	return { "old_data": old_data, "new_data": new_data }


## Dilate: grow selection outward by N voxels.
static func dilate(tile: WFCTileDef, selection: VoxelSelection,
		fill_id: int, iterations: int = 1) -> Dictionary:
	var old_data: Dictionary = {}
	var new_data: Dictionary = {}

	# Build set of solid positions (from selection)
	var solid: Dictionary = {}
	for pos in selection.get_positions():
		if tile.get_voxel(pos.x, pos.y, pos.z) != 0:
			solid[pos] = true

	for _i in iterations:
		var to_add: Array[Vector3i] = []
		for pos in solid:
			for n in VoxelQuery.NEIGHBORS_6:
				var np: Vector3i = (pos as Vector3i) + n
				if not solid.has(np) and VoxelQuery._in_bounds(np) and \
						tile.get_voxel(np.x, np.y, np.z) == 0:
					if not new_data.has(np):
						old_data[np] = 0
						new_data[np] = fill_id
					to_add.append(np)
		for pos in to_add:
			solid[pos] = true

	return { "old_data": old_data, "new_data": new_data }


## Scale selection from centroid by a float factor.
## Supports fractional (0.25, 0.5, 0.75) and integer (2, 3, 4) factors.
## Uses nearest-neighbor resampling from source voxels.
static func scale(tile: WFCTileDef, selection: VoxelSelection,
		factor: float) -> Dictionary:
	var positions := selection.get_positions()
	if positions.is_empty() or factor < 0.25:
		return { "old_data": {}, "new_data": {}, "new_positions": [] as Array[Vector3i] }

	var bb := selection.get_bounding_box()
	var center := bb.position + bb.size * 0.5

	var old_data: Dictionary = {}
	var new_data: Dictionary = {}
	var new_positions: Array[Vector3i] = []

	# Collect source voxels
	var src_voxels: Dictionary = {}
	for pos in positions:
		src_voxels[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	# Compute bounding box extents
	var bb_min := Vector3(bb.position)
	var bb_max := Vector3(bb.position + bb.size)

	# Scaled bounding box
	var scaled_size := (bb_max - bb_min) * factor
	var scaled_min := center - scaled_size * 0.5
	var scaled_max := center + scaled_size * 0.5

	# For each destination voxel in the scaled region, sample from source
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
				if not VoxelQuery._in_bounds(dest):
					continue
				# Inverse map to source
				var src_f := (Vector3(dest) + Vector3(0.5, 0.5, 0.5) - center) / factor + center
				var src := Vector3i(int(floorf(src_f.x)), int(floorf(src_f.y)), int(floorf(src_f.z)))
				var vid: int = src_voxels.get(src, 0)
				if vid != 0:
					new_positions.append(dest)
					new_data[dest] = vid

	# Collect old data at destination positions
	for pos in new_data:
		old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)
	# Also need old data at source positions (they'll be cleared)
	for pos in positions:
		if not old_data.has(pos):
			old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)

	return { "old_data": old_data, "new_data": new_data,
			"new_positions": new_positions, "clear_positions": positions }


## Erode: shrink selection inward by N voxels.
static func erode(tile: WFCTileDef, selection: VoxelSelection,
		iterations: int = 1) -> Dictionary:
	var old_data: Dictionary = {}
	var new_data: Dictionary = {}

	var solid: Dictionary = {}
	for pos in selection.get_positions():
		if tile.get_voxel(pos.x, pos.y, pos.z) != 0:
			solid[pos] = true

	for _i in iterations:
		var to_remove: Array[Vector3i] = []
		for pos in solid:
			var p: Vector3i = pos as Vector3i
			for n in VoxelQuery.NEIGHBORS_6:
				var np := p + n
				if not solid.has(np):
					to_remove.append(p)
					break
		for pos in to_remove:
			solid.erase(pos)
			if not old_data.has(pos):
				old_data[pos] = tile.get_voxel(pos.x, pos.y, pos.z)
				new_data[pos] = 0

	return { "old_data": old_data, "new_data": new_data }
