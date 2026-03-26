class_name VoxelSettingsDialog
extends AcceptDialog

## Settings dialog for the voxel editor.
## Contains tile properties and display settings (marker scale).

signal tile_name_changed(name: String)
signal edge_changed(side: String, edge_type: int)
signal biome_changed(biome: String)
signal weight_changed(weight: float)
signal surface_material_changed(mat_id: int)
signal tile_size_changed(size: Vector3i)
signal tags_changed(tags: PackedStringArray)
signal marker_scale_changed(value: float)

var _tile_properties_panel: TilePropertiesPanel
var _marker_scale_slider: HSlider
var _marker_scale_label: Label


func _ready() -> void:
	title = "Tile Settings"
	min_size = Vector2i(400, 500)

	var dialog_vbox := VBoxContainer.new()
	dialog_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# ── Tile properties ──
	_tile_properties_panel = TilePropertiesPanel.new()
	_tile_properties_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tile_properties_panel.tile_name_changed.connect(func(n): tile_name_changed.emit(n))
	_tile_properties_panel.edge_changed.connect(func(s, e): edge_changed.emit(s, e))
	_tile_properties_panel.biome_changed.connect(func(b): biome_changed.emit(b))
	_tile_properties_panel.weight_changed.connect(func(w): weight_changed.emit(w))
	_tile_properties_panel.surface_material_changed.connect(func(m): surface_material_changed.emit(m))
	_tile_properties_panel.tile_size_changed.connect(func(s): tile_size_changed.emit(s))
	_tile_properties_panel.tags_changed.connect(func(t): tags_changed.emit(t))
	dialog_vbox.add_child(_tile_properties_panel)

	dialog_vbox.add_child(HSeparator.new())

	# ── Display Settings ──
	var display_header := Label.new()
	display_header.text = "Display Settings"
	display_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	dialog_vbox.add_child(display_header)

	var marker_row := HBoxContainer.new()
	_marker_scale_label = Label.new()
	_marker_scale_label.text = "Marker Scale: 1.0x"
	_marker_scale_label.custom_minimum_size.x = 130
	marker_row.add_child(_marker_scale_label)

	_marker_scale_slider = HSlider.new()
	_marker_scale_slider.min_value = 0.25
	_marker_scale_slider.max_value = 5.0
	_marker_scale_slider.value = 1.0
	_marker_scale_slider.step = 0.25
	_marker_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_marker_scale_slider.value_changed.connect(_on_marker_scale_changed)
	marker_row.add_child(_marker_scale_slider)
	dialog_vbox.add_child(marker_row)

	add_child(dialog_vbox)


func sync_from_tile(tile: WFCTileDef) -> void:
	if _tile_properties_panel:
		_tile_properties_panel.sync_from_tile(tile)


func _on_marker_scale_changed(value: float) -> void:
	_marker_scale_label.text = "Marker Scale: %.2gx" % value
	marker_scale_changed.emit(value)
