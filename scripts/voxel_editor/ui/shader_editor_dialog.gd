class_name ShaderEditorDialog
extends AcceptDialog

## Dialog for writing and running procedural voxel shaders.
## Shows a code editor, preset selector, region controls, and live preview.

signal apply_requested(code: String, origin: Vector3i, region_size: Vector3i, vid: int)

var _preset_button: OptionButton
var _code_edit: CodeEdit
var _origin_x: SpinBox
var _origin_y: SpinBox
var _origin_z: SpinBox
var _size_x: SpinBox
var _size_y: SpinBox
var _size_z: SpinBox
var _error_label: Label
var _desc_label: Label
var _apply_btn: Button
var _preview_btn: Button

var _tile_size := Vector3i(128, 112, 128)


func _ready() -> void:
	title = "Procedural Shader"
	min_size = Vector2i(520, 520)
	# Remove the default OK button text and add our own buttons
	get_ok_button().text = "Close"

	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Preset selector
	var preset_row := HBoxContainer.new()
	var preset_lbl := Label.new()
	preset_lbl.text = "Preset:"
	preset_row.add_child(preset_lbl)

	_preset_button = OptionButton.new()
	_preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_button.add_item("(custom)", 0)
	var idx := 1
	for preset_name in ProceduralTool.PRESETS:
		_preset_button.add_item(preset_name, idx)
		idx += 1
	_preset_button.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_button)
	root.add_child(preset_row)

	# Description label
	_desc_label = Label.new()
	_desc_label.text = ""
	_desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_desc_label)

	# Code editor
	_code_edit = CodeEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size.y = 180
	_code_edit.text = "return vid if sqrt((x-cx)*(x-cx) + (y-cy)*(y-cy) + (z-cz)*(z-cz)) <= min(sx, min(sy, sz)) * 0.5 else -1"
	_code_edit.gutters_draw_line_numbers = true
	_code_edit.scroll_smooth = true
	_code_edit.syntax_highlighter = _create_highlighter()
	_code_edit.text_changed.connect(func(): _preset_button.selected = 0)
	root.add_child(_code_edit)

	# Error display
	_error_label = Label.new()
	_error_label.text = ""
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_error_label)

	# Region controls
	root.add_child(HSeparator.new())

	var region_lbl := Label.new()
	region_lbl.text = "Region"
	region_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(region_lbl)

	var origin_row := HBoxContainer.new()
	origin_row.add_child(_make_label("Origin:"))
	_origin_x = _make_spin(0, 0, 255, "X")
	_origin_y = _make_spin(0, 0, 255, "Y")
	_origin_z = _make_spin(0, 0, 255, "Z")
	origin_row.add_child(_origin_x)
	origin_row.add_child(_origin_y)
	origin_row.add_child(_origin_z)
	root.add_child(origin_row)

	var size_row := HBoxContainer.new()
	size_row.add_child(_make_label("Size:"))
	_size_x = _make_spin(32, 1, 256, "W")
	_size_y = _make_spin(32, 1, 256, "H")
	_size_z = _make_spin(32, 1, 256, "D")
	size_row.add_child(_size_x)
	size_row.add_child(_size_y)
	size_row.add_child(_size_z)
	root.add_child(size_row)

	# Help text
	var help := Label.new()
	help.text = "Variables: x y z current sx sy sz cx cy cz nx ny nz vid ox oy oz PI TAU"
	help.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	help.add_theme_font_size_override("font_size", 11)
	root.add_child(help)

	var help2 := Label.new()
	help2.text = "Return voxel ID (vid = palette entry, 0 = air, -1 = no change)"
	help2.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	help2.add_theme_font_size_override("font_size", 11)
	root.add_child(help2)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END

	_preview_btn = Button.new()
	_preview_btn.text = "Preview"
	_preview_btn.pressed.connect(_on_preview)
	btn_row.add_child(_preview_btn)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.pressed.connect(_on_apply)
	btn_row.add_child(_apply_btn)

	root.add_child(btn_row)

	add_child(root)


func set_tile_size(ts: Vector3i) -> void:
	_tile_size = ts
	if _origin_x:
		_origin_x.max_value = ts.x - 1
		_origin_y.max_value = ts.y - 1
		_origin_z.max_value = ts.z - 1
		_size_x.max_value = ts.x
		_size_y.max_value = ts.y
		_size_z.max_value = ts.z


## Set the region from the current selection bounding box.
func set_region(origin: Vector3i, size: Vector3i) -> void:
	if _origin_x:
		_origin_x.value = origin.x
		_origin_y.value = origin.y
		_origin_z.value = origin.z
		_size_x.value = size.x
		_size_y.value = size.y
		_size_z.value = size.z


func get_origin() -> Vector3i:
	return Vector3i(int(_origin_x.value), int(_origin_y.value), int(_origin_z.value))


func get_region_size() -> Vector3i:
	return Vector3i(int(_size_x.value), int(_size_y.value), int(_size_z.value))


func get_code() -> String:
	return _code_edit.text


func show_error(msg: String) -> void:
	_error_label.text = msg


func clear_error() -> void:
	_error_label.text = ""


func _on_preset_selected(index: int) -> void:
	if index == 0:
		_desc_label.text = ""
		return
	var preset_name: String = _preset_button.get_item_text(index)
	if ProceduralTool.PRESETS.has(preset_name):
		var preset: Dictionary = ProceduralTool.PRESETS[preset_name]
		_code_edit.text = preset["code"]
		_desc_label.text = preset.get("description", "")


func _on_preview() -> void:
	clear_error()
	apply_requested.emit(get_code(), get_origin(), get_region_size(), -99)  # -99 = preview sentinel


func _on_apply() -> void:
	clear_error()
	apply_requested.emit(get_code(), get_origin(), get_region_size(), 0)


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = 50
	return lbl


func _make_spin(default: float, min_val: float, max_val: float, prefix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default
	spin.prefix = prefix + ":"
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _create_highlighter() -> CodeHighlighter:
	var hl := CodeHighlighter.new()
	hl.number_color = Color(0.8, 0.9, 0.5)
	hl.function_color = Color(0.4, 0.7, 1.0)
	hl.symbol_color = Color(0.7, 0.7, 0.7)
	hl.member_variable_color = Color(0.9, 0.6, 0.4)
	for kw in ["var", "return", "if", "else", "elif", "for", "while", "and", "or", "not", "in", "true", "false"]:
		hl.add_keyword_color(kw, Color(1.0, 0.4, 0.5))
	for fn in ["sqrt", "sin", "cos", "tan", "abs", "min", "max", "floor", "ceil", "round",
			"pow", "fmod", "clamp", "lerp", "sign", "float", "int", "randf", "randi"]:
		hl.add_keyword_color(fn, Color(0.4, 0.8, 1.0))
	for v in ["x", "y", "z", "current", "sx", "sy", "sz", "cx", "cy", "cz",
			"nx", "ny", "nz", "vid", "ox", "oy", "oz", "PI", "TAU"]:
		hl.add_keyword_color(v, Color(0.9, 0.7, 0.5))
	return hl
