#ifndef MATERIAL_SIMULATOR_NATIVE_H
#define MATERIAL_SIMULATOR_NATIVE_H

#include "voxel_chunk_store.h"
#include "voxel_coord.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <thread>
#include <vector>

namespace godot {

class MaterialSimulatorNative : public Node {
	GDCLASS(MaterialSimulatorNative, Node)

public:
	static constexpr int CHUNK_X = voxl::CHUNK_X;
	static constexpr int CHUNK_Y = voxl::CHUNK_Y;
	static constexpr int CHUNK_Z = voxl::CHUNK_Z;
	static constexpr int CHUNK_VOL = voxl::CHUNK_VOL;

	static constexpr float VOXEL_SCALE = voxl::VOXEL_SCALE;
	static constexpr float INV_VOXEL_SCALE = voxl::INV_VOXEL_SCALE;

	static constexpr uint8_t MAT_AIR     = 0;
	static constexpr uint8_t MAT_STONE   = 1;
	static constexpr uint8_t MAT_BEDROCK = 2;
	static constexpr uint8_t MAT_WATER   = 3;
	static constexpr uint8_t MAT_DIRT    = 4;
	static constexpr uint8_t MAT_MUD     = 5;
	static constexpr uint8_t MAT_LAVA    = 6;
	static constexpr uint8_t MAT_ACID    = 7;
	static constexpr uint8_t MAT_GAS     = 8;
	static constexpr uint16_t NOT_LOADED  = voxl::NOT_LOADED;
	static constexpr uint16_t NO_REACTION = voxl::NO_REACTION;

	static constexpr int NUM_WORKERS = 8;

	MaterialSimulatorNative();
	~MaterialSimulatorNative();

	void initialize(VoxelChunkStore *store, Node3D *player);
	void place_fluid(const Vector3i &pos, int fluid_id);
	void remove_voxel(const Vector3i &pos);
	void sync_voxel(const Vector3i &pos, int voxel_id);

	int get_active_cell_count() const;
	double get_last_tick_ms() const;
	int get_last_changes_count() const;

	void _physics_process(double delta);

protected:
	static void _bind_methods();

private:
	// ── Material helpers (base material = low byte) ──

	static inline uint8_t base_material(uint16_t id) { return id & 0xFF; }
	static inline uint8_t visual_variant(uint16_t id) { return (id >> 8) & 0xFF; }
	static inline uint16_t make_voxel_id(uint8_t base, uint8_t visual) {
		return (static_cast<uint16_t>(visual) << 8) | base;
	}

	static inline bool is_fluid(uint16_t id) {
		uint8_t b = base_material(id);
		return b == MAT_WATER || b == MAT_LAVA || b == MAT_ACID ||
				b == 32 || b == 42 || b == 47 || b == 50 || b == 55 ||
				b == 62 || b == 65 || b == 72 || b == 75 || b == 82 || b == 86 ||
				(b >= 90 && b <= 102) || (b >= 104 && b <= 113) || b == 122 || b == 36;
	}
	static inline bool is_gas(uint16_t id) {
		uint8_t b = base_material(id);
		return b == MAT_GAS || b == 18 || b == 19 || b == 43 || b == 52 ||
				b == 74 || b == 83 || b == 103;
	}
	static inline bool is_powder(uint16_t id) {
		uint8_t b = base_material(id);
		return b == MAT_MUD || b == 9 || b == 10 || b == 13 || b == 14 ||
				b == 15 || b == 16 || b == 17 || b == 31 || b == 46 ||
				b == 51 || b == 61 || b == 63 || b == 64 || b == 73 ||
				b == 76 || b == 114;
	}
	static inline bool is_solid(uint16_t id) {
		uint8_t b = base_material(id);
		return b != MAT_AIR && !is_fluid(id) && !is_gas(id) && !is_powder(id);
	}

	static inline int world_to_voxel(float w) {
		return int(Math::floor(w * INV_VOXEL_SCALE));
	}

	// ── State ──

	VoxelChunkStore *_store = nullptr;
	Node3D *_player = nullptr;
	int _origin_y = 0;

	double _sim_timer = 0.0;
	int _tick_count = 0;
	int64_t _last_tick_usec = 0;
	int _last_changes_count = 0;
	bool _sim_ready = false;

	// ── Tick pipeline ──

	void _dispatch_tick();

	// ── Main-thread write (between ticks) ──

	void _write_cell(const Vector3i &world_pos, uint16_t val);

	// ── Per-cell simulation (wx/wz = world voxel coords, ly = local Y 0..CHUNK_Y-1) ──

	inline uint16_t _read_raw(int wx, int ly, int wz) const {
		if (ly < 0 || ly >= CHUNK_Y) return MAT_BEDROCK;
		if (!_store) return NOT_LOADED;
		VoxelChunkStore::Chunk *c = _store->chunk_at(voxl::chunk_coord_x(wx), voxl::chunk_coord_z(wz));
		if (!c || c->state.load(std::memory_order_acquire) != VoxelChunkStore::Chunk::LOADED) {
			return NOT_LOADED;
		}
		int lx = voxl::local_coord_x(wx), lz = voxl::local_coord_z(wz);
		return c->current[voxl::voxel_index(lx, ly, lz)];
	}

	inline void _write_next(int wx, int ly, int wz, uint16_t val) {
		if (ly < 0 || ly >= CHUNK_Y || !_store) return;
		VoxelChunkStore::Chunk *c = _store->chunk_at(voxl::chunk_coord_x(wx), voxl::chunk_coord_z(wz));
		if (!c || c->state.load(std::memory_order_acquire) != VoxelChunkStore::Chunk::LOADED) return;
		int lx = voxl::local_coord_x(wx), lz = voxl::local_coord_z(wz);
		c->next_buf[voxl::voxel_index(lx, ly, lz)] = val;
	}

	// Writes val into next_buf only if the target slot has not been claimed by another
	// write this tick. Returns true when the write lands; callers rely on the return
	// value to decide whether to clear the source cell, keeping fluid/gas counts
	// conserved under contention.
	inline bool _write_next_if_unchanged(int wx, int ly, int wz, uint16_t val) {
		if (ly < 0 || ly >= CHUNK_Y || !_store) return false;
		VoxelChunkStore::Chunk *c = _store->chunk_at(voxl::chunk_coord_x(wx), voxl::chunk_coord_z(wz));
		if (!c || c->state.load(std::memory_order_acquire) != VoxelChunkStore::Chunk::LOADED) return false;
		int lx = voxl::local_coord_x(wx), lz = voxl::local_coord_z(wz);
		int idx = voxl::voxel_index(lx, ly, lz);
		if (c->next_buf[idx] != c->current[idx]) return false;
		c->next_buf[idx] = val;
		return true;
	}

	uint16_t _react(int wx, int ly, int wz, uint16_t my_id);
	void _sim_fluid(int wx, int ly, int wz, uint16_t id);
	void _sim_gas(int wx, int ly, int wz, uint16_t id);
	void _sim_powder(int wx, int ly, int wz, uint16_t id);
	void _sim_cell(int wx, int ly, int wz);
};

} // namespace godot

#endif // MATERIAL_SIMULATOR_NATIVE_H
