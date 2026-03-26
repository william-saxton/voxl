class_name EditorToolManager
extends Node

## Layered tool system: PrimaryMode determines what happens to voxels,
## ShapeTool determines which voxels are affected.
## All mutations go through the undo system.

enum PrimaryMode { ADD, SUBTRACT, PAINT }
enum ShapeType { BRUSH, LINE, BOX, CIRCLE, POLYGON }
enum ToolType { SHAPE, FILL, EXTRUDE, SELECT, TRANSFORM, METADATA }

signal mode_changed(mode: PrimaryMode)
signal shape_changed(shape_type: ShapeType)
signal tool_type_changed(tool_type: ToolType)
signal hollow_changed(is_hollow: bool)
signal palette_pick(palette_index: int)
signal selection_changed()
signal select_settings_changed()  ## Emitted when select mode, connectivity, or filters change
signal symmetry_changed()

var current_mode: PrimaryMode = PrimaryMode.ADD:
	set(value):
		_cancel_shape()
		current_mode = value
		mode_changed.emit(value)

var current_shape_type: ShapeType = ShapeType.BRUSH:
	set(value):
		_cancel_shape()
		current_shape_type = value
		current_shape = _create_shape(value)
		shape_changed.emit(value)

var current_tool_type: ToolType = ToolType.SHAPE:
	set(value):
		_cancel_shape()
		if transform_tool.is_any_active():
			transform_tool.cancel()
			if _transform_gizmo:
				_transform_gizmo.clear_rotate_feedback()
		current_tool_type = value
		_update_gizmo()
		tool_type_changed.emit(value)

var selected_palette_index: int = 1
var current_shape: ShapeTool = BrushShape.new()
var undo_manager := VoxelUndoManager.new()

## Fill, Extrude, and Transform tools
var fill_tool := FillTool.new()
var extrude_tool := ExtrudeTool.new()
var transform_tool := TransformTool.new()

## Symmetry system
var symmetry := SymmetryManager.new()
var _symmetry_renderer: SymmetryRenderer

## Selection system
var selection := VoxelSelection.new()
var select_tool := SelectTool.new()
var clipboard := VoxelClipboard.new()
var _selection_renderer: SelectionRenderer
var _transform_gizmo: TransformGizmo
var _metadata_renderer: MetadataRenderer
var _paste_mode := false  ## True when floating paste preview is active
var _mirror_place_mode := false  ## True when placing a custom mirror plane
var _select_ref_id: int = -1  ## Voxel ID at first click for criteria filtering

## Hollow toggle for box/circle/polygon shapes
var hollow := false

## Polygon sides count
var polygon_sides: int = 6

## Brush tool properties
var brush_size: int = 1
var brush_flat := false

## Brush drag state
var _brush_dragging := false
var _brush_last_pos := Vector3i.ZERO
var _brush_drag_normal := Vector3i(0, 1, 0)
var _brush_drag_action: Dictionary = {}  ## Single undo action for the whole stroke

var _editor_main: VoxelEditorMain
var _camera: Camera3D
var _viewport: SubViewport
var _viewport_container: SubViewportContainer
var _highlight: HoverHighlight
var _shape_preview: ShapePreview

## Working plane for two-click shapes (set on first click)
var _work_plane_point := Vector3.ZERO
var _work_plane_normal := Vector3.ZERO


func initialize(editor_main: VoxelEditorMain, viewport: SubViewport,
		camera: Camera3D, highlight: HoverHighlight,
		viewport_container: SubViewportContainer) -> void:
	_editor_main = editor_main
	_viewport = viewport
	_camera = camera
	_highlight = highlight
	_viewport_container = viewport_container

	# Create shape preview node in the viewport's 3D scene
	_shape_preview = ShapePreview.new()
	_shape_preview.name = "ShapePreview"
	viewport.add_child(_shape_preview)

	# Create selection renderer
	_selection_renderer = SelectionRenderer.new()
	_selection_renderer.name = "SelectionRenderer"
	viewport.add_child(_selection_renderer)

	# Create transform gizmo
	_transform_gizmo = TransformGizmo.new()
	_transform_gizmo.name = "TransformGizmo"
	_transform_gizmo.visible = false
	viewport.add_child(_transform_gizmo)

	# Create symmetry renderer
	_symmetry_renderer = SymmetryRenderer.new()
	_symmetry_renderer.name = "SymmetryRenderer"
	viewport.add_child(_symmetry_renderer)
	symmetry.symmetry_changed.connect(_on_symmetry_changed)

	# Create metadata renderer
	_metadata_renderer = MetadataRenderer.new()
	_metadata_renderer.name = "MetadataRenderer"
	viewport.add_child(_metadata_renderer)

	selection.selection_changed.connect(func(): _on_selection_changed())
	undo_manager.on_selection_restore = func(positions: Array):
		selection.set_positions(positions)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			# Mode shortcuts
			KEY_B:
				current_mode = PrimaryMode.ADD
				get_viewport().set_input_as_handled()
			KEY_E:
				current_mode = PrimaryMode.SUBTRACT
				get_viewport().set_input_as_handled()
			KEY_P:
				current_mode = PrimaryMode.PAINT
				get_viewport().set_input_as_handled()
			# Shape shortcuts
			KEY_1:
				current_shape_type = ShapeType.BRUSH
				get_viewport().set_input_as_handled()
			KEY_2:
				current_shape_type = ShapeType.LINE
				get_viewport().set_input_as_handled()
			KEY_3:
				current_shape_type = ShapeType.BOX
				get_viewport().set_input_as_handled()
			KEY_4:
				current_shape_type = ShapeType.CIRCLE
				get_viewport().set_input_as_handled()
			KEY_5:
				current_shape_type = ShapeType.POLYGON
				get_viewport().set_input_as_handled()
			# Tool type shortcuts
			KEY_F:
				current_tool_type = ToolType.FILL if current_tool_type != ToolType.FILL else ToolType.SHAPE
				get_viewport().set_input_as_handled()
			KEY_G:
				current_tool_type = ToolType.EXTRUDE if current_tool_type != ToolType.EXTRUDE else ToolType.SHAPE
				get_viewport().set_input_as_handled()
			KEY_S:
				current_tool_type = ToolType.SELECT if current_tool_type != ToolType.SELECT else ToolType.SHAPE
				get_viewport().set_input_as_handled()
			KEY_K:
				current_tool_type = ToolType.METADATA if current_tool_type != ToolType.METADATA else ToolType.SHAPE
				get_viewport().set_input_as_handled()
			KEY_T:
				current_tool_type = ToolType.TRANSFORM if current_tool_type != ToolType.TRANSFORM else ToolType.SHAPE
				get_viewport().set_input_as_handled()
			# View mode cycle
			KEY_V:
				_editor_main._cycle_view_mode()
				get_viewport().set_input_as_handled()
			# Wireframe toggle
			KEY_W:
				var renderer := _editor_main.get_tile_renderer()
				renderer.show_wireframe = not renderer.show_wireframe
				get_viewport().set_input_as_handled()
			# Selection connectivity cycle (Geometry ↔ Face)
			KEY_Q:
				_cycle_connectivity()
				get_viewport().set_input_as_handled()
			# Hollow toggle
			KEY_H:
				hollow = not hollow
				_sync_hollow()
				hollow_changed.emit(hollow)
				get_viewport().set_input_as_handled()
			# Clipboard shortcuts
			KEY_C:
				if key.ctrl_pressed:
					copy_selection()
					get_viewport().set_input_as_handled()
			KEY_X:
				if key.ctrl_pressed:
					cut_selection()
					get_viewport().set_input_as_handled()
			KEY_V:
				if key.ctrl_pressed:
					begin_paste()
					get_viewport().set_input_as_handled()
			# Selection shortcuts
			KEY_A:
				if key.ctrl_pressed:
					select_all()
					get_viewport().set_input_as_handled()
			KEY_DELETE:
				delete_selection()
				get_viewport().set_input_as_handled()
			# Undo/Redo
			KEY_Z:
				if key.ctrl_pressed and key.shift_pressed:
					_do_redo()
					get_viewport().set_input_as_handled()
				elif key.ctrl_pressed:
					_do_undo()
					get_viewport().set_input_as_handled()
			KEY_Y:
				if key.ctrl_pressed:
					_do_redo()
					get_viewport().set_input_as_handled()
			# Arrow keys for transform nudge
			KEY_LEFT:
				if current_tool_type == ToolType.TRANSFORM:
					_nudge_transform(Vector3i(-1, 0, 0))
					get_viewport().set_input_as_handled()
			KEY_RIGHT:
				if current_tool_type == ToolType.TRANSFORM:
					_nudge_transform(Vector3i(1, 0, 0))
					get_viewport().set_input_as_handled()
			KEY_UP:
				if current_tool_type == ToolType.TRANSFORM:
					if key.shift_pressed:
						_nudge_transform(Vector3i(0, 1, 0))
					else:
						_nudge_transform(Vector3i(0, 0, -1))
					get_viewport().set_input_as_handled()
			KEY_DOWN:
				if current_tool_type == ToolType.TRANSFORM:
					if key.shift_pressed:
						_nudge_transform(Vector3i(0, -1, 0))
					else:
						_nudge_transform(Vector3i(0, 0, 1))
					get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if transform_tool.is_any_active():
					_commit_transform()
					get_viewport().set_input_as_handled()
			# Cancel
			KEY_ESCAPE:
				if transform_tool.is_any_active():
					transform_tool.cancel()
					if _transform_gizmo:
						_transform_gizmo.clear_rotate_feedback()
					if _shape_preview:
						_shape_preview.clear()
					_selection_renderer.update_selection(selection)
					get_viewport().set_input_as_handled()
				elif _mirror_place_mode:
					_mirror_place_mode = false
					if _shape_preview:
						_shape_preview.clear()
					get_viewport().set_input_as_handled()
				elif _paste_mode:
					_paste_mode = false
					if _shape_preview:
						_shape_preview.clear()
					get_viewport().set_input_as_handled()
				elif select_tool.is_active():
					select_tool.cancel()
					if _shape_preview:
						_shape_preview.clear()
					get_viewport().set_input_as_handled()
				elif current_shape.active:
					_cancel_shape()
					get_viewport().set_input_as_handled()
				elif extrude_tool.active:
					extrude_tool.cancel()
					if _shape_preview:
						_shape_preview.clear()
					get_viewport().set_input_as_handled()
				elif not selection.is_empty():
					selection.clear()
					get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _camera or not _viewport:
		return
	_update_hover()


func _container_to_viewport(container_pos: Vector2) -> Vector2:
	var container_size := _viewport_container.size
	var vp_size := Vector2(_viewport.size)
	if container_size.x <= 0 or container_size.y <= 0:
		return container_pos
	return container_pos * vp_size / container_size


func _update_hover() -> void:
	var container_mouse := _viewport_container.get_local_mouse_position()
	var container_size := _viewport_container.size
	if container_mouse.x < 0 or container_mouse.y < 0 or \
			container_mouse.x >= container_size.x or container_mouse.y >= container_size.y:
		if _highlight:
			_highlight.visible = false
		if _shape_preview:
			_shape_preview.clear()
		return

	var mouse_pos := _container_to_viewport(container_mouse)
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)

	var tile := _editor_main.get_tile()
	if not tile:
		if _highlight:
			_highlight.visible = false
		return

	# Paste preview
	if _paste_mode:
		if _highlight:
			_highlight.visible = false
		_update_paste_preview(ray_origin, ray_dir)
		return

	# Mirror plane placement preview
	if _mirror_place_mode:
		_update_mirror_place_preview(ray_origin, ray_dir, tile)
		return

	# Metadata mode — highlight clicked voxel
	if current_tool_type == ToolType.METADATA:
		var meta_result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
		if _highlight:
			if meta_result.hit:
				_highlight.visible = true
				_highlight.set_voxel_pos(meta_result.position)
			else:
				_highlight.visible = false
		if _shape_preview:
			_shape_preview.clear()
		return

	# Transform tool — active drag or gizmo hover
	if current_tool_type == ToolType.TRANSFORM:
		if _highlight:
			_highlight.visible = false
		_update_transform_hover(ray_origin, ray_dir)
		return

	# Select tool hover
	if current_tool_type == ToolType.SELECT and select_tool.is_active():
		if _highlight:
			_highlight.visible = false
		_update_select_hover(ray_origin, ray_dir)
		return

	# Extrude active — preview is updated via handle_viewport_drag, just hide highlight
	if extrude_tool.active:
		if _highlight:
			_highlight.visible = false
		return

	# If shape is active, update based on phase
	if current_shape.active:
		if current_shape.in_height_phase():
			# Height phase: track mouse movement along screen-space face_normal
			_update_height_from_mouse()
			if _shape_preview:
				_shape_preview.set_preview_color(current_mode)
				_update_shape_preview()
		else:
			# Shape definition phase: project onto the face plane
			if _project_onto_plane(ray_origin, ray_dir):
				current_shape.update(_plane_hit_pos)
				if _shape_preview:
					_shape_preview.set_preview_color(current_mode)
					_update_shape_preview()
		if _highlight:
			_highlight.visible = false
		return

	# Brush drag — project mouse onto the working plane from the first click
	if _brush_dragging:
		if _project_onto_plane(ray_origin, ray_dir):
			var drag_pos := _plane_hit_pos
			if drag_pos != _brush_last_pos and _in_bounds(drag_pos):
				var palette := _editor_main.get_palette()
				if palette:
					current_shape.begin(drag_pos, _brush_drag_normal)
					var positions := current_shape.commit()
					_brush_apply_positions(positions, tile, palette)
					_brush_last_pos = drag_pos
			if brush_size > 1 and current_shape is BrushShape and _shape_preview:
				_highlight.visible = false
				var brush_preview := (current_shape as BrushShape)._generate_brush(drag_pos)
				_shape_preview.set_preview_color(current_mode)
				_shape_preview.update_positions(brush_preview)
			elif _highlight:
				_highlight.visible = true
				_highlight.set_voxel_pos(drag_pos)
		else:
			if _highlight:
				_highlight.visible = false
			if _shape_preview:
				_shape_preview.clear()
		return

	# Normal hover for non-active state
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)

	if _highlight:
		if result.hit:
			var hover_pos: Vector3i
			var face_normal: Vector3i
			if current_mode == PrimaryMode.ADD:
				hover_pos = result.previous
				face_normal = result.previous - result.position
			else:
				hover_pos = result.position
				face_normal = result.previous - result.position

			_update_highlight_color()

			# Brush with size > 1: show full sphere/circle preview
			var is_brush := current_shape_type == ShapeType.BRUSH and brush_size > 1
			if is_brush and _shape_preview and current_shape is BrushShape:
				_highlight.visible = false
				current_shape.face_normal = face_normal
				var brush_positions := (current_shape as BrushShape)._generate_brush(hover_pos)
				var all_positions := brush_positions
				if symmetry.has_any_symmetry():
					all_positions = _expand_with_symmetry(brush_positions)
				_shape_preview.set_preview_color(current_mode)
				_shape_preview.update_positions(all_positions)
			else:
				_highlight.visible = true
				_highlight.set_voxel_pos(hover_pos)

				# Show symmetry mirror previews
				if _shape_preview and symmetry.has_any_symmetry():
					var mirrored: Array[Vector3i] = _expand_with_symmetry([hover_pos])
					var sym_only: Array[Vector3i] = []
					for mp in mirrored:
						if mp != hover_pos:
							sym_only.append(mp)
					if not sym_only.is_empty():
						_shape_preview.set_preview_color(current_mode)
						_shape_preview.update_positions(sym_only)
					else:
						_shape_preview.clear()
				elif _shape_preview:
					_shape_preview.clear()
		else:
			_highlight.visible = false
			if _shape_preview:
				_shape_preview.clear()
	elif _shape_preview:
		_shape_preview.clear()


func handle_viewport_click(event: InputEventMouseButton) -> void:
	if not _camera or not _editor_main:
		return

	var tile := _editor_main.get_tile()
	var palette := _editor_main.get_palette()
	if not tile or not palette:
		return

	# Handle button release
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _brush_dragging:
			_brush_dragging = false
			undo_manager.commit_action(_brush_drag_action)
			_brush_drag_action = {}
			return
		if extrude_tool.active:
			_handle_extrude_release(tile, palette)
			return
		if select_tool.is_brush_dragging():
			select_tool.end_brush()
			return
		if transform_tool.is_any_active():
			_commit_transform()
			return

	var mouse_pos := _container_to_viewport(event.position)
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir := _camera.project_ray_normal(mouse_pos)

	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Alt+click = eyedropper in any mode
		if event.alt_pressed:
			var eye_result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
			if eye_result.hit:
				var idx := palette.find_entry(eye_result.voxel_id)
				if idx >= 0:
					selected_palette_index = idx
					palette_pick.emit(idx)
			return

		# Paste mode — click to commit paste at hover position
		if _paste_mode:
			var paste_result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
			if paste_result.hit:
				_commit_paste(tile, paste_result.previous)
			else:
				# Fallback to ground plane when no voxels exist yet
				var ground := _raycast_ground(ray_origin, ray_dir)
				if ground.x >= 0:
					_commit_paste(tile, ground)
			return

		# Mirror plane placement — click a face to place a plane
		if _mirror_place_mode:
			_handle_mirror_place_click(tile, ray_origin, ray_dir)
			return

		# Metadata tool — click to place/edit metadata points
		if current_tool_type == ToolType.METADATA:
			_handle_metadata_click(tile, ray_origin, ray_dir)
			return

		# Transform tool
		if current_tool_type == ToolType.TRANSFORM:
			_handle_transform_click(tile, ray_origin, ray_dir, event)
			return

		# Select tool
		if current_tool_type == ToolType.SELECT:
			_handle_select_click(tile, ray_origin, ray_dir, event)
			return

		# Fill/Extrude tools handle clicks directly
		if current_tool_type == ToolType.FILL:
			_handle_fill_click(tile, palette, ray_origin, ray_dir)
			return
		if current_tool_type == ToolType.EXTRUDE:
			_handle_extrude_click(tile, palette, ray_origin, ray_dir, event.position.y)
			return

		# If shape is active, this is the next click — commit or advance phase
		if current_shape.active:
			# Update with final position using appropriate projection
			if current_shape.in_height_phase():
				_update_height_from_mouse()
			else:
				if _project_onto_plane(ray_origin, ray_dir):
					current_shape.update(_plane_hit_pos)

			var positions := current_shape.commit()

			if current_shape.active:
				# Shape transitioned to height phase — capture mouse start position
				_setup_height_tracking()
				if _shape_preview:
					_shape_preview.set_preview_color(current_mode)
					_update_shape_preview()
			elif not positions.is_empty():
				_apply_mode_to_positions(positions, tile, palette)
				if _shape_preview:
					_shape_preview.clear()
			else:
				if _shape_preview:
					_shape_preview.clear()
			return

		# First click — get target position and face normal
		var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
		var target_pos: Vector3i
		var face_normal := Vector3i(0, 1, 0)  # Default up

		match current_mode:
			PrimaryMode.ADD:
				if result.hit:
					target_pos = result.previous
					face_normal = result.previous - result.position
				else:
					var ground := _raycast_ground(ray_origin, ray_dir)
					if ground.x < 0:
						return
					target_pos = ground
					face_normal = Vector3i(0, 1, 0)
			PrimaryMode.SUBTRACT:
				if not result.hit:
					return
				target_pos = result.position
				face_normal = result.previous - result.position
			PrimaryMode.PAINT:
				if not result.hit:
					return
				target_pos = result.position
				face_normal = result.previous - result.position

		if not _in_bounds(target_pos):
			return

		# Set up working plane for two-click shapes
		_work_plane_normal = Vector3(face_normal)
		_work_plane_point = Vector3(target_pos) + Vector3(0.5, 0.5, 0.5)

		# Begin the shape
		_sync_hollow()
		current_shape.begin(target_pos, face_normal)

		if not current_shape.requires_drag:
			# Immediate commit (single voxel / brush)
			var positions := current_shape.commit()
			if current_shape_type == ShapeType.BRUSH:
				# Start drag mode — create one undo action for the whole stroke
				_brush_dragging = true
				_brush_last_pos = target_pos
				_brush_drag_normal = face_normal
				_brush_drag_action = undo_manager.create_action(_mode_action_name())
				_brush_apply_positions(positions, tile, palette)
			else:
				_apply_mode_to_positions(positions, tile, palette)
		else:
			# Show initial preview
			if _shape_preview:
				_shape_preview.set_preview_color(current_mode)
				_update_shape_preview()

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# Right-click during mirror placement = cancel
		if _mirror_place_mode:
			_mirror_place_mode = false
			if _shape_preview:
				_shape_preview.clear()
			return
		# Right-click during active extrude = cancel
		if extrude_tool.active:
			extrude_tool.cancel()
			if _shape_preview:
				_shape_preview.clear()
			return
		# Right-click during active shape = cancel
		if current_shape.active:
			_cancel_shape()
			return
		# In metadata mode, right-click removes the metadata point
		if current_tool_type == ToolType.METADATA:
			var meta_rm := VoxelRaycast.cast(tile, ray_origin, ray_dir)
			if meta_rm.hit:
				_editor_main.remove_metadata_at(meta_rm.position)
			return
		# Otherwise, right-click removes a voxel
		var rm_result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
		if rm_result.hit:
			_apply_subtract_single(tile, rm_result.position)


func _apply_mode_to_positions(positions: Array[Vector3i], tile: WFCTileDef,
		palette: VoxelPalette) -> void:
	if positions.is_empty():
		return

	# Expand positions through symmetry
	var all_positions: Array[Vector3i] = _expand_with_symmetry(positions)

	var voxel_id := palette.get_voxel_id(selected_palette_index)
	var action := undo_manager.create_action(_mode_action_name())
	var renderer := _editor_main.get_tile_renderer()

	for pos in all_positions:
		if not _in_bounds(pos):
			continue
		var old_id := tile.get_voxel(pos.x, pos.y, pos.z)
		match current_mode:
			PrimaryMode.ADD:
				undo_manager.add_voxel_change(action, pos, old_id, voxel_id)
			PrimaryMode.SUBTRACT:
				undo_manager.add_voxel_change(action, pos, old_id, 0)
			PrimaryMode.PAINT:
				if old_id != 0:  # Only paint non-air
					undo_manager.add_voxel_change(action, pos, old_id, voxel_id)

	undo_manager.apply_and_commit(action, tile, renderer)


## Apply positions during a brush drag stroke — records into _brush_drag_action
## and writes voxels immediately, but does NOT commit (that happens on release).
func _brush_apply_positions(positions: Array[Vector3i], tile: WFCTileDef,
		palette: VoxelPalette) -> void:
	if positions.is_empty():
		return
	var all_positions: Array[Vector3i] = _expand_with_symmetry(positions)
	var voxel_id := palette.get_voxel_id(selected_palette_index)
	var renderer := _editor_main.get_tile_renderer()

	for pos in all_positions:
		if not _in_bounds(pos):
			continue
		var old_id := tile.get_voxel(pos.x, pos.y, pos.z)
		var new_id := old_id
		match current_mode:
			PrimaryMode.ADD:
				new_id = voxel_id
			PrimaryMode.SUBTRACT:
				new_id = 0
			PrimaryMode.PAINT:
				if old_id != 0:
					new_id = voxel_id
		if new_id != old_id:
			undo_manager.add_voxel_change(_brush_drag_action, pos, old_id, new_id)
			tile.set_voxel(pos.x, pos.y, pos.z, new_id)
			renderer.mark_voxel_dirty(pos.x, pos.y, pos.z)


func _handle_fill_click(tile: WFCTileDef, palette: VoxelPalette,
		ray_origin: Vector3, ray_dir: Vector3) -> void:
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)

	var target_pos: Vector3i
	match current_mode:
		PrimaryMode.ADD:
			# Fill air: start from the air voxel adjacent to the clicked face
			if result.hit:
				target_pos = result.previous
			else:
				var ground := _raycast_ground(ray_origin, ray_dir)
				if ground.x < 0:
					return
				target_pos = ground
		_:
			# Subtract/Paint: operate on the solid voxel that was clicked
			if not result.hit:
				return
			target_pos = result.position

	var raw_positions: Array[Vector3i] = fill_tool.execute(tile, target_pos, current_mode)
	if raw_positions.is_empty():
		return

	var positions: Array[Vector3i] = _expand_with_symmetry(raw_positions)
	var voxel_id := palette.get_voxel_id(selected_palette_index)
	var action := undo_manager.create_action("Fill")
	var renderer := _editor_main.get_tile_renderer()

	for pos in positions:
		if not _in_bounds(pos):
			continue
		var old_id := tile.get_voxel(pos.x, pos.y, pos.z)
		match current_mode:
			PrimaryMode.ADD:
				undo_manager.add_voxel_change(action, pos, old_id, voxel_id)
			PrimaryMode.SUBTRACT:
				undo_manager.add_voxel_change(action, pos, old_id, 0)
			PrimaryMode.PAINT:
				if old_id != 0:
					undo_manager.add_voxel_change(action, pos, old_id, voxel_id)

	undo_manager.apply_and_commit(action, tile, renderer)


func _handle_extrude_click(tile: WFCTileDef, _palette: VoxelPalette,
		ray_origin: Vector3, ray_dir: Vector3, mouse_y: float) -> void:
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	if not result.hit:
		return
	var face_dir := result.previous - result.position
	if extrude_tool.begin(tile, result.position, face_dir, _camera, mouse_y):
		# Show initial preview
		if _shape_preview:
			_shape_preview.set_preview_color(current_mode)
			_shape_preview.update_positions(extrude_tool.get_preview(current_mode))


func _handle_extrude_release(tile: WFCTileDef, palette: VoxelPalette) -> void:
	if not extrude_tool.active:
		return
	var layer_count := extrude_tool.layers
	var ext_result: Dictionary = extrude_tool.commit(tile, current_mode)
	var targets: Array = ext_result.targets
	if _shape_preview:
		_shape_preview.clear()
	if targets.is_empty():
		return

	# Expand extrude targets through symmetry
	var sym_targets: Array[Vector3i] = []
	for t in targets:
		sym_targets.append(t as Vector3i)
	sym_targets = _expand_with_symmetry(sym_targets)

	var voxel_id := palette.get_voxel_id(selected_palette_index)
	var action := undo_manager.create_action("Extrude %d layers" % layer_count)
	var renderer := _editor_main.get_tile_renderer()

	for i in sym_targets.size():
		var pos: Vector3i = sym_targets[i]
		if not _in_bounds(pos):
			continue
		var old_id := tile.get_voxel(pos.x, pos.y, pos.z)
		match current_mode:
			PrimaryMode.ADD:
				var src_id: int = ext_result.voxel_ids.get(pos, voxel_id)
				undo_manager.add_voxel_change(action, pos, old_id, src_id)
			PrimaryMode.SUBTRACT:
				undo_manager.add_voxel_change(action, pos, old_id, 0)
			PrimaryMode.PAINT:
				if old_id != 0:
					undo_manager.add_voxel_change(action, pos, old_id, voxel_id)

	undo_manager.apply_and_commit(action, tile, renderer)


## Handle mouse drag for extrude tool preview updates.
func handle_viewport_drag(event: InputEventMouseMotion) -> void:
	if not extrude_tool.active:
		return
	extrude_tool.update_drag(event.position.y)
	if _shape_preview:
		_shape_preview.set_preview_color(current_mode)
		_shape_preview.update_positions(extrude_tool.get_preview(current_mode))


func _apply_subtract_single(tile: WFCTileDef, pos: Vector3i) -> void:
	var positions: Array[Vector3i] = _expand_with_symmetry([pos])
	var action := undo_manager.create_action("Remove voxel")
	for p in positions:
		var old_id := tile.get_voxel(p.x, p.y, p.z)
		undo_manager.add_voxel_change(action, p, old_id, 0)
	undo_manager.apply_and_commit(action, tile, _editor_main.get_tile_renderer())


func _mode_action_name() -> String:
	var mode_str := "Add" if current_mode == PrimaryMode.ADD else \
		("Subtract" if current_mode == PrimaryMode.SUBTRACT else "Paint")
	var shape_str: String = ShapeType.keys()[current_shape_type].to_lower()
	return "%s %s" % [mode_str, shape_str]


func _cancel_shape() -> void:
	if current_shape.active:
		current_shape.cancel()
	if _shape_preview:
		_shape_preview.clear()


func _create_shape(shape_type: ShapeType) -> ShapeTool:
	var s: ShapeTool
	match shape_type:
		ShapeType.BRUSH:
			var b := BrushShape.new()
			b.brush_size = brush_size
			b.flat = brush_flat
			s = b
		ShapeType.LINE:
			s = LineShape.new()
		ShapeType.BOX:
			s = BoxShape.new()
		ShapeType.CIRCLE:
			s = CircleShape.new()
		ShapeType.POLYGON:
			s = PolygonShape.new()
		_:
			s = BrushShape.new()
	s.hollow = hollow
	s.sides = polygon_sides
	return s


## Update the shape preview — uses wireframe box for BoxShape, per-voxel cubes otherwise.
func _update_shape_preview() -> void:
	if not _shape_preview:
		return
	if current_shape is BoxShape:
		var box: BoxShape = current_shape as BoxShape
		var min_p := Vector3i(
			mini(box._start.x, box._end.x),
			mini(box._start.y, box._end.y),
			mini(box._start.z, box._end.z))
		var max_p := Vector3i(
			maxi(box._start.x, box._end.x),
			maxi(box._start.y, box._end.y),
			maxi(box._start.z, box._end.z))
		# In height phase, extend the box along face_normal
		if current_shape.in_height_phase():
			var h: int = current_shape._height
			var offset := current_shape.face_normal * h
			# Expand AABB to include the extruded end
			var ext_min := Vector3i(
				mini(min_p.x, min_p.x + offset.x),
				mini(min_p.y, min_p.y + offset.y),
				mini(min_p.z, min_p.z + offset.z))
			var ext_max := Vector3i(
				maxi(max_p.x, max_p.x + offset.x),
				maxi(max_p.y, max_p.y + offset.y),
				maxi(max_p.z, max_p.z + offset.z))
			min_p = ext_min
			max_p = ext_max
		_shape_preview.update_box_wireframe(min_p, max_p)
	else:
		var preview: Array[Vector3i] = current_shape.get_preview()
		_shape_preview.update_positions(_expand_with_symmetry(preview))


func _sync_hollow() -> void:
	current_shape.hollow = hollow
	current_shape.sides = polygon_sides
	if current_shape is BrushShape:
		current_shape.brush_size = brush_size
		current_shape.flat = brush_flat


## Project ray onto the working plane. Returns true and writes to out_pos if hit.
var _plane_hit_pos := Vector3i.ZERO
var _plane_hit_float := Vector3.ZERO

func _project_onto_plane(ray_origin: Vector3, ray_dir: Vector3) -> bool:
	var denom := _work_plane_normal.dot(ray_dir)
	if absf(denom) < 0.0001:
		return false
	var t := _work_plane_normal.dot(_work_plane_point - ray_origin) / denom
	if t < 0.0:
		return false
	var hit := ray_origin + ray_dir * t
	_plane_hit_float = hit
	_plane_hit_pos = Vector3i(int(floorf(hit.x)), int(floorf(hit.y)), int(floorf(hit.z)))
	return true


## Compute the angle of a point on a plane perpendicular to the given axis.
func _compute_angle_on_plane(point: Vector3, center: Vector3, axis: int) -> float:
	var rel := point - center
	match axis:
		0:  # X — use Y and Z
			return rad_to_deg(atan2(rel.z, rel.y))
		1:  # Y — use X and Z
			return rad_to_deg(atan2(rel.x, rel.z))
		_:  # Z — use X and Y
			return rad_to_deg(atan2(rel.y, rel.x))


## Height tracking via screen-space mouse delta — no raycasting needed.
## Captures the screen direction of face_normal and start mouse position at
## phase transition, then tracks how far the mouse moves along that direction.
var _height_start_mouse := Vector2.ZERO
var _height_screen_dir := Vector2.ZERO   # Normalized screen direction of face_normal
var _height_pixels_per_voxel := 20.0     # How many screen pixels = 1 voxel of height

const HEIGHT_MIN_PIXELS_PER_VOXEL := 4.0


func _setup_height_tracking() -> void:
	_height_start_mouse = _container_to_viewport(
		_viewport_container.get_local_mouse_position())
	# Project face_normal to screen space to get the drag direction
	var base_world := _work_plane_point
	var face_n := Vector3(current_shape.face_normal)
	var screen_base := _camera.unproject_position(base_world)
	var screen_tip := _camera.unproject_position(base_world + face_n)
	var screen_delta := screen_tip - screen_base
	var ppu := screen_delta.length()
	if ppu < HEIGHT_MIN_PIXELS_PER_VOXEL:
		# Face normal nearly perpendicular to screen — fall back to vertical drag
		_height_screen_dir = Vector2(0, -1)
		_height_pixels_per_voxel = 20.0
	else:
		_height_screen_dir = screen_delta / ppu
		_height_pixels_per_voxel = ppu


func _update_height_from_mouse() -> void:
	var current_mouse := _container_to_viewport(
		_viewport_container.get_local_mouse_position())
	var delta := current_mouse - _height_start_mouse
	var projected := delta.dot(_height_screen_dir)
	current_shape.set_height(int(roundf(projected / _height_pixels_per_voxel)))


func _do_undo() -> void:
	var tile := _editor_main.get_tile()
	if tile:
		undo_manager.undo(tile, _editor_main.get_tile_renderer())


func _do_redo() -> void:
	var tile := _editor_main.get_tile()
	if tile:
		undo_manager.redo(tile, _editor_main.get_tile_renderer())


func _in_bounds(pos: Vector3i) -> bool:
	var tile := _editor_main.get_tile()
	if tile:
		return pos.x >= 0 and pos.x < tile.tile_size_x and \
				pos.y >= 0 and pos.y < tile.tile_size_y and \
				pos.z >= 0 and pos.z < tile.tile_size_z
	return pos.x >= 0 and pos.x < WFCTileDef.TILE_X and \
			pos.y >= 0 and pos.y < WFCTileDef.TILE_Y and \
			pos.z >= 0 and pos.z < WFCTileDef.TILE_Z


func _update_highlight_color() -> void:
	if not _highlight:
		return
	var paint_color := Color.TRANSPARENT
	if current_mode == PrimaryMode.PAINT:
		var palette := _editor_main.get_palette()
		if palette and selected_palette_index >= 0 and selected_palette_index < palette.entries.size():
			paint_color = palette.entries[selected_palette_index].color
	_highlight.set_mode_color(current_mode, paint_color)


func _raycast_ground(origin: Vector3, dir: Vector3) -> Vector3i:
	if absf(dir.y) < 0.001:
		return Vector3i(-1, -1, -1)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector3i(-1, -1, -1)
	var hit_point := origin + dir * t
	var vx := int(floorf(hit_point.x))
	var vz := int(floorf(hit_point.z))
	var tile := _editor_main.get_tile()
	var max_x: int = tile.tile_size_x if tile else WFCTileDef.TILE_X
	var max_z: int = tile.tile_size_z if tile else WFCTileDef.TILE_Z
	if vx < 0 or vx >= max_x or vz < 0 or vz >= max_z:
		return Vector3i(-1, -1, -1)
	return Vector3i(vx, 0, vz)


# --- Selection system ---

func _on_selection_changed() -> void:
	if _selection_renderer:
		_selection_renderer.update_selection(selection)
	_update_gizmo()
	selection_changed.emit()


func _update_gizmo() -> void:
	if not _transform_gizmo:
		return
	if current_tool_type == ToolType.TRANSFORM and not selection.is_empty():
		# Sync gizmo visual mode with transform tool mode
		match transform_tool.mode:
			TransformTool.TransformMode.ROTATE:
				_transform_gizmo.set_gizmo_mode(TransformGizmo.GizmoMode.ROTATE)
			TransformTool.TransformMode.SCALE:
				_transform_gizmo.set_gizmo_mode(TransformGizmo.GizmoMode.SCALE)
			_:
				_transform_gizmo.set_gizmo_mode(TransformGizmo.GizmoMode.MOVE)
		_transform_gizmo.update_position(selection.get_positions())
	else:
		_transform_gizmo.visible = false


func _handle_select_click(tile: WFCTileDef, ray_origin: Vector3,
		ray_dir: Vector3, event: InputEventMouseButton) -> void:
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	if not result.hit:
		if not event.shift_pressed:
			selection.clear()
		return

	var face := result.previous - result.position

	match select_tool.mode:
		SelectTool.SelectMode.BOX:
			if select_tool._box_active:
				# Second click — commit box selection with filters
				if _project_onto_plane(ray_origin, ray_dir):
					select_tool.update(_plane_hit_pos)
				var positions := select_tool.commit_box(tile, _select_ref_id)
				var sym_positions: Array[Vector3i] = _expand_with_symmetry(positions)
				if event.shift_pressed:
					selection.add_array(sym_positions)
				else:
					selection.set_positions(sym_positions)
				if _shape_preview:
					_shape_preview.clear()
			else:
				# First click — start box, capture ref voxel for filtering
				if not event.shift_pressed:
					selection.clear()
				_select_ref_id = tile.get_voxel(
					result.position.x, result.position.y, result.position.z)
				_work_plane_normal = Vector3(face)
				_work_plane_point = Vector3(result.position) + Vector3(0.5, 0.5, 0.5)
				select_tool.begin(result.position, face)

		SelectTool.SelectMode.BRUSH:
			# Click starts drag — add clicked voxel(s) within brush size, drag adds more
			if not event.shift_pressed and not select_tool.is_brush_dragging():
				selection.clear()
			var brush_positions: Array[Vector3i] = select_tool.get_brush_positions(result.position)
			var brush_sym: Array[Vector3i] = _expand_with_symmetry(brush_positions)
			for bp in brush_sym:
				selection.add(bp)
			select_tool.begin(result.position, face)

		SelectTool.SelectMode.MAGIC:
			# Flood select using query (connectivity + filters)
			if not event.shift_pressed:
				selection.clear()
			var positions := select_tool.magic_select(tile, result.position, face)
			var sym_positions_m: Array[Vector3i] = _expand_with_symmetry(positions)
			if event.shift_pressed:
				selection.add_array(sym_positions_m)
			else:
				selection.set_positions(sym_positions_m)


## Update select tool preview during hover.
func _update_select_hover(ray_origin: Vector3, ray_dir: Vector3) -> void:
	if select_tool.mode == SelectTool.SelectMode.BOX and select_tool._box_active:
		if _project_onto_plane(ray_origin, ray_dir):
			select_tool.update(_plane_hit_pos)
			if _shape_preview:
				_shape_preview.set_preview_color(PrimaryMode.ADD)
				var box_min := Vector3i(
					mini(select_tool._box_start.x, select_tool._box_end.x),
					mini(select_tool._box_start.y, select_tool._box_end.y),
					mini(select_tool._box_start.z, select_tool._box_end.z))
				var box_max := Vector3i(
					maxi(select_tool._box_start.x, select_tool._box_end.x),
					maxi(select_tool._box_start.y, select_tool._box_end.y),
					maxi(select_tool._box_start.z, select_tool._box_end.z))
				_shape_preview.update_box_wireframe(box_min, box_max)
	elif select_tool.mode == SelectTool.SelectMode.BRUSH and select_tool.is_brush_dragging():
		# Brush drag — add voxels within brush size as mouse moves
		var tile := _editor_main.get_tile()
		if tile:
			var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
			if result.hit:
				var drag_positions: Array[Vector3i] = select_tool.get_brush_positions(result.position)
				var drag_sym: Array[Vector3i] = _expand_with_symmetry(drag_positions)
				for dp in drag_sym:
					selection.add(dp)


# --- Clipboard operations ---

func copy_selection() -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	clipboard.copy(tile, selection)


func cut_selection() -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	clipboard.copy(tile, selection)
	delete_selection()


func begin_paste() -> void:
	if clipboard.is_empty():
		return
	_paste_mode = true


func _commit_paste(tile: WFCTileDef, anchor: Vector3i) -> void:
	_paste_mode = false
	var paste_data := clipboard.get_paste_data(anchor)
	var positions: Array = paste_data.positions
	var voxel_ids: Dictionary = paste_data.voxel_ids
	if positions.is_empty():
		return

	var action := undo_manager.create_action("Paste")
	var renderer := _editor_main.get_tile_renderer()

	# Build typed array for symmetry expansion
	var typed_positions: Array[Vector3i] = []
	for pos in positions:
		typed_positions.append(pos as Vector3i)

	if symmetry.has_any_symmetry():
		# For each original position, mirror it and paste the same voxel ID
		var done := {}
		for pos in typed_positions:
			var mirrored: Array[Vector3i] = symmetry.mirror_positions(pos)
			for mp in mirrored:
				if _in_bounds(mp) and not done.has(mp):
					done[mp] = true
					var old_id := tile.get_voxel(mp.x, mp.y, mp.z)
					var new_id: int = voxel_ids.get(pos, 0)
					undo_manager.add_voxel_change(action, mp, old_id, new_id)
	else:
		for pos in positions:
			var p: Vector3i = pos
			var old_id := tile.get_voxel(p.x, p.y, p.z)
			var new_id: int = voxel_ids[p]
			undo_manager.add_voxel_change(action, p, old_id, new_id)

	undo_manager.apply_and_commit(action, tile, renderer)
	if _shape_preview:
		_shape_preview.clear()


func _update_paste_preview(ray_origin: Vector3, ray_dir: Vector3) -> void:
	var tile := _editor_main.get_tile()
	if not tile:
		return
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	var anchor := Vector3i(-1, -1, -1)
	if result.hit:
		anchor = result.previous
	else:
		# Fallback to ground plane when no voxels exist yet
		anchor = _raycast_ground(ray_origin, ray_dir)
	if anchor.x >= 0 and _shape_preview:
		var preview := clipboard.get_paste_preview(anchor)
		_shape_preview.set_preview_color(PrimaryMode.ADD)
		_shape_preview.update_positions(preview)
	elif _shape_preview:
		_shape_preview.clear()


# --- Selection actions ---

func select_all() -> void:
	var tile := _editor_main.get_tile()
	if not tile:
		return
	var positions: Array[Vector3i] = []
	for x in tile.tile_size_x:
		for y in tile.tile_size_y:
			for z in tile.tile_size_z:
				if tile.get_voxel(x, y, z) != 0:
					positions.append(Vector3i(x, y, z))
				if positions.size() >= 100000:
					break
			if positions.size() >= 100000:
				break
		if positions.size() >= 100000:
			break
	selection.set_positions(positions)


func delete_selection() -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var action := undo_manager.create_action("Delete selection")
	action.selection_before = selection.get_positions().duplicate()
	var renderer := _editor_main.get_tile_renderer()
	for pos in selection.get_positions():
		var old_id := tile.get_voxel(pos.x, pos.y, pos.z)
		if old_id != 0:
			undo_manager.add_voxel_change(action, pos, old_id, 0)
	selection.clear()
	action.selection_after = [] as Array[Vector3i]
	undo_manager.apply_and_commit(action, tile, renderer)


# --- Edit operations (operate on selection, go through undo) ---

func apply_edit_op(op_result: Dictionary, description: String) -> void:
	var tile := _editor_main.get_tile()
	if not tile:
		return
	var old_data: Dictionary = op_result.get("old_data", {})
	var new_data: Dictionary = op_result.get("new_data", {})
	var clear_positions = op_result.get("clear_positions", null)
	var new_positions = op_result.get("new_positions", null)

	if old_data.is_empty() and new_data.is_empty():
		return

	var action := undo_manager.create_action(description)
	var renderer := _editor_main.get_tile_renderer()

	# Save selection state for undo
	action.selection_before = selection.get_positions().duplicate()

	# Clear source positions (for move-type operations like rotate/flip)
	if clear_positions != null:
		for pos in clear_positions:
			var p: Vector3i = pos
			if not new_data.has(p):
				var old_id := tile.get_voxel(p.x, p.y, p.z)
				if old_id != 0:
					undo_manager.add_voxel_change(action, p, old_id, 0)

	# Write new data
	for pos in new_data:
		var p: Vector3i = pos
		var old_id := tile.get_voxel(p.x, p.y, p.z)
		var new_id: int = new_data[p]
		if old_id != new_id:
			undo_manager.add_voxel_change(action, p, old_id, new_id)

	# Update selection to new positions if provided
	if new_positions != null:
		selection.set_positions(new_positions)

	# Save selection state for redo
	action.selection_after = selection.get_positions().duplicate()

	undo_manager.apply_and_commit(action, tile, renderer)


func rotate_selection(axis: int) -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var result := EditOperations.rotate(tile, selection, axis)
	apply_edit_op(result, "Rotate %s" % ["X", "Y", "Z"][axis])


func flip_selection(axis: int) -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var result := EditOperations.flip(tile, selection, axis)
	apply_edit_op(result, "Flip %s" % ["X", "Y", "Z"][axis])


func mirror_selection(axis: int) -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var result := EditOperations.mirror(tile, selection, axis)
	apply_edit_op(result, "Mirror %s" % ["X", "Y", "Z"][axis])


func hollow_selection() -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var result := EditOperations.hollow(tile, selection)
	apply_edit_op(result, "Hollow")


func flood_interior_selection() -> void:
	var tile := _editor_main.get_tile()
	var palette := _editor_main.get_palette()
	if not tile or not palette or selection.is_empty():
		return
	var fill_id := palette.get_voxel_id(selected_palette_index)
	var result := EditOperations.flood_interior(tile, selection, fill_id)
	apply_edit_op(result, "Flood interior")


func dilate_selection(iterations: int = 1) -> void:
	var tile := _editor_main.get_tile()
	var palette := _editor_main.get_palette()
	if not tile or not palette or selection.is_empty():
		return
	var fill_id := palette.get_voxel_id(selected_palette_index)
	var result := EditOperations.dilate(tile, selection, fill_id, iterations)
	apply_edit_op(result, "Dilate %d" % iterations)


func erode_selection(iterations: int = 1) -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var result := EditOperations.erode(tile, selection, iterations)
	apply_edit_op(result, "Erode %d" % iterations)


func scale_selection(factor: float) -> void:
	var tile := _editor_main.get_tile()
	if not tile or selection.is_empty():
		return
	var result := EditOperations.scale(tile, selection, factor)
	apply_edit_op(result, "Scale %.2gx" % factor)


# --- Selection settings ---

func _cycle_connectivity() -> void:
	var q := select_tool.query
	if q.connectivity == VoxelQuery.Connectivity.GEOMETRY:
		q.connectivity = VoxelQuery.Connectivity.FACE
	else:
		q.connectivity = VoxelQuery.Connectivity.GEOMETRY
	fill_tool.query.connectivity = q.connectivity
	select_settings_changed.emit()


func toggle_filter_color() -> void:
	select_tool.query.filter_color = not select_tool.query.filter_color
	fill_tool.query.filter_color = select_tool.query.filter_color
	select_settings_changed.emit()


func toggle_filter_material() -> void:
	select_tool.query.filter_material = not select_tool.query.filter_material
	fill_tool.query.filter_material = select_tool.query.filter_material
	select_settings_changed.emit()


# --- Symmetry ---

func _on_symmetry_changed() -> void:
	_update_symmetry_visuals()
	symmetry_changed.emit()


func _update_symmetry_visuals() -> void:
	if _symmetry_renderer:
		_symmetry_renderer.update_planes(symmetry.get_plane_visuals())


func sync_symmetry_tile_size() -> void:
	var tile := _editor_main.get_tile()
	if tile:
		symmetry.set_tile_size(tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
		if _symmetry_renderer:
			_symmetry_renderer.set_tile_size(tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
		_update_symmetry_visuals()


## Apply symmetry expansion to positions, filtering out-of-bounds results.
func _expand_with_symmetry(positions: Array[Vector3i]) -> Array[Vector3i]:
	if not symmetry.has_any_symmetry():
		return positions
	var expanded: Array[Vector3i] = symmetry.apply_symmetry(positions)
	# Filter out-of-bounds
	var result: Array[Vector3i] = []
	for pos in expanded:
		if _in_bounds(pos):
			result.append(pos)
	return result


# --- Metadata tool ---

func _handle_metadata_click(tile: WFCTileDef, ray_origin: Vector3,
		ray_dir: Vector3) -> void:
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	if not result.hit:
		return
	# Click on existing voxel — place metadata at that position
	var pos := result.position
	_editor_main.open_metadata_dialog(pos)


var _metadata_tool_ref: MetadataTool

func set_metadata_tool(tool: MetadataTool) -> void:
	_metadata_tool_ref = tool
	if _metadata_renderer:
		_metadata_renderer.set_metadata_tool(tool)


func refresh_metadata_markers() -> void:
	var tile := _editor_main.get_tile()
	if _metadata_renderer and tile:
		_metadata_renderer.update_markers(tile)


func set_marker_scale(scale: float) -> void:
	if _metadata_renderer:
		_metadata_renderer.marker_scale = scale
		refresh_metadata_markers()


## Enter custom mirror plane placement mode.
func begin_mirror_place() -> void:
	_mirror_place_mode = true


## Handle click during mirror plane placement.
func _handle_mirror_place_click(tile: WFCTileDef, ray_origin: Vector3,
		ray_dir: Vector3) -> void:
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	if not result.hit:
		# Try ground plane
		var ground := _raycast_ground(ray_origin, ray_dir)
		if ground.x < 0:
			return
		# Default to Y axis at ground level
		symmetry.add_custom_plane(Vector3i(0, 1, 0), float(ground.y))
		_mirror_place_mode = false
		if _shape_preview:
			_shape_preview.clear()
		return

	# Determine which axis based on the clicked face normal
	var face := result.previous - result.position
	var axis := Vector3i.ZERO
	var plane_pos: float

	if absi(face.x) > 0:
		axis = Vector3i(1, 0, 0)
		# Place plane at the boundary between the two voxels
		plane_pos = float(result.position.x) + (0.5 + 0.5 * signf(float(face.x)))
	elif absi(face.y) > 0:
		axis = Vector3i(0, 1, 0)
		plane_pos = float(result.position.y) + (0.5 + 0.5 * signf(float(face.y)))
	else:
		axis = Vector3i(0, 0, 1)
		plane_pos = float(result.position.z) + (0.5 + 0.5 * signf(float(face.z)))

	symmetry.add_custom_plane(axis, plane_pos)
	_mirror_place_mode = false
	if _shape_preview:
		_shape_preview.clear()


## Show a preview plane while hovering in mirror placement mode.
func _update_mirror_place_preview(ray_origin: Vector3, ray_dir: Vector3,
		tile: WFCTileDef) -> void:
	if _highlight:
		_highlight.visible = false

	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	if not result.hit:
		if _shape_preview:
			_shape_preview.clear()
		return

	# Show the face the user is hovering as a single-voxel highlight
	if _shape_preview:
		_shape_preview.set_preview_color(PrimaryMode.PAINT)
		_shape_preview.update_positions([result.position])


## Remove a custom mirror plane by index.
func remove_custom_mirror_plane(index: int) -> void:
	symmetry.remove_custom_plane(index)


## Remove all custom mirror planes.
func clear_custom_mirror_planes() -> void:
	symmetry.clear_custom_planes()


# --- Transform ---

func _nudge_transform(offset: Vector3i) -> void:
	var tile := _editor_main.get_tile()
	if not tile:
		return
	if not transform_tool.active:
		# Start a new move from current selection
		transform_tool.begin_move(tile, selection, Vector3i.ZERO)
	transform_tool.nudge(offset)
	# Show preview
	if _shape_preview:
		_shape_preview.set_preview_color(PrimaryMode.ADD)
		_shape_preview.update_positions(transform_tool.get_move_preview())


func _commit_transform() -> void:
	var tile := _editor_main.get_tile()
	if not tile:
		return

	if transform_tool.rotating:
		var degrees := transform_tool.get_rotate_degrees()
		var axis := transform_tool.get_rotate_axis()
		transform_tool.cancel()
		if _transform_gizmo:
			_transform_gizmo.clear_rotate_feedback()
		if absf(degrees) < 0.5:
			if _shape_preview:
				_shape_preview.clear()
			_update_gizmo()
			return
		var result := EditOperations.rotate_degrees(tile, selection, axis, degrees)
		apply_edit_op(result, "Rotate %.0f°" % degrees)
	elif transform_tool.scaling:
		var factor := transform_tool.get_scale_factor()
		transform_tool.cancel()
		if is_equal_approx(factor, 1.0):
			if _shape_preview:
				_shape_preview.clear()
			_update_gizmo()
			return
		var result := EditOperations.scale(tile, selection, factor)
		apply_edit_op(result, "Scale %.2gx" % factor)
	elif transform_tool.active:
		var result := transform_tool.commit_move(tile)
		apply_edit_op(result, "Move selection")
	else:
		return

	if _shape_preview:
		_shape_preview.clear()
	_update_gizmo()


func _handle_transform_click(tile: WFCTileDef, ray_origin: Vector3,
		ray_dir: Vector3, event: InputEventMouseButton) -> void:
	if not event.pressed:
		# Release — commit any active drag
		if transform_tool.is_any_active():
			_commit_transform()
		return

	# Test gizmo handles first
	var mouse_pos := _container_to_viewport(event.position)
	var handle := _transform_gizmo.test_hit(_camera, mouse_pos)

	if handle != TransformGizmo.Handle.NONE:
		var gizmo_center := _transform_gizmo.global_position

		# Ring click → start rotate drag
		var ring_axis := _transform_gizmo.ring_handle_to_axis(handle)
		if ring_axis >= 0:
			# Set work plane perpendicular to the rotation axis
			var axis_vectors := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
			_work_plane_normal = axis_vectors[ring_axis]
			_work_plane_point = gizmo_center
			if _project_onto_plane(ray_origin, ray_dir):
				var start_angle := _compute_angle_on_plane(
					_plane_hit_float, gizmo_center, ring_axis)
				transform_tool.begin_rotate(tile, selection, ring_axis, start_angle)
			return

		# Scale mode: axis/plane/center handle click → start scale drag
		if transform_tool.mode == TransformTool.TransformMode.SCALE:
			var scale_constraint := _handle_to_constraint(handle)
			_setup_transform_drag_plane(scale_constraint, gizmo_center, ray_dir)
			if _project_onto_plane(ray_origin, ray_dir):
				var dist := _plane_hit_float.distance_to(gizmo_center)
				transform_tool.begin_scale(tile, selection, dist)
			return

		# Move mode (default): axis/plane/center handle click → start move drag
		var constraint := _handle_to_constraint(handle)
		transform_tool.constraint = constraint
		_setup_transform_drag_plane(constraint, gizmo_center, ray_dir)
		if _project_onto_plane(ray_origin, ray_dir):
			transform_tool.begin_move(tile, selection, _plane_hit_pos)
		return

	# Fallback: click on a selected voxel for free drag (move only)
	var result := VoxelRaycast.cast(tile, ray_origin, ray_dir)
	if not result.hit:
		return

	var clicked := result.position
	if selection.contains(clicked):
		transform_tool.constraint = TransformTool.Constraint.FREE
		var face := result.previous - result.position
		_work_plane_normal = Vector3(face)
		_work_plane_point = Vector3(clicked) + Vector3(0.5, 0.5, 0.5)
		transform_tool.begin_move(tile, selection, clicked)


func _setup_transform_drag_plane(constraint: TransformTool.Constraint,
		center: Vector3, ray_dir: Vector3) -> void:
	_work_plane_point = center
	match constraint:
		TransformTool.Constraint.AXIS_X:
			# Best plane containing X axis: pick the one most facing camera
			var dot_y := absf(ray_dir.y)
			var dot_z := absf(ray_dir.z)
			_work_plane_normal = Vector3.UP if dot_y > dot_z else Vector3.BACK
		TransformTool.Constraint.AXIS_Y:
			var dot_x := absf(ray_dir.x)
			var dot_z := absf(ray_dir.z)
			_work_plane_normal = Vector3.RIGHT if dot_x > dot_z else Vector3.BACK
		TransformTool.Constraint.AXIS_Z:
			var dot_x := absf(ray_dir.x)
			var dot_y := absf(ray_dir.y)
			_work_plane_normal = Vector3.RIGHT if dot_x > dot_y else Vector3.UP
		TransformTool.Constraint.PLANE_XY:
			_work_plane_normal = Vector3.BACK
		TransformTool.Constraint.PLANE_XZ:
			_work_plane_normal = Vector3.UP
		TransformTool.Constraint.PLANE_YZ:
			_work_plane_normal = Vector3.RIGHT
		_:  # FREE
			# Use camera-facing plane
			_work_plane_normal = -ray_dir


func _handle_to_constraint(handle: TransformGizmo.Handle) -> TransformTool.Constraint:
	match handle:
		TransformGizmo.Handle.AXIS_X, TransformGizmo.Handle.AXIS_NEG_X:
			return TransformTool.Constraint.AXIS_X
		TransformGizmo.Handle.AXIS_Y, TransformGizmo.Handle.AXIS_NEG_Y:
			return TransformTool.Constraint.AXIS_Y
		TransformGizmo.Handle.AXIS_Z, TransformGizmo.Handle.AXIS_NEG_Z:
			return TransformTool.Constraint.AXIS_Z
		TransformGizmo.Handle.PLANE_XY:
			return TransformTool.Constraint.PLANE_XY
		TransformGizmo.Handle.PLANE_XZ:
			return TransformTool.Constraint.PLANE_XZ
		TransformGizmo.Handle.PLANE_YZ:
			return TransformTool.Constraint.PLANE_YZ
		TransformGizmo.Handle.FREE:
			return TransformTool.Constraint.FREE
	return TransformTool.Constraint.FREE


func _update_transform_hover(ray_origin: Vector3, ray_dir: Vector3) -> void:
	# Highlight gizmo handles on hover (even when not dragging)
	if _transform_gizmo and _transform_gizmo.visible and not transform_tool.is_any_active():
		var mouse_pos := _container_to_viewport(
			_viewport_container.get_local_mouse_position())
		var handle := _transform_gizmo.test_hit(_camera, mouse_pos)
		_transform_gizmo.set_highlight(handle)

	# Rotate drag update
	if transform_tool.rotating:
		if _project_onto_plane(ray_origin, ray_dir):
			var angle := _compute_angle_on_plane(
				_plane_hit_float, _transform_gizmo.global_position,
				transform_tool.get_rotate_axis())
			var snap := Input.is_key_pressed(KEY_SHIFT)
			transform_tool.update_rotate(angle, snap)
			if _shape_preview:
				_shape_preview.set_preview_color(PrimaryMode.ADD)
				_shape_preview.update_positions(transform_tool.get_rotate_preview())
			if _transform_gizmo:
				_transform_gizmo.set_rotate_feedback(
					transform_tool.get_rotate_axis(),
					transform_tool._rotate_start_angle,
					transform_tool._rotate_start_angle + transform_tool._rotate_degrees)
		return

	# Scale drag update
	if transform_tool.scaling:
		if _project_onto_plane(ray_origin, ray_dir):
			var dist := _plane_hit_float.distance_to(_transform_gizmo.global_position)
			transform_tool.update_scale(dist)
			if _shape_preview:
				_shape_preview.set_preview_color(PrimaryMode.ADD)
				_shape_preview.update_positions(transform_tool.get_scale_preview())
		return

	# Move drag update
	if not transform_tool.active:
		return
	if _project_onto_plane(ray_origin, ray_dir):
		transform_tool.update_move(_plane_hit_pos)
		if _shape_preview:
			_shape_preview.set_preview_color(PrimaryMode.ADD)
			_shape_preview.update_positions(transform_tool.get_move_preview())
