#include "material_simulator_native.h"
#include <godot_cpp/variant/aabb.hpp>

using namespace godot;

// ── Constructor / Destructor ──

MaterialSimulatorNative::MaterialSimulatorNative() {
	_reallocate_chunks();
}

MaterialSimulatorNative::~MaterialSimulatorNative() {
	_stop_loaders();
	delete[] _chunks;
	_chunks = nullptr;
}

// ── Bindings ──

void MaterialSimulatorNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "terrain", "player"), &MaterialSimulatorNative::initialize, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("place_fluid", "pos", "fluid_id"), &MaterialSimulatorNative::place_fluid);
	ClassDB::bind_method(D_METHOD("remove_voxel", "pos"), &MaterialSimulatorNative::remove_voxel);
	ClassDB::bind_method(D_METHOD("sync_voxel", "pos", "voxel_id"), &MaterialSimulatorNative::sync_voxel);
	ClassDB::bind_method(D_METHOD("get_active_cell_count"), &MaterialSimulatorNative::get_active_cell_count);
	ClassDB::bind_method(D_METHOD("get_last_tick_ms"), &MaterialSimulatorNative::get_last_tick_ms);
	ClassDB::bind_method(D_METHOD("get_last_changes_count"), &MaterialSimulatorNative::get_last_changes_count);
	ClassDB::bind_method(D_METHOD("set_sim_radius", "radius"), &MaterialSimulatorNative::set_sim_radius);
	ClassDB::bind_method(D_METHOD("get_sim_radius"), &MaterialSimulatorNative::get_sim_radius);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "sim_radius"), "set_sim_radius", "get_sim_radius");

	ADD_SIGNAL(MethodInfo("voxel_changed",
			PropertyInfo(Variant::VECTOR3I, "pos"),
			PropertyInfo(Variant::INT, "new_voxel")));
}

void MaterialSimulatorNative::_notification(int p_what) {
	if (p_what == NOTIFICATION_PREDELETE) {
		_stop_loaders();
	}
}

// ── Chunk allocation ──

void MaterialSimulatorNative::_reallocate_chunks() {
	delete[] _chunks;
	int tc = _total_chunks();
	_chunks = new SimChunk[tc];
	_grid.assign(tc, nullptr);
}

// ── sim_radius property ──

void MaterialSimulatorNative::set_sim_radius(int radius) {
	if (radius < 1) radius = 1;
	if (radius == _sim_radius) return;
	_sim_radius = radius;
	if (_sim_ready) {
		_stop_loaders();
		_reallocate_chunks();
		_setup_sim();
	} else {
		_reallocate_chunks();
	}
}

int MaterialSimulatorNative::get_sim_radius() const {
	return _sim_radius;
}

// ── Public API ──

void MaterialSimulatorNative::initialize(Object *p_terrain, Node3D *p_player) {
	_terrain = p_terrain;
	_player = p_player;

	_voxel_tool = _terrain->call("get_voxel_tool");
	_voxel_tool->call("set_channel", 0);

	set_physics_process(true);

	// Sim generates its own terrain data, so start immediately
	_setup_sim();
}

void MaterialSimulatorNative::place_fluid(const Vector3i &pos, int fluid_id) {
	if (_voxel_tool.is_null()) return;
	_voxel_tool->call("set_voxel", pos, fluid_id);
	if (_sim_ready) {
		_write_cell(pos, static_cast<uint16_t>(fluid_id));
	}
}

void MaterialSimulatorNative::remove_voxel(const Vector3i &pos) {
	if (_voxel_tool.is_null()) return;
	_voxel_tool->call("set_voxel", pos, 0);
	if (_sim_ready) {
		_write_cell(pos, MAT_AIR);
	}
}

void MaterialSimulatorNative::sync_voxel(const Vector3i &pos, int voxel_id) {
	if (_sim_ready) {
		_write_cell(pos, static_cast<uint16_t>(voxel_id));
	}
}

int MaterialSimulatorNative::get_active_cell_count() const {
	if (!_sim_ready) return 0;
	int count = 0;
	int tc = _total_chunks();
	for (int i = 0; i < tc; i++) {
		if (_chunks[i].state == SimChunk::LOADED)
			count += CHUNK_VOL;
	}
	return count;
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
	return _voxel_get(_voxel_tool, pos) == value;
}

// ── Chunk grid lookup ──

MaterialSimulatorNative::SimChunk *MaterialSimulatorNative::_chunk_at(int cx, int cz) const {
	int gx = cx - (_center_cx - _sim_radius);
	int gz = cz - (_center_cz - _sim_radius);
	if (gx < 0 || gx >= _grid_w() || gz < 0 || gz >= _grid_h()) return nullptr;
	return _grid_at(gx, gz);
}

// ── Buffer writes (main thread, between ticks) ──

void MaterialSimulatorNative::_write_cell(const Vector3i &world_pos, uint16_t val) {
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
	_center_cx = _chunk_coord(world_to_voxel(pp.x));
	_center_cz = _chunk_coord(world_to_voxel(pp.z));

	int gw = _grid_w();
	int gh = _grid_h();
	_grid.assign(gw * gh, nullptr);

	int pool_idx = 0;
	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			SimChunk *c = &_chunks[pool_idx++];
			c->wcx = _center_cx - _sim_radius + gx;
			c->wcz = _center_cz - _sim_radius + gz;
			c->state = SimChunk::UNLOADED;
			std::fill(c->buf_a, c->buf_a + CHUNK_VOL, NOT_LOADED);
			std::fill(c->buf_b, c->buf_b + CHUNK_VOL, NOT_LOADED);
			c->current = c->buf_a;
			c->next_buf = c->buf_b;
			_grid_at(gx, gz) = c;
		}
	}
}

// ── Sim setup ──

void MaterialSimulatorNative::_setup_sim() {
	_init_grid();
	_start_loaders();

	int gw = _grid_w();
	int gh = _grid_h();
	for (int gz = 0; gz < gh; gz++)
		for (int gx = 0; gx < gw; gx++)
			_queue_chunk_load(_grid_at(gx, gz), _grid_at(gx, gz)->wcx, _grid_at(gx, gz)->wcz);

	_sim_ready = true;
	_sim_timer = 0.0;

	UtilityFunctions::print(String("[MaterialSimulatorNative] sim ready (center_chunk={0},{1}, radius={2})")
			.format(Array::make(_center_cx, _center_cz, _sim_radius)));
}

// ── Chunk loader thread pool ──

void MaterialSimulatorNative::_start_loaders() {
	_stop_loaders();

	_loaders_running.store(true);

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

}

void MaterialSimulatorNative::_loader_thread_func(int loader_id) {
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

		// Generate flat terrain directly in C++.
		// Build one Z-slice template, then copy it for all Z values.
		uint16_t slice[CHUNK_X * CHUNK_Y];
		for (int ly = 0; ly < CHUNK_Y; ly++) {
			int world_y = _origin_y + ly;
			uint16_t mat;
			if (world_y <= 0)       mat = MAT_BEDROCK;
			else if (world_y <= 14) mat = MAT_STONE;
			else if (world_y == 15) mat = MAT_DIRT;
			else                    mat = MAT_AIR;
			std::fill(&slice[ly * CHUNK_X], &slice[(ly + 1) * CHUNK_X], mat);
		}
		for (int lz = 0; lz < CHUNK_Z; lz++) {
			std::memcpy(&result->data[lz * CHUNK_X * CHUNK_Y], slice, CHUNK_X * CHUNK_Y * sizeof(uint16_t));
		}

		{
			std::lock_guard<std::mutex> lock(_loader_result_mutex);
			_loader_results.push_back(result);
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
			std::memcpy(c->current, result->data, CHUNK_VOL * sizeof(uint16_t));
			std::memcpy(c->next_buf, result->data, CHUNK_VOL * sizeof(uint16_t));
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
	int new_cx = _chunk_coord(world_to_voxel(pp.x));
	int new_cz = _chunk_coord(world_to_voxel(pp.z));

	if (new_cx == _center_cx && new_cz == _center_cz) return;

	int dx = new_cx - _center_cx;
	int dz = new_cz - _center_cz;

	UtilityFunctions::print(String("[MaterialSimulatorNative] recenter grid ({0},{1}) -> ({2},{3})")
			.format(Array::make(_center_cx, _center_cz, new_cx, new_cz)));

	_deferred_changes.clear();

	int gw = _grid_w();
	int gh = _grid_h();
	int tc = _total_chunks();

	if (abs(dx) > _sim_radius * 2 || abs(dz) > _sim_radius * 2) {
		_center_cx = new_cx;
		_center_cz = new_cz;

		for (int i = 0; i < tc; i++)
			_unload_chunk(&_chunks[i]);

		_init_grid();
		for (int gz = 0; gz < gh; gz++)
			for (int gx = 0; gx < gw; gx++)
				_queue_chunk_load(_grid_at(gx, gz), _grid_at(gx, gz)->wcx, _grid_at(gx, gz)->wcz);
		return;
	}

	int new_min_cx = new_cx - _sim_radius;
	int new_min_cz = new_cz - _sim_radius;

	std::vector<SimChunk *> old_grid(_grid);
	_grid.assign(gw * gh, nullptr);

	std::vector<SimChunk *> recycled;

	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			SimChunk *c = old_grid[gx + gz * gw];
			if (!c) continue;

			int new_gx = c->wcx - new_min_cx;
			int new_gz = c->wcz - new_min_cz;

			if (new_gx >= 0 && new_gx < gw && new_gz >= 0 && new_gz < gh) {
				_grid_at(new_gx, new_gz) = c;
			} else {
				_unload_chunk(c);
				recycled.push_back(c);
			}
		}
	}

	int ri = 0;
	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			if (_grid_at(gx, gz) != nullptr) continue;

			SimChunk *c = recycled[ri++];
			int wcx = new_min_cx + gx;
			int wcz = new_min_cz + gz;
			c->wcx = wcx;
			c->wcz = wcz;
			c->state = SimChunk::LOADING;
			std::fill(c->buf_a, c->buf_a + CHUNK_VOL, NOT_LOADED);
			std::fill(c->buf_b, c->buf_b + CHUNK_VOL, NOT_LOADED);
			c->current = c->buf_a;
			c->next_buf = c->buf_b;
			_grid_at(gx, gz) = c;
		}
	}

	_center_cx = new_cx;
	_center_cz = new_cz;

	{
		std::lock_guard<std::mutex> lock(_loader_queue_mutex);
		while (!_loader_queue.empty()) _loader_queue.pop();
	}

	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			SimChunk *c = _grid_at(gx, gz);
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

	int gw = _grid_w();
	int gh = _grid_h();
	int tc = _total_chunks();

	std::vector<SimChunk *> loaded;
	loaded.reserve(tc);
	for (int gz = 0; gz < gh; gz++)
		for (int gx = 0; gx < gw; gx++)
			if (_grid_at(gx, gz) && _grid_at(gx, gz)->state == SimChunk::LOADED)
				loaded.push_back(_grid_at(gx, gz));

	if (loaded.empty()) {
		_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;
		return;
	}

	for (auto *c : loaded)
		std::memcpy(c->next_buf, c->current, CHUNK_VOL * sizeof(uint16_t));

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
		UtilityFunctions::print(String("[MaterialSimulatorNative] tick {0}: {1} changes, {2} ms, {3}/{4} loaded")
				.format(Array::make(_tick_count, _last_changes_count, get_last_tick_ms(),
						(int)loaded.size(), tc)));
	}
}

// ── Change detection and application ──

void MaterialSimulatorNative::_collect_and_apply_changes() {
	if (_voxel_tool.is_null()) return;

	int pw_x = 0, pw_z = 0;
	if (_player) {
		Vector3 pp = _player->get_global_position();
		pw_x = world_to_voxel(pp.x);
		pw_z = world_to_voxel(pp.z);
	}

	int max_dist = _sim_radius * CHUNK_X;
	int applied = 0;
	int total = 0;

	int gw = _grid_w();
	int gh = _grid_h();

	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			SimChunk *c = _grid_at(gx, gz);
			if (!c || c->state != SimChunk::LOADED) continue;

			int base_wx = c->wcx * CHUNK_X;
			int base_wz = c->wcz * CHUNK_Z;

			int chunk_mid_x = base_wx + CHUNK_X / 2;
			int chunk_mid_z = base_wz + CHUNK_Z / 2;
			if (abs(chunk_mid_x - pw_x) > max_dist || abs(chunk_mid_z - pw_z) > max_dist) {
				continue;
			}

			for (int i = 0; i < CHUNK_VOL; i++) {
				uint16_t old_id = c->current[i];
				uint16_t new_id = c->next_buf[i];
				if (old_id == new_id) continue;

				total++;

				int lx = i % CHUNK_X;
				int ly = (i / CHUNK_X) % CHUNK_Y;
				int lz = i / (CHUNK_X * CHUNK_Y);
				Vector3i world_pos(base_wx + lx, _origin_y + ly, base_wz + lz);

				if (applied < APPLY_CHANGES_CAP) {
					if (_voxel_set(world_pos, new_id)) {
						emit_signal("voxel_changed", world_pos, (int)new_id);
						applied++;
					}
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
		pw_x = world_to_voxel(pp.x);
		pw_z = world_to_voxel(pp.z);
	}

	int max_dist = _sim_radius * CHUNK_X;
	int batch = MIN((int)_deferred_changes.size(), APPLY_CHANGES_CAP);
	for (int i = 0; i < batch; i++) {
		const auto &dc = _deferred_changes[i];
		if (abs(dc.world_pos.x - pw_x) > max_dist || abs(dc.world_pos.z - pw_z) > max_dist) continue;

		int wy = dc.world_pos.y - _origin_y;
		if (wy < 0 || wy >= CHUNK_Y) continue;
		{
			SimChunk *c = _chunk_at(_chunk_coord(dc.world_pos.x), _chunk_coord(dc.world_pos.z));
			if (!c || c->state != SimChunk::LOADED) continue;
			int lx = _local_coord(dc.world_pos.x), lz = _local_coord(dc.world_pos.z);
			int idx = lx + wy * CHUNK_X + lz * CHUNK_X * CHUNK_Y;
			if (c->current[idx] != (uint16_t)dc.new_type) continue;
		}

		if (!_voxel_set(dc.world_pos, dc.new_type)) continue;
		emit_signal("voxel_changed", dc.world_pos, dc.new_type);
	}
	_deferred_changes.erase(_deferred_changes.begin(), _deferred_changes.begin() + batch);
}

// ── Simulation functions ──

uint16_t MaterialSimulatorNative::_react(int x, int y, int z, uint16_t my_id) {
	const int dirs[6][3] = {
		{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}
	};

	uint8_t my_base = base_material(my_id);

	for (int i = 0; i < 6; i++) {
		int nx = x + dirs[i][0], ny = y + dirs[i][1], nz = z + dirs[i][2];
		uint16_t ni = _read_raw(nx, ny, nz);
		uint8_t ni_base = base_material(ni);
		if (ni_base == MAT_AIR || ni == NOT_LOADED) continue;

		if (my_base == MAT_WATER && ni_base == MAT_LAVA) {
			_write_next(nx, ny, nz, MAT_STONE);
			return MAT_AIR;
		}
		if (my_base == MAT_LAVA && ni_base == MAT_WATER) {
			_write_next(nx, ny, nz, MAT_AIR);
			return MAT_STONE;
		}
		if (my_base == MAT_WATER && ni_base == MAT_ACID) {
			_write_next(nx, ny, nz, MAT_GAS);
			return MAT_GAS;
		}
		if (my_base == MAT_ACID && ni_base == MAT_WATER) {
			_write_next(nx, ny, nz, MAT_GAS);
			return MAT_GAS;
		}
		if (my_base == MAT_DIRT && ni_base == MAT_WATER) {
			return MAT_MUD;
		}
	}
	return NO_REACTION;
}

void MaterialSimulatorNative::_sim_fluid(int x, int y, int z, uint16_t id) {
	uint8_t id_base = base_material(id);
	// Lava ticks slower
	if (id_base == MAT_LAVA && (_tick_count % 3) != 0) {
		_write_next(x, y, z, id);
		return;
	}

	// Check reactions
	uint16_t rx = _react(x, y, z, id);
	if (rx != NO_REACTION) {
		_write_next(x, y, z, rx);
		return;
	}

	static constexpr int dirs8[8][2] = {
		{1,0}, {-1,0}, {0,1}, {0,-1},
		{1,1}, {1,-1}, {-1,1}, {-1,-1}
	};

	uint32_t hash = static_cast<uint32_t>(
		(x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (_tick_count * 2654435761u));

	uint16_t below = _read_raw(x, y - 1, z);

	// 1. Fall straight down into air
	if (base_material(below) == MAT_AIR) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, MAT_AIR);
		return;
	}

	// 2. Fall through gas (swap)
	if (is_gas(below)) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, below);
		return;
	}

	// 3. On solid ground: stay (settled puddle)
	if (is_solid(below)) {
		_write_next(x, y, z, id);
		return;
	}

	// 4. On fluid: find shortest path down
	// Debug: log fluid-on-fluid occurrences (limited)
	static int _dbg_fof_count = 0;
	bool dbg = (_dbg_fof_count < 20);
	if (dbg) {
		_dbg_fof_count++;
		UtilityFunctions::print(String("[FLUID_DBG] fluid-on-fluid at ({0},{1},{2}) id={3} below={4} tick={5}")
			.format(Array::make(x, y, z, (int)id, (int)below, _tick_count)));
	}

	// 4a. Try diagonal-down — move to neighbor at y-1 if path is clear
	int start = hash & 7;
	for (int i = 0; i < 8; i++) {
		int di = (start + i) & 7;
		int nx = x + dirs8[di][0], nz = z + dirs8[di][1];
		uint16_t side = _read_raw(nx, y, nz);
		if (is_solid(side) || side == NOT_LOADED) continue;
		uint16_t diag = _read_raw(nx, y - 1, nz);
		if (base_material(diag) == MAT_AIR) {
			if (dbg) UtilityFunctions::print(String("[FLUID_DBG] 4a: move diag-down to ({0},{1},{2})")
				.format(Array::make(nx, y - 1, nz)));
			_write_next_if_unchanged(nx, y - 1, nz, id);
			_write_next(x, y, z, MAT_AIR);
			return;
		}
	}

	if (dbg) UtilityFunctions::print("[FLUID_DBG] 4a failed, trying 4b");

	// 4b. Move horizontally toward air that has a drop below it
	start = (hash >> 3) & 7;
	for (int i = 0; i < 8; i++) {
		int di = (start + i) & 7;
		int nx = x + dirs8[di][0], nz = z + dirs8[di][1];
		uint16_t side = _read_raw(nx, y, nz);
		if (base_material(side) != MAT_AIR) continue;
		uint16_t side_below = _read_raw(nx, y - 1, nz);
		if (base_material(side_below) == MAT_AIR || is_gas(side_below)) {
			if (dbg) UtilityFunctions::print(String("[FLUID_DBG] 4b: move to ({0},{1},{2})")
				.format(Array::make(nx, y, nz)));
			_write_next_if_unchanged(nx, y, nz, id);
			_write_next(x, y, z, MAT_AIR);
			return;
		}
	}

	if (dbg) UtilityFunctions::print("[FLUID_DBG] 4b failed, trying 4c");

	// 4c. Spread to any air neighbor (one random dir, anti-jitter)
	int dir = (hash >> 6) & 7;
	int nx = x + dirs8[dir][0], nz = z + dirs8[dir][1];
	if (base_material(_read_raw(nx, y, nz)) == MAT_AIR) {
		if (dbg) UtilityFunctions::print(String("[FLUID_DBG] 4c: spread to ({0},{1},{2})")
			.format(Array::make(nx, y, nz)));
		_write_next_if_unchanged(nx, y, nz, id);
		_write_next(x, y, z, MAT_AIR);
		return;
	}

	if (dbg) UtilityFunctions::print("[FLUID_DBG] ALL FAILED - staying put");

	// Can't move: stay (pool is full)
	_write_next(x, y, z, id);
}

void MaterialSimulatorNative::_sim_gas(int x, int y, int z, uint16_t id) {
	// Gas ticks every other pair of ticks
	if ((_tick_count >> 1) % 2 != 0) {
		_write_next(x, y, z, id);
		return;
	}

	// Gas dissipates over time via random chance
	uint32_t hash = static_cast<uint32_t>(
		(x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (_tick_count * 2654435761u));
	if ((hash & 0xF) == 0) {
		_write_next(x, y, z, MAT_AIR);
		return;
	}

	// Rise: check above
	uint16_t above = _read_raw(x, y + 1, z);

	if (base_material(above) == MAT_AIR) {
		_write_next(x, y + 1, z, id);
		_write_next(x, y, z, MAT_AIR);
		return;
	}
	if (is_fluid(above)) {
		// Swap with fluid (gas rises through fluid)
		_write_next(x, y + 1, z, id);
		_write_next(x, y, z, above);
		return;
	}

	// Can't rise: spread horizontally
	const int cd[4][3] = {{1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1}};
	int start_dir = (hash >> 4) & 3;
	for (int i = 0; i < 4; i++) {
		int di = (start_dir + i) & 3;
		int nx = x + cd[di][0], nz = z + cd[di][2];
		if (base_material(_read_raw(nx, y, nz)) == MAT_AIR) {
			_write_next_if_unchanged(nx, y, nz, id);
			_write_next(x, y, z, MAT_AIR);
			return;
		}
	}

	// Trapped: stay
	_write_next(x, y, z, id);
}

void MaterialSimulatorNative::_sim_cell(int x, int y, int z) {
	uint16_t id = _read_raw(x, y, z);
	uint8_t id_base = base_material(id);

	if (id_base == MAT_AIR || id_base == MAT_BEDROCK || id == NOT_LOADED) {
		return;
	}

	if (is_solid(id)) {
		uint16_t rx = _react(x, y, z, id);
		if (rx != NO_REACTION) {
			_write_next(x, y, z, rx);
		}
		return;
	}

	if (is_gas(id))
		_sim_gas(x, y, z, id);
	else if (is_fluid(id))
		_sim_fluid(x, y, z, id);
}
