class_name PaletteEditorPanel
extends PanelContainer

## Palette management panel: create/edit/delete entries, switch palettes,
## import/export .tres files.

signal entry_changed(index: int)
signal palette_switched(index: int)
signal entry_removed(index: int)

var _palette_set: TilePaletteSet
var _palette_selector: OptionButton
var _btn_dup_palette: Button
var _btn_del_palette: Button

var _btn_del_entry: Button
var _entry_name_edit: LineEdit
var _entry_color_picker: ColorPickerButton
var _entry_material_option: OptionButton
var _mat_search_edit: LineEdit
var _shader_label: Label
var _btn_shader_load: Button
var _btn_shader_clear: Button
var _shader_dialog: FileDialog
var _shader_params_container: VBoxContainer
var _selected_entry: int = -1

var _material_list: Array[Dictionary] = []  # cached from MaterialRegistry


func _ready() -> void:
	_material_list = MaterialRegistry.get_all_materials()

	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# ── Palette selector row ──
	var pal_label := Label.new()
	pal_label.text = "Palette Set"
	pal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(pal_label)

	var pal_row := HBoxContainer.new()
	_palette_selector = OptionButton.new()
	_palette_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_selector.item_selected.connect(_on_palette_selected)
	pal_row.add_child(_palette_selector)

	_btn_dup_palette = Button.new()
	_btn_dup_palette.text = "Dup"
	_btn_dup_palette.tooltip_text = "Duplicate active palette"
	_btn_dup_palette.pressed.connect(_on_dup_palette)
	pal_row.add_child(_btn_dup_palette)

	_btn_del_palette = Button.new()
	_btn_del_palette.text = "Del"
	_btn_del_palette.tooltip_text = "Delete active palette"
	_btn_del_palette.pressed.connect(_on_del_palette)
	pal_row.add_child(_btn_del_palette)
	root.add_child(pal_row)

	root.add_child(HSeparator.new())

	# ── Entry editor ──
	var entry_label := Label.new()
	entry_label.text = "Entry Properties"
	entry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(entry_label)

	# Name
	var name_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size.x = 60
	name_row.add_child(name_lbl)
	_entry_name_edit = LineEdit.new()
	_entry_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry_name_edit.text_submitted.connect(_on_entry_name_changed)
	name_row.add_child(_entry_name_edit)
	root.add_child(name_row)

	# Color
	var color_row := HBoxContainer.new()
	var color_lbl := Label.new()
	color_lbl.text = "Color:"
	color_lbl.custom_minimum_size.x = 60
	color_row.add_child(color_lbl)
	_entry_color_picker = ColorPickerButton.new()
	_entry_color_picker.custom_minimum_size = Vector2(80, 28)
	_entry_color_picker.color_changed.connect(_on_entry_color_changed)
	color_row.add_child(_entry_color_picker)
	root.add_child(color_row)

	# Material — searchable dropdown
	var mat_row := HBoxContainer.new()
	var mat_lbl := Label.new()
	mat_lbl.text = "Material:"
	mat_lbl.custom_minimum_size.x = 60
	mat_row.add_child(mat_lbl)

	var mat_vbox := VBoxContainer.new()
	mat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_entry_material_option = OptionButton.new()
	_entry_material_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in _material_list:
		_entry_material_option.add_item(m["name"], m["id"])
	_entry_material_option.item_selected.connect(_on_entry_material_changed)
	mat_vbox.add_child(_entry_material_option)

	_mat_search_edit = LineEdit.new()
	_mat_search_edit.placeholder_text = "Filter materials..."
	_mat_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mat_search_edit.clear_button_enabled = true
	_mat_search_edit.text_changed.connect(_on_mat_search_changed)
	mat_vbox.add_child(_mat_search_edit)

	mat_row.add_child(mat_vbox)
	root.add_child(mat_row)

	# Shader material
	var shader_row := HBoxContainer.new()
	var shader_lbl := Label.new()
	shader_lbl.text = "Shader:"
	shader_lbl.custom_minimum_size.x = 60
	shader_row.add_child(shader_lbl)
	_shader_label = Label.new()
	_shader_label.text = "(none)"
	_shader_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shader_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shader_row.add_child(_shader_label)
	_btn_shader_load = Button.new()
	_btn_shader_load.text = "Load"
	_btn_shader_load.pressed.connect(_on_shader_load)
	shader_row.add_child(_btn_shader_load)
	_btn_shader_clear = Button.new()
	_btn_shader_clear.text = "X"
	_btn_shader_clear.tooltip_text = "Clear shader material"
	_btn_shader_clear.pressed.connect(_on_shader_clear)
	shader_row.add_child(_btn_shader_clear)
	root.add_child(shader_row)

	# Shader parameters container
	_shader_params_container = VBoxContainer.new()
	root.add_child(_shader_params_container)

	# File dialog for loading shader materials
	_shader_dialog = FileDialog.new()
	_shader_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_shader_dialog.access = FileDialog.ACCESS_RESOURCES
	_shader_dialog.filters = PackedStringArray([
		"*.gdshader ; Shader", "*.tres ; Resource", "*.res ; Resource", "*.material ; Material"])
	_shader_dialog.title = "Load Shader Material"
	_shader_dialog.file_selected.connect(_on_shader_file_selected)
	add_child(_shader_dialog)

	root.add_child(HSeparator.new())

	# Delete entry button (Add is handled per-group in PalettePanel)
	_btn_del_entry = Button.new()
	_btn_del_entry.text = "Delete Entry"
	_btn_del_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_del_entry.pressed.connect(_on_del_entry)
	root.add_child(_btn_del_entry)

	add_child(root)


func set_palette_set(ps: TilePaletteSet) -> void:
	_palette_set = ps
	_rebuild_palette_selector()


func set_selected_entry(index: int) -> void:
	_selected_entry = index
	_update_entry_editor()


func _rebuild_palette_selector() -> void:
	if not _palette_selector or not _palette_set:
		return
	_palette_selector.clear()
	for i in _palette_set.count():
		_palette_selector.add_item(_palette_set.get_palette_name(i), i)
	_palette_selector.selected = _palette_set.active_index
	_btn_del_palette.disabled = _palette_set.count() <= 1


func _update_entry_editor() -> void:
	if not _palette_set or _selected_entry < 0:
		_entry_name_edit.text = ""
		_entry_color_picker.color = Color.WHITE
		_btn_del_entry.disabled = true
		return

	var pal := _palette_set.get_active()
	if not pal or _selected_entry >= pal.entries.size():
		return

	var entry: PaletteEntry = pal.entries[_selected_entry]
	_entry_name_edit.text = entry.entry_name
	_entry_color_picker.color = entry.color
	_btn_del_entry.disabled = _selected_entry == 0  # Can't delete Air

	# Select matching material in dropdown
	for i in _entry_material_option.item_count:
		if _entry_material_option.get_item_id(i) == entry.base_material:
			_entry_material_option.selected = i
			break

	# Show shader material name
	if entry.shader_material:
		var path: String = entry.shader_material.resource_path
		_shader_label.text = path.get_file() if not path.is_empty() else entry.shader_material.get_class()
	else:
		_shader_label.text = "(none)"
	_btn_shader_clear.disabled = entry.shader_material == null
	_rebuild_shader_params(entry.shader_material)


func _on_palette_selected(index: int) -> void:
	if not _palette_set:
		return
	if _palette_set.set_active(index):
		palette_switched.emit(index)


func _on_dup_palette() -> void:
	if not _palette_set:
		return
	var new_idx := _palette_set.duplicate_active()
	if new_idx >= 0:
		_palette_set.set_active(new_idx)
		_rebuild_palette_selector()
		palette_switched.emit(new_idx)


func _on_del_palette() -> void:
	if not _palette_set or _palette_set.count() <= 1:
		return
	var old_idx := _palette_set.active_index
	if _palette_set.remove_palette(old_idx):
		_rebuild_palette_selector()
		palette_switched.emit(_palette_set.active_index)


func _on_del_entry() -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry <= 0 or _selected_entry >= pal.entries.size():
		return
	var idx := _selected_entry
	pal.entries.remove_at(idx)
	_palette_set.sync_entry_count()
	_selected_entry = mini(idx, pal.entries.size() - 1)
	entry_removed.emit(idx)


func _on_entry_name_changed(new_name: String) -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	pal.entries[_selected_entry].entry_name = new_name
	# Sync name to all palettes (names are shared)
	for p in _palette_set.palettes:
		if p != pal and _selected_entry < p.entries.size():
			p.entries[_selected_entry].entry_name = new_name
	entry_changed.emit(_selected_entry)


func _on_entry_color_changed(color: Color) -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	pal.entries[_selected_entry].color = color
	entry_changed.emit(_selected_entry)


func _on_mat_search_changed(text: String) -> void:
	var filter := text.strip_edges().to_lower()
	_entry_material_option.clear()
	for m in _material_list:
		var mname: String = m["name"]
		if filter.is_empty() or mname.to_lower().contains(filter):
			_entry_material_option.add_item(mname, m["id"])
	# Re-select the current entry's material if visible
	if _palette_set and _selected_entry >= 0:
		var pal := _palette_set.get_active()
		if pal and _selected_entry < pal.entries.size():
			var base := pal.entries[_selected_entry].base_material
			for i in _entry_material_option.item_count:
				if _entry_material_option.get_item_id(i) == base:
					_entry_material_option.selected = i
					break


func _on_entry_material_changed(option_index: int) -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	var mat_id := _entry_material_option.get_item_id(option_index)
	pal.entries[_selected_entry].base_material = mat_id
	# Sync material to all palettes (materials are shared)
	for p in _palette_set.palettes:
		if _selected_entry < p.entries.size():
			p.entries[_selected_entry].base_material = mat_id
	entry_changed.emit(_selected_entry)


func _rebuild_shader_params(mat: Material) -> void:
	for child in _shader_params_container.get_children():
		child.queue_free()

	if not mat is ShaderMaterial:
		return
	var sm := mat as ShaderMaterial
	if not sm.shader:
		return

	var params := sm.shader.get_shader_uniform_list()
	for param in params:
		var uname: String = param["name"]
		var utype: int = param["type"]
		var _hint: int = param.get("hint", 0)
		var hint_string: String = param.get("hint_string", "")
		var current: Variant = sm.get_shader_parameter(uname)

		# source_color vec4 → ColorPickerButton
		if utype == TYPE_COLOR or (utype == TYPE_VECTOR4 and hint_string.contains("source_color")):
			var color_val: Color = current if current is Color else Color.WHITE
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = _pretty_name(uname) + ":"
			lbl.custom_minimum_size.x = 100
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(lbl)
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(60, 24)
			picker.color = color_val
			picker.color_changed.connect(_on_shader_param_changed.bind(sm, uname))
			row.add_child(picker)
			_shader_params_container.add_child(row)

		# float → HSlider with value label
		elif utype == TYPE_FLOAT:
			var float_val: float = current if current is float else 0.0
			var min_val := 0.0
			var max_val := 1.0
			var step := 0.01
			if not hint_string.is_empty():
				var parts := hint_string.split(",")
				if parts.size() >= 2:
					min_val = float(parts[0].strip_edges())
					max_val = float(parts[1].strip_edges())
				if parts.size() >= 3:
					step = float(parts[2].strip_edges())

			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = _pretty_name(uname) + ":"
			lbl.custom_minimum_size.x = 100
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(lbl)
			var slider := HSlider.new()
			slider.min_value = min_val
			slider.max_value = max_val
			slider.step = step
			slider.value = float_val
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.custom_minimum_size.x = 80
			var val_label := Label.new()
			val_label.text = "%.2f" % float_val
			val_label.custom_minimum_size.x = 40
			slider.value_changed.connect(func(v: float) -> void:
				val_label.text = "%.2f" % v
				_on_shader_param_changed.call(v, sm, uname)
			)
			row.add_child(slider)
			row.add_child(val_label)
			_shader_params_container.add_child(row)


func _on_shader_param_changed(value: Variant, sm: ShaderMaterial, param_name: String) -> void:
	sm.set_shader_parameter(param_name, value)
	entry_changed.emit(_selected_entry)


static func _pretty_name(uname: String) -> String:
	return uname.replace("_", " ").capitalize()


func _on_shader_load() -> void:
	_shader_dialog.popup_centered(Vector2i(700, 500))


func _on_shader_clear() -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	pal.entries[_selected_entry].shader_material = null
	_shader_label.text = "(none)"
	_btn_shader_clear.disabled = true
	_rebuild_shader_params(null)
	entry_changed.emit(_selected_entry)


func _on_shader_file_selected(path: String) -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	var loaded := ResourceLoader.load(path)
	var mat: Material
	if loaded is Material:
		mat = loaded
	elif loaded is Shader:
		var sm := ShaderMaterial.new()
		sm.shader = loaded
		mat = sm
	if mat:
		pal.entries[_selected_entry].shader_material = mat
		_shader_label.text = path.get_file()
		_btn_shader_clear.disabled = false
		_rebuild_shader_params(mat)
		entry_changed.emit(_selected_entry)
