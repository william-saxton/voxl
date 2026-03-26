class_name EditorTools
extends Node

## Tool state machine for the voxel editor.
## Handles mouse input in the 3D viewport to place/remove/paint voxels.

enum Tool { PLACE, REMOVE, PAINT, EYEDROPPER }

signal tool_changed(tool: Tool)
signal palette_pick(palette_index: int)

var current_tool: Tool = Tool.PLACE:
	set(value):
		current_tool = value
		tool_changed.emit(value)

var selected_palette_index: int = 1  ## Currently selected palette entry

var _editor_main: VoxelEditorMain
var _camera: Camera3D
var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _highlight: HoverHighlight


func initialize(editor_main: VoxelEditorMain, viewport: SubViewport,
		camera: Camera3D, highlight: HoverHighlight,
		viewport_container: SubViewportContainer) -> void:
	_editor_main = editor_main
	_viewport = viewport
	_camera = camera
	_highlight = highlight
	_viewport_container = viewport_container


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcuts for tool selection
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_B:
				current_tool = Tool.PLACE
				get_viewport().set_input_as_handled()
			KEY_E:
				current_tool = Tool.REMOVE
				get_viewport().set_input_as_handled()
			KEY_P:
				current_tool = Tool.PAINT
				get_viewport().set_input_as_handled()
			KEY_I:
				current_tool = Tool.EYEDROPPER
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _camera or not _viewport:
		return
	_update_hover()


## Convert a position from SubViewportContainer space to SubViewport space.
func _container_to_viewport(container_pos: Vector2) -> Vector2:
	var container_size := _viewport_container.size
	var vp_size := Vector2(_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return container_pos
	return container_pos * vp_size / container_size


func _update_hover() -> void:
	# Get mouse in container local space, then transform to viewport space
	var container_mouse := _viewport_container.get_local_mouse_position()
	var container_size := _viewport_container.size
	# Check if mouse is within container bounds
	if container_mouse.x < 0 or container_mouse.y < 0 or \
			container_mouse.x >= container_size.x or container_mouse.y >= container_size.y:
		if _highlight:
			_highlight.visible = false
		return

	var mouse_pos := _container_to_viewport(container_mouse)
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)

	var tile := _editor_main.get_tile()
	if not tile:
		if _highlight:
			_highlight.visible = false
		return

	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)

	if _highlight:
		if result.hit:
			_highlight.visible = true
			if current_tool == Tool.PLACE:
				_highlight.set_voxel_pos(result.previous)
			else:
				_highlight.set_voxel_pos(result.position)
		else:
			_highlight.visible = false


func handle_viewport_click(event: InputEventMouseButton) -> void:
	if not _camera or not _editor_main:
		return

	var tile := _editor_main.get_tile()
	var palette := _editor_main.get_palette()
	if not tile or not palette:
		return

	var mouse_pos := _container_to_viewport(event.position)
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)

	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)

	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		match current_tool:
			Tool.PLACE:
				if result.hit:
					_place_voxel(tile, palette, result.previous)
				else:
					# If no hit, try placing on the ground plane (y=0)
					var ground := _raycast_ground(ray_origin, ray_dir)
					if ground.x >= 0:
						_place_voxel(tile, palette, ground)
			Tool.REMOVE:
				if result.hit:
					_remove_voxel(tile, result.position)
			Tool.PAINT:
				if result.hit:
					_paint_voxel(tile, palette, result.position)
			Tool.EYEDROPPER:
				if result.hit:
					var idx := palette.find_entry(result.voxel_id)
					if idx >= 0:
						selected_palette_index = idx
						palette_pick.emit(idx)

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Right-click always removes
		if result.hit:
			_remove_voxel(tile, result.position)


func _place_voxel(tile: WFCTileDef, palette: VoxelPalette, pos: Vector3i) -> void:
	if pos.x < 0 or pos.x >= WFCTileDef.TILE_X or \
			pos.y < 0 or pos.y >= WFCTileDef.TILE_Y or \
			pos.z < 0 or pos.z >= WFCTileDef.TILE_Z:
		return
	var voxel_id := palette.get_voxel_id(selected_palette_index)
	tile.set_voxel(pos.x, pos.y, pos.z, voxel_id)
	_editor_main.get_tile_renderer().mark_voxel_dirty(pos.x, pos.y, pos.z)


func _remove_voxel(tile: WFCTileDef, pos: Vector3i) -> void:
	tile.set_voxel(pos.x, pos.y, pos.z, 0)
	_editor_main.get_tile_renderer().mark_voxel_dirty(pos.x, pos.y, pos.z)


func _paint_voxel(tile: WFCTileDef, palette: VoxelPalette, pos: Vector3i) -> void:
	var voxel_id := palette.get_voxel_id(selected_palette_index)
	tile.set_voxel(pos.x, pos.y, pos.z, voxel_id)
	_editor_main.get_tile_renderer().mark_voxel_dirty(pos.x, pos.y, pos.z)


func _raycast_ground(origin: Vector3, dir: Vector3) -> Vector3i:
	# Intersect with y=0 plane
	if absf(dir.y) < 0.001:
		return Vector3i(-1, -1, -1)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector3i(-1, -1, -1)
	var hit_point := origin + dir * t
	var vx := int(floorf(hit_point.x))
	var vz := int(floorf(hit_point.z))
	if vx < 0 or vx >= WFCTileDef.TILE_X or vz < 0 or vz >= WFCTileDef.TILE_Z:
		return Vector3i(-1, -1, -1)
	return Vector3i(vx, 0, vz)
