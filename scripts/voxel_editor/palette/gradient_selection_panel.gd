class_name GradientSelectionPanel
extends PanelContainer

## Displays the currently multi-selected palette entries with weight sliders.
## Used for weighted random placement when painting with multiple entries.

signal weights_changed()

var _palette: VoxelPalette
var _container: VBoxContainer
var _header: Label
var _gradient_preview: Control

## Maps palette index → weight (0.0 - 1.0)
var _weights: Dictionary = {}
## Ordered list of selected indices
var _selected_indices: Array[int] = []


func _ready() -> void:
	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_header = Label.new()
	_header.text = "Gradient Selection"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_header)

	_gradient_preview = _GradientPreview.new()
	_gradient_preview.custom_minimum_size = Vector2(0, 24)
	_gradient_preview.panel = self
	root.add_child(_gradient_preview)

	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 60

	_container = VBoxContainer.new()
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_container)
	root.add_child(scroll)

	add_child(root)
	visible = false


func set_palette(palette: VoxelPalette) -> void:
	_palette = palette


func update_selection(indices: Array[int]) -> void:
	_selected_indices = indices.duplicate()

	# Remove weights for deselected entries
	var to_remove: Array[int] = []
	for key: int in _weights:
		if key not in _selected_indices:
			to_remove.append(key)
	for key in to_remove:
		_weights.erase(key)

	# Add default weight for new entries
	for idx in _selected_indices:
		if idx not in _weights:
			_weights[idx] = 1.0

	visible = _selected_indices.size() > 1
	_rebuild_ui()
	weights_changed.emit()


func get_weighted_entries() -> Array[Dictionary]:
	## Returns array of { index: int, weight: float } normalized so weights sum to 1.0
	var result: Array[Dictionary] = []
	var total := 0.0
	for idx in _selected_indices:
		total += _weights.get(idx, 1.0)
	if total <= 0.0:
		total = 1.0
	for idx in _selected_indices:
		var w: float = _weights.get(idx, 1.0) / total
		result.append({ "index": idx, "weight": w })
	return result


func pick_random_index() -> int:
	## Pick a random palette index weighted by the slider values.
	if _selected_indices.size() <= 1:
		return _selected_indices[0] if not _selected_indices.is_empty() else 1

	var entries := get_weighted_entries()
	var roll := randf()
	var cumulative := 0.0
	for e in entries:
		cumulative += e["weight"]
		if roll <= cumulative:
			return e["index"]
	return entries[-1]["index"]


func _rebuild_ui() -> void:
	for child in _container.get_children():
		child.queue_free()

	if not _palette or _selected_indices.size() <= 1:
		return

	_header.text = "Gradient Selection (%d)" % _selected_indices.size()

	for idx in _selected_indices:
		if idx < 0 or idx >= _palette.entries.size():
			continue
		var entry: PaletteEntry = _palette.entries[idx]

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Color swatch
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = entry.color
		row.add_child(swatch)

		# Name
		var lbl := Label.new()
		var ename: String = entry.entry_name if entry.entry_name != "" else "Entry %d" % idx
		lbl.text = " %s" % ename
		lbl.custom_minimum_size.x = 70
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		# Weight slider
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = _weights.get(idx, 1.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 60

		var val_label := Label.new()
		val_label.text = "%.0f%%" % (_weights.get(idx, 1.0) * 100.0)
		val_label.custom_minimum_size.x = 36
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		var captured_idx: int = idx
		slider.value_changed.connect(func(v: float) -> void:
			_weights[captured_idx] = v
			val_label.text = "%.0f%%" % (v * 100.0)
			_gradient_preview.queue_redraw()
			weights_changed.emit()
		)

		row.add_child(slider)
		row.add_child(val_label)

		_container.add_child(row)

	_gradient_preview.queue_redraw()


## Inner class for the gradient bar preview
class _GradientPreview extends Control:
	var panel: GradientSelectionPanel

	func _draw() -> void:
		if not panel or not panel._palette:
			return
		var entries := panel.get_weighted_entries()
		if entries.is_empty():
			return

		var w := size.x
		var h := size.y
		var x := 0.0

		for e in entries:
			var idx: int = e["index"]
			var weight: float = e["weight"]
			var seg_w: float = w * weight
			if idx >= 0 and idx < panel._palette.entries.size():
				var color: Color = panel._palette.entries[idx].color
				draw_rect(Rect2(x, 0, seg_w, h), color)
			x += seg_w
