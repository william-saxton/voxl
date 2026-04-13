extends Node
## Autoload singleton that manages syncing palettes and tiles with a remote
## MinIO instance over the S3 HTTP API.  Provides push / pull / listing
## operations and caches results locally under user://asset_cache/.

signal connection_status_changed(connected: bool)
signal sync_completed(bucket: String, changes: Array[Dictionary])
signal asset_downloaded(bucket: String, key: String, local_path: String)
signal asset_uploaded(bucket: String, key: String, etag: String)
signal new_remote_assets(bucket: String, keys: PackedStringArray)

const PALETTE_BUCKET := "voxl-palettes"
const TILE_BUCKET    := "voxl-tiles"
const CONFIG_PATH    := "user://sync_config.cfg"
const CACHE_DIR      := "user://asset_cache"

var endpoint: String = ""
var enabled: bool = false
var connected: bool = false
var auto_push: bool = true       ## Auto-push tiles/palettes on save
var auto_pull: bool = true       ## Auto-pull new/changed assets when detected
var poll_interval: float = 5.0   ## Seconds between remote listing checks (0 = disabled)

var _s3: S3Client
var _poll_timer: Timer
var _push_timer: Timer

## Set these from the editor to enable the 5-second push check.
var _pending_palette: VoxelPalette = null
var _palette_dirty: bool = false
var _pending_tile: WFCTileDef = null
var _tile_dirty: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_s3 = S3Client.new()
	add_child(_s3)
	_s3.request_failed.connect(_on_s3_error)

	_poll_timer = Timer.new()
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll_tick)
	add_child(_poll_timer)

	_push_timer = Timer.new()
	_push_timer.one_shot = false
	_push_timer.wait_time = 5.0
	_push_timer.timeout.connect(_on_push_tick)
	add_child(_push_timer)

	_ensure_cache_dirs()
	_load_config()
	if enabled and not endpoint.is_empty():
		test_connection()


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	endpoint      = cfg.get_value("sync", "endpoint", "")
	enabled       = cfg.get_value("sync", "enabled", false)
	auto_push     = cfg.get_value("sync", "auto_push", true)
	auto_pull     = cfg.get_value("sync", "auto_pull", true)
	poll_interval = cfg.get_value("sync", "poll_interval", 5.0)
	_s3.endpoint = endpoint


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sync", "endpoint", endpoint)
	cfg.set_value("sync", "enabled", enabled)
	cfg.set_value("sync", "auto_push", auto_push)
	cfg.set_value("sync", "auto_pull", auto_pull)
	cfg.set_value("sync", "poll_interval", poll_interval)
	cfg.save(CONFIG_PATH)
	_s3.endpoint = endpoint
	_restart_poll_timer()


# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

func test_connection() -> void:
	if endpoint.is_empty():
		connected = false
		connection_status_changed.emit(false)
		return
	_s3.endpoint = endpoint
	_s3.check_health(func(result: Dictionary) -> void:
		connected = result.get("reachable", false)
		connection_status_changed.emit(connected)
		if connected:
			if auto_pull:
				_initial_pull_palettes()
			refresh_remote_listing(PALETTE_BUCKET)
			refresh_remote_listing(TILE_BUCKET)
			_restart_poll_timer()
	)


## On startup, pull all remote palettes so the editor has the latest shared set.
func _initial_pull_palettes() -> void:
	_s3.list_objects(PALETTE_BUCKET, func(result: Dictionary) -> void:
		var objects: Array = result.get("objects", [])
		for obj in objects:
			var key: String = obj.get("key", "")
			if not key.is_empty():
				pull_palette(key)
	)


func _restart_poll_timer() -> void:
	_poll_timer.stop()
	_push_timer.stop()
	if connected and enabled and poll_interval > 0.0:
		_poll_timer.wait_time = poll_interval
		_poll_timer.start()
	if connected and enabled and auto_push:
		_push_timer.start()


## Mark the palette as dirty so it gets pushed on the next 5-second tick.
func mark_palette_dirty(palette: VoxelPalette) -> void:
	_pending_palette = palette
	_palette_dirty = true


## Mark the tile as dirty so it gets pushed on the next 5-second tick.
func mark_tile_dirty(tile: WFCTileDef, palette: VoxelPalette) -> void:
	_pending_tile = tile
	_pending_palette = palette
	_tile_dirty = true


func _on_push_tick() -> void:
	if not connected or not enabled or not auto_push:
		return
	if _palette_dirty and _pending_palette:
		_palette_dirty = false
		push_palette(_pending_palette)
	if _tile_dirty and _pending_tile:
		_tile_dirty = false
		push_tile(_pending_tile, _pending_palette)


func _on_poll_tick() -> void:
	if not connected or not enabled:
		_poll_timer.stop()
		return
	_s3.check_health(func(result: Dictionary) -> void:
		var reachable: bool = result.get("reachable", false)
		if not reachable:
			connected = false
			connection_status_changed.emit(false)
			_poll_timer.stop()
			return
		_poll_refresh(PALETTE_BUCKET)
		_poll_refresh(TILE_BUCKET)
	)


func _poll_refresh(bucket: String) -> void:
	_s3.list_objects(bucket, func(result: Dictionary) -> void:
		var objects: Array = result.get("objects", [])
		var changes := _diff_listing(bucket, objects)
		_save_listing_cache(bucket, objects)

		var updated_keys: PackedStringArray = []
		for change in changes:
			if change["status"] in ["new", "modified"]:
				updated_keys.append(change["key"])

		if not updated_keys.is_empty():
			new_remote_assets.emit(bucket, updated_keys)
			if auto_pull:
				for key in updated_keys:
					if bucket == PALETTE_BUCKET:
						pull_palette(key)
					else:
						pull_tile(key)
	)


# ---------------------------------------------------------------------------
# Remote listing & diff
# ---------------------------------------------------------------------------

## Fetch remote object listing and diff against local cache.
func refresh_remote_listing(bucket: String) -> void:
	_s3.list_objects(bucket, func(result: Dictionary) -> void:
		var objects: Array = result.get("objects", [])
		var changes := _diff_listing(bucket, objects)
		_save_listing_cache(bucket, objects)
		sync_completed.emit(bucket, changes)
	)


func _diff_listing(bucket: String, remote_objects: Array) -> Array[Dictionary]:
	var cached := _load_listing_cache(bucket)
	var changes: Array[Dictionary] = []
	var cached_keys := {}
	for obj in cached:
		cached_keys[obj["key"]] = obj.get("etag", "")

	for obj in remote_objects:
		var key: String = obj["key"]
		var etag: String = obj.get("etag", "")
		if not cached_keys.has(key):
			changes.append({ "key": key, "status": "new" })
		elif cached_keys[key] != etag:
			changes.append({ "key": key, "status": "modified" })
		cached_keys.erase(key)

	for key in cached_keys:
		changes.append({ "key": key, "status": "deleted" })

	return changes


func _load_listing_cache(bucket: String) -> Array:
	var path := "%s/%s_listing.json" % [CACHE_DIR, bucket]
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return []
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return []
	var data = json.data
	if data is Dictionary:
		return data.get("objects", [])
	return []


func _save_listing_cache(bucket: String, objects: Array) -> void:
	var path := "%s/%s_listing.json" % [CACHE_DIR, bucket]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify({ "objects": objects }, "\t"))


## Return the cached listing for UI display.
func get_cached_listing(bucket: String) -> Array:
	return _load_listing_cache(bucket)


# ---------------------------------------------------------------------------
# Push palette
# ---------------------------------------------------------------------------

func push_palette(palette: VoxelPalette) -> void:
	if not connected:
		_on_s3_error("Not connected to remote")
		return
	var data := _palette_to_json_bytes(palette)
	var key := "%s.json" % palette.palette_name.to_snake_case()
	if key == ".json":
		key = "default.json"
	_s3.put_object(PALETTE_BUCKET, key, data, "application/json",
		func(result: Dictionary) -> void:
			asset_uploaded.emit(PALETTE_BUCKET, result.get("key", key), result.get("etag", ""))
	)


func _palette_to_json_bytes(palette: VoxelPalette) -> PackedByteArray:
	var entries := []
	for entry in palette.entries:
		entries.append({
			"name": entry.entry_name,
			"color": [entry.color.r, entry.color.g, entry.color.b, entry.color.a],
			"base_material": entry.base_material,
		})
	var dict := { "palette_name": palette.palette_name, "entries": entries }
	return JSON.stringify(dict, "\t").to_utf8_buffer()


# ---------------------------------------------------------------------------
# Pull palette
# ---------------------------------------------------------------------------

func pull_palette(key: String) -> void:
	if not connected:
		_on_s3_error("Not connected to remote")
		return
	_s3.get_object(PALETTE_BUCKET, key,
		func(result: Dictionary) -> void:
			var body: PackedByteArray = result.get("body", PackedByteArray())
			var palette := _palette_from_json_bytes(body)
			if palette:
				var local_path := "%s/%s/%s" % [CACHE_DIR, PALETTE_BUCKET, key]
				_write_bytes(local_path, body)
				asset_downloaded.emit(PALETTE_BUCKET, key, local_path)
			else:
				_on_s3_error("Failed to parse palette: %s" % key)
	)


func _palette_from_json_bytes(data: PackedByteArray) -> VoxelPalette:
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		return null
	var dict = json.data
	if not dict is Dictionary:
		return null
	var palette := VoxelPalette.new()
	palette.palette_name = dict.get("palette_name", "remote")
	palette.entries.clear()
	for entry_data in dict.get("entries", []):
		var entry := PaletteEntry.new()
		entry.entry_name = entry_data.get("name", "")
		var c: Array = entry_data.get("color", [1.0, 1.0, 1.0, 1.0])
		entry.color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
		entry.base_material = int(entry_data.get("base_material", 1))
		palette.entries.append(entry)
	return palette


## Build a VoxelPalette from cached bytes (for use by the browser dialog).
func palette_from_cache(key: String) -> VoxelPalette:
	var path := "%s/%s/%s" % [CACHE_DIR, PALETTE_BUCKET, key]
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	return _palette_from_json_bytes(f.get_buffer(f.get_length()))


# ---------------------------------------------------------------------------
# Push tile  (.voxltile binary format)
# ---------------------------------------------------------------------------

func push_tile(tile: WFCTileDef, palette: VoxelPalette) -> void:
	if not connected:
		_on_s3_error("Not connected to remote")
		return
	var data := serialize_tile(tile, palette)
	var key := "%s.voxltile" % tile.tile_name.to_snake_case()
	if key == ".voxltile":
		key = "untitled.voxltile"
	_s3.put_object(TILE_BUCKET, key, data, "application/octet-stream",
		func(result: Dictionary) -> void:
			asset_uploaded.emit(TILE_BUCKET, result.get("key", key), result.get("etag", ""))
	)


## Serialize a tile to the .voxltile binary format:
##   [4 bytes: header_len LE] [header_len bytes: JSON header] [gzip voxel_data]
func serialize_tile(tile: WFCTileDef, palette: VoxelPalette) -> PackedByteArray:
	var palette_entries := []
	if palette:
		for entry in palette.entries:
			palette_entries.append({
				"name": entry.entry_name,
				"color": [entry.color.r, entry.color.g, entry.color.b, entry.color.a],
				"base_material": entry.base_material,
			})

	var header := {
		"format_version": 1,
		"tile_name": tile.tile_name,
		"tile_size_x": tile.tile_size_x,
		"tile_size_y": tile.tile_size_y,
		"tile_size_z": tile.tile_size_z,
		"edge_north": tile.edge_north,
		"edge_south": tile.edge_south,
		"edge_east": tile.edge_east,
		"edge_west": tile.edge_west,
		"weight": tile.weight,
		"rotatable": tile.rotatable,
		"tags": Array(tile.tags),
		"surface_material": tile.surface_material,
		"biome": tile.biome,
		"metadata_points": tile.metadata_points,
		"palette_entries": palette_entries,
	}
	var header_bytes := JSON.stringify(header).to_utf8_buffer()
	var compressed := tile.voxel_data.compress(FileAccess.COMPRESSION_GZIP)

	var out := PackedByteArray()
	out.resize(4 + header_bytes.size() + compressed.size())
	out.encode_u32(0, header_bytes.size())
	for i in header_bytes.size():
		out[4 + i] = header_bytes[i]
	for i in compressed.size():
		out[4 + header_bytes.size() + i] = compressed[i]
	return out


# ---------------------------------------------------------------------------
# Pull tile
# ---------------------------------------------------------------------------

func pull_tile(key: String) -> void:
	if not connected:
		_on_s3_error("Not connected to remote")
		return
	_s3.get_object(TILE_BUCKET, key,
		func(result: Dictionary) -> void:
			var body: PackedByteArray = result.get("body", PackedByteArray())
			var local_path := "%s/%s/%s" % [CACHE_DIR, TILE_BUCKET, key]
			_write_bytes(local_path, body)
			asset_downloaded.emit(TILE_BUCKET, key, local_path)
	)


## Deserialize a .voxltile binary blob into a WFCTileDef + VoxelPalette.
func deserialize_tile(data: PackedByteArray) -> Dictionary:
	if data.size() < 4:
		return {}
	var header_len := data.decode_u32(0)
	if data.size() < int(4 + header_len):
		return {}

	var header_bytes := data.slice(4, 4 + header_len)
	var json := JSON.new()
	if json.parse(header_bytes.get_string_from_utf8()) != OK:
		return {}
	var header: Dictionary = json.data

	var tile := WFCTileDef.new()
	tile.tile_name       = header.get("tile_name", "")
	tile.tile_size_x     = int(header.get("tile_size_x", WFCTileDef.DEFAULT_TILE_X))
	tile.tile_size_y     = int(header.get("tile_size_y", WFCTileDef.DEFAULT_TILE_Y))
	tile.tile_size_z     = int(header.get("tile_size_z", WFCTileDef.DEFAULT_TILE_Z))
	tile.edge_north      = int(header.get("edge_north", 0))
	tile.edge_south      = int(header.get("edge_south", 0))
	tile.edge_east       = int(header.get("edge_east", 0))
	tile.edge_west       = int(header.get("edge_west", 0))
	tile.weight          = float(header.get("weight", 1.0))
	tile.rotatable       = header.get("rotatable", false)
	tile.surface_material = int(header.get("surface_material", MaterialRegistry.STONE))
	tile.biome           = header.get("biome", "")
	tile.metadata_points = header.get("metadata_points", {})

	var tags_arr: Array = header.get("tags", [])
	tile.tags = PackedStringArray(tags_arr)

	var compressed := data.slice(4 + header_len)
	var expected_size := tile.tile_size_x * tile.tile_size_y * tile.tile_size_z * 2
	tile.voxel_data = compressed.decompress(expected_size, FileAccess.COMPRESSION_GZIP)

	var palette_data: Array = header.get("palette_entries", [])
	var pal_dicts: Array[Dictionary] = []
	for pd in palette_data:
		pal_dicts.append({
			"name": pd.get("name", ""),
			"color": _arr_to_color(pd.get("color", [1, 1, 1, 1])),
			"base_material": int(pd.get("base_material", 1)),
		})
	tile.palette_entries = pal_dicts

	var palette := VoxelPalette.new()
	palette.entries.clear()
	for pd in palette_data:
		var entry := PaletteEntry.new()
		entry.entry_name = pd.get("name", "")
		entry.color = _arr_to_color(pd.get("color", [1, 1, 1, 1]))
		entry.base_material = int(pd.get("base_material", 1))
		palette.entries.append(entry)

	return { "tile": tile, "palette": palette }


## Build a tile + palette from a cached .voxltile file.
func tile_from_cache(key: String) -> Dictionary:
	var path := "%s/%s/%s" % [CACHE_DIR, TILE_BUCKET, key]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	return deserialize_tile(f.get_buffer(f.get_length()))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _ensure_cache_dirs() -> void:
	for sub in [PALETTE_BUCKET, TILE_BUCKET]:
		var dir_path := "%s/%s" % [CACHE_DIR, sub]
		DirAccess.make_dir_recursive_absolute(dir_path)


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(data)


func _arr_to_color(arr: Variant) -> Color:
	if arr is Array and arr.size() >= 3:
		return Color(arr[0], arr[1], arr[2], arr[3] if arr.size() > 3 else 1.0)
	return Color.WHITE


func _on_s3_error(error: String) -> void:
	push_warning("[AssetSync] %s" % error)
