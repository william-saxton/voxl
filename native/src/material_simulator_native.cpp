#include "material_simulator_native.h"
#include <climits>
#include <godot_cpp/variant/aabb.hpp>

using namespace godot;

// ── Constructor / Destructor ──

MaterialSimulatorNative::MaterialSimulatorNative() {
	_chunks = new SimChunk[TOTAL_CHUNKS];
	std::memset(_grid, 0, sizeof(_grid));
}

MaterialSimulatorNative::~MaterialSimulatorNative() {
	_stop_loaders();
	delete[] _chunks;
	_chunks = nullptr;
}

// ── Bindings ──

void MaterialSimulatorNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "terrain", "player"), &MaterialSimulatorNative::initialize, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("place_fluid", "pos", "fluid_base", "level"), &MaterialSimulatorNative::place_fluid, DEFVAL(FLUID_LEVELS - 1));
	ClassDB::bind_method(D_METHOD("remove_voxel", "pos"), &MaterialSimulatorNative::remove_voxel);
	ClassDB::bind_method(D_METHOD("sync_voxel", "pos", "voxel_id"), &MaterialSimulatorNative::sync_voxel);
	ClassDB::bind_method(D_METHOD("get_active_cell_count"), &MaterialSimulatorNative::get_active_cell_count);
	ClassDB::bind_method(D_METHOD("get_source_block_count"), &MaterialSimulatorNative::get_source_block_count);
	ClassDB::bind_method(D_METHOD("get_last_tick_ms"), &MaterialSimulatorNative::get_last_tick_ms);
	ClassDB::bind_method(D_METHOD("get_last_changes_count"), &MaterialSimulatorNative::get_last_changes_count);

	ADD_SIGNAL(MethodInfo("voxel_changed",
			PropertyInfo(Variant::VECTOR3I, "pos"),
			PropertyInfo(Variant::INT, "new_voxel")));
}

void MaterialSimulatorNative::_notification(int p_what) {
	if (p_what == NOTIFICATION_PREDELETE) {
		_stop_loaders();
	}
}

// ── Public API ──

void MaterialSimulatorNative::initialize(Object *p_terrain, Node3D *p_player) {
	_terrain = p_terrain;
	_player = p_player;

	_voxel_tool = _terrain->call("get_voxel_tool");
	_voxel_tool->call("set_channel", 0);

	set_physics_process(true);
	_wait_for_terrain();
}

void MaterialSimulatorNative::place_fluid(const Vector3i &pos, int fluid_base, int level) {
	if (_voxel_tool.is_null()) return;
	int fluid_id = fluid_base + CLAMP(level, 0, FLUID_LEVELS - 1);
	_voxel_tool->call("set_voxel", pos, fluid_id);
	_source_positions.insert(_pos_key(pos));
	if (_sim_ready) {
		_write_cell(pos, encode(fluid_id, true));
	}
}

void MaterialSimulatorNative::remove_voxel(const Vector3i &pos) {
	if (_voxel_tool.is_null()) return;
	_voxel_tool->call("set_voxel", pos, 0);
	_source_positions.erase(_pos_key(pos));
	if (_sim_ready) {
		_write_cell(pos, MAT_AIR);
	}
}

void MaterialSimulatorNative::sync_voxel(const Vector3i &pos, int voxel_id) {
	if (_sim_ready) {
		_write_cell(pos, encode(voxel_id, false));
	}
}

int MaterialSimulatorNative::get_active_cell_count() const {
	if (!_sim_ready) return 0;
	int count = 0;
	for (int i = 0; i < TOTAL_CHUNKS; i++) {
		if (_chunks[i].state == SimChunk::LOADED)
			count += CHUNK_VOL;
	}
	return count;
}

int MaterialSimulatorNative::get_source_block_count() const {
	return static_cast<int>(_source_positions.size());
}

double MaterialSimulatorNative::get_last_tick_ms() const {
	return _last_tick_usec / 1000.0;
}

int MaterialSimulatorNative::get_last_changes_count() const {
	return _last_changes_count;
}

// ── VoxelTool wrappers ──

int MaterialSimulatorNative::_voxel_get(const Ref<RefCounted> &tool, const Vector3i &pos) const {
	return tool->call("get_voxel", pos);
}

bool MaterialSimulatorNative::_voxel_set(const Vector3i &pos, int value) {
	_voxel_tool->call("set_voxel", pos, value);
	// Verify the write landed. When "Area not editable", set_voxel silently
	// does nothing; a subsequent get_voxel returns the old value.
	return _voxel_get(_voxel_tool, pos) == value;
}

// ── Chunk grid lookup ──

MaterialSimulatorNative::SimChunk *MaterialSimulatorNative::_chunk_at(int cx, int cz) const {
	int gx = cx - (_center_cx - LOAD_RADIUS);
	int gz = cz - (_center_cz - LOAD_RADIUS);
	if (gx < 0 || gx >= GRID_W || gz < 0 || gz >= GRID_H) return nullptr;
	return _grid[gx][gz];
}

// ── Buffer writes (main thread, between ticks) ──

void MaterialSimulatorNative::_write_cell(const Vector3i &world_pos, uint8_t val) {
	int wy = world_pos.y - _origin_y;
	if (wy < 0 || wy >= CHUNK_Y) return;

	int cx = _chunk_coord(world_pos.x);
	int cz = _chunk_coord(world_pos.z);
	SimChunk *c = _chunk_at(cx, cz);
	if (!c || c->state != SimChunk::LOADED) return;

	int lx = _local_coord(world_pos.x);
	int lz = _local_coord(world_pos.z);
	c->current[lx + wy * CHUNK_X + lz * CHUNK_X * CHUNK_Y] = val;
}

// ── Terrain wait ──

void MaterialSimulatorNative::_wait_for_terrain() {
	_sim_ready = false;
	_terrain_poll_counter = 0;
	_sim_timer = -100.0;
}

// ── Grid initialization ──

void MaterialSimulatorNative::_init_grid() {
	Vector3 pp = _player ? _player->get_global_position() : Vector3(0, 0, 0);
	_center_cx = _chunk_coord(int(Math::floor(pp.x)));
	_center_cz = _chunk_coord(int(Math::floor(pp.z)));

	int pool_idx = 0;
	for (int gz = 0; gz < GRID_H; gz++) {
		for (int gx = 0; gx < GRID_W; gx++) {
			SimChunk *c = &_chunks[pool_idx++];
			c->wcx = _center_cx - LOAD_RADIUS + gx;
			c->wcz = _center_cz - LOAD_RADIUS + gz;
			c->state = SimChunk::UNLOADED;
			std::memset(c->buf_a, NOT_LOADED, CHUNK_VOL);
			std::memset(c->buf_b, NOT_LOADED, CHUNK_VOL);
			c->current = c->buf_a;
			c->next_buf = c->buf_b;
			_grid[gx][gz] = c;
		}
	}
}

// ── Sim setup ──

void MaterialSimulatorNative::_setup_sim() {
	_init_grid();
	_start_loaders();

	for (int gz = 0; gz < GRID_H; gz++)
		for (int gx = 0; gx < GRID_W; gx++)
			_queue_chunk_load(_grid[gx][gz], _grid[gx][gz]->wcx, _grid[gx][gz]->wcz);

	_sim_ready = true;
	_sim_timer = 0.0;

	UtilityFunctions::print(String("[MaterialSimulatorNative] sim ready (center_chunk={0},{1}, {2} sources)")
			.format(Array::make(_center_cx, _center_cz, (int)_source_positions.size())));
}

// ── Chunk loader thread pool ──

void MaterialSimulatorNative::_start_loaders() {
	_stop_loaders();

	_loaders_running.store(true);

	_loader_voxel_tools.resize(NUM_LOADERS);
	for (int i = 0; i < NUM_LOADERS; i++) {
		_loader_voxel_tools[i] = _terrain->call("get_voxel_tool");
		_loader_voxel_tools[i]->call("set_channel", 0);
	}

	_loader_threads.resize(NUM_LOADERS);
	for (int i = 0; i < NUM_LOADERS; i++) {
		_loader_threads[i] = std::thread(&MaterialSimulatorNative::_loader_thread_func, this, i);
	}
}

void MaterialSimulatorNative::_stop_loaders() {
	_loaders_running.store(false);
	_loader_cv.notify_all();

	for (auto &t : _loader_threads) {
		if (t.joinable()) t.join();
	}
	_loader_threads.clear();

	{
		std::lock_guard<std::mutex> lock(_loader_queue_mutex);
		while (!_loader_queue.empty()) _loader_queue.pop();
	}

	{
		std::lock_guard<std::mutex> lock(_loader_result_mutex);
		for (auto *r : _loader_results) delete r;
		_loader_results.clear();
	}

	_loader_voxel_tools.clear();
}

void MaterialSimulatorNative::_loader_thread_func(int loader_id) {
	Ref<RefCounted> tool = _loader_voxel_tools[loader_id];

	while (_loaders_running.load()) {
		ChunkLoadRequest req;
		{
			std::unique_lock<std::mutex> lock(_loader_queue_mutex);
			_loader_cv.wait(lock, [this]() {
				return !_loader_queue.empty() || !_loaders_running.load();
			});
			if (!_loaders_running.load()) break;
			if (_loader_queue.empty()) continue;
			req = _loader_queue.front();
			_loader_queue.pop();
		}

		if (req.chunk->state != SimChunk::LOADING ||
				req.chunk->wcx != req.wcx || req.chunk->wcz != req.wcz) {
			continue;
		}

		ChunkLoadResult *result = new ChunkLoadResult();
		result->chunk = req.chunk;
		result->wcx = req.wcx;
		result->wcz = req.wcz;

		int base_wx = req.wcx * CHUNK_X;
		int base_wz = req.wcz * CHUNK_Z;

		// Retry loop: Godot's VoxelTool returns AIR (0) for terrain blocks that
		// haven't been generated yet. If we import all-AIR into the sim, fluid will
		// flow through what should be solid ground and permanently overwrite it.
		// We retry until the chunk has at least one solid voxel, or give up after
		// several attempts (the chunk may legitimately be all-air above the surface).
		static constexpr int MAX_LOAD_RETRIES = 8;
		static constexpr int RETRY_DELAY_MS   = 100;

		bool chunk_reassigned = false;

		for (int attempt = 0; attempt <= MAX_LOAD_RETRIES && _loaders_running.load(); attempt++) {
			if (attempt > 0) {
				std::this_thread::sleep_for(std::chrono::milliseconds(RETRY_DELAY_MS));
				// Abort if the chunk was reassigned to a different position while waiting.
				if (req.chunk->state != SimChunk::LOADING ||
						req.chunk->wcx != req.wcx || req.chunk->wcz != req.wcz) {
					chunk_reassigned = true;
					break;
				}
			}

			for (int lz = 0; lz < CHUNK_Z; lz++) {
				for (int ly = 0; ly < CHUNK_Y; ly++) {
					for (int lx = 0; lx < CHUNK_X; lx++) {
						Vector3i world_pos(base_wx + lx, _origin_y + ly, base_wz + lz);
						int voxel = _voxel_get(tool, world_pos);
						bool is_src = _source_positions.count(_pos_key(world_pos)) > 0;
						int idx = lx + ly * CHUNK_X + lz * CHUNK_X * CHUNK_Y;
						result->data[idx] = encode(voxel, is_src);
					}
				}
			}

			// Check whether the terrain was actually generated.
			// A sim chunk (32 tall) spans two Zylann terrain blocks (each 16 tall).
			// The lower half (local Y 0..15, world Y -16..-1) typically generates first
			// with solid stone, while the upper half (local Y 16..31, world Y 0..+15)
			// may still be ungenerated and return all-AIR. If we accept the chunk in
			// that state, fluid flows through the un-generated surface.
			//
			// Strategy: retry while lower half has solid but upper half is all-AIR,
			// which is the partial-generation fingerprint. Stop when both halves are
			// consistent, or when we give up after MAX_LOAD_RETRIES.
			bool lower_solid = false, upper_solid = false;
			for (int j = 0; j < CHUNK_VOL; j++) {
				int ly = (j / CHUNK_X) % CHUNK_Y;
				if ((result->data[j] & ID_MASK) != MAT_AIR) {
					if (ly < CHUNK_Y / 2) lower_solid = true;
					else upper_solid = true;
				}
				if (lower_solid && upper_solid) break;
			}
			// Require BOTH halves to have solid before accepting the chunk.
			// This catches:
			//   all-air  (lower=F, upper=F): ungenerated terrain → retry
			//   partial  (lower=T, upper=F): lower block loaded but upper not → retry
			//   complete (lower=T, upper=T): fully generated → accept
			// Give up after MAX_LOAD_RETRIES either way.
			if ((lower_solid && upper_solid) || attempt == MAX_LOAD_RETRIES)
				break;
		}

		if (!chunk_reassigned) {
			// Correction sweep: re-verify every AIR cell the retry loop accepted.
			// By the time we reach here, the terrain should be fully generated (we
			// waited up to MAX_LOAD_RETRIES × RETRY_DELAY_MS for it). Re-reading AIR
			// cells in the background thread is cheap and keeps the main thread free.
			for (int j = 0; j < CHUNK_VOL; j++) {
				if ((result->data[j] & ID_MASK) != MAT_AIR) continue;
				int lx = j % CHUNK_X;
				int ly = (j / CHUNK_X) % CHUNK_Y;
				int lz = j / (CHUNK_X * CHUNK_Y);
				Vector3i world_pos(base_wx + lx, _origin_y + ly, base_wz + lz);
				int tv = _voxel_get(tool, world_pos);
				if (tv != MAT_AIR) {
					result->data[j] = encode(tv, false);
				}
			}

			std::lock_guard<std::mutex> lock(_loader_result_mutex);
			_loader_results.push_back(result);
		} else {
			delete result;
		}
	}
}

void MaterialSimulatorNative::_queue_chunk_load(SimChunk *chunk, int wcx, int wcz) {
	chunk->wcx = wcx;
	chunk->wcz = wcz;
	chunk->state = SimChunk::LOADING;
	std::memset(chunk->buf_a, NOT_LOADED, CHUNK_VOL);
	std::memset(chunk->buf_b, NOT_LOADED, CHUNK_VOL);
	chunk->current = chunk->buf_a;
	chunk->next_buf = chunk->buf_b;

	{
		std::lock_guard<std::mutex> lock(_loader_queue_mutex);
		_loader_queue.push({chunk, wcx, wcz});
	}
	_loader_cv.notify_one();
}

void MaterialSimulatorNative::_drain_loader_results() {
	std::lock_guard<std::mutex> lock(_loader_result_mutex);
	for (auto *result : _loader_results) {
		SimChunk *c = result->chunk;
		if (c->state == SimChunk::LOADING && c->wcx == result->wcx && c->wcz == result->wcz) {
			std::memcpy(c->current, result->data, CHUNK_VOL);
			std::memcpy(c->next_buf, result->data, CHUNK_VOL);
			c->state = SimChunk::LOADED;
		}
		delete result;
	}
	_loader_results.clear();
}

// ── Grid management ──

void MaterialSimulatorNative::_unload_chunk(SimChunk *chunk) {
	chunk->state = SimChunk::UNLOADED;
}

void MaterialSimulatorNative::_recenter_grid() {
	if (!_player) return;

	Vector3 pp = _player->get_global_position();
	int new_cx = _chunk_coord(int(Math::floor(pp.x)));
	int new_cz = _chunk_coord(int(Math::floor(pp.z)));

	if (new_cx == _center_cx && new_cz == _center_cz) return;

	int dx = new_cx - _center_cx;
	int dz = new_cz - _center_cz;

	UtilityFunctions::print(String("[MaterialSimulatorNative] recenter grid ({0},{1}) -> ({2},{3})")
			.format(Array::make(_center_cx, _center_cz, new_cx, new_cz)));

	// Drop all pending deferred terrain writes. They reference the old chunk layout
	// and may write stale values (e.g. AIR) that the loader would then re-import,
	// permanently replacing solid voxels with fluid.
	_deferred_changes.clear();

	if (abs(dx) > LOAD_RADIUS * 2 || abs(dz) > LOAD_RADIUS * 2) {
		_center_cx = new_cx;
		_center_cz = new_cz;

		for (int i = 0; i < TOTAL_CHUNKS; i++)
			_unload_chunk(&_chunks[i]);

		_init_grid();
		for (int gz = 0; gz < GRID_H; gz++)
			for (int gx = 0; gx < GRID_W; gx++)
				_queue_chunk_load(_grid[gx][gz], _grid[gx][gz]->wcx, _grid[gx][gz]->wcz);
		return;
	}

	int new_min_cx = new_cx - LOAD_RADIUS;
	int new_min_cz = new_cz - LOAD_RADIUS;

	SimChunk *old_grid[GRID_W][GRID_H];
	std::memcpy(old_grid, _grid, sizeof(_grid));
	std::memset(_grid, 0, sizeof(_grid));

	std::vector<SimChunk *> recycled;

	for (int gz = 0; gz < GRID_H; gz++) {
		for (int gx = 0; gx < GRID_W; gx++) {
			SimChunk *c = old_grid[gx][gz];
			if (!c) continue;

			int new_gx = c->wcx - new_min_cx;
			int new_gz = c->wcz - new_min_cz;

			if (new_gx >= 0 && new_gx < GRID_W && new_gz >= 0 && new_gz < GRID_H) {
				_grid[new_gx][new_gz] = c;
			} else {
				_unload_chunk(c);
				recycled.push_back(c);
			}
		}
	}

	int ri = 0;
	for (int gz = 0; gz < GRID_H; gz++) {
		for (int gx = 0; gx < GRID_W; gx++) {
			if (_grid[gx][gz] != nullptr) continue;

			SimChunk *c = recycled[ri++];
			int wcx = new_min_cx + gx;
			int wcz = new_min_cz + gz;
			c->wcx = wcx;
			c->wcz = wcz;
			c->state = SimChunk::LOADING;
			std::memset(c->buf_a, NOT_LOADED, CHUNK_VOL);
			std::memset(c->buf_b, NOT_LOADED, CHUNK_VOL);
			c->current = c->buf_a;
			c->next_buf = c->buf_b;
			_grid[gx][gz] = c;
		}
	}

	_center_cx = new_cx;
	_center_cz = new_cz;

	{
		std::lock_guard<std::mutex> lock(_loader_queue_mutex);
		while (!_loader_queue.empty()) _loader_queue.pop();
	}

	for (int gz = 0; gz < GRID_H; gz++) {
		for (int gx = 0; gx < GRID_W; gx++) {
			SimChunk *c = _grid[gx][gz];
			if (c && c->state == SimChunk::LOADING) {
				std::lock_guard<std::mutex> lock(_loader_queue_mutex);
				_loader_queue.push({c, c->wcx, c->wcz});
			}
		}
	}
	_loader_cv.notify_all();
}

// ── Physics process ──

void MaterialSimulatorNative::_physics_process(double delta) {
	if (_sim_timer < -50.0) {
		_terrain_poll_counter++;
		if (_terrain_poll_counter % 30 == 0) {
			Vector3 pp = _player ? _player->get_global_position() : Vector3(0, 0, 0);
			Vector3i sample_pos(int(Math::floor(pp.x)), _origin_y, int(Math::floor(pp.z)));
			int sample = _voxel_get(_voxel_tool, sample_pos);
			if (sample != 0) {
				UtilityFunctions::print(String("[MaterialSimulatorNative] terrain ready after {0}s")
						.format(Array::make(_terrain_poll_counter / 60.0)));
				_terrain_poll_counter = 0;
				_setup_sim();
			} else if (_terrain_poll_counter > 1800) {
				UtilityFunctions::push_error("MaterialSimulatorNative: terrain never loaded, giving up");
				_sim_timer = 0.0;
				_terrain_poll_counter = 0;
			}
		}
		return;
	}

	if (!_sim_ready) return;

	_process_deferred_changes();

	_sim_timer += delta;
	if (_sim_timer < 0.05) return;
	_sim_timer -= 0.05;
	_tick_count++;
	_dispatch_tick();
}

// ── Dispatch tick ──

void MaterialSimulatorNative::_dispatch_tick() {
	int64_t t0 = Time::get_singleton()->get_ticks_usec();

	_recenter_grid();
	_drain_loader_results();

	std::vector<SimChunk *> loaded;
	loaded.reserve(TOTAL_CHUNKS);
	for (int gz = 0; gz < GRID_H; gz++)
		for (int gx = 0; gx < GRID_W; gx++)
			if (_grid[gx][gz] && _grid[gx][gz]->state == SimChunk::LOADED)
				loaded.push_back(_grid[gx][gz]);

	if (loaded.empty()) {
		_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;
		return;
	}

	for (auto *c : loaded)
		std::memcpy(c->next_buf, c->current, CHUNK_VOL);

	int parity = _tick_count % 2;
	int num_chunks = (int)loaded.size();
	std::thread workers[NUM_WORKERS];

	for (int w = 0; w < NUM_WORKERS; w++) {
		int c_start = w * num_chunks / NUM_WORKERS;
		int c_end = (w + 1) * num_chunks / NUM_WORKERS;

		workers[w] = std::thread([this, &loaded, c_start, c_end, parity]() {
			for (int ci = c_start; ci < c_end; ci++) {
				SimChunk *chunk = loaded[ci];
				int base_wx = chunk->wcx * CHUNK_X;
				int base_wz = chunk->wcz * CHUNK_Z;

				for (int lz = 0; lz < CHUNK_Z; lz++) {
					for (int ly = 0; ly < CHUNK_Y; ly++) {
						for (int lx = 0; lx < CHUNK_X; lx++) {
							int wx = base_wx + lx;
							int wz = base_wz + lz;
							if (((wx + ly + wz) & 1) != parity) continue;
							_sim_cell(wx, ly, wz);
						}
					}
				}
			}
		});
	}
	for (int w = 0; w < NUM_WORKERS; w++)
		workers[w].join();

	_collect_and_apply_changes();

	for (auto *c : loaded)
		std::swap(c->current, c->next_buf);

	_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;

	if (_tick_count <= 5 || _tick_count % 120 == 0) {
		Vector3 pp = _player ? _player->get_global_position() : Vector3(0, 0, 0);
		UtilityFunctions::print(String("[MaterialSimulatorNative] tick {0}: {1} changes, {2} ms, {3}/{4} loaded")
				.format(Array::make(_tick_count, _last_changes_count, get_last_tick_ms(),
						(int)loaded.size(), TOTAL_CHUNKS)));
	}
}

// ── Change detection and application ──

void MaterialSimulatorNative::_collect_and_apply_changes() {
	if (_voxel_tool.is_null()) return;

	int pw_x = 0, pw_z = 0;
	if (_player) {
		Vector3 pp = _player->get_global_position();
		pw_x = int(Math::floor(pp.x));
		pw_z = int(Math::floor(pp.z));
	}

	int applied = 0;
	int total = 0;
	int skipped_chunks = 0;

	for (int gz = 0; gz < GRID_H; gz++) {
		for (int gx = 0; gx < GRID_W; gx++) {
			SimChunk *c = _grid[gx][gz];
			if (!c || c->state != SimChunk::LOADED) continue;

			int base_wx = c->wcx * CHUNK_X;
			int base_wz = c->wcz * CHUNK_Z;

			int chunk_mid_x = base_wx + CHUNK_X / 2;
			int chunk_mid_z = base_wz + CHUNK_Z / 2;
			if (abs(chunk_mid_x - pw_x) > 224 || abs(chunk_mid_z - pw_z) > 224) {
				skipped_chunks++;
				continue;
			}

			for (int i = 0; i < CHUNK_VOL; i++) {
				uint8_t old_id = mid(c->current[i]);
				uint8_t new_id = mid(c->next_buf[i]);
				if (old_id == new_id) continue;

				total++;

				int lx = i % CHUNK_X;
				int ly = (i / CHUNK_X) % CHUNK_Y;
				int lz = i / (CHUNK_X * CHUNK_Y);
				Vector3i world_pos(base_wx + lx, _origin_y + ly, base_wz + lz);

				// Safety valve: before writing any fluid to Godot terrain, verify the
				// terrain actually has a passable voxel there. If the terrain has solid,
				// the sim loaded stale/incorrect data — correct both buffers and skip.
				// This guards against AIR→FLUID and FLUID→FLUID cascading corruption.
				if (is_fluid(new_id)) {
					int terrain_voxel = _voxel_get(_voxel_tool, world_pos);
					if (is_solid(static_cast<uint8_t>(terrain_voxel))) {
						uint8_t correct = encode(terrain_voxel, false);
						c->current[i] = correct;
						c->next_buf[i] = correct;
						continue;
					}
				}

				// If a source fluid is converting to a non-fluid (depleted by reaction),
				// remove it from source tracking now. This way, if the chunk later
				// reloads with stale terrain data, the loader won't re-instate the
				// source and cause reactions to repeat indefinitely.
				if (src(c->current[i]) && is_fluid(mid(c->current[i])) && !is_fluid(new_id)) {
					_source_positions.erase(_pos_key(world_pos));
				}

				if (applied < APPLY_CHANGES_CAP) {
					if (_voxel_set(world_pos, new_id)) {
						emit_signal("voxel_changed", world_pos, (int)new_id);
						applied++;
					}
					// Write failed: sim still advances (no freeze). Terrain is
					// temporarily out of sync but self-corrects once editable.
				} else {
					_deferred_changes.push_back({world_pos, (int)new_id});
				}
			}
		}
	}

	_last_changes_count = total;
}

void MaterialSimulatorNative::_process_deferred_changes() {
	if (_deferred_changes.empty()) return;

	int pw_x = 0, pw_z = 0;
	if (_player) {
		Vector3 pp = _player->get_global_position();
		pw_x = int(Math::floor(pp.x));
		pw_z = int(Math::floor(pp.z));
	}

	int batch = MIN((int)_deferred_changes.size(), APPLY_CHANGES_CAP);
	for (int i = 0; i < batch; i++) {
		const auto &dc = _deferred_changes[i];
		if (abs(dc.world_pos.x - pw_x) > 224 || abs(dc.world_pos.z - pw_z) > 224) continue;

		// Staleness check: only apply if the simulation's current state still agrees.
		// If the chunk isn't fully loaded, never write — a stale AIR entry written to
		// terrain would be re-imported by the loader and permanently delete solid voxels.
		int wy = dc.world_pos.y - _origin_y;
		if (wy < 0 || wy >= CHUNK_Y) continue; // outside sim Y range, discard
		{
			SimChunk *c = _chunk_at(_chunk_coord(dc.world_pos.x), _chunk_coord(dc.world_pos.z));
			if (!c || c->state != SimChunk::LOADED) continue; // chunk not ready, discard
			int lx = _local_coord(dc.world_pos.x), lz = _local_coord(dc.world_pos.z);
			int idx = lx + wy * CHUNK_X + lz * CHUNK_X * CHUNK_Y;
			if (mid(c->current[idx]) != (uint8_t)dc.new_type) continue; // sim moved on, discard
		}

		if (!_voxel_set(dc.world_pos, dc.new_type)) continue; // write failed, discard; sim will regenerate
		emit_signal("voxel_changed", dc.world_pos, dc.new_type);
	}
	_deferred_changes.erase(_deferred_changes.begin(), _deferred_changes.begin() + batch);
}

// ── Source depletion ──

// Called from within _react (worker thread). Climbs the fluid level gradient from
// (wx, wy, wz) back toward the source that fed this cell, then decrements it.
//
// Fluid spread reduces level by spread_loss each hop, so level increases as you
// move toward the source — hill-climbing reliably finds it in at most FLUID_LEVELS
// steps. At each position we also check all neighbours for the src flag directly,
// so a source one step off the main gradient path is still caught.
//
// _write_next_if_unchanged prevents double-decrement from concurrent workers and
// gracefully skips sources whose own simulation already modified them this tick.
void MaterialSimulatorNative::_deplete_adjacent_source(int wx, int wy, int wz, uint8_t base) {
	// Include horizontal diagonals: fluid spreads diagonally so the uphill
	// gradient or the source itself may only be reachable via a diagonal step.
	static const int dirs[10][3] = {
		{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1},
		{1,0,1},{1,0,-1},{-1,0,1},{-1,0,-1}
	};

	int cx = wx, cy = wy, cz = wz;
	int cur_lvl = (int)flvl(mid(_read_raw(cx, cy, cz)));

	for (int step = 0; step <= FLUID_LEVELS; step++) {
		int best_lvl = cur_lvl;
		int bx = cx, by = cy, bz = cz;

		for (int i = 0; i < 10; i++) {
			int nx = cx + dirs[i][0], ny = cy + dirs[i][1], nz = cz + dirs[i][2];
			uint8_t nr = _read_raw(nx, ny, nz);
			uint8_t ni = mid(nr);
			if (!is_fluid(ni) || fbase(ni) != base) continue;

			if (src(nr)) {
				uint8_t lvl = flvl(ni);
				_write_next_if_unchanged(nx, ny, nz,
						(lvl == 0) ? MAT_AIR : mkfluid(base, lvl - 1, true));
				return;
			}

			int nl = (int)flvl(ni);
			if (nl > best_lvl) { best_lvl = nl; bx = nx; by = ny; bz = nz; }
		}

		if (bx == cx && by == cy && bz == cz) return; // local maximum, no source reachable
		cx = bx; cy = by; cz = bz;
		cur_lvl = best_lvl;
	}
}

// ── Simulation functions ──

uint8_t MaterialSimulatorNative::_react(int x, int y, int z, uint8_t my_id, uint8_t my_raw) {
	uint8_t my_b = fbase(my_id);
	bool my_src = src(my_raw);

	const int dirs[6][3] = {
		{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}
	};

	for (int i = 0; i < 6; i++) {
		int nx = x + dirs[i][0], ny = y + dirs[i][1], nz = z + dirs[i][2];
		uint8_t nr = _read_raw(nx, ny, nz);
		uint8_t ni = mid(nr);
		if (ni == MAT_AIR) continue;
		uint8_t nb = fbase(ni);

		if (my_b == MAT_WATER_BASE && nb == MAT_LAVA_BASE) {
			_write_next(nx, ny, nz, MAT_STONE);
			if (!my_src) {
				_deplete_adjacent_source(x, y, z, MAT_WATER_BASE);
				if (!src(nr)) _deplete_adjacent_source(nx, ny, nz, MAT_LAVA_BASE);
				return MAT_AIR;
			}
			uint8_t l = flvl(my_id);
			return (l == 0) ? MAT_AIR : mkfluid(my_b, l - 1, true);
		}
		if (my_b == MAT_LAVA_BASE && nb == MAT_WATER_BASE) {
			_write_next(nx, ny, nz, MAT_AIR);
			if (!my_src) {
				_deplete_adjacent_source(x, y, z, MAT_LAVA_BASE);
				if (!src(nr)) _deplete_adjacent_source(nx, ny, nz, MAT_WATER_BASE);
				return MAT_STONE;
			}
			uint8_t l = flvl(my_id);
			return (l == 0) ? MAT_STONE : mkfluid(my_b, l - 1, true);
		}
		if (my_b == MAT_WATER_BASE && nb == MAT_ACID_BASE) {
			uint8_t gas = mkfluid(MAT_GAS_BASE, FLUID_LEVELS - 1, false);
			// Acid neighbour: source blocks decrement symmetrically, non-source converts to gas
			if (src(nr)) {
				uint8_t al = flvl(ni);
				_write_next_if_unchanged(nx, ny, nz, al == 0 ? gas : mkfluid(nb, al - 1, true));
			} else {
				_write_next(nx, ny, nz, gas);
				_deplete_adjacent_source(nx, ny, nz, MAT_ACID_BASE);
			}
			// Self: source decrements, non-source converts to gas
			if (!my_src) {
				_deplete_adjacent_source(x, y, z, MAT_WATER_BASE);
				return gas;
			}
			uint8_t l = flvl(my_id);
			return l == 0 ? gas : mkfluid(my_b, l - 1, true);
		}
		if (my_b == MAT_ACID_BASE && nb == MAT_WATER_BASE) {
			uint8_t gas = mkfluid(MAT_GAS_BASE, FLUID_LEVELS - 1, false);
			if (src(nr)) {
				uint8_t wl = flvl(ni);
				_write_next_if_unchanged(nx, ny, nz, wl == 0 ? gas : mkfluid(nb, wl - 1, true));
			} else {
				_write_next(nx, ny, nz, gas);
				_deplete_adjacent_source(nx, ny, nz, MAT_WATER_BASE);
			}
			if (!my_src) {
				_deplete_adjacent_source(x, y, z, MAT_ACID_BASE);
				return gas;
			}
			uint8_t l = flvl(my_id);
			return l == 0 ? gas : mkfluid(my_b, l - 1, true);
		}
		if (my_id == MAT_DIRT && nb == MAT_WATER_BASE)
			return MAT_MUD;
	}
	return NO_REACTION;
}

bool MaterialSimulatorNative::_is_fed(int x, int y, int z, uint8_t base, uint8_t level) const {
	uint8_t above_raw = _read_raw(x, y + 1, z);
	if (above_raw == NOT_LOADED) return true; // don't evaporate while neighbor chunk is loading
	uint8_t above_id = mid(above_raw);
	if (is_fluid(above_id) && fbase(above_id) == base)
		return true;

	int needed = level + spread_loss(base);

	const int hd[8][3] = {
		{1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1},
		{1,0,1}, {1,0,-1}, {-1,0,1}, {-1,0,-1}
	};
	for (int i = 0; i < 8; i++) {
		uint8_t nr = _read_raw(x + hd[i][0], y + hd[i][1], z + hd[i][2]);
		if (nr == NOT_LOADED) return true; // don't evaporate while neighbor chunk is loading
		uint8_t ni = mid(nr);
		if (!is_fluid(ni) || fbase(ni) != base) continue;
		if (flvl(ni) >= needed) return true;
	}
	return false;
}

void MaterialSimulatorNative::_sim_fluid(int x, int y, int z, uint8_t raw) {
	uint8_t id   = mid(raw);
	uint8_t base = fbase(id);
	uint8_t lvl  = flvl(id);
	bool s       = src(raw);

	int td = (base == MAT_LAVA_BASE) ? 3 : 1;
	if (td > 1 && _tick_count % td != 0) {
		_write_next(x, y, z, raw);
		return;
	}

	uint8_t rx = _react(x, y, z, id, raw);
	if (rx != NO_REACTION) {
		_write_next(x, y, z, rx);
		return;
	}

	if (!s && !_is_fed(x, y, z, base, lvl)) {
		_write_next(x, y, z, (lvl == 0) ? MAT_AIR : mkfluid(base, lvl - 1, false));
		return;
	}

	uint8_t br = _read_raw(x, y - 1, z);
	uint8_t bi = mid(br);

	if (bi == MAT_AIR || is_gas(bi)) {
		_write_next(x, y - 1, z, mkfluid(base, FLUID_LEVELS - 1, false));
		if (s) {
			_write_next(x, y, z, raw);
		} else if (is_gas(bi)) {
			_write_next(x, y, z, br);
		} else {
			_write_next(x, y, z, MAT_AIR);
		}
		return;
	}

	if (is_fluid(bi) && fbase(bi) == base) {
		uint8_t bl = flvl(bi);
		if (bl < FLUID_LEVELS - 1) {
			int tr = std::min((int)lvl, FLUID_LEVELS - 1 - (int)bl);
			if (tr > 0) {
				_write_next(x, y - 1, z, mkfluid(base, bl + tr, src(br)));
				if (s) {
					_write_next(x, y, z, raw);
				} else {
					int rem = lvl - tr;
					_write_next(x, y, z, (rem == 0) ? MAT_AIR : mkfluid(base, rem, false));
				}
				return;
			}
		}
	}

	if (is_solid(bi)) {
		int sl = spread_loss(base);

		if (lvl >= sl) {
			int sp = lvl - sl;
			const int cd[4][3] = {{1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1}};
			for (int i = 0; i < 4; i++) {
				int nx = x + cd[i][0], nz = z + cd[i][2];
				uint8_t nr = _read_raw(nx, y, nz);
				uint8_t ni = mid(nr);
				if (ni == MAT_AIR) {
					_write_next_if_unchanged(nx, y, nz, mkfluid(base, sp, false));
				} else if (is_fluid(ni) && fbase(ni) == base && flvl(ni) < sp && !src(nr)) {
					_write_next_if_unchanged(nx, y, nz, mkfluid(base, sp, src(nr)));
				}
			}
		}

		int dsl = sl + 1;
		if (lvl >= dsl) {
			int dp = lvl - dsl;
			const int dd[4][3] = {{1,0,1}, {1,0,-1}, {-1,0,1}, {-1,0,-1}};
			for (int i = 0; i < 4; i++) {
				int nx = x + dd[i][0], nz = z + dd[i][2];
				uint8_t nr = _read_raw(nx, y, nz);
				uint8_t ni = mid(nr);
				if (ni == MAT_AIR) {
					_write_next_if_unchanged(nx, y, nz, mkfluid(base, dp, false));
				} else if (is_fluid(ni) && fbase(ni) == base && flvl(ni) < dp && !src(nr)) {
					_write_next_if_unchanged(nx, y, nz, mkfluid(base, dp, src(nr)));
				}
			}
		}
	}

	_write_next(x, y, z, raw);
}

void MaterialSimulatorNative::_sim_gas(int x, int y, int z, uint8_t raw) {
	uint8_t id   = mid(raw);
	uint8_t base = fbase(id);
	uint8_t lvl  = flvl(id);

	if ((_tick_count >> 1) % 2 != 0) {
		_write_next(x, y, z, raw);
		return;
	}

	if (lvl <= 1) {
		_write_next(x, y, z, MAT_AIR);
		return;
	}
	int nl = lvl - 1;

	uint8_t ar = _read_raw(x, y + 1, z);
	uint8_t ai = mid(ar);

	if (ai == MAT_AIR) {
		_write_next(x, y + 1, z, mkfluid(base, nl, false));
		_write_next(x, y, z, MAT_AIR);
		return;
	}
	if (is_gas(ai) && fbase(ai) == base && flvl(ai) < nl) {
		_write_next(x, y + 1, z, mkfluid(base, nl, false));
		_write_next(x, y, z, MAT_AIR);
		return;
	}
	if (is_fluid(ai)) {
		_write_next(x, y + 1, z, mkfluid(base, nl, false));
		_write_next(x, y, z, ar);
		return;
	}

	_write_next(x, y, z, mkfluid(base, nl, false));

	if (nl >= 4) {
		int sp = nl - 4;
		const int cd[4][3] = {{1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1}};
		for (int i = 0; i < 4; i++) {
			if (mid(_read_raw(x + cd[i][0], y, z + cd[i][2])) == MAT_AIR)
				_write_next_if_unchanged(x + cd[i][0], y, z + cd[i][2], mkfluid(base, sp, false));
		}
	}
}

void MaterialSimulatorNative::_sim_cell(int x, int y, int z) {
	uint8_t raw = _read_raw(x, y, z);
	uint8_t id = mid(raw);

	if (id == MAT_AIR || id == MAT_BEDROCK || id == NOT_LOADED) {
		return;
	}

	if (is_solid(id)) {
		uint8_t rx = _react(x, y, z, id, raw);
		if (rx != NO_REACTION) {
			_write_next(x, y, z, rx);
		}
		return;
	}

	if (is_gas(id))
		_sim_gas(x, y, z, raw);
	else if (is_fluid(id))
		_sim_fluid(x, y, z, raw);
}
