class_name RemoteBrowserDialog
extends AcceptDialog
## Dialog for browsing, pulling, and pushing assets to/from the remote MinIO store.

signal palette_pull_requested(palette: VoxelPalette)
signal tile_pull_requested(tile: WFCTileDef, palette: VoxelPalette)

var _tabs: TabContainer
var _palette_list: ItemList
var _tile_list: ItemList
var _refresh_btn: Button
var _pull_btn: Button
var _status_label: Label

# Cached listing data for mapping selection index → key
var _palette_keys: PackedStringArray = []
var _tile_keys: PackedStringArray = []


func _init() -> void:
	title = "Remote Asset Browser"
	min_size = Vector2i(560, 400)
	exclusive = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# -- Palettes tab --
	var pal_container := VBoxContainer.new()
	pal_container.name = "Palettes"
	_palette_list = ItemList.new()
	_palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_list.allow_reselect = true
	pal_container.add_child(_palette_list)
	_tabs.add_child(pal_container)

	# -- Tiles tab --
	var tile_container := VBoxContainer.new()
	tile_container.name = "Tiles"
	_tile_list = ItemList.new()
	_tile_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tile_list.allow_reselect = true
	tile_container.add_child(_tile_list)
	_tabs.add_child(tile_container)

	vbox.add_child(_tabs)

	# Bottom row: buttons + status
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(_on_refresh)
	bottom.add_child(_refresh_btn)

	_pull_btn = Button.new()
	_pull_btn.text = "Pull Selected"
	_pull_btn.pressed.connect(_on_pull)
	bottom.add_child(_pull_btn)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_status_label)

	vbox.add_child(bottom)
	add_child(vbox)


func show_browser() -> void:
	_populate_lists()
	popup_centered(Vector2i(560, 400))
	if AssetSyncManager.connected:
		_on_refresh()


# ---------------------------------------------------------------------------
# Populate from cached listings
# ---------------------------------------------------------------------------

func _populate_lists() -> void:
	_populate_bucket_list(
		AssetSyncManager.PALETTE_BUCKET, _palette_list, _palette_keys
	)
	_populate_bucket_list(
		AssetSyncManager.TILE_BUCKET, _tile_list, _tile_keys
	)


func _populate_bucket_list(bucket: String, item_list: ItemList,
		keys: PackedStringArray) -> void:
	item_list.clear()
	keys.clear()
	var objects: Array = AssetSyncManager.get_cached_listing(bucket)
	for obj in objects:
		var key: String = obj.get("key", "")
		var size: int = obj.get("size", 0)
		var size_str := _format_size(size)
		var last_mod: String = obj.get("last_modified", "")
		# Trim to just date portion if present
		if last_mod.length() > 10:
			last_mod = last_mod.left(10)
		item_list.add_item("%s   (%s, %s)" % [key, size_str, last_mod])
		keys.append(key)


func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1048576:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%.1f MB" % (bytes / 1048576.0)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

var _refresh_remaining := 0

func _on_refresh() -> void:
	if not AssetSyncManager.connected:
		_status_label.text = "Not connected"
		return
	_status_label.text = "Refreshing..."
	_refresh_remaining = 2
	if not AssetSyncManager.sync_completed.is_connected(_on_refresh_done):
		AssetSyncManager.sync_completed.connect(_on_refresh_done)
	AssetSyncManager.refresh_remote_listing(AssetSyncManager.PALETTE_BUCKET)
	AssetSyncManager.refresh_remote_listing(AssetSyncManager.TILE_BUCKET)


func _on_refresh_done(_bucket: String, _changes: Array[Dictionary]) -> void:
	_refresh_remaining -= 1
	if _refresh_remaining <= 0:
		AssetSyncManager.sync_completed.disconnect(_on_refresh_done)
		_populate_lists()
		_status_label.text = "Refreshed"


func _on_pull() -> void:
	var active_tab := _tabs.current_tab
	if active_tab == 0:
		_pull_selected_palette()
	else:
		_pull_selected_tile()


func _pull_selected_palette() -> void:
	var sel := _palette_list.get_selected_items()
	if sel.is_empty():
		_status_label.text = "Select a palette first"
		return
	var key := _palette_keys[sel[0]]
	_status_label.text = "Pulling %s..." % key
	var cb := func(_bucket: String, pulled_key: String, _path: String) -> void:
		_status_label.text = "Pulled: %s" % pulled_key
		var palette := AssetSyncManager.palette_from_cache(pulled_key)
		if palette:
			palette_pull_requested.emit(palette)
	AssetSyncManager.asset_downloaded.connect(cb, CONNECT_ONE_SHOT)
	AssetSyncManager.pull_palette(key)


func _pull_selected_tile() -> void:
	var sel := _tile_list.get_selected_items()
	if sel.is_empty():
		_status_label.text = "Select a tile first"
		return
	var key := _tile_keys[sel[0]]
	_status_label.text = "Pulling %s..." % key
	var cb := func(_bucket: String, pulled_key: String, _path: String) -> void:
		_status_label.text = "Pulled: %s" % pulled_key
		var result := AssetSyncManager.tile_from_cache(pulled_key)
		if not result.is_empty():
			tile_pull_requested.emit(result["tile"], result["palette"])
	AssetSyncManager.asset_downloaded.connect(cb, CONNECT_ONE_SHOT)
	AssetSyncManager.pull_tile(key)
