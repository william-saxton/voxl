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

# Shader plane-specific UI
var _shader_container: VBoxContainer
var _shader_path_edit: LineEdit
var _shader_browse_btn: Button
var _shader_dialog: FileDialog
var _plane_offset: SpinBox
var _plane_inset: SpinBox
var _plane_double_sided: CheckBox
var _plane_surface_label: Label
var _shader_surface_positions: PackedInt32Array
var _shader_face_normal: Vector3i
var _shader_params_container: VBoxContainer
var _shader_param_controls: Array[Dictionary] = []  # [{name, control, type}]


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

	# Shader plane controls (shown/hidden based on type)
	_shader_container = VBoxContainer.new()
	_shader_container.visible = false
	vbox.add_child(_shader_container)

	# Surface info label
	_plane_surface_label = Label.new()
	_plane_surface_label.text = "Surface: 0 voxels"
	_plane_surface_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	_shader_container.add_child(_plane_surface_label)

	# Shader path
	var shader_row := HBoxContainer.new()
	var shader_lbl := Label.new()
	shader_lbl.text = "Shader:"
	shader_lbl.custom_minimum_size.x = 70
	shader_row.add_child(shader_lbl)
	_shader_path_edit = LineEdit.new()
	_shader_path_edit.placeholder_text = "res://shaders/effect.gdshader"
	_shader_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shader_row.add_child(_shader_path_edit)
	_shader_browse_btn = Button.new()
	_shader_browse_btn.text = "Browse"
	_shader_browse_btn.pressed.connect(_on_shader_browse)
	shader_row.add_child(_shader_browse_btn)
	_shader_container.add_child(shader_row)

	# Shader file dialog
	_shader_dialog = FileDialog.new()
	_shader_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_shader_dialog.access = FileDialog.ACCESS_RESOURCES
	_shader_dialog.filters = PackedStringArray([
		"*.gdshader ; Shader",
		"*.tres ; ShaderMaterial",
		"*.res ; ShaderMaterial",
	])
	_shader_dialog.title = "Select Shader"
	_shader_dialog.file_selected.connect(_on_shader_selected)
	add_child(_shader_dialog)

	# Offset (distance above surface along face normal)
	var offset_row := HBoxContainer.new()
	var offset_lbl := Label.new()
	offset_lbl.text = "Offset:"
	offset_lbl.custom_minimum_size.x = 70
	offset_row.add_child(offset_lbl)
	_plane_offset = SpinBox.new()
	_plane_offset.min_value = -2.0
	_plane_offset.max_value = 10.0
	_plane_offset.step = 0.01
	_plane_offset.value = 0.05
	_plane_offset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offset_row.add_child(_plane_offset)
	_shader_container.add_child(offset_row)

	# Inset (shrink boundary edges inward)
	var inset_row := HBoxContainer.new()
	var inset_lbl := Label.new()
	inset_lbl.text = "Inset:"
	inset_lbl.custom_minimum_size.x = 70
	inset_row.add_child(inset_lbl)
	_plane_inset = SpinBox.new()
	_plane_inset.min_value = 0.0
	_plane_inset.max_value = 0.5
	_plane_inset.step = 0.01
	_plane_inset.value = 0.1
	_plane_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset_row.add_child(_plane_inset)
	_shader_container.add_child(inset_row)

	# Double sided
	_plane_double_sided = CheckBox.new()
	_plane_double_sided.text = "Double Sided"
	_plane_double_sided.button_pressed = true
	_shader_container.add_child(_plane_double_sided)

	# Shader parameters (dynamically populated from shader uniforms)
	var params_sep := HSeparator.new()
	_shader_container.add_child(params_sep)
	var params_lbl := Label.new()
	params_lbl.text = "Shader Parameters:"
	params_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_shader_container.add_child(params_lbl)
	_shader_params_container = VBoxContainer.new()
	_shader_container.add_child(_shader_params_container)

	# Refresh params when shader path changes
	_shader_path_edit.text_submitted.connect(func(_t: String): _refresh_shader_params())

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


## Open dialog for a new shader plane with pre-captured surface data.
func open_new_shader_plane(pos: Vector3i, surface_positions: PackedInt32Array,
		face_normal: Vector3i) -> void:
	_refresh_type_list()
	_pos = pos
	_is_new = true
	_delete_btn.visible = false
	_pos_label.text = "Position: (%d, %d, %d)" % [pos.x, pos.y, pos.z]

	# Select shader_plane type
	for i in _type_option.item_count:
		if _type_option.get_item_text(i) == "shader_plane":
			_type_option.selected = i
			break

	_clear_props()
	_particle_container.visible = false
	_shader_container.visible = true
	_props_container.get_parent().get_child(
		_props_container.get_index() - 1).visible = false
	_props_container.visible = false
	var add_btn_idx := _props_container.get_index() + 1
	var add_btn := _props_container.get_parent().get_child(add_btn_idx)
	if add_btn is Button:
		add_btn.visible = false

	# Store surface data
	_shader_surface_positions = surface_positions
	_shader_face_normal = face_normal
	_plane_surface_label.text = "Surface: %d voxels" % (surface_positions.size() / 3)

	# Reset fields to defaults
	_shader_path_edit.text = ""
	_plane_offset.value = 0.05
	_plane_inset.value = 0.1
	_plane_double_sided.button_pressed = true
	_refresh_shader_params()  # Clear params (no shader path yet)

	title = "New Shader Plane"
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
	var is_shader := _is_shader_plane_type(type_str)
	var is_generic := not is_particle and not is_shader
	_particle_container.visible = is_particle
	_shader_container.visible = is_shader
	_props_container.visible = is_generic

	_clear_props()
	if is_particle:
		_scene_path_edit.text = str(data.get("scene", ""))
		_auto_start_check.button_pressed = bool(data.get("auto_start", true))
		_one_shot_check.button_pressed = bool(data.get("one_shot", false))
		for key in data:
			if key in ["type", "scene", "auto_start", "one_shot"]:
				continue
			var row := _add_prop_row()
			row["key"].text = str(key)
			row["value"].text = str(data[key])
	elif is_shader:
		_shader_path_edit.text = str(data.get("shader_path", ""))
		_plane_offset.value = float(data.get("offset", 0.05))
		_plane_inset.value = float(data.get("inset", 0.1))
		_plane_double_sided.button_pressed = bool(data.get("double_sided", true))
		# Restore surface data
		var sp: Variant = data.get("surface_positions")
		if sp is PackedInt32Array:
			_shader_surface_positions = sp
		else:
			_shader_surface_positions = PackedInt32Array()
		_shader_face_normal = Vector3i(
			int(data.get("face_normal_x", 0)),
			int(data.get("face_normal_y", 1)),
			int(data.get("face_normal_z", 0)))
		_plane_surface_label.text = "Surface: %d voxels" % (_shader_surface_positions.size() / 3)
		# Restore shader parameters
		var saved_params: Variant = data.get("shader_params")
		_refresh_shader_params(saved_params if saved_params is Dictionary else {})
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


func _is_shader_plane_type(type_name: String) -> bool:
	return type_name == "shader_plane"


func _on_type_selected(_idx: int) -> void:
	var type_name := _type_option.get_item_text(_type_option.selected)
	var is_particle := _is_particle_type(type_name)
	var is_shader := _is_shader_plane_type(type_name)
	var is_generic := not is_particle and not is_shader
	_particle_container.visible = is_particle
	_shader_container.visible = is_shader
	_props_container.get_parent().get_child(
		_props_container.get_index() - 1).visible = is_generic  # props label
	_props_container.visible = is_generic
	# The "+ Add Property" button is right after _props_container
	var add_btn_idx := _props_container.get_index() + 1
	var add_btn := _props_container.get_parent().get_child(add_btn_idx)
	if add_btn is Button:
		add_btn.visible = is_generic

	if is_particle:
		_scene_path_edit.text = ""
		_auto_start_check.button_pressed = true
		_one_shot_check.button_pressed = false
	elif is_shader:
		_shader_path_edit.text = ""
		_plane_offset.value = 0.05
		_plane_inset.value = 0.1
		_plane_double_sided.button_pressed = true
		_refresh_shader_params()
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
	elif _is_shader_plane_type(type_str):
		props["shader_path"] = _shader_path_edit.text.strip_edges()
		props["offset"] = _plane_offset.value
		props["inset"] = _plane_inset.value
		props["double_sided"] = _plane_double_sided.button_pressed
		props["surface_positions"] = _shader_surface_positions
		props["face_normal_x"] = _shader_face_normal.x
		props["face_normal_y"] = _shader_face_normal.y
		props["face_normal_z"] = _shader_face_normal.z
		props["shader_params"] = _collect_shader_params()

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


func _on_shader_browse() -> void:
	_shader_dialog.popup_centered(Vector2i(700, 500))


func _on_shader_selected(path: String) -> void:
	_shader_path_edit.text = path
	_refresh_shader_params()


## Load shader uniforms and create UI controls for editable parameters.
func _refresh_shader_params(saved_params: Dictionary = {}) -> void:
	# Clear existing param controls
	for ctrl in _shader_param_controls:
		ctrl["row"].queue_free()
	_shader_param_controls.clear()

	var path := _shader_path_edit.text.strip_edges()
	if path.is_empty() or not ResourceLoader.exists(path):
		return

	var shader: Shader
	var loaded := ResourceLoader.load(path)
	if loaded is ShaderMaterial:
		shader = (loaded as ShaderMaterial).shader
	elif loaded is Shader:
		shader = loaded
	if not shader:
		return

	var uniforms := shader.get_shader_uniform_list()
	for u in uniforms:
		var uname: String = u["name"]
		var utype: int = u["type"]

		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = uname.replace("_", " ").capitalize() + ":"
		lbl.custom_minimum_size.x = 100
		row.add_child(lbl)

		var control: Control
		var saved_val: Variant = saved_params.get(uname)

		match utype:
			TYPE_FLOAT:
				var spin := SpinBox.new()
				spin.min_value = -1000.0
				spin.max_value = 1000.0
				spin.step = 0.01
				# Check for hint_range
				if u.has("hint_string") and not (u["hint_string"] as String).is_empty():
					var parts: PackedStringArray = (u["hint_string"] as String).split(",")
					if parts.size() >= 2:
						spin.min_value = float(parts[0].strip_edges())
						spin.max_value = float(parts[1].strip_edges())
					if parts.size() >= 3:
						spin.step = float(parts[2].strip_edges())
				if saved_val != null:
					spin.value = float(saved_val)
				elif u.has("default_value"):
					spin.value = float(u["default_value"])
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				control = spin
			TYPE_COLOR:
				var picker := ColorPickerButton.new()
				picker.custom_minimum_size = Vector2(60, 30)
				if saved_val != null and saved_val is Color:
					picker.color = saved_val
				elif u.has("default_value") and u["default_value"] is Color:
					picker.color = u["default_value"]
				picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				control = picker
			TYPE_BOOL:
				var check := CheckBox.new()
				if saved_val != null:
					check.button_pressed = bool(saved_val)
				elif u.has("default_value"):
					check.button_pressed = bool(u["default_value"])
				control = check
			TYPE_VECTOR2:
				var hbox := HBoxContainer.new()
				hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for axis in ["x", "y"]:
					var spin := SpinBox.new()
					spin.min_value = -1000.0
					spin.max_value = 1000.0
					spin.step = 0.01
					spin.prefix = axis + ":"
					spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					if saved_val != null and saved_val is Vector2:
						spin.value = saved_val[axis]
					hbox.add_child(spin)
				control = hbox
			_:
				# Unsupported type — skip
				row.queue_free()
				continue

		row.add_child(control)
		_shader_params_container.add_child(row)
		_shader_param_controls.append({
			"name": uname, "row": row, "control": control, "type": utype
		})


## Collect current shader param values into a Dictionary.
func _collect_shader_params() -> Dictionary:
	var result := {}
	for ctrl in _shader_param_controls:
		var uname: String = ctrl["name"]
		var utype: int = ctrl["type"]
		var c: Control = ctrl["control"]
		match utype:
			TYPE_FLOAT:
				result[uname] = (c as SpinBox).value
			TYPE_COLOR:
				result[uname] = (c as ColorPickerButton).color
			TYPE_BOOL:
				result[uname] = (c as CheckBox).button_pressed
			TYPE_VECTOR2:
				var hbox := c as HBoxContainer
				result[uname] = Vector2(
					(hbox.get_child(0) as SpinBox).value,
					(hbox.get_child(1) as SpinBox).value)
	return result


func _on_delete() -> void:
	point_deleted.emit(_pos)
	hide()
