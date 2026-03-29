class_name ShapeTool
extends RefCounted

## Base class for shape tools. A shape determines which voxels are affected
## by a gesture. Subclasses produce Array[Vector3i] positions.

## Whether this shape needs two clicks (true) or commits immediately (false).
var requires_drag := false

## Whether this shape supports a third click to define height.
var supports_height := false

## The face normal of the initial click — used as the projection plane.
var face_normal := Vector3i.ZERO

## Whether a gesture is in progress (between begin and commit/cancel).
var active := false

## Current phase: 1 = defining 2D shape, 2 = defining height.
var phase := 0

## Properties shared by box/circle/polygon shapes.
var hollow := false
var sides := 6

## Height state (used when supports_height = true)
var _base_positions: Array[Vector3i] = []
var _height := 0  # Positive = extrude along face_normal, can be 0 (flat)


## Start a new gesture at the given voxel position.
func begin(pos: Vector3i, face: Vector3i) -> void:
	face_normal = face
	active = true
	phase = 1
	_height = 0
	_base_positions.clear()
	_on_begin(pos)


## Update the gesture as the mouse moves to a new position.
## In phase 2 (height), height is set externally via set_height().
func update(pos: Vector3i) -> void:
	if not active:
		return
	if phase == 1:
		_on_update(pos)


## Attempt to advance/finalize the gesture.
## Returns the final positions if done, or empty if transitioning to height phase.
func commit() -> Array[Vector3i]:
	if phase == 1 and supports_height:
		# Transition to height phase — store FILLED positions (hollow applied later in 3D)
		var saved_hollow := hollow
		hollow = false
		_base_positions = _on_commit()
		hollow = saved_hollow
		if _base_positions.is_empty():
			active = false
			phase = 0
			return []
		phase = 2
		_height = 0
		return []  # Signal: not done yet, need height click

	# Final commit
	active = false
	phase = 0
	if not _base_positions.is_empty():
		# Height phase commit — extrude base positions
		var result := _extrude_positions(_base_positions, _height)
		_base_positions.clear()
		return result
	return _on_commit()


## Get a preview of the current shape for rendering.
func get_preview() -> Array[Vector3i]:
	if not active:
		return []
	if phase == 2:
		return _extrude_positions(_base_positions, _height)
	return _on_get_preview()


## Cancel the current gesture without applying.
func cancel() -> void:
	active = false
	phase = 0
	_base_positions.clear()
	_on_cancel()


## True when the shape is in height-definition phase (third click pending).
func in_height_phase() -> bool:
	return phase == 2


## Set height directly (used by EditorToolManager for float-precision tracking).
func set_height(h: int) -> void:
	_height = h


func _extrude_positions(base: Array[Vector3i], height: int) -> Array[Vector3i]:
	if height == 0:
		if not hollow:
			return base.duplicate()
		# Flat hollow: check only neighbors on the projection plane (exclude face_normal axis)
		return _apply_2d_hollow(base)

	var result: Array[Vector3i] = []
	var dir := 1 if height > 0 else -1
	var count := absi(height) + 1  # Include the base layer
	for layer in count:
		var offset := face_normal * (layer * dir)
		for pos in base:
			result.append(pos + offset)

	if not hollow:
		return result
	# 3D hollow: keep only positions that have at least one missing 6-neighbor
	return _apply_3d_hollow(result)


func _apply_2d_hollow(positions: Array[Vector3i]) -> Array[Vector3i]:
	var pos_set := {}
	for pos in positions:
		pos_set[pos] = true
	# 4 neighbors on the plane (exclude face_normal direction)
	var plane_neighbors: Array[Vector3i] = []
	for n in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
		if n != face_normal and n != -face_normal:
			plane_neighbors.append(n)
	var filtered: Array[Vector3i] = []
	for pos in positions:
		for n in plane_neighbors:
			if not pos_set.has(pos + n):
				filtered.append(pos)
				break
	return filtered


func _apply_3d_hollow(positions: Array[Vector3i]) -> Array[Vector3i]:
	var pos_set := {}
	for pos in positions:
		pos_set[pos] = true
	var filtered: Array[Vector3i] = []
	for pos in positions:
		for n in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
			if not pos_set.has(pos + n):
				filtered.append(pos)
				break
	return filtered


## Returns guide markers for the current shape. Override in subclasses.
## Returns Dictionary with optional keys:
##   "center": Vector3 — center point (rendered as circle)
##   "edge_midpoints": Array[Vector3] — edge midpoints (rendered as X marks)
func get_guide_markers() -> Dictionary:
	return {}


# --- Virtual methods for subclasses ---

func _on_begin(_pos: Vector3i) -> void:
	pass

func _on_update(_pos: Vector3i) -> void:
	pass

func _on_commit() -> Array[Vector3i]:
	return []

func _on_get_preview() -> Array[Vector3i]:
	return []

func _on_cancel() -> void:
	pass
