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
var _shader_label: Label
var _btn_shader_load: Button
var _btn_shader_clear: Button
var _shader_dialog: FileDialog
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

	# Material
	var mat_row := HBoxContainer.new()
	var mat_lbl := Label.new()
	mat_lbl.text = "Material:"
	mat_lbl.custom_minimum_size.x = 60
	mat_row.add_child(mat_lbl)
	_entry_material_option = OptionButton.new()
	_entry_material_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in _material_list:
		_entry_material_option.add_item(m["name"], m["id"])
	_entry_material_option.item_selected.connect(_on_entry_material_changed)
	mat_row.add_child(_entry_material_option)
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

	# File dialog for loading shader materials
	_shader_dialog = FileDialog.new()
	_shader_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_shader_dialog.access = FileDialog.ACCESS_RESOURCES
	_shader_dialog.filters = PackedStringArray([
		"*.tres ; Resource", "*.res ; Resource", "*.material ; Material"])
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


func _on_shader_load() -> void:
	_shader_dialog.popup_centered(Vector2i(700, 500))


func _on_shader_clear() -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	pal.entries[_selected_entry].shader_material = null
	_shader_label.text = "(none)"
	_btn_shader_clear.disabled = true
	entry_changed.emit(_selected_entry)


func _on_shader_file_selected(path: String) -> void:
	var pal := _palette_set.get_active() if _palette_set else null
	if not pal or _selected_entry < 0 or _selected_entry >= pal.entries.size():
		return
	var loaded := ResourceLoader.load(path)
	if loaded is Material:
		pal.entries[_selected_entry].shader_material = loaded
		_shader_label.text = path.get_file()
		_btn_shader_clear.disabled = false
		entry_changed.emit(_selected_entry)
