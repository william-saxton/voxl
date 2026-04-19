#include "material_simulator_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstdlib>
#include <unordered_set>

namespace godot {

// ── Constructor / Destructor ──

MaterialSimulatorNative::MaterialSimulatorNative() {}

MaterialSimulatorNative::~MaterialSimulatorNative() {}

// ── Bindings ──

void MaterialSimulatorNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "store", "player"),
			&MaterialSimulatorNative::initialize, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("place_fluid", "pos", "fluid_id"), &MaterialSimulatorNative::place_fluid);
	ClassDB::bind_method(D_METHOD("remove_voxel", "pos"), &MaterialSimulatorNative::remove_voxel);
	ClassDB::bind_method(D_METHOD("sync_voxel", "pos", "voxel_id"), &MaterialSimulatorNative::sync_voxel);
	ClassDB::bind_method(D_METHOD("get_active_cell_count"), &MaterialSimulatorNative::get_active_cell_count);
	ClassDB::bind_method(D_METHOD("get_last_tick_ms"), &MaterialSimulatorNative::get_last_tick_ms);
	ClassDB::bind_method(D_METHOD("get_last_changes_count"), &MaterialSimulatorNative::get_last_changes_count);
}

// ── Public API ──

void MaterialSimulatorNative::initialize(VoxelChunkStore *store, Node3D *player) {
	_store = store;
	_player = player;
	if (_store) _origin_y = _store->get_origin_y();
	_sim_ready = (_store != nullptr);
	set_physics_process(_sim_ready);
	if (_sim_ready) {
		UtilityFunctions::print("[MaterialSimulatorNative] sim ready (store-backed)");
	} else {
		UtilityFunctions::push_warning("[MaterialSimulatorNative] initialize called with null store");
	}
}

void MaterialSimulatorNative::place_fluid(const Vector3i &pos, int fluid_id) {
	_write_cell(pos, static_cast<uint16_t>(fluid_id));
}

void MaterialSimulatorNative::remove_voxel(const Vector3i &pos) {
	_write_cell(pos, MAT_AIR);
}

void MaterialSimulatorNative::sync_voxel(const Vector3i &pos, int voxel_id) {
	_write_cell(pos, static_cast<uint16_t>(voxel_id));
}

int MaterialSimulatorNative::get_active_cell_count() const {
	if (!_store) return 0;
	auto loaded = _store->loaded_chunks();
	return static_cast<int>(loaded.size()) * CHUNK_VOL;
}

double MaterialSimulatorNative::get_last_tick_ms() const {
	return _last_tick_usec / 1000.0;
}

int MaterialSimulatorNative::get_last_changes_count() const {
	return _last_changes_count;
}

// ── Main-thread write (between ticks) ──

void MaterialSimulatorNative::_write_cell(const Vector3i &world_pos, uint16_t val) {
	if (!_store) return;
	// Goes through the store's write_voxel, which also bumps dirty_version so the
	// mesher re-meshes the affected chunk.
	_store->write_voxel(world_pos.x, world_pos.y, world_pos.z, val);
}

// ── Physics process ──

void MaterialSimulatorNative::_physics_process(double delta) {
	if (!_sim_ready) return;

	_sim_timer += delta;
	if (_sim_timer < 0.05) return;
	_sim_timer -= 0.05;
	_tick_count++;
	_dispatch_tick();
}

// ── Dispatch tick ──

void MaterialSimulatorNative::_dispatch_tick() {
	int64_t t0 = Time::get_singleton()->get_ticks_usec();

	if (!_store) {
		_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;
		return;
	}

	std::vector<VoxelChunkStore::Chunk *> all_loaded = _store->loaded_chunks();
	if (all_loaded.empty()) {
		_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;
		return;
	}

	// Filter to active chunks + their 4 horizontal neighbors (cross-chunk reactions).
	std::unordered_set<VoxelChunkStore::Chunk *> active_set;
	for (auto *c : all_loaded) {
		if (c->sim_active.load(std::memory_order_relaxed)) {
			active_set.insert(c);
			// Include neighbors so edge reactions propagate.
			auto add_neighbor = [&](int ncx, int ncz) {
				auto *n = _store->chunk_at(ncx, ncz);
				if (n && n->state.load(std::memory_order_acquire) == VoxelChunkStore::Chunk::LOADED) {
					active_set.insert(n);
				}
			};
			add_neighbor(c->wcx - 1, c->wcz);
			add_neighbor(c->wcx + 1, c->wcz);
			add_neighbor(c->wcx, c->wcz - 1);
			add_neighbor(c->wcx, c->wcz + 1);
		}
	}
	std::vector<VoxelChunkStore::Chunk *> loaded(active_set.begin(), active_set.end());
	if (loaded.empty()) {
		_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;
		return;
	}

	// Seed next_buf with current state — workers overwrite only cells they touch.
	for (auto *c : loaded) {
		std::memcpy(c->next_buf, c->current, CHUNK_VOL * sizeof(uint16_t));
	}

	int parity = _tick_count % 2;
	int num_chunks = (int)loaded.size();
	std::thread workers[NUM_WORKERS];

	for (int w = 0; w < NUM_WORKERS; w++) {
		int c_start = w * num_chunks / NUM_WORKERS;
		int c_end = (w + 1) * num_chunks / NUM_WORKERS;

		workers[w] = std::thread([this, &loaded, c_start, c_end, parity]() {
			for (int ci = c_start; ci < c_end; ci++) {
				VoxelChunkStore::Chunk *chunk = loaded[ci];
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

	// Swap current/next_buf per chunk; bump generation+dirty_version for touched chunks.
	// memcmp is SIMD-accelerated — one ~115 KB compare per chunk is cheap.
	int total_changes = 0;
	for (auto *c : loaded) {
		if (std::memcmp(c->current, c->next_buf, CHUNK_VOL * sizeof(uint16_t)) == 0) {
			std::swap(c->current, c->next_buf);
			continue;
		}
		// Count per-cell diffs for diagnostics (not exactness-critical).
		int chunk_changes = 0;
		for (int i = 0; i < CHUNK_VOL; i++) {
			if (c->current[i] != c->next_buf[i]) chunk_changes++;
		}
		total_changes += chunk_changes;

		std::swap(c->current, c->next_buf);
		c->generation.fetch_add(1, std::memory_order_release);
		c->dirty_version.fetch_add(1, std::memory_order_relaxed);
	}

	// Clear sim_active on chunks that had zero changes and contain no simulatable cells.
	for (auto *c : loaded) {
		if (std::memcmp(c->current, c->next_buf, CHUNK_VOL * sizeof(uint16_t)) != 0) {
			// Had changes — stays active.
			continue;
		}
		// Scan for remaining simulatable cells. Early-exit on first find.
		bool still_active = false;
		for (int i = 0; i < CHUNK_VOL; i++) {
			uint16_t v = c->current[i];
			if (is_fluid(v) || is_gas(v) || is_powder(v)) {
				still_active = true;
				break;
			}
		}
		if (!still_active) {
			c->sim_active.store(false, std::memory_order_relaxed);
		}
	}

	_last_changes_count = total_changes;
	_last_tick_usec = Time::get_singleton()->get_ticks_usec() - t0;

	if (_tick_count <= 5 || _tick_count % 120 == 0) {
		UtilityFunctions::print(String("[MaterialSimulatorNative] tick {0}: {1} changes, {2} ms, {3}/{4} active")
				.format(Array::make(_tick_count, _last_changes_count, get_last_tick_ms(),
						(int)loaded.size(), (int)all_loaded.size())));
	}
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
			if (dirs[i][1] == 1) continue; // surface water on top → no reaction
			return MAT_MUD;
		}

		// LAVA + SAND → GLASS (lava cell stays, sand becomes glass)
		if (my_base == MAT_LAVA && ni_base == 9 /*SAND*/) {
			_write_next(nx, ny, nz, 12 /*GLASS*/);
			return MAT_LAVA;
		}
		if (my_base == 9 /*SAND*/ && ni_base == MAT_LAVA) {
			return 12; // GLASS
		}

		// ACID + STONE → dissolves (acid stays, stone becomes air)
		if (my_base == MAT_ACID && ni_base == MAT_STONE) {
			_write_next(nx, ny, nz, MAT_AIR);
			return MAT_ACID;
		}

		// OIL(72) + LAVA → SMOKE(18) + EMBER(64)
		if (my_base == 72 /*OIL*/ && ni_base == MAT_LAVA) {
			return 18; // SMOKE
		}
		if (my_base == MAT_LAVA && ni_base == 72 /*OIL*/) {
			_write_next(nx, ny, nz, 64 /*EMBER*/);
			return MAT_LAVA;
		}

		// GUNPOWDER(14) + LAVA/EMBER(64) → STEAM(8) (explosive)
		if (my_base == 14 /*GUNPOWDER*/ && (ni_base == MAT_LAVA || ni_base == 64)) {
			return MAT_GAS; // STEAM
		}

		// POISON(95) + WATER → both become TOXIC_GAS(19)
		if (my_base == 95 /*POISON*/ && ni_base == MAT_WATER) {
			_write_next(nx, ny, nz, 19 /*TOXIC_GAS*/);
			return 19;
		}
		if (my_base == MAT_WATER && ni_base == 95 /*POISON*/) {
			_write_next(nx, ny, nz, 19 /*TOXIC_GAS*/);
			return 19;
		}

		// EMBER(64) + WOOD(20) → LAVA (ignition)
		if (my_base == 64 /*EMBER*/ && ni_base == 20 /*WOOD*/) {
			_write_next(nx, ny, nz, MAT_LAVA);
			return MAT_LAVA;
		}
	}
	return NO_REACTION;
}

void MaterialSimulatorNative::_sim_fluid(int x, int y, int z, uint16_t id) {
	uint8_t id_base = base_material(id);
	if (id_base == MAT_LAVA && (_tick_count % 3) != 0) {
		_write_next(x, y, z, id);
		return;
	}

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

	if (base_material(below) == MAT_AIR) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, MAT_AIR);
		return;
	}

	if (is_gas(below)) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, below);
		return;
	}

	if (is_solid(below)) {
		_write_next(x, y, z, id);
		return;
	}

	// On fluid: cascade through diagonal-down, horizontal-toward-drop, random-spread.
	// Only clear the source cell when the move actually lands — otherwise the fluid
	// voxel is lost to target contention.
	int start = hash & 7;
	for (int i = 0; i < 8; i++) {
		int di = (start + i) & 7;
		int nx = x + dirs8[di][0], nz = z + dirs8[di][1];
		uint16_t side = _read_raw(nx, y, nz);
		if (is_solid(side) || side == NOT_LOADED) continue;
		uint16_t diag = _read_raw(nx, y - 1, nz);
		if (base_material(diag) == MAT_AIR) {
			if (_write_next_if_unchanged(nx, y - 1, nz, id)) {
				_write_next(x, y, z, MAT_AIR);
			} else {
				_write_next(x, y, z, id);
			}
			return;
		}
	}

	start = (hash >> 3) & 7;
	for (int i = 0; i < 8; i++) {
		int di = (start + i) & 7;
		int nx = x + dirs8[di][0], nz = z + dirs8[di][1];
		uint16_t side = _read_raw(nx, y, nz);
		if (base_material(side) != MAT_AIR) continue;
		uint16_t side_below = _read_raw(nx, y - 1, nz);
		if (base_material(side_below) == MAT_AIR || is_gas(side_below)) {
			if (_write_next_if_unchanged(nx, y, nz, id)) {
				_write_next(x, y, z, MAT_AIR);
			} else {
				_write_next(x, y, z, id);
			}
			return;
		}
	}

	int dir = (hash >> 6) & 7;
	int nx = x + dirs8[dir][0], nz = z + dirs8[dir][1];
	if (base_material(_read_raw(nx, y, nz)) == MAT_AIR) {
		if (_write_next_if_unchanged(nx, y, nz, id)) {
			_write_next(x, y, z, MAT_AIR);
		} else {
			_write_next(x, y, z, id);
		}
		return;
	}

	_write_next(x, y, z, id);
}

void MaterialSimulatorNative::_sim_gas(int x, int y, int z, uint16_t id) {
	if ((_tick_count >> 1) % 2 != 0) {
		_write_next(x, y, z, id);
		return;
	}

	uint32_t hash = static_cast<uint32_t>(
		(x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (_tick_count * 2654435761u));
	if ((hash & 0xF) == 0) {
		_write_next(x, y, z, MAT_AIR);
		return;
	}

	uint16_t above = _read_raw(x, y + 1, z);

	if (base_material(above) == MAT_AIR) {
		_write_next(x, y + 1, z, id);
		_write_next(x, y, z, MAT_AIR);
		return;
	}
	if (is_fluid(above)) {
		_write_next(x, y + 1, z, id);
		_write_next(x, y, z, above);
		return;
	}

	const int cd[4][3] = {{1,0,0}, {-1,0,0}, {0,0,1}, {0,0,-1}};
	int start_dir = (hash >> 4) & 3;
	for (int i = 0; i < 4; i++) {
		int di = (start_dir + i) & 3;
		int nx = x + cd[di][0], nz = z + cd[di][2];
		if (base_material(_read_raw(nx, y, nz)) == MAT_AIR) {
			if (_write_next_if_unchanged(nx, y, nz, id)) {
				_write_next(x, y, z, MAT_AIR);
			} else {
				_write_next(x, y, z, id);
			}
			return;
		}
	}

	_write_next(x, y, z, id);
}

void MaterialSimulatorNative::_sim_powder(int x, int y, int z, uint16_t id) {
	uint16_t rx = _react(x, y, z, id);
	if (rx != NO_REACTION) {
		_write_next(x, y, z, rx);
		return;
	}

	uint16_t below = _read_raw(x, y - 1, z);

	// Fall straight down into air.
	if (base_material(below) == MAT_AIR) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, MAT_AIR);
		return;
	}

	// Sink through gas (swap).
	if (is_gas(below)) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, below);
		return;
	}

	// Sink through fluid (swap — powder is heavier).
	if (is_fluid(below)) {
		_write_next(x, y - 1, z, id);
		_write_next(x, y, z, below);
		return;
	}

	// On solid or powder: try diagonal pile (slide down a slope).
	static constexpr int diag4[4][2] = {{1,0},{-1,0},{0,1},{0,-1}};
	uint32_t hash = static_cast<uint32_t>(
		(x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (_tick_count * 2654435761u));
	int start = hash & 3;
	for (int i = 0; i < 4; i++) {
		int di = (start + i) & 3;
		int nx = x + diag4[di][0], nz = z + diag4[di][1];
		uint16_t side = _read_raw(nx, y, nz);
		if (base_material(side) != MAT_AIR) continue;
		uint16_t diag = _read_raw(nx, y - 1, nz);
		if (base_material(diag) == MAT_AIR) {
			if (_write_next_if_unchanged(nx, y - 1, nz, id)) {
				_write_next(x, y, z, MAT_AIR);
			} else {
				_write_next(x, y, z, id);
			}
			return;
		}
	}

	// Can't move: stay (pile settled).
	_write_next(x, y, z, id);
}

void MaterialSimulatorNative::_sim_cell(int x, int y, int z) {
	uint16_t id = _read_raw(x, y, z);
	uint8_t id_base = base_material(id);

	if (id_base == MAT_AIR || id_base == MAT_BEDROCK || id == NOT_LOADED) {
		return;
	}

	if (is_powder(id)) {
		_sim_powder(x, y, z, id);
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

} // namespace godot
