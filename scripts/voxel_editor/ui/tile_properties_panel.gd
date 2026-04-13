class_name TilePropertiesPanel
extends PanelContainer

## Edits WFC tile/structure properties: name, edges, biome, weight, tags,
## surface material, and tile dimensions.

signal tile_name_changed(name: String)
signal edge_changed(side: String, edge_type: int)
signal biome_changed(biome: String)
signal weight_changed(weight: float)
signal surface_material_changed(mat_id: int)
signal tile_size_changed(size: Vector3i)
signal tags_changed(tags: PackedStringArray)

var _scroll: ScrollContainer
var _vbox: VBoxContainer

# Tile name
var _name_edit: LineEdit

# Tile size
var _size_x_spin: SpinBox
var _size_y_spin: SpinBox
var _size_z_spin: SpinBox
var _size_presets: OptionButton

# Edge type dropdowns
var _edge_north: OptionButton
var _edge_south: OptionButton
var _edge_east: OptionButton
var _edge_west: OptionButton

# WFC properties
var _biome_edit: LineEdit
var _weight_slider: HSlider
var _weight_label: Label
var _surface_mat: OptionButton

# Tags
var _tags_edit: LineEdit
var _tags_label: Label

const EDGE_NAMES := ["Solid Wall", "Open Ground", "Corridor", "Door", "Bedrock Wall", "Structure Internal"]
const SIZE_PRESETS := {
	"Default (128x112x128)": Vector3i(128, 112, 128),
	"Small Prop (32x32x32)": Vector3i(32, 32, 32),
	"Medium Prop (64x64x64)": Vector3i(64, 64, 64),
	"Tall (128x224x128)": Vector3i(128, 224, 128),
	"Wide (256x112x256)": Vector3i(256, 112, 256),
	"Custom": Vector3i(-1, -1, -1),
}


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Header ──
	var header := Label.new()
	header.text = "Tile Properties"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	_vbox.add_child(header)

	_vbox.add_child(HSeparator.new())

	# ── Tile Name ──
	_add_label("Name:")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "untitled"
	_name_edit.text_changed.connect(func(t): tile_name_changed.emit(t))
	_vbox.add_child(_name_edit)

	_vbox.add_child(HSeparator.new())

	# ── Tile Size ──
	_add_label("Tile Size:")

	_size_presets = OptionButton.new()
	var idx := 0
	for preset_name in SIZE_PRESETS:
		_size_presets.add_item(preset_name, idx)
		idx += 1
	_size_presets.item_selected.connect(_on_size_preset_selected)
	_vbox.add_child(_size_presets)

	var size_grid := GridContainer.new()
	size_grid.columns = 6

	size_grid.add_child(_make_dim_label("X:"))
	_size_x_spin = _make_dim_spin(1, 512, 128)
	size_grid.add_child(_size_x_spin)

	size_grid.add_child(_make_dim_label("Y:"))
	_size_y_spin = _make_dim_spin(1, 512, 112)
	size_grid.add_child(_size_y_spin)

	size_grid.add_child(_make_dim_label("Z:"))
	_size_z_spin = _make_dim_spin(1, 512, 128)
	size_grid.add_child(_size_z_spin)

	_vbox.add_child(size_grid)

	var apply_size_btn := Button.new()
	apply_size_btn.text = "Apply Size"
	apply_size_btn.tooltip_text = "Resize tile voxel data (preserves existing voxels in overlap)"
	apply_size_btn.pressed.connect(_on_apply_size)
	_vbox.add_child(apply_size_btn)

	_vbox.add_child(HSeparator.new())

	# ── Edge Types ──
	_add_label("Edge Types:")
	_edge_north = _make_edge_dropdown("North")
	_edge_south = _make_edge_dropdown("South")
	_edge_east = _make_edge_dropdown("East")
	_edge_west = _make_edge_dropdown("West")

	_vbox.add_child(HSeparator.new())

	# ── Biome ──
	_add_label("Biome:")
	_biome_edit = LineEdit.new()
	_biome_edit.placeholder_text = "e.g. stone_cavern"
	_biome_edit.text_changed.connect(func(t): biome_changed.emit(t))
	_vbox.add_child(_biome_edit)

	# ── Weight ──
	var weight_row := HBoxContainer.new()
	_weight_label = Label.new()
	_weight_label.text = "Weight: 1.0"
	_weight_label.custom_minimum_size.x = 80
	weight_row.add_child(_weight_label)

	_weight_slider = HSlider.new()
	_weight_slider.min_value = 0.1
	_weight_slider.max_value = 10.0
	_weight_slider.value = 1.0
	_weight_slider.step = 0.1
	_weight_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_slider.value_changed.connect(_on_weight_changed)
	weight_row.add_child(_weight_slider)
	_vbox.add_child(weight_row)

	# ── Surface Material ──
	_add_label("Surface Material:")
	_surface_mat = OptionButton.new()
	var materials := MaterialRegistry.get_all_materials()
	for mat in materials:
		_surface_mat.add_item(mat["name"], mat["id"])
	_surface_mat.item_selected.connect(_on_surface_mat_selected)
	_vbox.add_child(_surface_mat)

	_vbox.add_child(HSeparator.new())

	# ── Tags ──
	_add_label("Tags (comma separated):")
	_tags_edit = LineEdit.new()
	_tags_edit.placeholder_text = "e.g. corridor, spawn"
	_tags_edit.text_submitted.connect(_on_tags_submitted)
	_vbox.add_child(_tags_edit)

	_tags_label = Label.new()
	_tags_label.text = "Tags: (none)"
	_tags_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_tags_label.add_theme_font_size_override("font_size", 11)
	_vbox.add_child(_tags_label)

	_scroll.add_child(_vbox)
	add_child(_scroll)


## Sync all fields from a WFCTileDef.
func sync_from_tile(tile: WFCTileDef) -> void:
	if not tile:
		return
	_name_edit.text = tile.tile_name
	_size_x_spin.set_value_no_signal(tile.tile_size_x)
	_size_y_spin.set_value_no_signal(tile.tile_size_y)
	_size_z_spin.set_value_no_signal(tile.tile_size_z)
	_update_size_preset(tile.get_tile_size())
	_set_edge_dropdown(_edge_north, tile.edge_north)
	_set_edge_dropdown(_edge_south, tile.edge_south)
	_set_edge_dropdown(_edge_east, tile.edge_east)
	_set_edge_dropdown(_edge_west, tile.edge_west)
	_biome_edit.text = tile.biome
	_weight_slider.set_value_no_signal(tile.weight)
	_weight_label.text = "Weight: %.1f" % tile.weight
	_select_surface_mat(tile.surface_material)
	_update_tags_display(tile.tags)
	_tags_edit.text = ", ".join(tile.tags)


func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(lbl)


func _make_dim_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = 20
	return lbl


func _make_dim_spin(min_val: int, max_val: int, default_val: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.step = 16
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _make_edge_dropdown(side: String) -> OptionButton:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = side + ":"
	lbl.custom_minimum_size.x = 50
	row.add_child(lbl)

	var opt := OptionButton.new()
	for i in EDGE_NAMES.size():
		opt.add_item(EDGE_NAMES[i], i)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(func(idx: int): edge_changed.emit(side.to_lower(), idx))
	row.add_child(opt)

	_vbox.add_child(row)
	return opt


func _set_edge_dropdown(opt: OptionButton, value: int) -> void:
	for i in opt.item_count:
		if opt.get_item_id(i) == value:
			opt.selected = i
			return


func _select_surface_mat(mat_id: int) -> void:
	for i in _surface_mat.item_count:
		if _surface_mat.get_item_id(i) == mat_id:
			_surface_mat.selected = i
			return


func _update_size_preset(size: Vector3i) -> void:
	var idx := 0
	for preset_name in SIZE_PRESETS:
		if SIZE_PRESETS[preset_name] == size:
			_size_presets.selected = idx
			return
		idx += 1
	# No match — select "Custom"
	_size_presets.selected = SIZE_PRESETS.size() - 1


func _update_tags_display(tags: PackedStringArray) -> void:
	if tags.is_empty():
		_tags_label.text = "Tags: (none)"
	else:
		_tags_label.text = "Tags: " + ", ".join(tags)


func _on_size_preset_selected(idx: int) -> void:
	var keys := SIZE_PRESETS.keys()
	if idx >= keys.size():
		return
	var size: Vector3i = SIZE_PRESETS[keys[idx]]
	if size.x < 0:
		return  # "Custom" — user edits spins manually
	_size_x_spin.set_value_no_signal(size.x)
	_size_y_spin.set_value_no_signal(size.y)
	_size_z_spin.set_value_no_signal(size.z)


func _on_apply_size() -> void:
	var new_size := Vector3i(
		int(_size_x_spin.value),
		int(_size_y_spin.value),
		int(_size_z_spin.value))
	tile_size_changed.emit(new_size)


func _on_weight_changed(value: float) -> void:
	_weight_label.text = "Weight: %.1f" % value
	weight_changed.emit(value)


func _on_surface_mat_selected(idx: int) -> void:
	var mat_id := _surface_mat.get_item_id(idx)
	surface_material_changed.emit(mat_id)


func _on_tags_submitted(text: String) -> void:
	var parts := text.split(",")
	var tags := PackedStringArray()
	for part in parts:
		var trimmed := part.strip_edges()
		if not trimmed.is_empty():
			tags.append(trimmed)
	_update_tags_display(tags)
	tags_changed.emit(tags)
