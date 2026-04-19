#ifndef VOXL_VOXEL_MESHER_POOL_H
#define VOXL_VOXEL_MESHER_POOL_H

#include "material_palette.h"
#include "voxel_coord.h"

#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <queue>
#include <thread>
#include <unordered_set>
#include <vector>

namespace godot {

class VoxelChunkStore;

struct MeshJobResult {
	int wcx = 0;
	int wcz = 0;
	uint32_t generation_snapshot = 0;
	PackedVector3Array verts;
	PackedColorArray colors;
	PackedVector3Array normals;
	PackedVector3Array collision_faces; // flat triangles
	bool discarded = false;
};

class VoxelMesherPool {
public:
	VoxelMesherPool();
	~VoxelMesherPool();

	void start(int num_threads);
	void stop();

	// Submit a mesh job for a chunk. Safe to call from main thread.
	void submit(VoxelChunkStore *store, int wcx, int wcz, Ref<MaterialPalette> palette, int origin_y);

	// Drain completed results to main thread. Call each frame.
	std::vector<MeshJobResult> drain_results();

private:
	struct Job {
		VoxelChunkStore *store;
		int wcx;
		int wcz;
		Ref<MaterialPalette> palette;
		int origin_y;
	};

	std::vector<std::thread> _workers;
	std::mutex _queue_mtx;
	std::condition_variable _queue_cv;
	std::queue<Job> _queue;
	std::unordered_set<int64_t> _queued_chunks; // dedup: (wcx<<32)|wcz

	std::mutex _result_mtx;
	std::vector<MeshJobResult> _results;

	std::atomic<bool> _running{false};

	void _worker_fn(int id);
	void _execute_job(const Job &job, MeshJobResult &out);
};

} // namespace godot

#endif // VOXL_VOXEL_MESHER_POOL_H
