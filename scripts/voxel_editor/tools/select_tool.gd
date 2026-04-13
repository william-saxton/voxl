class_name SelectTool
extends RefCounted

## Selection tool with three sub-modes:
##   BOX: click two corners to select a 3D AABB region
##   BRUSH: click-drag to paint selection voxel by voxel
##   MAGIC: click a voxel to flood-select all connected matching voxels

enum SelectMode { BOX, BRUSH, MAGIC, OBJECT }

var mode: SelectMode = SelectMode.BOX
var query := VoxelQuery.new()
var brush_size: int = 1

## Box selection state
var _box_active := false
var _box_start := Vector3i.ZERO
var _box_end := Vector3i.ZERO
var _box_face := Vector3i.ZERO

## Brush drag state
var _brush_dragging := false


func begin(pos: Vector3i, face: Vector3i) -> void:
	match mode:
		SelectMode.BOX:
			_box_active = true
			_box_start = pos
			_box_end = pos
			_box_face = face
		SelectMode.BRUSH:
			_brush_dragging = true
			_box_face = face  # Store face for flat circle brush


func update(pos: Vector3i) -> void:
	if mode == SelectMode.BOX and _box_active:
		_box_end = pos


func end_brush() -> void:
	_brush_dragging = false


func is_brush_dragging() -> bool:
	return _brush_dragging


## Commit box selection — returns positions in the AABB matching query filters.
## ref_id is the voxel ID at the first click point, used for color/material filtering.
func commit_box(tile: WFCTileDef, ref_id: int = -1) -> Array[Vector3i]:
	_box_active = false
	var result: Array[Vector3i] = []
	var min_x := mini(_box_start.x, _box_end.x)
	var max_x := maxi(_box_start.x, _box_end.x)
	var min_y := mini(_box_start.y, _box_end.y)
	var max_y := maxi(_box_start.y, _box_end.y)
	var min_z := mini(_box_start.z, _box_end.z)
	var max_z := maxi(_box_start.z, _box_end.z)

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				var pos := Vector3i(x, y, z)
				if not VoxelQuery._in_bounds(pos):
					continue
				if ref_id >= 0:
					if query.matches(tile, pos, ref_id):
						result.append(pos)
				else:
					if tile.get_voxel(x, y, z) != 0:
						result.append(pos)
	return result


## Get box preview positions.
func get_box_preview() -> Array[Vector3i]:
	if not _box_active:
		return []
	var result: Array[Vector3i] = []
	var min_x := mini(_box_start.x, _box_end.x)
	var max_x := maxi(_box_start.x, _box_end.x)
	var min_y := mini(_box_start.y, _box_end.y)
	var max_y := maxi(_box_start.y, _box_end.y)
	var min_z := mini(_box_start.z, _box_end.z)
	var max_z := maxi(_box_start.z, _box_end.z)
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				if VoxelQuery._in_bounds(Vector3i(x, y, z)):
					result.append(Vector3i(x, y, z))
	return result


## Face select: flood fill from clicked voxel along a surface.
## Always uses FACE connectivity — only selects voxels that share an exposed
## face in the clicked direction. The query's filter_color / filter_material
## settings still apply for matching criteria.
func magic_select(tile: WFCTileDef, start: Vector3i,
		face_dir := Vector3i.ZERO) -> Array[Vector3i]:
	# Always use FACE connectivity for face select, preserving other query settings
	var old_conn := query.connectivity
	query.connectivity = VoxelQuery.Connectivity.FACE
	var result := query.flood_fill(tile, start, face_dir)
	query.connectivity = old_conn
	return result


## Object select: flood fill all connected geometry from clicked voxel.
## Always uses GEOMETRY connectivity (6-connected 3D BFS).
## The query's filter_color / filter_material settings control whether
## only matching color, material, or any non-air voxels are included.
func object_select(tile: WFCTileDef, start: Vector3i) -> Array[Vector3i]:
	var old_conn := query.connectivity
	query.connectivity = VoxelQuery.Connectivity.GEOMETRY
	var result := query.flood_fill(tile, start)
	query.connectivity = old_conn
	return result


## Get positions within brush radius around a center point.
## Produces a flat circle on the face plane (determined by _box_face from the
## initial click), not a 3D cube.
func get_brush_positions(center: Vector3i, face: Vector3i = _box_face) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if brush_size <= 1:
		if VoxelQuery._in_bounds(center):
			result.append(center)
		return result

	var r := brush_size - 1
	var r_sq := r * r

	# Determine which two axes form the circle plane based on the face normal.
	# Default to XZ plane if no face is set.
	var axis_a: int  # first planar axis index (0=x, 1=y, 2=z)
	var axis_b: int  # second planar axis index
	if face.y != 0 or face == Vector3i.ZERO:
		axis_a = 0; axis_b = 2  # XZ plane
	elif face.x != 0:
		axis_a = 1; axis_b = 2  # YZ plane
	else:
		axis_a = 0; axis_b = 1  # XY plane

	for da in range(-r, r + 1):
		for db in range(-r, r + 1):
			if da * da + db * db > r_sq:
				continue
			var offset := Vector3i.ZERO
			offset[axis_a] = da
			offset[axis_b] = db
			var pos := center + offset
			if VoxelQuery._in_bounds(pos):
				result.append(pos)
	return result


func cancel() -> void:
	_box_active = false
	_brush_dragging = false


func is_active() -> bool:
	return _box_active or _brush_dragging
