class_name ShapeOptions
extends VBoxContainer

## Shape tool options: hollow toggle, polygon sides count.

signal hollow_changed(is_hollow: bool)
signal sides_changed(sides: int)

var _hollow_check: CheckBox
var _sides_label: Label
var _sides_spin: SpinBox


func _ready() -> void:
	var header := Label.new()
	header.text = "Shape Options"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(header)

	_hollow_check = CheckBox.new()
	_hollow_check.text = "Hollow (H)"
	_hollow_check.toggled.connect(func(v): hollow_changed.emit(v))
	add_child(_hollow_check)

	var sides_row := HBoxContainer.new()
	_sides_label = Label.new()
	_sides_label.text = "Polygon Sides:"
	_sides_label.custom_minimum_size.x = 90
	sides_row.add_child(_sides_label)

	_sides_spin = SpinBox.new()
	_sides_spin.min_value = 3
	_sides_spin.max_value = 32
	_sides_spin.value = 6
	_sides_spin.step = 1
	_sides_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sides_spin.value_changed.connect(func(v): sides_changed.emit(int(v)))
	sides_row.add_child(_sides_spin)
	add_child(sides_row)

	add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Shift = constrain axis\n1-5 = switch shape"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)


func set_hollow(is_hollow: bool) -> void:
	_hollow_check.set_pressed_no_signal(is_hollow)


func set_sides(sides: int) -> void:
	_sides_spin.set_value_no_signal(sides)
