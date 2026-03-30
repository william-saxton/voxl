class_name VoxelUndoManager
extends RefCounted

## Diff-based undo/redo for voxel edits.
## Supports two formats:
##   - Dictionary diffs: { Vector3i -> { old_id, new_id } } (GDScript path)
##   - Packed diffs: PackedInt32Array [x,y,z,old_id,new_id, ...] (native path)
## Capped at MAX_ACTIONS to limit memory usage.

const MAX_ACTIONS := 50

## Each entry: { "diffs": Dictionary OR "packed_diffs": PackedInt32Array,
##   "description": String, "selection_before": Array[Vector3i] or null,
##   "selection_after": Array[Vector3i] or null }
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

## Called after undo/redo to restore selection. Set by EditorToolManager.
var on_selection_restore: Callable

## Native accelerator for bulk voxel writes
var _native: RefCounted

func _init() -> void:
	if ClassDB.class_exists(&"VoxelEditorNative"):
		_native = ClassDB.instantiate(&"VoxelEditorNative")


## Whether the native accelerator is available.
func has_native() -> bool:
	return _native != null


## Begin recording a new action. Returns an action handle (Dictionary).
## Call apply_and_commit() when done to finalize.
func create_action(description: String = "") -> Dictionary:
	return { "diffs": {}, "description": description,
			"selection_before": null, "selection_after": null }


## Record a single voxel change into an action handle.
func add_voxel_change(action: Dictionary, pos: Vector3i, old_id: int, new_id: int) -> void:
	if old_id == new_id:
		return
	# If this position was already changed in this action, keep the original old_id
	if action.diffs.has(pos):
		action.diffs[pos].new_id = new_id
	else:
		action.diffs[pos] = { "old_id": old_id, "new_id": new_id }


## Commit the action to the undo stack. Clears the redo stack.
## Returns true if the action had any changes.
func commit_action(action: Dictionary) -> bool:
	# Remove no-op entries (old == new after all updates)
	var cleaned: Dictionary = {}
	for pos: Vector3i in action.diffs:
		var diff: Dictionary = action.diffs[pos]
		if diff.old_id != diff.new_id:
			cleaned[pos] = diff
	if cleaned.is_empty():
		return false

	action.diffs = cleaned
	_undo_stack.push_back(action)
	_redo_stack.clear()

	# Cap stack size
	while _undo_stack.size() > MAX_ACTIONS:
		_undo_stack.pop_front()
	return true


## Apply an action's changes to the tile, then commit it.
## This is a convenience for the common case.
func apply_and_commit(action: Dictionary, tile: WFCTileDef, renderer: TileRenderer) -> bool:
	_bulk_apply(action.diffs, true, tile, renderer)
	return commit_action(action)


## Apply mode changes entirely in C++. Reads old IDs, applies mode, writes new IDs.
## Returns true if native path was used successfully.
## positions_flat: PackedInt32Array [x,y,z, x,y,z, ...]
## voxel_ids: PackedInt32Array, one per position
## mode: 0=ADD, 1=SUBTRACT, 2=PAINT
func apply_mode_native(positions_flat: PackedInt32Array, voxel_ids: PackedInt32Array,
		mode: int, description: String,
		tile: WFCTileDef, renderer: TileRenderer) -> bool:
	if not _native:
		return false
	tile._ensure_data()
	var result: Dictionary = _native.apply_mode_changes(
		tile.voxel_data, positions_flat, voxel_ids, mode,
		tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
	var packed_diffs: PackedInt32Array = result.undo_diffs
	if packed_diffs.is_empty():
		return true  # No actual changes, but native path worked
	tile.voxel_data = result.voxel_data
	var dirty_chunks: PackedInt32Array = result.dirty_chunks
	for chunk_idx in dirty_chunks:
		renderer.mark_chunk_dirty_by_index(chunk_idx)
	var action := {
		"packed_diffs": packed_diffs,
		"description": description,
		"selection_before": null,
		"selection_after": null
	}
	_undo_stack.push_back(action)
	_redo_stack.clear()
	while _undo_stack.size() > MAX_ACTIONS:
		_undo_stack.pop_front()
	return true


## Undo the most recent action.
func undo(tile: WFCTileDef, renderer: TileRenderer) -> bool:
	if _undo_stack.is_empty():
		return false
	var action: Dictionary = _undo_stack.pop_back()
	if action.has("packed_diffs"):
		_bulk_apply_packed(action.packed_diffs, false, tile, renderer)
	else:
		_bulk_apply(action.diffs, false, tile, renderer)
	_redo_stack.push_back(action)
	if action.get("selection_before") != null and on_selection_restore.is_valid():
		on_selection_restore.call(action.selection_before)
	return true


## Redo the most recently undone action.
func redo(tile: WFCTileDef, renderer: TileRenderer) -> bool:
	if _redo_stack.is_empty():
		return false
	var action: Dictionary = _redo_stack.pop_back()
	if action.has("packed_diffs"):
		_bulk_apply_packed(action.packed_diffs, true, tile, renderer)
	else:
		_bulk_apply(action.diffs, true, tile, renderer)
	_undo_stack.push_back(action)
	if action.get("selection_after") != null and on_selection_restore.is_valid():
		on_selection_restore.call(action.selection_after)
	return true


## Bulk-apply voxel changes from Dictionary diffs via C++ or GDScript fallback.
## use_new_id: true = apply new_id (do/redo), false = apply old_id (undo).
func _bulk_apply(diffs: Dictionary, use_new_id: bool,
		tile: WFCTileDef, renderer: TileRenderer) -> void:
	if diffs.is_empty():
		return

	if _native:
		# Ensure voxel_data is allocated (C++ can't call _ensure_data)
		tile._ensure_data()
		# Pack changes into flat int array: [x, y, z, id, x, y, z, id, ...]
		var packed := PackedInt32Array()
		packed.resize(diffs.size() * 4)
		var i := 0
		var id_key := "new_id" if use_new_id else "old_id"
		for pos: Vector3i in diffs:
			packed[i] = pos.x
			packed[i + 1] = pos.y
			packed[i + 2] = pos.z
			packed[i + 3] = diffs[pos][id_key]
			i += 4
		var result: Dictionary = _native.bulk_set_voxels(
			tile.voxel_data, packed,
			tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
		tile.voxel_data = result.voxel_data
		var dirty_chunks: PackedInt32Array = result.dirty_chunks
		for chunk_idx in dirty_chunks:
			renderer.mark_chunk_dirty_by_index(chunk_idx)
	else:
		var id_key := "new_id" if use_new_id else "old_id"
		for pos: Vector3i in diffs:
			tile.set_voxel(pos.x, pos.y, pos.z, diffs[pos][id_key])
			renderer.mark_voxel_dirty(pos.x, pos.y, pos.z)


## Bulk-apply packed diffs via C++ or GDScript fallback.
## packed_diffs: [x, y, z, old_id, new_id, ...] (5 ints per entry)
func _bulk_apply_packed(packed_diffs: PackedInt32Array, use_new_id: bool,
		tile: WFCTileDef, renderer: TileRenderer) -> void:
	var count := packed_diffs.size() / 5
	if count == 0:
		return

	if _native:
		tile._ensure_data()
		var result: Dictionary = _native.apply_undo_diffs(
			tile.voxel_data, packed_diffs, use_new_id,
			tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
		tile.voxel_data = result.voxel_data
		var dirty_chunks: PackedInt32Array = result.dirty_chunks
		for chunk_idx in dirty_chunks:
			renderer.mark_chunk_dirty_by_index(chunk_idx)
	else:
		var id_offset := 4 if use_new_id else 3
		for i in count:
			var base := i * 5
			var x := packed_diffs[base]
			var y := packed_diffs[base + 1]
			var z := packed_diffs[base + 2]
			var id := packed_diffs[base + id_offset]
			tile.set_voxel(x, y, z, id)
			renderer.mark_voxel_dirty(x, y, z)


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()


func get_undo_description() -> String:
	if _undo_stack.is_empty():
		return ""
	return _undo_stack.back().description


func get_redo_description() -> String:
	if _redo_stack.is_empty():
		return ""
	return _redo_stack.back().description
