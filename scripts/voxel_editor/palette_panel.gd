class_name PalettePanel
extends PanelContainer

## Palette entry list for the voxel editor, grouped by base material.
## Supports palette switching via TilePaletteSet.
## Supports search filtering and multi-select (Ctrl+click) for gradient painting.

signal entry_selected(index: int)
signal multi_selection_changed(indices: Array[int])
signal add_entry_requested(base_material: int)

var _palette: VoxelPalette
var _palette_set: TilePaletteSet
var _selected_index: int = 1
var _multi_selected: Array[int] = []  ## All selected indices (includes _selected_index)
var _scroll: ScrollContainer
var _list: VBoxContainer
var _entry_buttons: Array[Button] = []
var _palette_selector: OptionButton
var _search_edit: LineEdit
var _search_text: String = ""


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := Label.new()
	header.text = "Palette"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Palette selector dropdown (hidden if no palette set)
	_palette_selector = OptionButton.new()
	_palette_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_selector.item_selected.connect(_on_palette_selector_changed)
	_palette_selector.visible = false

	# Search bar
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search entries..."
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)

	vbox.add_child(header)
	vbox.add_child(_palette_selector)
	vbox.add_child(_search_edit)
	_scroll.add_child(_list)
	vbox.add_child(_scroll)
	add_child(vbox)


## Set a single palette (backward compatible).
func set_palette(palette: VoxelPalette) -> void:
	_palette = palette
	_rebuild_list()


## Set a palette set for multi-palette support.
func set_palette_set(ps: TilePaletteSet) -> void:
	_palette_set = ps
	_palette = ps.get_active()
	_rebuild_palette_selector()
	_rebuild_list()


func select_entry(index: int) -> void:
	_selected_index = index
	_multi_selected = [index]
	_update_selection()
	multi_selection_changed.emit(_multi_selected.duplicate())


func get_selected_index() -> int:
	return _selected_index


func get_multi_selected() -> Array[int]:
	return _multi_selected.duplicate()


func _rebuild_palette_selector() -> void:
	if not _palette_selector or not _palette_set:
		_palette_selector.visible = false
		return
	_palette_selector.clear()
	for i in _palette_set.count():
		_palette_selector.add_item(_palette_set.get_palette_name(i), i)
	_palette_selector.selected = _palette_set.active_index
	_palette_selector.visible = _palette_set.count() > 1


func _on_palette_selector_changed(index: int) -> void:
	if not _palette_set:
		return
	_palette_set.set_active(index)
	_palette = _palette_set.get_active()
	_rebuild_list()


func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges().to_lower()
	_rebuild_list()


func refresh() -> void:
	if _palette_set:
		_palette = _palette_set.get_active()
		_rebuild_palette_selector()
	_rebuild_list()


func _matches_search(entry_name: String, mat_name: String) -> bool:
	if _search_text.is_empty():
		return true
	var lower_entry := entry_name.to_lower()
	var lower_mat := mat_name.to_lower()
	return lower_entry.contains(_search_text) or lower_mat.contains(_search_text)


func _rebuild_list() -> void:
	# Clear existing
	for child in _list.get_children():
		child.queue_free()
	_entry_buttons.clear()

	if not _palette:
		return

	# Group entries by base material
	var groups: Dictionary = {}  # base_material → Array[int] (indices)
	for i in _palette.entries.size():
		var entry: PaletteEntry = _palette.entries[i]
		var base := entry.base_material
		if not groups.has(base):
			groups[base] = []
		groups[base].append(i)

	# Get all material types from registry so every type is shown
	var all_materials := MaterialRegistry.get_all_materials()

	for mat_info in all_materials:
		var base_mat: int = mat_info["id"]
		var mat_name: String = mat_info["name"]
		var indices: Array = groups.get(base_mat, [])

		# Skip Air group if it only has the reserved entry (index 0)
		if base_mat == MaterialRegistry.AIR and indices.size() <= 1:
			continue

		# Filter entries by search
		var visible_indices: Array[int] = []
		for idx: int in indices:
			var entry: PaletteEntry = _palette.entries[idx]
			var ename: String = entry.entry_name if entry.entry_name != "" else "Entry %d" % idx
			if _matches_search(ename, mat_name):
				visible_indices.append(idx)

		# Skip entire group if no entries match search
		if visible_indices.is_empty() and not _search_text.is_empty():
			continue

		# Group header row with material name and "+" button
		var header_row := HBoxContainer.new()
		header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var mat_tooltip: String = mat_info.get("tooltip", "")

		var group_label := Label.new()
		group_label.text = "── %s ──" % mat_name
		group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		group_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		if mat_tooltip != "":
			group_label.tooltip_text = "%s: %s" % [mat_name, mat_tooltip]
			group_label.mouse_filter = Control.MOUSE_FILTER_STOP
		header_row.add_child(group_label)

		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.tooltip_text = "Add %s entry" % mat_name
		add_btn.custom_minimum_size = Vector2(28, 24)
		var captured_mat: int = base_mat
		add_btn.pressed.connect(func(): add_entry_requested.emit(captured_mat))
		header_row.add_child(add_btn)

		_list.add_child(header_row)

		var entries_to_show: Array[int] = []
		if not _search_text.is_empty():
			entries_to_show = visible_indices
		else:
			for idx: int in indices:
				entries_to_show.append(idx)

		for idx in entries_to_show:
			var entry: PaletteEntry = _palette.entries[idx]
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 28)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

			# Color swatch via a ColorRect in an HBoxContainer
			var hbox := HBoxContainer.new()
			hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(20, 20)
			swatch.color = entry.color
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(swatch)

			var lbl := Label.new()
			lbl.text = " %s" % entry.entry_name if entry.entry_name != "" else " Entry %d" % idx
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(lbl)

			btn.add_child(hbox)

			var captured_idx: int = idx
			btn.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_on_entry_clicked(captured_idx, event.ctrl_pressed)
					btn.accept_event()
			)
			var entry_tip := "%s (ID: %d, base: %s)" % [entry.entry_name, idx, mat_name]
			if mat_tooltip != "":
				entry_tip += "\n%s" % mat_tooltip
			btn.tooltip_text = entry_tip

			_list.add_child(btn)
			# Pad button array to match indices
			while _entry_buttons.size() <= idx:
				_entry_buttons.append(null)
			_entry_buttons[idx] = btn

	_update_selection()


func _on_entry_clicked(index: int, ctrl_held: bool) -> void:
	if ctrl_held:
		# Toggle multi-select
		if index in _multi_selected:
			_multi_selected.erase(index)
			# If we removed the primary, pick another
			if index == _selected_index and not _multi_selected.is_empty():
				_selected_index = _multi_selected[0]
		else:
			_multi_selected.append(index)
		# Always keep at least one selected
		if _multi_selected.is_empty():
			_multi_selected = [index]
			_selected_index = index
		multi_selection_changed.emit(_multi_selected.duplicate())
	else:
		# Normal click — single select
		_selected_index = index
		_multi_selected = [index]
		multi_selection_changed.emit(_multi_selected.duplicate())
	_update_selection()
	entry_selected.emit(_selected_index)


func _on_entry_pressed(index: int) -> void:
	_selected_index = index
	_multi_selected = [index]
	_update_selection()
	entry_selected.emit(index)
	multi_selection_changed.emit(_multi_selected.duplicate())


func _update_selection() -> void:
	for i in _entry_buttons.size():
		var btn := _entry_buttons[i]
		if btn and is_instance_valid(btn):
			btn.flat = i not in _multi_selected
