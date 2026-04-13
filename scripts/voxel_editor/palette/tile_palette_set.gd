class_name TilePaletteSet
extends Resource

## Container for multiple palettes sharing the same entry structure.
## All palettes have identical entry counts — only colors differ.
## Switching the active palette re-colors the viewport instantly.

@export var palettes: Array[VoxelPalette] = []
@export var active_index: int = 0


func _init() -> void:
	if palettes.is_empty():
		palettes.append(VoxelPalette.create_default())


## Get the currently active palette.
func get_active() -> VoxelPalette:
	if active_index < 0 or active_index >= palettes.size():
		return palettes[0] if not palettes.is_empty() else null
	return palettes[active_index]


## Set the active palette by index. Returns true if changed.
func set_active(index: int) -> bool:
	if index < 0 or index >= palettes.size() or index == active_index:
		return false
	active_index = index
	return true


## Add a new palette by duplicating the active one with different colors.
func duplicate_active(new_name: String = "") -> int:
	var source := get_active()
	if not source:
		return -1
	var dup := source.duplicate(true) as VoxelPalette
	if new_name.is_empty():
		dup.palette_name = source.palette_name + " (copy)"
	else:
		dup.palette_name = new_name
	palettes.append(dup)
	return palettes.size() - 1


## Remove a palette by index. Cannot remove the last palette.
func remove_palette(index: int) -> bool:
	if palettes.size() <= 1 or index < 0 or index >= palettes.size():
		return false
	palettes.remove_at(index)
	if active_index >= palettes.size():
		active_index = palettes.size() - 1
	return true


## Rename a palette.
func rename_palette(index: int, new_name: String) -> void:
	if index >= 0 and index < palettes.size():
		palettes[index].palette_name = new_name


## Get palette count.
func count() -> int:
	return palettes.size()


## Get palette name by index.
func get_palette_name(index: int) -> String:
	if index < 0 or index >= palettes.size():
		return ""
	return palettes[index].palette_name


## Ensure all palettes have the same entry count as the active palette.
## Call after adding/removing entries in the active palette.
func sync_entry_count() -> void:
	var active := get_active()
	if not active:
		return
	var target_count := active.entries.size()
	for pal in palettes:
		if pal == active:
			continue
		while pal.entries.size() < target_count:
			# Copy entry structure from active palette, keep existing colors or use default
			var src: PaletteEntry = active.entries[pal.entries.size()]
			var entry := PaletteEntry.new()
			entry.entry_name = src.entry_name
			entry.color = src.color
			entry.base_material = src.base_material
			pal.entries.append(entry)
		while pal.entries.size() > target_count:
			pal.entries.pop_back()
