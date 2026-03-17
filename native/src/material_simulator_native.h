#ifndef MATERIAL_SIMULATOR_NATIVE_H
#define MATERIAL_SIMULATOR_NATIVE_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/time.hpp>

#include <mutex>
#include <thread>
#include <chrono>
#include <atomic>
#include <vector>
#include <unordered_set>
#include <cstring>
#include <algorithm>
#include <queue>
#include <condition_variable>

namespace godot {

class MaterialSimulatorNative : public Node {
	GDCLASS(MaterialSimulatorNative, Node)

public:
	static constexpr int CHUNK_X = 32;
	static constexpr int CHUNK_Y = 32;
	static constexpr int CHUNK_Z = 32;
	static constexpr int CHUNK_VOL = CHUNK_X * CHUNK_Y * CHUNK_Z;

	static constexpr int GRID_W = 11;
	static constexpr int GRID_H = 11;
	static constexpr int LOAD_RADIUS = 5;
	static constexpr int TOTAL_CHUNKS = GRID_W * GRID_H;

	static constexpr uint8_t MAT_AIR        = 0;
	static constexpr uint8_t MAT_STONE      = 1;
	static constexpr uint8_t MAT_BEDROCK    = 2;
	static constexpr uint8_t MAT_WATER_BASE = 3;
	static constexpr uint8_t MAT_DIRT       = 11;
	static constexpr uint8_t MAT_MUD        = 12;
	static constexpr uint8_t MAT_LAVA_BASE  = 13;
	static constexpr uint8_t MAT_ACID_BASE  = 21;
	static constexpr uint8_t MAT_GAS_BASE   = 29;
	static constexpr uint8_t NOT_LOADED     = 0x7F;
	static constexpr uint8_t NO_REACTION    = 0xFF;

	static constexpr int FLUID_LEVELS    = 8;
	static constexpr uint8_t SOURCE_FLAG = 0x80;
	static constexpr uint8_t ID_MASK     = 0x7F;

	static constexpr int APPLY_CHANGES_CAP = 256;
	static constexpr int NUM_WORKERS = 8;
	static constexpr int NUM_LOADERS = 4;

	MaterialSimulatorNative();
	~MaterialSimulatorNative();

	void initialize(Object *p_terrain, Node3D *p_player);
	void place_fluid(const Vector3i &pos, int fluid_base, int level = FLUID_LEVELS - 1);
	void remove_voxel(const Vector3i &pos);
	void sync_voxel(const Vector3i &pos, int voxel_id);

	int get_active_cell_count() const;
	int get_source_block_count() const;
	double get_last_tick_ms() const;
	int get_last_changes_count() const;

	void _physics_process(double delta);
	void _notification(int p_what);

protected:
	static void _bind_methods();

private:
	// ── Material helpers ──

	static inline uint8_t encode(int id, bool is_source) {
		return static_cast<uint8_t>((id & ID_MASK) | (is_source ? SOURCE_FLAG : 0));
	}
	static inline uint8_t mid(uint8_t raw) { return raw & ID_MASK; }
	static inline bool src(uint8_t raw) { return (raw & SOURCE_FLAG) != 0; }

	static inline uint8_t fbase(uint8_t id) {
		if (id >= MAT_WATER_BASE && id < MAT_WATER_BASE + FLUID_LEVELS) return MAT_WATER_BASE;
		if (id >= MAT_LAVA_BASE  && id < MAT_LAVA_BASE  + FLUID_LEVELS) return MAT_LAVA_BASE;
		if (id >= MAT_ACID_BASE  && id < MAT_ACID_BASE  + FLUID_LEVELS) return MAT_ACID_BASE;
		if (id >= MAT_GAS_BASE   && id < MAT_GAS_BASE   + FLUID_LEVELS) return MAT_GAS_BASE;
		return 0;
	}
	static inline uint8_t flvl(uint8_t id) {
		uint8_t b = fbase(id);
		return (b > 0) ? (id - b) : 0;
	}
	static inline uint8_t mkfluid(uint8_t base, int level, bool s) {
		uint8_t id = base + static_cast<uint8_t>(CLAMP(level, 0, FLUID_LEVELS - 1));
		return s ? (id | SOURCE_FLAG) : id;
	}
	static inline bool is_fluid(uint8_t id) {
		uint8_t b = fbase(id);
		return b == MAT_WATER_BASE || b == MAT_LAVA_BASE || b == MAT_ACID_BASE;
	}
	static inline bool is_gas(uint8_t id) { return fbase(id) == MAT_GAS_BASE; }
	static inline bool is_solid(uint8_t id) { return id != MAT_AIR && !is_fluid(id) && !is_gas(id); }
	static inline int spread_loss(uint8_t base) { return (base == MAT_LAVA_BASE) ? 2 : 1; }

	// ── Chunk coordinate helpers (CHUNK = 32 = 2^5, uses arithmetic right shift) ──

	static inline int _chunk_coord(int w) { return w >> 5; }
	static inline int _local_coord(int w) { return w & 0x1F; }

	// ── SimChunk ──

	struct SimChunk {
		uint8_t buf_a[CHUNK_VOL];
		uint8_t buf_b[CHUNK_VOL];
		uint8_t *current = buf_a;
		uint8_t *next_buf = buf_b;
		int wcx = 0, wcz = 0;
		enum State : uint8_t { UNLOADED, LOADING, LOADED } state = UNLOADED;
	};

	SimChunk *_chunks = nullptr;
	SimChunk *_grid[GRID_W][GRID_H] = {};
	int _center_cx = 0, _center_cz = 0;
	int _origin_y = -16;

	SimChunk *_chunk_at(int cx, int cz) const;

	// ── Terrain ──

	Object *_terrain = nullptr;
	Ref<RefCounted> _voxel_tool;
	Node3D *_player = nullptr;

	// ── State ──

	double _sim_timer = 0.0;
	int _tick_count = 0;
	int _terrain_poll_counter = 0;
	int64_t _last_tick_usec = 0;
	int _last_changes_count = 0;
	bool _sim_ready = false;
	std::unordered_set<int64_t> _source_positions;

	// ── Chunk loader thread pool ──

	struct ChunkLoadRequest {
		SimChunk *chunk;
		int wcx, wcz;
	};
	struct ChunkLoadResult {
		SimChunk *chunk;
		int wcx, wcz;
		uint8_t data[CHUNK_VOL];
	};

	std::vector<std::thread> _loader_threads;
	std::vector<Ref<RefCounted>> _loader_voxel_tools;
	std::mutex _loader_queue_mutex;
	std::condition_variable _loader_cv;
	std::queue<ChunkLoadRequest> _loader_queue;
	std::mutex _loader_result_mutex;
	std::vector<ChunkLoadResult *> _loader_results;
	std::atomic<bool> _loaders_running{false};

	void _start_loaders();
	void _stop_loaders();
	void _loader_thread_func(int loader_id);
	void _drain_loader_results();
	void _queue_chunk_load(SimChunk *chunk, int wcx, int wcz);

	// ── Deferred changes ──

	struct DeferredChange {
		Vector3i world_pos;
		int new_type;
	};
	std::vector<DeferredChange> _deferred_changes;

	// ── Lifecycle ──

	void _wait_for_terrain();
	void _setup_sim();
	void _init_grid();

	// ── Buffer writes ──

	void _write_cell(const Vector3i &world_pos, uint8_t val);

	// ── Tick ──

	void _dispatch_tick();
	void _collect_and_apply_changes();
	void _process_deferred_changes();

	// ── Grid management ──

	void _recenter_grid();
	void _unload_chunk(SimChunk *chunk);

	// ── Simulation (wx/wz = world coords, wy = local Y 0..CHUNK_Y-1) ──

	inline uint8_t _read_raw(int wx, int wy, int wz) const {
		if (wy < 0 || wy >= CHUNK_Y) return MAT_BEDROCK;
		SimChunk *c = _chunk_at(_chunk_coord(wx), _chunk_coord(wz));
		if (!c) return MAT_BEDROCK;
		if (c->state != SimChunk::LOADED) return NOT_LOADED; // distinct from solid bedrock
		int lx = _local_coord(wx), lz = _local_coord(wz);
		return c->current[lx + wy * CHUNK_X + lz * CHUNK_X * CHUNK_Y];
	}

	inline void _write_next(int wx, int wy, int wz, uint8_t val) {
		if (wy < 0 || wy >= CHUNK_Y) return;
		SimChunk *c = _chunk_at(_chunk_coord(wx), _chunk_coord(wz));
		if (!c || c->state != SimChunk::LOADED) return;
		int lx = _local_coord(wx), lz = _local_coord(wz);
		c->next_buf[lx + wy * CHUNK_X + lz * CHUNK_X * CHUNK_Y] = val;
	}

	inline void _write_next_if_unchanged(int wx, int wy, int wz, uint8_t val) {
		if (wy < 0 || wy >= CHUNK_Y) return;
		SimChunk *c = _chunk_at(_chunk_coord(wx), _chunk_coord(wz));
		if (!c || c->state != SimChunk::LOADED) return;
		int lx = _local_coord(wx), lz = _local_coord(wz);
		int idx = lx + wy * CHUNK_X + lz * CHUNK_X * CHUNK_Y;
		if (c->next_buf[idx] != c->current[idx]) return;
		c->next_buf[idx] = val;
	}

	void _deplete_adjacent_source(int wx, int wy, int wz, uint8_t base);
	uint8_t _react(int wx, int wy, int wz, uint8_t my_id, uint8_t my_raw);
	bool _is_fed(int wx, int wy, int wz, uint8_t base, uint8_t level) const;
	void _sim_fluid(int wx, int wy, int wz, uint8_t raw);
	void _sim_gas(int wx, int wy, int wz, uint8_t raw);
	void _sim_cell(int wx, int wy, int wz);

	// ── Utilities ──

	static int64_t _pos_key(const Vector3i &p) {
		return (int64_t(p.x) & 0xFFFFF) | ((int64_t(p.y) & 0xFFF) << 20) | ((int64_t(p.z) & 0xFFFFF) << 32);
	}

	static Vector3i _decode_pos_key(int64_t key) {
		int x = (int)(key & 0xFFFFF);
		if (x & 0x80000) x -= 0x100000;
		int y = (int)((key >> 20) & 0xFFF);
		if (y & 0x800) y -= 0x1000;
		int z = (int)((key >> 32) & 0xFFFFF);
		if (z & 0x80000) z -= 0x100000;
		return Vector3i(x, y, z);
	}

	int _voxel_get(const Ref<RefCounted> &tool, const Vector3i &pos) const;
	bool _voxel_set(const Vector3i &pos, int value); // returns false if area not editable
};

} // namespace godot

#endif
