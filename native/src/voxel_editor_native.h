#ifndef VOXEL_EDITOR_NATIVE_H
#define VOXEL_EDITOR_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/color.hpp>

#include <cstdint>
#include <vector>
#include <unordered_set>

namespace godot {

class VoxelEditorNative : public RefCounted {
	GDCLASS(VoxelEditorNative, RefCounted)

public:
	// Default tile dimensions (match WFCTileDef defaults)
	static constexpr int DEFAULT_TILE_X = 128;
	static constexpr int DEFAULT_TILE_Y = 112;
	static constexpr int DEFAULT_TILE_Z = 128;
	static constexpr int CHUNK_SIZE = 16;

	// Procedural shape preset IDs (must match GDScript ProceduralTool.PRESETS order)
	enum ProceduralShape {
		SHAPE_SPHERE = 0,
		SHAPE_HOLLOW_SPHERE,
		SHAPE_CYLINDER_Y,
		SHAPE_TORUS_Y,
		SHAPE_ARCH_Z,
		SHAPE_DOME,
		SHAPE_NOISE_TERRAIN,
		SHAPE_PYRAMID,
		SHAPE_CONE_Y,
		SHAPE_STAIRS_Z,
		SHAPE_SPIRAL_Y,
		SHAPE_CHECKERBOARD,
		SHAPE_CLEAR,
		SHAPE_COUNT,
	};

	VoxelEditorNative();
	~VoxelEditorNative();

	// ── Greedy chunk mesher ──
	// tile_x/y/z parameters allow variable tile sizes (default = 128x112x128)
	Ref<ArrayMesh> build_chunk_mesh(
			const PackedByteArray &voxel_data,
			int chunk_x, int chunk_y, int chunk_z,
			const PackedColorArray &palette_colors,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

	Ref<ArrayMesh> build_wireframe(
			const PackedByteArray &voxel_data,
			int chunk_x, int chunk_y, int chunk_z,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

	// ── DDA Raycast ──
	Dictionary raycast(
			const PackedByteArray &voxel_data,
			const Vector3 &origin, const Vector3 &direction, float max_dist,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

	// ── BFS operations ──
	PackedVector3Array flood_fill(
			const PackedByteArray &voxel_data,
			const Vector3i &start,
			int criteria, int range, int max_voxels,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

	PackedVector3Array flood_fill_air(
			const PackedByteArray &voxel_data,
			const Vector3i &start,
			int range, int max_voxels,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

	PackedVector3Array find_surface(
			const PackedByteArray &voxel_data,
			const Vector3i &start, const Vector3i &face_dir,
			int criteria, int range, int max_voxels,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

	// ── Bulk voxel writes ──
	// Writes voxel changes to voxel_data and returns dirty chunk indices.
	// changes: flat PackedInt32Array of [x, y, z, voxel_id, x, y, z, voxel_id, ...]
	// Returns Dictionary {"voxel_data": PackedByteArray, "dirty_chunks": PackedInt32Array}
	Dictionary bulk_set_voxels(
			PackedByteArray voxel_data,
			const PackedInt32Array &changes,
			int tile_x, int tile_y, int tile_z);

	// ── Mode-based shape apply (full pipeline in C++) ──
	// Reads old voxel IDs, applies mode logic, writes new IDs, returns undo diffs.
	// positions: flat [x, y, z, x, y, z, ...] (3 ints per position)
	// voxel_ids: one target voxel ID per position
	// mode: 0=ADD, 1=SUBTRACT, 2=PAINT
	// Returns {"voxel_data", "dirty_chunks", "undo_diffs":[x,y,z,old,new,...]}
	Dictionary apply_mode_changes(
			PackedByteArray voxel_data,
			const PackedInt32Array &positions,
			const PackedInt32Array &voxel_ids,
			int mode,
			int tile_x, int tile_y, int tile_z);

	// ── Apply packed undo diffs (for undo/redo) ──
	// packed_diffs: [x, y, z, old_id, new_id, ...] (5 ints per entry)
	// use_new_id: true = apply new_id (redo), false = apply old_id (undo)
	// Returns {"voxel_data", "dirty_chunks"}
	Dictionary apply_undo_diffs(
			PackedByteArray voxel_data,
			const PackedInt32Array &packed_diffs,
			bool use_new_id,
			int tile_x, int tile_y, int tile_z);

	// ── Procedural shape preview ──
	// Returns an ArrayMesh of the shape's outer surface for live preview.
	Ref<ArrayMesh> procedural_preview_mesh(
			int shape_id,
			const Vector3i &origin, const Vector3i &region_size,
			const Color &color);

	// Returns a Dictionary { Vector3i -> int } of positions to place.
	// vid = voxel ID to place. Reads existing voxels from voxel_data.
	Dictionary procedural_execute(
			int shape_id,
			const PackedByteArray &voxel_data,
			const Vector3i &origin, const Vector3i &region_size,
			int vid,
			int tile_x = DEFAULT_TILE_X, int tile_y = DEFAULT_TILE_Y, int tile_z = DEFAULT_TILE_Z);

protected:
	static void _bind_methods();

private:
	// ── Helpers — accept tile dimensions ──
	static inline int _voxel_index(int x, int y, int z, int tx, int ty) {
		return (x + y * tx + z * tx * ty) * 2;
	}

	static inline bool _in_bounds(int x, int y, int z, int tx, int ty, int tz) {
		return x >= 0 && x < tx && y >= 0 && y < ty && z >= 0 && z < tz;
	}

	static inline uint16_t _get_voxel(const uint8_t *data, int data_size,
			int x, int y, int z, int tx, int ty, int tz) {
		if (!_in_bounds(x, y, z, tx, ty, tz)) return 0;
		int idx = _voxel_index(x, y, z, tx, ty);
		if (idx + 1 >= data_size) return 0;
		return data[idx] | (data[idx + 1] << 8);
	}

	static inline bool _matches(uint16_t vid, uint16_t ref_id, int criteria) {
		if (vid == 0) return false;
		if (criteria == 1 && vid != ref_id) return false;          // color
		if (criteria == 2 && (vid & 0xFF) != (ref_id & 0xFF)) return false; // material
		return true;
	}

	// Greedy mesher internals
	void _greedy_face(const uint8_t *data, int data_size,
			const PackedColorArray &palette_colors,
			int ox, int oy, int oz,
			int axis, int dir,
			PackedVector3Array &verts, PackedColorArray &colors,
			PackedVector3Array &normals,
			int tile_x, int tile_y, int tile_z);

	static Color _resolve_palette_color(const PackedColorArray &palette_colors, uint16_t voxel_id);

	// Raycast internals
	static float _ray_aabb_enter(const Vector3 &origin, const Vector3 &dir,
			const Vector3 &aabb_min, const Vector3 &aabb_max);
	static float _t_to_boundary(float pos, float dir, int step);

	// Neighbor offsets for BFS
	static constexpr int NEIGHBORS_6[6][3] = {
		{1, 0, 0}, {-1, 0, 0},
		{0, 1, 0}, {0, -1, 0},
		{0, 0, 1}, {0, 0, -1},
	};

	// Procedural shape evaluation — returns true if voxel should be filled
	static bool _eval_shape(int shape_id,
			int x, int y, int z,
			int ox, int oy, int oz,
			int sx, int sy, int sz,
			double cx, double cy, double cz);

	// Build surface mesh from a filled-voxel set
	static Ref<ArrayMesh> _build_surface_mesh(
			const std::vector<bool> &filled,
			const Vector3i &origin, const Vector3i &region_size,
			const Color &color);

	// Hash for Vector3i used in unordered containers
	struct Vec3iHash {
		size_t operator()(const Vector3i &v) const {
			size_t h = std::hash<int>()(v.x);
			h ^= std::hash<int>()(v.y) + 0x9e3779b9 + (h << 6) + (h >> 2);
			h ^= std::hash<int>()(v.z) + 0x9e3779b9 + (h << 6) + (h >> 2);
			return h;
		}
	};
};

} // namespace godot

#endif // VOXEL_EDITOR_NATIVE_H
