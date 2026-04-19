#include "voxel_chunk_store.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstring>

namespace godot {

namespace {
// Default flat-terrain materials (match MaterialRegistry base IDs).
constexpr uint16_t MAT_AIR = 0;
constexpr uint16_t MAT_STONE = 1;
constexpr uint16_t MAT_BEDROCK = 2;
constexpr uint16_t MAT_DIRT = 4;
} // namespace

void VoxelChunkStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "anchor", "sim_radius"),
			&VoxelChunkStore::initialize);
	ClassDB::bind_method(D_METHOD("stop"), &VoxelChunkStore::stop);
	ClassDB::bind_method(D_METHOD("tick"), &VoxelChunkStore::tick);

	ClassDB::bind_method(D_METHOD("set_sim_radius", "radius"), &VoxelChunkStore::set_sim_radius);
	ClassDB::bind_method(D_METHOD("get_sim_radius"), &VoxelChunkStore::get_sim_radius);
	ClassDB::bind_method(D_METHOD("set_origin_y", "origin_y"), &VoxelChunkStore::set_origin_y);
	ClassDB::bind_method(D_METHOD("get_origin_y"), &VoxelChunkStore::get_origin_y);

	ClassDB::bind_method(D_METHOD("get_voxel", "world_pos"), &VoxelChunkStore::gd_get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "world_pos", "value"), &VoxelChunkStore::gd_set_voxel);
	ClassDB::bind_method(D_METHOD("get_chunk_generation", "chunk_coord"), &VoxelChunkStore::gd_get_chunk_generation);
	ClassDB::bind_method(D_METHOD("get_chunk_state", "chunk_coord"), &VoxelChunkStore::gd_get_chunk_state);
	ClassDB::bind_method(D_METHOD("loaded_chunk_count"), &VoxelChunkStore::gd_loaded_chunk_count);
	ClassDB::bind_method(D_METHOD("self_test"), &VoxelChunkStore::gd_self_test);
}

VoxelChunkStore::VoxelChunkStore() {
	_generator = &VoxelChunkStore::_flat_terrain_generator;
}

VoxelChunkStore::~VoxelChunkStore() {
	stop();
	delete[] _chunks;
	_chunks = nullptr;
}

void VoxelChunkStore::_notification(int p_what) {
	if (p_what == NOTIFICATION_EXIT_TREE || p_what == NOTIFICATION_PREDELETE) {
		stop();
	}
}

// ── Generator ──

void VoxelChunkStore::set_generator_fn(GeneratorFn fn) {
	if (fn) {
		_generator = std::move(fn);
	} else {
		_generator = &VoxelChunkStore::_flat_terrain_generator;
	}
}

void VoxelChunkStore::_flat_terrain_generator(int /*wcx*/, int /*wcz*/, int origin_y, uint16_t *out) {
	uint16_t slice[voxl::CHUNK_X * voxl::CHUNK_Y];
	for (int ly = 0; ly < voxl::CHUNK_Y; ly++) {
		int world_y = origin_y + ly;
		uint16_t mat;
		if (world_y <= 0) mat = MAT_BEDROCK;
		else if (world_y <= 14) mat = MAT_STONE;
		else if (world_y == 15) mat = MAT_DIRT;
		else mat = MAT_AIR;
		std::fill(&slice[ly * voxl::CHUNK_X], &slice[(ly + 1) * voxl::CHUNK_X], mat);
	}
	for (int lz = 0; lz < voxl::CHUNK_Z; lz++) {
		std::memcpy(&out[lz * voxl::CHUNK_X * voxl::CHUNK_Y], slice,
				voxl::CHUNK_X * voxl::CHUNK_Y * sizeof(uint16_t));
	}
}

// ── Lifecycle ──

void VoxelChunkStore::set_sim_radius(int radius) {
	if (radius < 1) radius = 1;
	if (radius == _sim_radius) return;
	_sim_radius = radius;
	if (_started) {
		_stop_loaders();
		_reallocate_chunks();
		_init_grid();
		_start_loaders();
		int gw = _grid_w();
		int gh = _grid_h();
		for (int gz = 0; gz < gh; gz++) {
			for (int gx = 0; gx < gw; gx++) {
				Chunk *c = _grid_at(gx, gz);
				_queue_chunk_load(c, c->wcx, c->wcz);
			}
		}
	} else {
		_reallocate_chunks();
	}
}

void VoxelChunkStore::initialize(Node3D *anchor, int sim_radius) {
	_anchor = anchor;
	if (sim_radius > 0) _sim_radius = sim_radius;

	_reallocate_chunks();
	_init_grid();
	_start_loaders();

	int gw = _grid_w();
	int gh = _grid_h();
	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			Chunk *c = _grid_at(gx, gz);
			_queue_chunk_load(c, c->wcx, c->wcz);
		}
	}

	_started = true;

	UtilityFunctions::print(String("[VoxelChunkStore] ready (center_chunk={0},{1}, radius={2})")
			.format(Array::make(_center_cx, _center_cz, _sim_radius)));
}

void VoxelChunkStore::stop() {
	if (!_started && _loader_threads.empty()) return;
	_stop_loaders();
	_started = false;
}

void VoxelChunkStore::tick() {
	if (!_started) return;
	_drain_loader_results();
	_recenter_grid();
}

// ── Chunk allocation & grid ──

void VoxelChunkStore::_reallocate_chunks() {
	delete[] _chunks;
	int tc = _total_chunks();
	_chunks = new Chunk[tc];
	_grid.assign(tc, nullptr);
}

void VoxelChunkStore::_init_grid() {
	Vector3 pp = _anchor ? _anchor->get_global_position() : Vector3(0, 0, 0);
	_center_cx = voxl::chunk_coord_x(voxl::world_to_voxel(pp.x));
	_center_cz = voxl::chunk_coord_z(voxl::world_to_voxel(pp.z));

	int gw = _grid_w();
	int gh = _grid_h();
	_grid.assign(gw * gh, nullptr);

	int pool_idx = 0;
	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			Chunk *c = &_chunks[pool_idx++];
			c->wcx = _center_cx - _sim_radius + gx;
			c->wcz = _center_cz - _sim_radius + gz;
			c->state.store(Chunk::UNLOADED, std::memory_order_release);
			c->generation.store(0, std::memory_order_release);
			c->dirty_version.store(0, std::memory_order_release);
			std::fill(c->voxels, c->voxels + voxl::CHUNK_VOL, voxl::NOT_LOADED);
			std::fill(c->voxels_next, c->voxels_next + voxl::CHUNK_VOL, voxl::NOT_LOADED);
			c->current = c->voxels;
			c->next_buf = c->voxels_next;
			_grid_at(gx, gz) = c;
		}
	}
}

VoxelChunkStore::Chunk *VoxelChunkStore::chunk_at(int cx, int cz) const {
	int gx = cx - (_center_cx - _sim_radius);
	int gz = cz - (_center_cz - _sim_radius);
	if (gx < 0 || gx >= _grid_w() || gz < 0 || gz >= _grid_h()) return nullptr;
	return _grid_at(gx, gz);
}

std::vector<VoxelChunkStore::Chunk *> VoxelChunkStore::loaded_chunks() const {
	std::vector<Chunk *> out;
	out.reserve(_grid.size());
	for (Chunk *c : _grid) {
		if (c && c->state.load(std::memory_order_acquire) == Chunk::LOADED) {
			out.push_back(c);
		}
	}
	return out;
}

void VoxelChunkStore::notify_dirty(int wcx, int wcz) {
	for (auto &cb : _dirty_subscribers) cb(wcx, wcz);
}

void VoxelChunkStore::_unload_chunk(Chunk *c) {
	c->state.store(Chunk::UNLOADED, std::memory_order_release);
}

void VoxelChunkStore::_queue_chunk_load(Chunk *c, int wcx, int wcz) {
	c->wcx = wcx;
	c->wcz = wcz;
	c->state.store(Chunk::LOADING, std::memory_order_release);
	std::fill(c->voxels, c->voxels + voxl::CHUNK_VOL, voxl::NOT_LOADED);
	std::fill(c->voxels_next, c->voxels_next + voxl::CHUNK_VOL, voxl::NOT_LOADED);
	c->current = c->voxels;
	c->next_buf = c->voxels_next;

	{
		std::lock_guard<std::mutex> lock(_loader_queue_mutex);
		_loader_queue.push({c, wcx, wcz});
	}
	_loader_cv.notify_one();
}

void VoxelChunkStore::_recenter_grid() {
	if (!_anchor) return;

	Vector3 pp = _anchor->get_global_position();
	int new_cx = voxl::chunk_coord_x(voxl::world_to_voxel(pp.x));
	int new_cz = voxl::chunk_coord_z(voxl::world_to_voxel(pp.z));

	if (new_cx == _center_cx && new_cz == _center_cz) return;

	int dx = new_cx - _center_cx;
	int dz = new_cz - _center_cz;

	int gw = _grid_w();
	int gh = _grid_h();
	int tc = _total_chunks();

	if (std::abs(dx) > _sim_radius * 2 || std::abs(dz) > _sim_radius * 2) {
		// Teleport: reinit everything.
		_center_cx = new_cx;
		_center_cz = new_cz;

		for (int i = 0; i < tc; i++) _unload_chunk(&_chunks[i]);
		_init_grid();
		for (int gz = 0; gz < gh; gz++) {
			for (int gx = 0; gx < gw; gx++) {
				Chunk *c = _grid_at(gx, gz);
				_queue_chunk_load(c, c->wcx, c->wcz);
			}
		}
		return;
	}

	int new_min_cx = new_cx - _sim_radius;
	int new_min_cz = new_cz - _sim_radius;

	std::vector<Chunk *> old_grid(_grid);
	_grid.assign(gw * gh, nullptr);

	std::vector<Chunk *> recycled;
	for (int gz = 0; gz < gh; gz++) {
		for (int gx = 0; gx < gw; gx++) {
			Chunk *c = old_grid[gx + gz * gw];
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
			Chunk *c = recycled[ri++];
			int wcx = new_min_cx + gx;
			int wcz = new_min_cz + gz;
			c->wcx = wcx;
			c->wcz = wcz;
			c->state.store(Chunk::LOADING, std::memory_order_release);
			std::fill(c->voxels, c->voxels + voxl::CHUNK_VOL, voxl::NOT_LOADED);
			std::fill(c->voxels_next, c->voxels_next + voxl::CHUNK_VOL, voxl::NOT_LOADED);
			c->current = c->voxels;
			c->next_buf = c->voxels_next;
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
			Chunk *c = _grid_at(gx, gz);
			if (c && c->state.load(std::memory_order_acquire) == Chunk::LOADING) {
				std::lock_guard<std::mutex> lock(_loader_queue_mutex);
				_loader_queue.push({c, c->wcx, c->wcz});
			}
		}
	}
	_loader_cv.notify_all();
}

// ── Loader pool ──

void VoxelChunkStore::_start_loaders() {
	_stop_loaders();
	_loaders_running.store(true);
	_loader_threads.resize(NUM_LOADERS);
	for (int i = 0; i < NUM_LOADERS; i++) {
		_loader_threads[i] = std::thread(&VoxelChunkStore::_loader_thread_func, this, i);
	}
}

void VoxelChunkStore::_stop_loaders() {
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

void VoxelChunkStore::_loader_thread_func(int /*id*/) {
	while (_loaders_running.load()) {
		LoadRequest req;
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

		// Discard if the slot has been reassigned since the request was queued.
		if (req.chunk->state.load(std::memory_order_acquire) != Chunk::LOADING ||
				req.chunk->wcx != req.wcx || req.chunk->wcz != req.wcz) {
			continue;
		}

		LoadResult *result = new LoadResult();
		result->chunk = req.chunk;
		result->wcx = req.wcx;
		result->wcz = req.wcz;

		_generator(req.wcx, req.wcz, _origin_y, result->data);

		{
			std::lock_guard<std::mutex> lock(_loader_result_mutex);
			_loader_results.push_back(result);
		}
	}
}

void VoxelChunkStore::_drain_loader_results() {
	std::vector<LoadResult *> batch;
	{
		std::lock_guard<std::mutex> lock(_loader_result_mutex);
		batch.swap(_loader_results);
	}
	for (auto *result : batch) {
		Chunk *c = result->chunk;
		if (c->state.load(std::memory_order_acquire) == Chunk::LOADING &&
				c->wcx == result->wcx && c->wcz == result->wcz) {
			std::memcpy(c->voxels, result->data, voxl::CHUNK_VOL * sizeof(uint16_t));
			std::memcpy(c->voxels_next, result->data, voxl::CHUNK_VOL * sizeof(uint16_t));
			c->current = c->voxels;
			c->next_buf = c->voxels_next;
			c->generation.fetch_add(1, std::memory_order_release);
			c->dirty_version.fetch_add(1, std::memory_order_relaxed);
			c->state.store(Chunk::LOADED, std::memory_order_release);

			for (auto &cb : _dirty_subscribers) cb(result->wcx, result->wcz);
		}
		delete result;
	}
}

// ── Dirty subscribers ──

void VoxelChunkStore::subscribe_dirty(DirtyCallback cb) {
	_dirty_subscribers.push_back(std::move(cb));
}

// ── GDScript-bound accessors ──

int VoxelChunkStore::gd_get_voxel(const Vector3i &world_pos) const {
	return read_voxel(world_pos.x, world_pos.y, world_pos.z);
}

bool VoxelChunkStore::gd_set_voxel(const Vector3i &world_pos, int value) {
	bool ok = write_voxel(world_pos.x, world_pos.y, world_pos.z, static_cast<uint16_t>(value));
	if (ok && value != 0) {
		Chunk *c = chunk_at(voxl::chunk_coord_x(world_pos.x), voxl::chunk_coord_z(world_pos.z));
		if (c) c->sim_active.store(true, std::memory_order_relaxed);
	}
	return ok;
}

int VoxelChunkStore::gd_get_chunk_generation(const Vector2i &chunk_coord) const {
	Chunk *c = chunk_at(chunk_coord.x, chunk_coord.y);
	if (!c) return -1;
	return static_cast<int>(c->generation.load(std::memory_order_acquire));
}

int VoxelChunkStore::gd_get_chunk_state(const Vector2i &chunk_coord) const {
	Chunk *c = chunk_at(chunk_coord.x, chunk_coord.y);
	if (!c) return -1;
	return static_cast<int>(c->state.load(std::memory_order_acquire));
}

int VoxelChunkStore::gd_loaded_chunk_count() const {
	int n = 0;
	int tc = _total_chunks();
	for (int i = 0; i < tc; i++) {
		if (_chunks[i].state.load(std::memory_order_acquire) == Chunk::LOADED) n++;
	}
	return n;
}

Dictionary VoxelChunkStore::gd_self_test() {
	// Counts voxels by base material across all loaded chunks.
	// Used to verify flat-terrain generator output in a unit test.
	int64_t air = 0, stone = 0, bedrock = 0, dirt = 0, other = 0;
	int loaded = 0;
	int tc = _total_chunks();
	for (int i = 0; i < tc; i++) {
		if (_chunks[i].state.load(std::memory_order_acquire) != Chunk::LOADED) continue;
		loaded++;
		const uint16_t *v = _chunks[i].current;
		for (int k = 0; k < voxl::CHUNK_VOL; k++) {
			uint8_t b = static_cast<uint8_t>(v[k] & 0xFF);
			switch (b) {
				case MAT_AIR: air++; break;
				case MAT_STONE: stone++; break;
				case MAT_BEDROCK: bedrock++; break;
				case MAT_DIRT: dirt++; break;
				default: other++; break;
			}
		}
	}

	Dictionary d;
	d["loaded_chunks"] = loaded;
	d["total_chunks"] = tc;
	d["air"] = air;
	d["stone"] = stone;
	d["bedrock"] = bedrock;
	d["dirt"] = dirt;
	d["other"] = other;
	d["chunk_volume"] = voxl::CHUNK_VOL;
	return d;
}

} // namespace godot
