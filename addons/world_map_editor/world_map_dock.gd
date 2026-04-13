@tool
extends Control

const CELL_SIZE := 32.0

var _world_map: WorldMap
var _selected_biome: int = 1  # 1-based index into biome_palette
var _mode: int = 0  # 0 = paint biome, 1 = fixed chunk
var _camera_offset := Vector2.ZERO
var _zoom: float = 1.0
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _painting: bool = false

@onready var _grid_canvas: Control = %GridCanvas
@onready var _width_spin: SpinBox = %WidthSpin
@onready var _height_spin: SpinBox = %HeightSpin
@onready var _biome_list: ItemList = %BiomeList
@onready var _mode_button: OptionButton = %ModeButton
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _add_biome_button: Button = %AddBiomeButton
@onready var _file_dialog: FileDialog = %FileDialog
@onready var _fixed_file_dialog: FileDialog = %FixedFileDialog
var _pending_fixed_cell := Vector2i.ZERO


func _ready() -> void:
	_world_map = WorldMap.new()
	_setup_default_biomes()
	_refresh_biome_list()

	_width_spin.value = _world_map.grid_width
	_height_spin.value = _world_map.grid_height
	_width_spin.value_changed.connect(_on_size_changed)
	_height_spin.value_changed.connect(_on_size_changed)

	_mode_button.add_item("Paint Biome", 0)
	_mode_button.add_item("Fixed Chunk", 1)
	_mode_button.item_selected.connect(func(idx: int) -> void: _mode = idx)

	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_add_biome_button.pressed.connect(_on_add_biome_pressed)

	_biome_list.item_selected.connect(func(idx: int) -> void: _selected_biome = idx + 1)

	_grid_canvas.draw.connect(_draw_grid)
	_grid_canvas.gui_input.connect(_on_canvas_input)

	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.add_filter("*.tres", "WorldMap Resource")
	_file_dialog.file_selected.connect(_on_file_selected)

	_fixed_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_fixed_file_dialog.add_filter("*.res;*.tres", "Tile Resource")
	_fixed_file_dialog.file_selected.connect(_on_fixed_file_selected)


func _setup_default_biomes() -> void:
	var stone_biome := BiomeDef.new()
	stone_biome.biome_name = "stone_cavern"
	stone_biome.color = Color(0.5, 0.5, 0.55)
	stone_biome.surface_material = MaterialRegistry.STONE

	var dirt_biome := BiomeDef.new()
	dirt_biome.biome_name = "dirt_plains"
	dirt_biome.color = Color(0.55, 0.35, 0.18)
	dirt_biome.surface_material = MaterialRegistry.DIRT

	var lava_biome := BiomeDef.new()
	lava_biome.biome_name = "lava_forge"
	lava_biome.color = Color(0.9, 0.3, 0.1)
	lava_biome.surface_material = MaterialRegistry.LAVA

	_world_map.biome_palette = [stone_biome, dirt_biome, lava_biome]


func _refresh_biome_list() -> void:
	_biome_list.clear()
	for biome in _world_map.biome_palette:
		var idx := _biome_list.add_item(biome.biome_name)
		_biome_list.set_item_custom_bg_color(idx, biome.color)
		# Ensure text is readable against the background
		var lum := biome.color.r * 0.299 + biome.color.g * 0.587 + biome.color.b * 0.114
		_biome_list.set_item_custom_fg_color(idx, Color.BLACK if lum > 0.5 else Color.WHITE)


func _draw_grid() -> void:
	if not _world_map:
		return

	var w := _world_map.grid_width
	var h := _world_map.grid_height
	var cs := CELL_SIZE * _zoom

	for gz in h:
		for gx in w:
			var rect := Rect2(
				_camera_offset + Vector2(gx, gz) * cs,
				Vector2(cs, cs)
			)
			var biome_id := _world_map.get_cell(gx, gz)

			# Fill cell color
			if _world_map.is_fixed(gx, gz):
				_grid_canvas.draw_rect(rect, Color(0.2, 0.8, 0.9, 0.7))
			elif biome_id > 0:
				var biome := _world_map.get_biome(biome_id)
				if biome:
					_grid_canvas.draw_rect(rect, biome.color)
				else:
					_grid_canvas.draw_rect(rect, Color(0.15, 0.15, 0.15))
			else:
				_grid_canvas.draw_rect(rect, Color(0.1, 0.1, 0.1))

			# Cell border
			_grid_canvas.draw_rect(rect, Color(0.3, 0.3, 0.3), false, 1.0)

			# Label
			var label := ""
			if _world_map.is_fixed(gx, gz):
				label = "F"
			elif biome_id > 0:
				var biome := _world_map.get_biome(biome_id)
				if biome:
					label = biome.biome_name.left(3).to_upper()
			if label != "" and cs >= 20.0:
				_grid_canvas.draw_string(
					ThemeDB.fallback_font,
					rect.position + Vector2(4, cs * 0.65),
					label,
					HORIZONTAL_ALIGNMENT_LEFT,
					int(cs - 8),
					int(cs * 0.35)
				)


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_drag_start = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_painting = true
			_handle_paint(mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_painting = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 1.1, 0.2, 5.0)
			_grid_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom / 1.1, 0.2, 5.0)
			_grid_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_erase(mb.position)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_camera_offset += mm.relative
			_grid_canvas.queue_redraw()
		elif _painting and _mode == 0:
			_handle_paint(mm.position)


func _handle_paint(pos: Vector2) -> void:
	var cell := _screen_to_cell(pos)
	if cell.x < 0 or cell.x >= _world_map.grid_width:
		return
	if cell.y < 0 or cell.y >= _world_map.grid_height:
		return

	if _mode == 0:
		# Paint biome
		_world_map.set_cell(cell.x, cell.y, _selected_biome)
		_grid_canvas.queue_redraw()
	elif _mode == 1:
		# Fixed chunk — open file picker (only if not already open)
		if not _fixed_file_dialog.visible:
			_pending_fixed_cell = cell
			_fixed_file_dialog.popup_centered(Vector2i(600, 400))


func _handle_erase(pos: Vector2) -> void:
	var cell := _screen_to_cell(pos)
	if cell.x < 0 or cell.x >= _world_map.grid_width:
		return
	if cell.y < 0 or cell.y >= _world_map.grid_height:
		return
	_world_map.set_cell(cell.x, cell.y, 0)
	_world_map.clear_fixed_chunk(cell.x, cell.y)
	_grid_canvas.queue_redraw()


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var cs := CELL_SIZE * _zoom
	var local := screen_pos - _camera_offset
	return Vector2i(int(floorf(local.x / cs)), int(floorf(local.y / cs)))


func _on_size_changed(_value: float) -> void:
	_world_map.resize(int(_width_spin.value), int(_height_spin.value))
	_grid_canvas.queue_redraw()


func _on_save_pressed() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.popup_centered(Vector2i(600, 400))


func _on_load_pressed() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		ResourceSaver.save(_world_map, path)
		print("[WorldMapEditor] Saved to: ", path)
	else:
		var loaded := ResourceLoader.load(path)
		if loaded is WorldMap:
			_world_map = loaded
			_width_spin.value = _world_map.grid_width
			_height_spin.value = _world_map.grid_height
			_refresh_biome_list()
			_grid_canvas.queue_redraw()
			print("[WorldMapEditor] Loaded: ", path)
		else:
			push_error("[WorldMapEditor] File is not a WorldMap resource: " + path)


func _on_fixed_file_selected(path: String) -> void:
	_world_map.set_fixed_chunk(_pending_fixed_cell.x, _pending_fixed_cell.y, path)
	_grid_canvas.queue_redraw()


func _on_add_biome_pressed() -> void:
	var biome := BiomeDef.new()
	biome.biome_name = "new_biome_%d" % (_world_map.biome_palette.size() + 1)
	biome.color = Color(randf(), randf(), randf())
	_world_map.biome_palette.append(biome)
	_refresh_biome_list()
