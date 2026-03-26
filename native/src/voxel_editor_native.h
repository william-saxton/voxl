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

namespace godot {

class VoxelEditorNative : public RefCounted {
	GDCLASS(VoxelEditorNative, RefCounted)

public:
	// Default tile dimensions (match WFCTileDef defaults)
	static constexpr int DEFAULT_TILE_X = 128;
	static constexpr int DEFAULT_TILE_Y = 112;
	static constexpr int DEFAULT_TILE_Z = 128;
	static constexpr int CHUNK_SIZE = 16;

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
};

} // namespace godot

#endif // VOXEL_EDITOR_NATIVE_H
