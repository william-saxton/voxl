extends Node

const SIM_RADIUS: int = 7
const EXPECTED_LOADED_CHUNKS: int = (SIM_RADIUS * 2 + 1) * (SIM_RADIUS * 2 + 1)
const CHUNK_VOL: int = 32 * 112 * 32  # 114_688

# Flat-terrain generator with origin_y=0 produces per chunk:
#   bedrock: y=0       -> 32*1*32  = 1_024
#   stone:   y=1..14   -> 32*14*32 = 14_336
#   dirt:    y=15      -> 32*1*32  = 1_024
#   air:     y=16..111 -> 32*96*32 = 98_304
const EXPECTED_BEDROCK_PER_CHUNK: int = 1_024
const EXPECTED_STONE_PER_CHUNK:   int = 14_336
const EXPECTED_DIRT_PER_CHUNK:    int = 1_024
const EXPECTED_AIR_PER_CHUNK:     int = 98_304

const LOAD_TIMEOUT_SEC: float = 5.0

var _store: VoxelChunkStore
var _anchor: Node3D
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	_anchor = Node3D.new()
	_anchor.name = "Anchor"
	add_child(_anchor)

	_store = VoxelChunkStore.new()
	_store.name = "Store"
	add_child(_store)
	_store.initialize(_anchor, SIM_RADIUS)

	print("[test] initialized VoxelChunkStore with sim_radius=%d (expecting %d chunks)"
			% [SIM_RADIUS, EXPECTED_LOADED_CHUNKS])


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_store.tick()

	var loaded := _store.loaded_chunk_count()
	if loaded >= EXPECTED_LOADED_CHUNKS:
		_run_assertions()
		_finished = true
		get_tree().quit()
		return

	if _elapsed > LOAD_TIMEOUT_SEC:
		push_error("[test] TIMEOUT: only %d / %d chunks loaded after %.2fs"
				% [loaded, EXPECTED_LOADED_CHUNKS, _elapsed])
		_finished = true
		get_tree().quit()


func _run_assertions() -> void:
	var r: Dictionary = _store.self_test()
	var expected_bedrock: int = EXPECTED_BEDROCK_PER_CHUNK * EXPECTED_LOADED_CHUNKS
	var expected_stone:   int = EXPECTED_STONE_PER_CHUNK   * EXPECTED_LOADED_CHUNKS
	var expected_dirt:    int = EXPECTED_DIRT_PER_CHUNK    * EXPECTED_LOADED_CHUNKS
	var expected_air:     int = EXPECTED_AIR_PER_CHUNK     * EXPECTED_LOADED_CHUNKS

	var ok := true
	ok = _assert_eq("loaded_chunks", r.loaded_chunks, EXPECTED_LOADED_CHUNKS) and ok
	ok = _assert_eq("total_chunks",  r.total_chunks,  EXPECTED_LOADED_CHUNKS) and ok
	ok = _assert_eq("chunk_volume",  r.chunk_volume,  CHUNK_VOL) and ok
	ok = _assert_eq("bedrock",       r.bedrock,       expected_bedrock) and ok
	ok = _assert_eq("stone",         r.stone,         expected_stone)   and ok
	ok = _assert_eq("dirt",          r.dirt,          expected_dirt)    and ok
	ok = _assert_eq("air",           r.air,           expected_air)     and ok
	ok = _assert_eq("other",         r.other,         0)                and ok

	# Spot-check a read via the bound accessor.
	var stone_mid: int = _store.get_voxel(Vector3i(0, 7, 0))
	ok = _assert_eq("voxel at (0,7,0)", stone_mid, 1) and ok  # MAT_STONE = 1
	var dirt_top: int = _store.get_voxel(Vector3i(0, 15, 0))
	ok = _assert_eq("voxel at (0,15,0)", dirt_top, 4) and ok  # MAT_DIRT = 4
	var air_above: int = _store.get_voxel(Vector3i(0, 16, 0))
	ok = _assert_eq("voxel at (0,16,0)", air_above, 0) and ok # MAT_AIR = 0

	# Hot-path write bumps generation.
	var gen_before: int = _store.get_chunk_generation(Vector2i(0, 0))
	var wrote_ok: bool = _store.set_voxel(Vector3i(0, 16, 0), 1)
	var gen_after: int = _store.get_chunk_generation(Vector2i(0, 0))
	ok = _assert_eq("set_voxel returned true", wrote_ok, true) and ok
	ok = _assert_true("generation increased after write",
			gen_after > gen_before,
			"before=%d after=%d" % [gen_before, gen_after]) and ok

	if ok:
		print("[test] PASS (%.2fs)  %s" % [_elapsed, r])
	else:
		push_error("[test] FAIL  %s" % [r])


func _assert_eq(name: String, actual, expected) -> bool:
	if actual == expected:
		return true
	push_error("[test] FAIL %s: expected %s, got %s" % [name, expected, actual])
	return false


func _assert_true(name: String, cond: bool, detail: String) -> bool:
	if cond:
		return true
	push_error("[test] FAIL %s (%s)" % [name, detail])
	return false
