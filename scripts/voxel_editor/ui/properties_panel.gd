class_name PropertiesPanel
extends PanelContainer

## Context-sensitive right panel that shows controls for the active tool/mode.
## Swaps visible sub-panel based on EditorToolManager state.

signal shape_hollow_changed(is_hollow: bool)
signal shape_sides_changed(sides: int)
signal query_connectivity_changed(is_face: bool)
signal query_color_changed(enabled: bool)
signal query_material_changed(enabled: bool)
signal query_range_changed(range_val: int)
signal transform_wrap_changed(enabled: bool)
signal y_slice_changed(value: int)

var _scroll: ScrollContainer
var _vbox: VBoxContainer

# Sub-panels
var _shape_options: ShapeOptions
var _query_options: QueryOptions
var _transform_options: TransformOptions

# Always-visible sections
var _info_label: Label
var _selection_label: Label
var _y_slice_label: Label
var _y_slice_slider: HSlider


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Tool-specific sub-panels ──
	_shape_options = ShapeOptions.new()
	_shape_options.hollow_changed.connect(func(v): shape_hollow_changed.emit(v))
	_shape_options.sides_changed.connect(func(v): shape_sides_changed.emit(v))
	_vbox.add_child(_shape_options)

	_query_options = QueryOptions.new()
	_query_options.connectivity_changed.connect(func(v): query_connectivity_changed.emit(v))
	_query_options.color_changed.connect(func(v): query_color_changed.emit(v))
	_query_options.material_changed.connect(func(v): query_material_changed.emit(v))
	_query_options.range_changed.connect(func(v): query_range_changed.emit(v))
	_vbox.add_child(_query_options)

	_transform_options = TransformOptions.new()
	_transform_options.wrap_changed.connect(func(v): transform_wrap_changed.emit(v))
	_vbox.add_child(_transform_options)

	# ── Always-visible info ──
	_vbox.add_child(HSeparator.new())

	_info_label = Label.new()
	_info_label.text = ""
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_vbox.add_child(_info_label)

	_selection_label = Label.new()
	_selection_label.text = "Selection: 0 voxels"
	_vbox.add_child(_selection_label)

	_vbox.add_child(HSeparator.new())

	# Y-slice slider
	var slice_row := HBoxContainer.new()
	_y_slice_label = Label.new()
	_y_slice_label.text = "Y Slice: off"
	_y_slice_label.custom_minimum_size.x = 80
	slice_row.add_child(_y_slice_label)

	_y_slice_slider = HSlider.new()
	_y_slice_slider.min_value = 0
	_y_slice_slider.max_value = WFCTileDef.DEFAULT_TILE_Y
	_y_slice_slider.value = 0
	_y_slice_slider.step = 1
	_y_slice_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_y_slice_slider.value_changed.connect(_on_y_slice_changed)
	slice_row.add_child(_y_slice_slider)
	_vbox.add_child(slice_row)

	_scroll.add_child(_vbox)
	add_child(_scroll)

	# Start hidden
	_shape_options.visible = true
	_query_options.visible = false
	_transform_options.visible = false


## Update which sub-panel is visible based on tool type.
func set_tool_context(tool_type: int, mode: int) -> void:
	_shape_options.visible = false
	_query_options.visible = false
	_transform_options.visible = false

	# EditorToolManager.ToolType: SHAPE=0, FILL=1, EXTRUDE=2, SELECT=3, TRANSFORM=4, METADATA=5
	match tool_type:
		0:  # SHAPE
			_shape_options.visible = true
			_info_label.text = "Shape mode: click to place/remove voxels"
		1:  # FILL
			_query_options.visible = true
			_info_label.text = "Fill: click to flood fill connected voxels"
		2:  # EXTRUDE
			_query_options.visible = true
			_info_label.text = "Extrude: click face, drag to extrude"
		3:  # SELECT
			_query_options.visible = true
			_info_label.text = "Select: choose voxels for edit operations"
		4:  # TRANSFORM
			_transform_options.visible = true
			_info_label.text = "Transform: drag gizmo or use arrow keys, Enter to confirm"
		5:  # METADATA
			_info_label.text = "Metadata: click a voxel to place or edit spawn points, triggers, and other markers"


func set_selection_count(count: int) -> void:
	_selection_label.text = "Selection: %d voxel%s" % [count, "s" if count != 1 else ""]


func set_palette_entry_info(entry_name: String, voxel_id: int) -> void:
	# Could show current palette entry info — reserved for future use
	pass


func sync_shape_options(is_hollow: bool, sides: int) -> void:
	_shape_options.set_hollow(is_hollow)
	_shape_options.set_sides(sides)


func sync_query_options(is_face: bool, filter_color: bool, filter_material: bool,
		range_val: int) -> void:
	_query_options.set_state(is_face, filter_color, filter_material, range_val)


func sync_transform_options(wrap: bool) -> void:
	_transform_options.set_wrap(wrap)


func set_tile_height(max_y: int) -> void:
	_y_slice_slider.max_value = max_y


func _on_y_slice_changed(value: float) -> void:
	var v := int(value)
	if v == 0:
		_y_slice_label.text = "Y Slice: off"
	else:
		_y_slice_label.text = "Y Slice: %d" % v
	y_slice_changed.emit(v)
