class_name TransformOptions
extends VBoxContainer

## Transform tool options: wrap toggle, constraint info.

signal wrap_changed(enabled: bool)

var _wrap_check: CheckBox


func _ready() -> void:
	var header := Label.new()
	header.text = "Transform Options"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(header)

	_wrap_check = CheckBox.new()
	_wrap_check.text = "Wrap at Tile Edges"
	_wrap_check.tooltip_text = "Positions wrap around tile boundaries using posmod"
	_wrap_check.toggled.connect(func(v): wrap_changed.emit(v))
	add_child(_wrap_check)

	add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Arrow keys: nudge\nShift+Up/Down: nudge Y\nEnter: confirm move\nEscape: cancel\n\nGizmo handles:\n  Arrows = lock axis\n  Planes = lock plane\n  Center = free move"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(hint)


func set_wrap(enabled: bool) -> void:
	_wrap_check.set_pressed_no_signal(enabled)
