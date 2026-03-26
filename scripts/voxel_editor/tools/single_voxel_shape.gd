class_name SingleVoxelShape
extends ShapeTool

## Shape tool that affects a single voxel per click.
## Reimplements the original editor_tools.gd single-click behavior.

var _pos := Vector3i.ZERO


func _on_begin(pos: Vector3i) -> void:
	_pos = pos


func _on_update(pos: Vector3i) -> void:
	_pos = pos


func _on_commit() -> Array[Vector3i]:
	return [_pos]


func _on_get_preview() -> Array[Vector3i]:
	return [_pos]
