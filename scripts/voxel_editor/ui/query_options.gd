class_name QueryOptions
extends VBoxContainer

## Query options for Fill, Extrude, and Select tools.
## Controls connectivity mode, color/material filters, and search range.

signal connectivity_changed(is_face: bool)
signal color_changed(enabled: bool)
signal material_changed(enabled: bool)
signal range_changed(range_val: int)

var _connectivity_check: CheckBox
var _color_check: CheckBox
var _material_check: CheckBox
var _range_label: Label
var _range_slider: HSlider


func _ready() -> void:
	var header := Label.new()
	header.text = "Query Options"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(header)

	# Connectivity mode
	_connectivity_check = CheckBox.new()
	_connectivity_check.text = "Face Connectivity (Q)"
	_connectivity_check.tooltip_text = "When enabled, only selects voxels sharing an exposed face in the clicked direction.\nWhen disabled, selects all 6-connected non-air voxels (Geometry mode)."
	_connectivity_check.toggled.connect(func(v): connectivity_changed.emit(v))
	add_child(_connectivity_check)

	add_child(HSeparator.new())

	# Filters
	var filter_label := Label.new()
	filter_label.text = "Filters (stackable):"
	filter_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(filter_label)

	_color_check = CheckBox.new()
	_color_check.text = "Match Color"
	_color_check.tooltip_text = "Only match voxels with the exact same visual ID"
	_color_check.toggled.connect(func(v): color_changed.emit(v))
	add_child(_color_check)

	_material_check = CheckBox.new()
	_material_check.text = "Match Material"
	_material_check.tooltip_text = "Only match voxels with the same base material type"
	_material_check.toggled.connect(func(v): material_changed.emit(v))
	add_child(_material_check)

	add_child(HSeparator.new())

	# Range slider
	var range_row := HBoxContainer.new()
	_range_label = Label.new()
	_range_label.text = "Range: 64"
	_range_label.custom_minimum_size.x = 70
	range_row.add_child(_range_label)

	_range_slider = HSlider.new()
	_range_slider.min_value = 4
	_range_slider.max_value = 128
	_range_slider.value = 64
	_range_slider.step = 4
	_range_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_range_slider.value_changed.connect(_on_range_changed)
	range_row.add_child(_range_slider)
	add_child(range_row)


func set_state(is_face: bool, filter_color: bool, filter_material: bool,
		range_val: int) -> void:
	_connectivity_check.set_pressed_no_signal(is_face)
	_color_check.set_pressed_no_signal(filter_color)
	_material_check.set_pressed_no_signal(filter_material)
	_range_slider.set_value_no_signal(range_val)
	_range_label.text = "Range: %d" % range_val


func _on_range_changed(value: float) -> void:
	var v := int(value)
	_range_label.text = "Range: %d" % v
	range_changed.emit(v)
