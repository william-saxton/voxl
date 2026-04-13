class_name TileExportDialog
extends ConfirmationDialog

## Dialog for exporting a tile with three modes:
## - Full Tile: exports the entire tile at current dimensions
## - Smallest Possible: auto-crops to bounding box of non-air voxels
## - Selected Only: exports only selected voxels (cropped to selection bounds)

signal export_requested(mode: int, path: String)

enum ExportMode { FULL_TILE, SMALLEST, SELECTED_ONLY }

var _mode_option: OptionButton
var _info_label: Label
var _path_edit: LineEdit
var _browse_btn: Button
var _file_dialog: FileDialog

var _tile: WFCTileDef
var _selection_count: int = 0


func _ready() -> void:
	title = "Export Tile"
	min_size = Vector2i(450, 250)

	var vbox := VBoxContainer.new()

	# Mode selector
	var mode_row := HBoxContainer.new()
	var mode_lbl := Label.new()
	mode_lbl.text = "Export Mode:"
	mode_lbl.custom_minimum_size.x = 100
	mode_row.add_child(mode_lbl)

	_mode_option = OptionButton.new()
	_mode_option.add_item("Full Tile", ExportMode.FULL_TILE)
	_mode_option.add_item("Smallest Possible (auto-crop)", ExportMode.SMALLEST)
	_mode_option.add_item("Selected Only", ExportMode.SELECTED_ONLY)
	_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_option.item_selected.connect(_on_mode_changed)
	mode_row.add_child(_mode_option)
	vbox.add_child(mode_row)

	vbox.add_child(HSeparator.new())

	# Info label
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_info_label)

	vbox.add_child(HSeparator.new())

	# File path
	var path_row := HBoxContainer.new()
	var path_lbl := Label.new()
	path_lbl.text = "Save to:"
	path_lbl.custom_minimum_size.x = 60
	path_row.add_child(path_lbl)

	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.placeholder_text = "res://resources/wfc_tiles/my_tile.tres"
	path_row.add_child(_path_edit)

	_browse_btn = Button.new()
	_browse_btn.text = "..."
	_browse_btn.pressed.connect(_on_browse)
	path_row.add_child(_browse_btn)
	vbox.add_child(path_row)

	add_child(vbox)

	# File dialog
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.filters = PackedStringArray(["*.tres ; Tile Resource"])
	_file_dialog.title = "Export Tile As..."
	_file_dialog.file_selected.connect(func(p): _path_edit.text = p)
	add_child(_file_dialog)

	confirmed.connect(_on_confirmed)
	_update_info()


func set_tile(tile: WFCTileDef) -> void:
	_tile = tile
	_update_info()


func set_selection_count(count: int) -> void:
	_selection_count = count
	_update_info()


func _on_mode_changed(_idx: int) -> void:
	_update_info()


func _update_info() -> void:
	if not _info_label:
		return
	var mode: int = _mode_option.get_selected_id() if _mode_option else ExportMode.FULL_TILE
	match mode:
		ExportMode.FULL_TILE:
			if _tile:
				_info_label.text = "Exports the full tile at %dx%dx%d.\nFile size: ~%.1f MB" % [
					_tile.tile_size_x, _tile.tile_size_y, _tile.tile_size_z,
					float(_tile.get_tile_vol() * 2) / 1048576.0]
			else:
				_info_label.text = "Exports the full tile at current dimensions."
		ExportMode.SMALLEST:
			_info_label.text = "Auto-crops to the bounding box of all non-air voxels.\nResulting tile dimensions will be as small as possible."
		ExportMode.SELECTED_ONLY:
			if _selection_count > 0:
				_info_label.text = "Exports only the %d selected voxels.\nCropped to selection bounding box." % _selection_count
			else:
				_info_label.text = "No voxels selected. Select voxels first, then export."


func _on_browse() -> void:
	_file_dialog.popup_centered(Vector2i(700, 500))


func _on_confirmed() -> void:
	var path := _path_edit.text.strip_edges()
	if path.is_empty():
		return
	var mode: int = _mode_option.get_selected_id()
	export_requested.emit(mode, path)


## Compute the bounding box of all non-air voxels in the tile.
## Returns { min: Vector3i, max: Vector3i } or empty dict if all air.
static func compute_bounding_box(tile: WFCTileDef) -> Dictionary:
	var min_pos := Vector3i(tile.tile_size_x, tile.tile_size_y, tile.tile_size_z)
	var max_pos := Vector3i(-1, -1, -1)

	for z in tile.tile_size_z:
		for y in tile.tile_size_y:
			for x in tile.tile_size_x:
				if tile.get_voxel(x, y, z) != 0:
					min_pos.x = mini(min_pos.x, x)
					min_pos.y = mini(min_pos.y, y)
					min_pos.z = mini(min_pos.z, z)
					max_pos.x = maxi(max_pos.x, x)
					max_pos.y = maxi(max_pos.y, y)
					max_pos.z = maxi(max_pos.z, z)

	if max_pos.x < 0:
		return {}
	return { "min": min_pos, "max": max_pos }


## Export a tile using the specified mode.
## selection_positions: Array[Vector3i] — needed for SELECTED_ONLY mode.
static func export_tile(tile: WFCTileDef, mode: int,
		selection_positions: Array[Vector3i] = []) -> WFCTileDef:
	var exported := WFCTileDef.new()
	exported.tile_name = tile.tile_name
	exported.edge_north = tile.edge_north
	exported.edge_south = tile.edge_south
	exported.edge_east = tile.edge_east
	exported.edge_west = tile.edge_west
	exported.weight = tile.weight
	exported.rotatable = tile.rotatable
	exported.tags = tile.tags.duplicate()
	exported.surface_material = tile.surface_material
	exported.biome = tile.biome

	match mode:
		ExportMode.FULL_TILE:
			exported.tile_size_x = tile.tile_size_x
			exported.tile_size_y = tile.tile_size_y
			exported.tile_size_z = tile.tile_size_z
			exported.voxel_data = tile.voxel_data.duplicate()
			exported.metadata_points = tile.metadata_points.duplicate(true)

		ExportMode.SMALLEST:
			var bb := compute_bounding_box(tile)
			if bb.is_empty():
				exported.tile_size_x = 1
				exported.tile_size_y = 1
				exported.tile_size_z = 1
				exported._ensure_data()
				return exported

			var min_p: Vector3i = bb["min"]
			var max_p: Vector3i = bb["max"]
			var sx := max_p.x - min_p.x + 1
			var sy := max_p.y - min_p.y + 1
			var sz := max_p.z - min_p.z + 1
			exported.tile_size_x = sx
			exported.tile_size_y = sy
			exported.tile_size_z = sz
			exported._ensure_data()

			for z in sz:
				for y in sy:
					for x in sx:
						var vid := tile.get_voxel(min_p.x + x, min_p.y + y, min_p.z + z)
						exported.set_voxel(x, y, z, vid)

			# Remap metadata points
			for key in tile.metadata_points:
				var pt: Vector3i = key
				if pt.x >= min_p.x and pt.x <= max_p.x and \
						pt.y >= min_p.y and pt.y <= max_p.y and \
						pt.z >= min_p.z and pt.z <= max_p.z:
					var local := pt - min_p
					exported.metadata_points[local] = tile.metadata_points[key]

		ExportMode.SELECTED_ONLY:
			if selection_positions.is_empty():
				return exported

			# Compute selection bounding box
			var min_p := selection_positions[0]
			var max_p := selection_positions[0]
			for pos in selection_positions:
				min_p.x = mini(min_p.x, pos.x)
				min_p.y = mini(min_p.y, pos.y)
				min_p.z = mini(min_p.z, pos.z)
				max_p.x = maxi(max_p.x, pos.x)
				max_p.y = maxi(max_p.y, pos.y)
				max_p.z = maxi(max_p.z, pos.z)

			var sx := max_p.x - min_p.x + 1
			var sy := max_p.y - min_p.y + 1
			var sz := max_p.z - min_p.z + 1
			exported.tile_size_x = sx
			exported.tile_size_y = sy
			exported.tile_size_z = sz
			exported._ensure_data()

			# Only copy selected voxels
			var sel_set := {}
			for pos in selection_positions:
				sel_set[pos] = true

			for pos in selection_positions:
				var vid := tile.get_voxel(pos.x, pos.y, pos.z)
				exported.set_voxel(pos.x - min_p.x, pos.y - min_p.y, pos.z - min_p.z, vid)

			# Remap metadata points within selection
			for key in tile.metadata_points:
				if sel_set.has(key):
					var pt: Vector3i = key
					var local := pt - min_p
					exported.metadata_points[local] = tile.metadata_points[key]

	return exported
