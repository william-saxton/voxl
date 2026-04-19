#ifndef VOXL_VOXEL_WORLD_H
#define VOXL_VOXEL_WORLD_H

#include "material_palette.h"
#include "voxel_mesher_pool.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>
#include <memory>
#include <unordered_map>

namespace godot {

class VoxelChunkStore;
class VoxelMesherPool;
class MeshInstance3D;
class StaticBody3D;
class CollisionShape3D;

class VoxelWorld : public Node3D {
	GDCLASS(VoxelWorld, Node3D)

public:
	VoxelWorld();
	~VoxelWorld();

	void set_anchor_path(const NodePath &p);
	NodePath get_anchor_path() const { return _anchor_path; }

	void set_sim_radius(int r);
	int get_sim_radius() const { return _sim_radius; }

	void set_origin_y(int y);
	int get_origin_y() const { return _origin_y; }

	void set_palette(const Ref<MaterialPalette> &p);
	Ref<MaterialPalette> get_palette() const { return _palette; }

	void set_mesher_thread_count(int n);
	int get_mesher_thread_count() const { return _mesher_threads; }

	// ── Scripting facade ──
	int gd_get_voxel(const Vector3i &pos) const;
	bool gd_set_voxel(const Vector3i &pos, int value);
	// Batched write. positions: flat [x,y,z,x,y,z,...] (3*N ints). values: N ints.
	// Returns count of voxels actually written. One FFI instead of N — important for
	// bulk operations like explosion cleanup or debris landing.
	int gd_set_voxels(const PackedInt32Array &positions, const PackedInt32Array &values);
	// DDA raycast in world space. Returns a Dictionary with keys
	//   hit (bool), position (Vector3i), previous_position (Vector3i),
	//   normal (Vector3), voxel_id (int), distance (float)
	// or Variant() (null) when no voxel is hit within max_distance.
	Variant gd_raycast(const Vector3 &origin, const Vector3 &direction, float max_distance) const;

	// Direct store access for sim integration (Phase 4).
	VoxelChunkStore *get_store() const { return _store; }

	void _ready();
	void _process(double delta);
	void _notification(int p_what);

protected:
	static void _bind_methods();

private:
	NodePath _anchor_path;
	int _sim_radius = 7;
	int _origin_y = 0;
	int _mesher_threads = 4;
	Ref<MaterialPalette> _palette;

	VoxelChunkStore *_store = nullptr;
	std::unique_ptr<VoxelMesherPool> _mesher;
	Ref<StandardMaterial3D> _shared_material;

	Node3D *_anchor_node = nullptr;

	std::vector<MeshJobResult> _pending_mesh_results;

	struct ChunkRenderState {
		MeshInstance3D *mesh_node = nullptr;
		StaticBody3D *body_node = nullptr;
		CollisionShape3D *shape_node = nullptr;
		uint32_t last_applied_generation = 0;
		uint32_t last_queued_dirty_version = 0;
	};
	// Key = (int64)wcx << 32 | (uint32)wcz — fast hash, covers full int32 range via static_cast.
	std::unordered_map<int64_t, ChunkRenderState> _render_state;

	static int64_t _chunk_key(int wcx, int wcz) {
		return (static_cast<int64_t>(wcx) << 32) | static_cast<uint32_t>(wcz);
	}

	void _on_chunk_dirty(int wcx, int wcz);
	void _queue_mesh_job(int wcx, int wcz);
	void _apply_mesh_results();
	void _cleanup_orphan_render_nodes();
	void _poll_dirty_chunks();

	ChunkRenderState &_ensure_render_state(int wcx, int wcz);
};

} // namespace godot

#endif // VOXL_VOXEL_WORLD_H
