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
#include <cstring>
#include <algorithm>
#include <queue>
#include <condition_variable>

namespace godot {

class MaterialSimulatorNative : public Node {
	GDCLASS(MaterialSimulatorNative, Node)

public:
	static constexpr int CHUNK_X = 32;
	static constexpr int CHUNK_Y = 112;
	static constexpr int CHUNK_Z = 32;
	static constexpr int CHUNK_VOL = CHUNK_X * CHUNK_Y * CHUNK_Z;

	static constexpr float VOXEL_SCALE = 0.25f;
	static constexpr float INV_VOXEL_SCALE = 4.0f;

	static constexpr uint8_t MAT_AIR     = 0;
	static constexpr uint8_t MAT_STONE   = 1;
	static constexpr uint8_t MAT_BEDROCK = 2;
	static constexpr uint8_t MAT_WATER   = 3;
	static constexpr uint8_t MAT_DIRT    = 4;
	static constexpr uint8_t MAT_MUD     = 5;
	static constexpr uint8_t MAT_LAVA    = 6;
	static constexpr uint8_t MAT_ACID    = 7;
	static constexpr uint8_t MAT_GAS     = 8;
	static constexpr uint8_t NOT_LOADED  = 0x7F;
	static constexpr uint8_t NO_REACTION = 0xFF;

	static constexpr int APPLY_CHANGES_CAP = 2048;
	static constexpr int NUM_WORKERS = 8;
	static constexpr int NUM_LOADERS = 4;

	MaterialSimulatorNative();
	~MaterialSimulatorNative();

	void initialize(Object *p_terrain, Node3D *p_player);
	void place_fluid(const Vector3i &pos, int fluid_id);
	void remove_voxel(const Vector3i &pos);
	void sync_voxel(const Vector3i &pos, int voxel_id);

	void set_sim_radius(int radius);
	int get_sim_radius() const;

	int get_active_cell_count() const;
	double get_last_tick_ms() const;
	int get_last_changes_count() const;

	void _physics_process(double delta);
	void _notification(int p_what);

protected:
	static void _bind_methods();

private:
	// ── Material helpers ──

	static inline bool is_fluid(uint8_t id) {
		return id == MAT_WATER || id == MAT_LAVA || id == MAT_ACID;
	}
	static inline bool is_gas(uint8_t id) { return id == MAT_GAS; }
	static inline bool is_solid(uint8_t id) {
		return id != MAT_AIR && !is_fluid(id) && !is_gas(id);
	}

	// ── World-to-voxel coordinate conversion ──

	static inline int world_to_voxel(float w) {
		return int(Math::floor(w * INV_VOXEL_SCALE));
	}

	// ── Chunk coordinate helpers (CHUNK = 32 = 2^5, uses arithmetic right shift) ──

	static inline int _chunk_coord(int w) { return w >> 5; }
	static inline int _local_coord(int w) { return w & 0x1F; }

	// ── Grid size (configurable from GDScript via sim_radius property) ──

	int _sim_radius = 7;
	int _grid_w() const { return _sim_radius * 2 + 1; }
	int _grid_h() const { return _sim_radius * 2 + 1; }
	int _total_chunks() const { return _grid_w() * _grid_h(); }

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
	std::vector<SimChunk *> _grid;
	int _center_cx = 0, _center_cz = 0;
	int _origin_y = 0;

	SimChunk *_chunk_at(int cx, int cz) const;

	// Grid access helpers
	SimChunk *& _grid_at(int gx, int gz) { return _grid[gx + gz * _grid_w()]; }
	SimChunk * _grid_at(int gx, int gz) const { return _grid[gx + gz * _grid_w()]; }

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
	void _reallocate_chunks();

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
		if (c->state != SimChunk::LOADED) return NOT_LOADED;
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

	uint8_t _react(int wx, int wy, int wz, uint8_t my_id);
	void _sim_fluid(int wx, int wy, int wz, uint8_t id);
	void _sim_gas(int wx, int wy, int wz, uint8_t id);
	void _sim_cell(int wx, int wy, int wz);

	// ── Utilities ──

	int _voxel_get(const Ref<RefCounted> &tool, const Vector3i &pos) const;
	bool _voxel_set(const Vector3i &pos, int value);
};

} // namespace godot

#endif
