class_name VoxelUndoManager
extends RefCounted

## Diff-based undo/redo for voxel edits.
## Each action stores a Dictionary of { Vector3i -> { old_id: int, new_id: int } }.
## Capped at MAX_ACTIONS to limit memory usage.

const MAX_ACTIONS := 50

## Each entry: { "diffs": Dictionary, "description": String,
##   "selection_before": Array[Vector3i] or null,
##   "selection_after": Array[Vector3i] or null }
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

## Called after undo/redo to restore selection. Set by EditorToolManager.
var on_selection_restore: Callable


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
	for pos: Vector3i in action.diffs:
		var diff: Dictionary = action.diffs[pos]
		tile.set_voxel(pos.x, pos.y, pos.z, diff.new_id)
		renderer.mark_voxel_dirty(pos.x, pos.y, pos.z)
	return commit_action(action)


## Undo the most recent action.
func undo(tile: WFCTileDef, renderer: TileRenderer) -> bool:
	if _undo_stack.is_empty():
		return false
	var action: Dictionary = _undo_stack.pop_back()
	# Apply old values
	for pos: Vector3i in action.diffs:
		var diff: Dictionary = action.diffs[pos]
		tile.set_voxel(pos.x, pos.y, pos.z, diff.old_id)
		renderer.mark_voxel_dirty(pos.x, pos.y, pos.z)
	_redo_stack.push_back(action)
	# Restore selection to before state
	if action.get("selection_before") != null and on_selection_restore.is_valid():
		on_selection_restore.call(action.selection_before)
	return true


## Redo the most recently undone action.
func redo(tile: WFCTileDef, renderer: TileRenderer) -> bool:
	if _redo_stack.is_empty():
		return false
	var action: Dictionary = _redo_stack.pop_back()
	# Apply new values
	for pos: Vector3i in action.diffs:
		var diff: Dictionary = action.diffs[pos]
		tile.set_voxel(pos.x, pos.y, pos.z, diff.new_id)
		renderer.mark_voxel_dirty(pos.x, pos.y, pos.z)
	_undo_stack.push_back(action)
	# Restore selection to after state
	if action.get("selection_after") != null and on_selection_restore.is_valid():
		on_selection_restore.call(action.selection_after)
	return true


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
