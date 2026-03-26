class_name MetadataEditDialog
extends ConfirmationDialog

## Dialog for editing a single metadata point's type and properties.
## Type list is populated dynamically from MetadataTool's registry.

signal point_confirmed(pos: Vector3i, type: String, properties: Dictionary)
signal point_deleted(pos: Vector3i)

var _pos: Vector3i
var _pos_label: Label
var _type_option: OptionButton
var _props_container: VBoxContainer
var _prop_entries: Array[Dictionary] = []  # [{key: LineEdit, value: LineEdit}]
var _delete_btn: Button
var _is_new: bool = true
var _metadata_tool: MetadataTool
var _type_names: PackedStringArray

# Particle-specific UI
var _particle_container: VBoxContainer
var _scene_path_edit: LineEdit
var _scene_browse_btn: Button
var _scene_dialog: FileDialog
var _auto_start_check: CheckBox
var _one_shot_check: CheckBox


func _ready() -> void:
	title = "Metadata Point"
	min_size = Vector2i(400, 350)

	var vbox := VBoxContainer.new()

	# Position label
	_pos_label = Label.new()
	_pos_label.text = "Position: (0, 0, 0)"
	vbox.add_child(_pos_label)

	vbox.add_child(HSeparator.new())

	# Type selector
	var type_row := HBoxContainer.new()
	var type_lbl := Label.new()
	type_lbl.text = "Type:"
	type_lbl.custom_minimum_size.x = 60
	type_row.add_child(type_lbl)

	_type_option = OptionButton.new()
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_option.item_selected.connect(_on_type_selected)
	type_row.add_child(_type_option)
	vbox.add_child(type_row)

	vbox.add_child(HSeparator.new())

	# Properties
	var props_lbl := Label.new()
	props_lbl.text = "Properties (key = value):"
	props_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(props_lbl)

	_props_container = VBoxContainer.new()
	vbox.add_child(_props_container)

	var add_prop_btn := Button.new()
	add_prop_btn.text = "+ Add Property"
	add_prop_btn.pressed.connect(_add_prop_row)
	vbox.add_child(add_prop_btn)

	vbox.add_child(HSeparator.new())

	# Particle-specific controls (shown/hidden based on type)
	_particle_container = VBoxContainer.new()
	_particle_container.visible = false
	vbox.add_child(_particle_container)

	var scene_row := HBoxContainer.new()
	var scene_lbl := Label.new()
	scene_lbl.text = "Scene:"
	scene_lbl.custom_minimum_size.x = 70
	scene_row.add_child(scene_lbl)
	_scene_path_edit = LineEdit.new()
	_scene_path_edit.placeholder_text = "res://particles/effect.tscn"
	_scene_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_row.add_child(_scene_path_edit)
	_scene_browse_btn = Button.new()
	_scene_browse_btn.text = "Browse"
	_scene_browse_btn.pressed.connect(_on_scene_browse)
	scene_row.add_child(_scene_browse_btn)
	_particle_container.add_child(scene_row)

	var checks_row := HBoxContainer.new()
	_auto_start_check = CheckBox.new()
	_auto_start_check.text = "Auto Start"
	_auto_start_check.button_pressed = true
	checks_row.add_child(_auto_start_check)
	_one_shot_check = CheckBox.new()
	_one_shot_check.text = "One Shot"
	checks_row.add_child(_one_shot_check)
	_particle_container.add_child(checks_row)

	# Scene file dialog
	_scene_dialog = FileDialog.new()
	_scene_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_scene_dialog.access = FileDialog.ACCESS_RESOURCES
	_scene_dialog.filters = PackedStringArray(["*.tscn ; Scene", "*.scn ; Scene"])
	_scene_dialog.title = "Select Particle Scene"
	_scene_dialog.file_selected.connect(_on_scene_selected)
	add_child(_scene_dialog)

	vbox.add_child(HSeparator.new())

	# Delete button
	_delete_btn = Button.new()
	_delete_btn.text = "Delete Point"
	_delete_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_delete_btn.pressed.connect(_on_delete)
	vbox.add_child(_delete_btn)

	add_child(vbox)
	confirmed.connect(_on_confirmed)


## Set the metadata tool reference to populate types from the registry.
func set_metadata_tool(tool: MetadataTool) -> void:
	_metadata_tool = tool
	_refresh_type_list()


func _refresh_type_list() -> void:
	if not _type_option or not _metadata_tool:
		return
	_type_option.clear()

	# Group by category
	var by_category: Dictionary = _metadata_tool.get_types_by_category()
	_type_names = PackedStringArray()
	var idx := 0

	for cat in by_category:
		if idx > 0:
			_type_option.add_separator(cat)
		var types: Array = by_category[cat]
		for type_name in types:
			var _info: Dictionary = _metadata_tool.get_type_info(type_name)
			_type_option.add_item(type_name)
			var item_idx := _type_option.item_count - 1
			# Tint the icon area with the type's color
			_type_option.set_item_metadata(item_idx, type_name)
			_type_names.append(type_name)
		idx += 1


## Open dialog for a new point.
func open_new(pos: Vector3i, default_type: String = "") -> void:
	_refresh_type_list()
	_pos = pos
	_is_new = true
	_delete_btn.visible = false
	_pos_label.text = "Position: (%d, %d, %d)" % [pos.x, pos.y, pos.z]

	# Pre-select the requested type if provided
	var selected_idx := 0
	if not default_type.is_empty():
		for i in _type_option.item_count:
			if _type_option.get_item_text(i) == default_type:
				selected_idx = i
				break
	_type_option.selected = selected_idx
	_clear_props()
	_on_type_selected(selected_idx)
	title = "New Metadata Point"
	popup_centered()


## Open dialog to edit an existing point.
func open_edit(pos: Vector3i, data: Dictionary) -> void:
	_refresh_type_list()
	_pos = pos
	_is_new = false
	_delete_btn.visible = true
	_pos_label.text = "Position: (%d, %d, %d)" % [pos.x, pos.y, pos.z]

	# Set type
	var type_str: String = data.get("type", "custom")
	for i in _type_option.item_count:
		if _type_option.get_item_text(i) == type_str:
			_type_option.selected = i
			break

	# Populate fields based on type
	var is_particle := _is_particle_type(type_str)
	_particle_container.visible = is_particle
	_props_container.visible = not is_particle

	_clear_props()
	if is_particle:
		_scene_path_edit.text = str(data.get("scene", ""))
		_auto_start_check.button_pressed = bool(data.get("auto_start", true))
		_one_shot_check.button_pressed = bool(data.get("one_shot", false))
		# Also populate any extra custom properties
		for key in data:
			if key in ["type", "scene", "auto_start", "one_shot"]:
				continue
			var row := _add_prop_row()
			row["key"].text = str(key)
			row["value"].text = str(data[key])
	else:
		for key in data:
			if key == "type":
				continue
			var row := _add_prop_row()
			row["key"].text = str(key)
			row["value"].text = str(data[key])

	title = "Edit Metadata Point"
	popup_centered()


func _is_particle_type(type_name: String) -> bool:
	return type_name == "particle"


func _on_type_selected(_idx: int) -> void:
	var type_name := _type_option.get_item_text(_type_option.selected)
	var is_particle := _is_particle_type(type_name)
	_particle_container.visible = is_particle
	_props_container.get_parent().get_child(
		_props_container.get_index() - 1).visible = not is_particle  # props label
	_props_container.visible = not is_particle
	# The "+ Add Property" button is right after _props_container
	var add_btn_idx := _props_container.get_index() + 1
	var add_btn := _props_container.get_parent().get_child(add_btn_idx)
	if add_btn is Button:
		add_btn.visible = not is_particle

	if is_particle:
		# Reset particle fields to defaults
		_scene_path_edit.text = ""
		_auto_start_check.button_pressed = true
		_one_shot_check.button_pressed = false
	elif _prop_entries.is_empty():
		_populate_defaults_for_current_type()


func _populate_defaults_for_current_type() -> void:
	if not _metadata_tool:
		return
	var type_name := _type_option.get_item_text(_type_option.selected)
	var defaults: Dictionary = _metadata_tool.get_default_properties(type_name)
	_clear_props()
	for key in defaults:
		var row := _add_prop_row()
		row["key"].text = str(key)
		row["value"].text = str(defaults[key])


func _clear_props() -> void:
	for entry in _prop_entries:
		entry["row"].queue_free()
	_prop_entries.clear()


func _add_prop_row() -> Dictionary:
	var row := HBoxContainer.new()

	var key_edit := LineEdit.new()
	key_edit.placeholder_text = "key"
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_edit)

	var eq_lbl := Label.new()
	eq_lbl.text = "="
	row.add_child(eq_lbl)

	var val_edit := LineEdit.new()
	val_edit.placeholder_text = "value"
	val_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val_edit)

	var del_btn := Button.new()
	del_btn.text = "X"
	var entry := { "row": row, "key": key_edit, "value": val_edit }
	del_btn.pressed.connect(func():
		row.queue_free()
		_prop_entries.erase(entry))
	row.add_child(del_btn)

	_props_container.add_child(row)
	_prop_entries.append(entry)
	return entry


func _on_confirmed() -> void:
	var type_str := _type_option.get_item_text(_type_option.selected)
	var props := {}

	# Collect particle-specific fields
	if _is_particle_type(type_str):
		props["scene"] = _scene_path_edit.text.strip_edges()
		props["auto_start"] = _auto_start_check.button_pressed
		props["one_shot"] = _one_shot_check.button_pressed

	# Collect generic key=value properties
	for entry in _prop_entries:
		var key: String = entry["key"].text.strip_edges()
		var value: String = entry["value"].text.strip_edges()
		if not key.is_empty():
			if value.is_valid_int():
				props[key] = value.to_int()
			elif value.is_valid_float():
				props[key] = value.to_float()
			else:
				props[key] = value
	point_confirmed.emit(_pos, type_str, props)


func _on_scene_browse() -> void:
	_scene_dialog.popup_centered(Vector2i(700, 500))


func _on_scene_selected(path: String) -> void:
	_scene_path_edit.text = path


func _on_delete() -> void:
	point_deleted.emit(_pos)
	hide()
