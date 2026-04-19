#ifndef VOXL_VOXEL_CHUNK_STORE_H
#define VOXL_VOXEL_CHUNK_STORE_H

#include "voxel_coord.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

namespace godot {

class VoxelChunkStore : public Node {
	GDCLASS(VoxelChunkStore, Node)

public:
	struct Chunk {
		alignas(64) uint16_t voxels[voxl::CHUNK_VOL];
		alignas(64) uint16_t voxels_next[voxl::CHUNK_VOL];
		uint16_t *current = voxels;
		uint16_t *next_buf = voxels_next;
		int wcx = 0;
		int wcz = 0;
		enum State : uint8_t { UNLOADED = 0, LOADING = 1, LOADED = 2 };
		std::atomic<uint8_t> state{UNLOADED};
		std::atomic<uint32_t> generation{0};
		std::atomic<uint32_t> dirty_version{0};
		std::atomic<bool> sim_active{false};
	};

	using GeneratorFn = std::function<void(int wcx, int wcz, int origin_y, uint16_t *out)>;
	using DirtyCallback = std::function<void(int wcx, int wcz)>;

	static constexpr int NUM_LOADERS = 4;

	VoxelChunkStore();
	~VoxelChunkStore();

	void set_sim_radius(int radius);
	int get_sim_radius() const { return _sim_radius; }

	void set_origin_y(int origin_y) { _origin_y = origin_y; }
	int get_origin_y() const { return _origin_y; }

	// C++ API: set a custom generator. Default is flat-terrain.
	void set_generator_fn(GeneratorFn fn);

	// GDScript API: initialize with an anchor Node3D (player, camera, etc.)
	// and start loader threads. Called once from scene setup.
	void initialize(Node3D *anchor, int sim_radius);

	void stop();

	// Main-thread tick: drains loader results, recenters around anchor if moved.
	// Call from owning node's _process.
	void tick();

	// ── Hot-path C++ accessors (no locks; readers see atomic state) ──

	Chunk *chunk_at(int cx, int cz) const;

	// Snapshot of currently-loaded chunks (main thread only — called between store->tick()
	// invocations, so the grid is not being reshuffled concurrently).
	std::vector<Chunk *> loaded_chunks() const;

	// Notify dirty subscribers without writing a voxel. Used when an external system
	// (e.g. the sim) has already modified chunk contents and wants VoxelWorld to re-mesh.
	void notify_dirty(int wcx, int wcz);

	inline uint16_t read_voxel(int wx, int wy, int wz) const {
		int ly = wy - _origin_y;
		if (ly < 0 || ly >= voxl::CHUNK_Y) return voxl::NOT_LOADED;
		Chunk *c = chunk_at(voxl::chunk_coord_x(wx), voxl::chunk_coord_z(wz));
		if (!c || c->state.load(std::memory_order_acquire) != Chunk::LOADED) {
			return voxl::NOT_LOADED;
		}
		int lx = voxl::local_coord_x(wx);
		int lz = voxl::local_coord_z(wz);
		return c->current[voxl::voxel_index(lx, ly, lz)];
	}

	inline bool write_voxel(int wx, int wy, int wz, uint16_t val) {
		int ly = wy - _origin_y;
		if (ly < 0 || ly >= voxl::CHUNK_Y) return false;
		Chunk *c = chunk_at(voxl::chunk_coord_x(wx), voxl::chunk_coord_z(wz));
		if (!c || c->state.load(std::memory_order_acquire) != Chunk::LOADED) return false;
		int lx = voxl::local_coord_x(wx);
		int lz = voxl::local_coord_z(wz);
		c->current[voxl::voxel_index(lx, ly, lz)] = val;
		c->dirty_version.fetch_add(1, std::memory_order_relaxed);
		c->generation.fetch_add(1, std::memory_order_release);
		if (val != 0) c->sim_active.store(true, std::memory_order_relaxed);
		return true;
	}

	// ── Dirty subscriber registration (C++) ──
	void subscribe_dirty(DirtyCallback cb);

	// ── GDScript-bound methods ──
	int gd_get_voxel(const Vector3i &world_pos) const;
	bool gd_set_voxel(const Vector3i &world_pos, int value);
	int gd_get_chunk_generation(const Vector2i &chunk_coord) const;
	int gd_get_chunk_state(const Vector2i &chunk_coord) const;
	int gd_loaded_chunk_count() const;
	Dictionary gd_self_test();

	void _notification(int p_what);

protected:
	static void _bind_methods();

private:
	// ── Grid ──
	int _sim_radius = 7;
	int _origin_y = 0;
	Node3D *_anchor = nullptr;
	bool _started = false;

	Chunk *_chunks = nullptr;
	std::vector<Chunk *> _grid;
	int _center_cx = 0;
	int _center_cz = 0;

	int _grid_w() const { return _sim_radius * 2 + 1; }
	int _grid_h() const { return _sim_radius * 2 + 1; }
	int _total_chunks() const { return _grid_w() * _grid_h(); }
	Chunk *&_grid_at(int gx, int gz) { return _grid[gx + gz * _grid_w()]; }
	Chunk *_grid_at(int gx, int gz) const { return _grid[gx + gz * _grid_w()]; }

	void _reallocate_chunks();
	void _init_grid();
	void _recenter_grid();
	void _unload_chunk(Chunk *c);
	void _queue_chunk_load(Chunk *c, int wcx, int wcz);

	// ── Loader pool ──
	struct LoadRequest {
		Chunk *chunk;
		int wcx;
		int wcz;
	};
	struct LoadResult {
		Chunk *chunk;
		int wcx;
		int wcz;
		uint16_t data[voxl::CHUNK_VOL];
	};

	std::vector<std::thread> _loader_threads;
	std::mutex _loader_queue_mutex;
	std::condition_variable _loader_cv;
	std::queue<LoadRequest> _loader_queue;
	std::mutex _loader_result_mutex;
	std::vector<LoadResult *> _loader_results;
	std::atomic<bool> _loaders_running{false};

	void _start_loaders();
	void _stop_loaders();
	void _loader_thread_func(int id);
	void _drain_loader_results();

	// ── Generator ──
	GeneratorFn _generator;
	static void _flat_terrain_generator(int wcx, int wcz, int origin_y, uint16_t *out);

	// ── Dirty subscribers ──
	std::vector<DirtyCallback> _dirty_subscribers;
};

} // namespace godot

#endif // VOXL_VOXEL_CHUNK_STORE_H
