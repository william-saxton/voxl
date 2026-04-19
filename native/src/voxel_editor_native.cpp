#include "voxel_editor_native.h"
#include "voxel_greedy.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <queue>
#include <cstring>

namespace godot {

VoxelEditorNative::VoxelEditorNative() {}
VoxelEditorNative::~VoxelEditorNative() {}

void VoxelEditorNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_chunk_mesh", "voxel_data", "chunk_x", "chunk_y", "chunk_z",
			"palette_colors", "tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::build_chunk_mesh,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));
	ClassDB::bind_method(D_METHOD("build_wireframe", "voxel_data", "chunk_x", "chunk_y", "chunk_z",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::build_wireframe,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));
	ClassDB::bind_method(D_METHOD("raycast", "voxel_data", "origin", "direction", "max_dist",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::raycast,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));
	ClassDB::bind_method(D_METHOD("flood_fill", "voxel_data", "start", "criteria", "range", "max_voxels",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::flood_fill,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));
	ClassDB::bind_method(D_METHOD("flood_fill_air", "voxel_data", "start", "range", "max_voxels",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::flood_fill_air,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));
	ClassDB::bind_method(D_METHOD("find_surface", "voxel_data", "start", "face_dir", "criteria", "range", "max_voxels",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::find_surface,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));

	ClassDB::bind_method(D_METHOD("bulk_set_voxels", "voxel_data", "changes", "tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::bulk_set_voxels);
	ClassDB::bind_method(D_METHOD("apply_mode_changes", "voxel_data", "positions", "voxel_ids", "mode",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::apply_mode_changes);
	ClassDB::bind_method(D_METHOD("apply_undo_diffs", "voxel_data", "packed_diffs", "use_new_id",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::apply_undo_diffs);
	ClassDB::bind_method(D_METHOD("procedural_preview_mesh", "shape_id", "origin", "region_size", "color"),
			&VoxelEditorNative::procedural_preview_mesh);
	ClassDB::bind_method(D_METHOD("arch_preview_mesh", "point_a", "point_b", "thickness", "color"),
			&VoxelEditorNative::arch_preview_mesh);
	ClassDB::bind_method(D_METHOD("arch_execute", "point_a", "point_b", "thickness",
			"voxel_data", "vid", "tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::arch_execute,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));
	ClassDB::bind_method(D_METHOD("procedural_execute", "shape_id", "voxel_data", "origin", "region_size", "vid",
			"tile_x", "tile_y", "tile_z"),
			&VoxelEditorNative::procedural_execute,
			DEFVAL(DEFAULT_TILE_X), DEFVAL(DEFAULT_TILE_Y), DEFVAL(DEFAULT_TILE_Z));

}

// ═══════════════════════════════════════════════════════════════════════════
// Greedy Chunk Mesher
// ═══════════════════════════════════════════════════════════════════════════

Ref<ArrayMesh> VoxelEditorNative::build_chunk_mesh(
		const PackedByteArray &voxel_data,
		int chunk_x, int chunk_y, int chunk_z,
		const PackedColorArray &palette_colors,
		int tile_x, int tile_y, int tile_z) {

	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();
	int tile_vol = tile_x * tile_y * tile_z;
	if (data_size < tile_vol * 2) {
		return Ref<ArrayMesh>();
	}

	PackedVector3Array verts;
	PackedColorArray colors;
	PackedVector3Array normals;

	int ox = chunk_x * CHUNK_SIZE;
	int oy = chunk_y * CHUNK_SIZE;
	int oz = chunk_z * CHUNK_SIZE;

	for (int axis = 0; axis < 3; axis++) {
		for (int dir = 0; dir < 2; dir++) {
			voxl_greedy::build_face_quads<CHUNK_SIZE>(
					data, data_size, palette_colors, ox, oy, oz, axis, dir,
					verts, colors, normals, tile_x, tile_y, tile_z);
		}
	}

	if (verts.size() == 0) {
		return Ref<ArrayMesh>();
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_COLOR] = colors;
	arrays[Mesh::ARRAY_NORMAL] = normals;

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}

// ═══════════════════════════════════════════════════════════════════════════
// Wireframe Builder
// ═══════════════════════════════════════════════════════════════════════════

Ref<ArrayMesh> VoxelEditorNative::build_wireframe(
		const PackedByteArray &voxel_data,
		int chunk_x, int chunk_y, int chunk_z,
		int tile_x, int tile_y, int tile_z) {

	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();
	int tile_vol = tile_x * tile_y * tile_z;
	if (data_size < tile_vol * 2) {
		return Ref<ArrayMesh>();
	}

	PackedVector3Array line_verts;
	int ox = chunk_x * CHUNK_SIZE;
	int oy = chunk_y * CHUNK_SIZE;
	int oz = chunk_z * CHUNK_SIZE;

	auto add_face_edges = [&line_verts](Vector3 corner, Vector3 u, Vector3 v) {
		Vector3 c0 = corner;
		Vector3 c1 = corner + u;
		Vector3 c2 = corner + u + v;
		Vector3 c3 = corner + v;
		line_verts.push_back(c0); line_verts.push_back(c1);
		line_verts.push_back(c1); line_verts.push_back(c2);
		line_verts.push_back(c2); line_verts.push_back(c3);
		line_verts.push_back(c3); line_verts.push_back(c0);
	};

	for (int lz = 0; lz < CHUNK_SIZE; lz++) {
		for (int ly = 0; ly < CHUNK_SIZE; ly++) {
			for (int lx = 0; lx < CHUNK_SIZE; lx++) {
				int wx = ox + lx, wy = oy + ly, wz = oz + lz;
				if (_get_voxel(data, data_size, wx, wy, wz, tile_x, tile_y, tile_z) == 0) continue;

				Vector3 p(static_cast<float>(lx), static_cast<float>(ly), static_cast<float>(lz));

				if (_get_voxel(data, data_size, wx + 1, wy, wz, tile_x, tile_y, tile_z) == 0)
					add_face_edges(p + Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1));
				if (_get_voxel(data, data_size, wx - 1, wy, wz, tile_x, tile_y, tile_z) == 0)
					add_face_edges(p, Vector3(0, 1, 0), Vector3(0, 0, 1));
				if (_get_voxel(data, data_size, wx, wy + 1, wz, tile_x, tile_y, tile_z) == 0)
					add_face_edges(p + Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1));
				if (_get_voxel(data, data_size, wx, wy - 1, wz, tile_x, tile_y, tile_z) == 0)
					add_face_edges(p, Vector3(1, 0, 0), Vector3(0, 0, 1));
				if (_get_voxel(data, data_size, wx, wy, wz + 1, tile_x, tile_y, tile_z) == 0)
					add_face_edges(p + Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0));
				if (_get_voxel(data, data_size, wx, wy, wz - 1, tile_x, tile_y, tile_z) == 0)
					add_face_edges(p, Vector3(1, 0, 0), Vector3(0, 1, 0));
			}
		}
	}

	if (line_verts.size() == 0) {
		return Ref<ArrayMesh>();
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = line_verts;

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_LINES, arrays);
	return mesh;
}

// ═══════════════════════════════════════════════════════════════════════════
// DDA Raycast
// ═══════════════════════════════════════════════════════════════════════════

float VoxelEditorNative::_ray_aabb_enter(const Vector3 &origin, const Vector3 &dir,
		const Vector3 &aabb_min, const Vector3 &aabb_max) {
	float t_min = -1e30f;
	float t_max = 1e30f;

	for (int i = 0; i < 3; i++) {
		if (std::abs(dir[i]) < 1e-8f) {
			if (origin[i] < aabb_min[i] || origin[i] > aabb_max[i])
				return -1.0f;
		} else {
			float inv_d = 1.0f / dir[i];
			float t1 = (aabb_min[i] - origin[i]) * inv_d;
			float t2 = (aabb_max[i] - origin[i]) * inv_d;
			if (t1 > t2) { float tmp = t1; t1 = t2; t2 = tmp; }
			t_min = std::max(t_min, t1);
			t_max = std::min(t_max, t2);
			if (t_min > t_max) return -1.0f;
		}
	}
	return t_min;
}

float VoxelEditorNative::_t_to_boundary(float pos, float dir, int step) {
	if (dir == 0.0f) return 1e30f;
	float boundary;
	if (step > 0) {
		boundary = std::floor(pos) + 1.0f;
	} else {
		boundary = std::floor(pos);
		if (pos == boundary) boundary -= 1.0f;
	}
	return (boundary - pos) / dir;
}

Dictionary VoxelEditorNative::raycast(
		const PackedByteArray &voxel_data,
		const Vector3 &origin, const Vector3 &direction, float max_dist,
		int tile_x, int tile_y, int tile_z) {

	Dictionary result;
	result["hit"] = false;
	result["position"] = Vector3i(0, 0, 0);
	result["previous"] = Vector3i(0, 0, 0);
	result["voxel_id"] = 0;
	result["distance"] = 0.0f;

	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();
	int tile_vol = tile_x * tile_y * tile_z;
	if (data_size < tile_vol * 2 || direction.length_squared() < 1e-10f) {
		return result;
	}

	Vector3 ray_dir = direction.normalized();

	Vector3 aabb_min(0, 0, 0);
	Vector3 aabb_max(static_cast<float>(tile_x), static_cast<float>(tile_y), static_cast<float>(tile_z));
	float t_enter = _ray_aabb_enter(origin, ray_dir, aabb_min, aabb_max);

	Vector3 start;
	if (t_enter > 0.0f) {
		start = origin + ray_dir * (t_enter + 0.001f);
	} else {
		start = origin;
	}

	int vx = static_cast<int>(std::floor(start.x));
	int vy = static_cast<int>(std::floor(start.y));
	int vz = static_cast<int>(std::floor(start.z));

	int step_x = ray_dir.x >= 0 ? 1 : -1;
	int step_y = ray_dir.y >= 0 ? 1 : -1;
	int step_z = ray_dir.z >= 0 ? 1 : -1;

	float t_max_x = _t_to_boundary(start.x, ray_dir.x, step_x);
	float t_max_y = _t_to_boundary(start.y, ray_dir.y, step_y);
	float t_max_z = _t_to_boundary(start.z, ray_dir.z, step_z);

	float t_delta_x = ray_dir.x != 0.0f ? std::abs(1.0f / ray_dir.x) : 1e30f;
	float t_delta_y = ray_dir.y != 0.0f ? std::abs(1.0f / ray_dir.y) : 1e30f;
	float t_delta_z = ray_dir.z != 0.0f ? std::abs(1.0f / ray_dir.z) : 1e30f;

	Vector3i prev(vx, vy, vz);
	constexpr int MAX_STEPS = 300;

	for (int step = 0; step < MAX_STEPS; step++) {
		if (vx < 0 || vx >= tile_x || vy < 0 || vy >= tile_y || vz < 0 || vz >= tile_z) {
			if (step > 0) break;
		} else {
			uint16_t vid = _get_voxel(data, data_size, vx, vy, vz, tile_x, tile_y, tile_z);
			if (vid != 0) {
				result["hit"] = true;
				result["position"] = Vector3i(vx, vy, vz);
				result["previous"] = prev;
				result["voxel_id"] = static_cast<int>(vid);
				float dist = std::max(t_enter, 0.0f) + std::min(t_max_x, std::min(t_max_y, t_max_z));
				result["distance"] = dist;
				return result;
			}
		}

		prev = Vector3i(vx, vy, vz);

		if (t_max_x < t_max_y) {
			if (t_max_x < t_max_z) {
				vx += step_x; t_max_x += t_delta_x;
			} else {
				vz += step_z; t_max_z += t_delta_z;
			}
		} else {
			if (t_max_y < t_max_z) {
				vy += step_y; t_max_y += t_delta_y;
			} else {
				vz += step_z; t_max_z += t_delta_z;
			}
		}
	}

	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// BFS Flood Fill (solid voxels)
// ═══════════════════════════════════════════════════════════════════════════

PackedVector3Array VoxelEditorNative::flood_fill(
		const PackedByteArray &voxel_data,
		const Vector3i &start,
		int criteria, int range, int max_voxels,
		int tile_x, int tile_y, int tile_z) {

	PackedVector3Array result;
	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();
	int tile_vol = tile_x * tile_y * tile_z;
	if (data_size < tile_vol * 2) return result;

	uint16_t ref_id = _get_voxel(data, data_size, start.x, start.y, start.z, tile_x, tile_y, tile_z);
	if (ref_id == 0) return result;

	std::vector<bool> visited(tile_vol, false);

	auto idx = [tile_x, tile_y](int x, int y, int z) -> int {
		return x + y * tile_x + z * tile_x * tile_y;
	};

	std::queue<Vector3i> queue;
	queue.push(start);
	visited[idx(start.x, start.y, start.z)] = true;

	while (!queue.empty() && result.size() < max_voxels) {
		Vector3i pos = queue.front();
		queue.pop();
		result.push_back(pos);

		for (int n = 0; n < 6; n++) {
			int nx = pos.x + NEIGHBORS_6[n][0];
			int ny = pos.y + NEIGHBORS_6[n][1];
			int nz = pos.z + NEIGHBORS_6[n][2];

			if (!_in_bounds(nx, ny, nz, tile_x, tile_y, tile_z)) continue;
			int ni = idx(nx, ny, nz);
			if (visited[ni]) continue;

			if (std::abs(nx - start.x) > range || std::abs(ny - start.y) > range ||
					std::abs(nz - start.z) > range) continue;

			uint16_t vid = _get_voxel(data, data_size, nx, ny, nz, tile_x, tile_y, tile_z);
			if (!_matches(vid, ref_id, criteria)) continue;

			visited[ni] = true;
			queue.push(Vector3i(nx, ny, nz));
		}
	}

	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// BFS Flood Fill (air voxels)
// ═══════════════════════════════════════════════════════════════════════════

PackedVector3Array VoxelEditorNative::flood_fill_air(
		const PackedByteArray &voxel_data,
		const Vector3i &start,
		int range, int max_voxels,
		int tile_x, int tile_y, int tile_z) {

	PackedVector3Array result;
	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();
	int tile_vol = tile_x * tile_y * tile_z;
	if (data_size < tile_vol * 2) return result;

	if (_get_voxel(data, data_size, start.x, start.y, start.z, tile_x, tile_y, tile_z) != 0) return result;

	std::vector<bool> visited(tile_vol, false);

	auto idx = [tile_x, tile_y](int x, int y, int z) -> int {
		return x + y * tile_x + z * tile_x * tile_y;
	};

	std::queue<Vector3i> queue;
	queue.push(start);
	visited[idx(start.x, start.y, start.z)] = true;

	while (!queue.empty() && result.size() < max_voxels) {
		Vector3i pos = queue.front();
		queue.pop();
		result.push_back(pos);

		for (int n = 0; n < 6; n++) {
			int nx = pos.x + NEIGHBORS_6[n][0];
			int ny = pos.y + NEIGHBORS_6[n][1];
			int nz = pos.z + NEIGHBORS_6[n][2];

			if (!_in_bounds(nx, ny, nz, tile_x, tile_y, tile_z)) continue;
			int ni = idx(nx, ny, nz);
			if (visited[ni]) continue;

			if (std::abs(nx - start.x) > range || std::abs(ny - start.y) > range ||
					std::abs(nz - start.z) > range) continue;

			if (_get_voxel(data, data_size, nx, ny, nz, tile_x, tile_y, tile_z) != 0) continue;

			visited[ni] = true;
			queue.push(Vector3i(nx, ny, nz));
		}
	}

	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Surface Find (FACE connectivity)
// ═══════════════════════════════════════════════════════════════════════════

PackedVector3Array VoxelEditorNative::find_surface(
		const PackedByteArray &voxel_data,
		const Vector3i &start, const Vector3i &face_dir,
		int criteria, int range, int max_voxels,
		int tile_x, int tile_y, int tile_z) {

	PackedVector3Array result;
	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();
	int tile_vol = tile_x * tile_y * tile_z;
	if (data_size < tile_vol * 2) return result;

	uint16_t ref_id = _get_voxel(data, data_size, start.x, start.y, start.z, tile_x, tile_y, tile_z);
	if (ref_id == 0) return result;

	int check_x = start.x + face_dir.x;
	int check_y = start.y + face_dir.y;
	int check_z = start.z + face_dir.z;
	if (_in_bounds(check_x, check_y, check_z, tile_x, tile_y, tile_z) &&
			_get_voxel(data, data_size, check_x, check_y, check_z, tile_x, tile_y, tile_z) != 0) {
		return result;
	}

	std::vector<bool> visited(tile_vol, false);

	auto idx = [tile_x, tile_y](int x, int y, int z) -> int {
		return x + y * tile_x + z * tile_x * tile_y;
	};

	std::queue<Vector3i> queue;
	queue.push(start);
	visited[idx(start.x, start.y, start.z)] = true;

	while (!queue.empty() && result.size() < max_voxels) {
		Vector3i pos = queue.front();
		queue.pop();
		result.push_back(pos);

		for (int n = 0; n < 6; n++) {
			int nx = pos.x + NEIGHBORS_6[n][0];
			int ny = pos.y + NEIGHBORS_6[n][1];
			int nz = pos.z + NEIGHBORS_6[n][2];

			if (!_in_bounds(nx, ny, nz, tile_x, tile_y, tile_z)) continue;
			int ni = idx(nx, ny, nz);
			if (visited[ni]) continue;

			if (std::abs(nx - start.x) > range || std::abs(ny - start.y) > range ||
					std::abs(nz - start.z) > range) continue;

			uint16_t vid = _get_voxel(data, data_size, nx, ny, nz, tile_x, tile_y, tile_z);
			if (!_matches(vid, ref_id, criteria)) continue;

			int fx = nx + face_dir.x;
			int fy = ny + face_dir.y;
			int fz = nz + face_dir.z;
			if (_in_bounds(fx, fy, fz, tile_x, tile_y, tile_z) &&
					_get_voxel(data, data_size, fx, fy, fz, tile_x, tile_y, tile_z) != 0) {
				continue;
			}

			visited[ni] = true;
			queue.push(Vector3i(nx, ny, nz));
		}
	}

	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Bulk Voxel Writes
// ═══════════════════════════════════════════════════════════════════════════

Dictionary VoxelEditorNative::bulk_set_voxels(
		PackedByteArray voxel_data,
		const PackedInt32Array &changes,
		int tile_x, int tile_y, int tile_z) {

	Dictionary result;
	int count = changes.size() / 4;
	if (count == 0) {
		result["voxel_data"] = voxel_data;
		result["dirty_chunks"] = PackedInt32Array();
		return result;
	}

	int data_size = voxel_data.size();
	uint8_t *data = voxel_data.ptrw();
	const int *ch = changes.ptr();

	int chunks_x = (tile_x + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int chunks_y = (tile_y + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int chunks_z = (tile_z + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int total_chunks = chunks_x * chunks_y * chunks_z;

	// Track dirty chunks as a bitset
	std::vector<bool> dirty(total_chunks, false);

	for (int i = 0; i < count; i++) {
		int x = ch[i * 4];
		int y = ch[i * 4 + 1];
		int z = ch[i * 4 + 2];
		uint16_t vid = (uint16_t)ch[i * 4 + 3];

		if (!_in_bounds(x, y, z, tile_x, tile_y, tile_z)) continue;

		int idx = _voxel_index(x, y, z, tile_x, tile_y);
		if (idx + 1 >= data_size) continue;
		data[idx] = vid & 0xFF;
		data[idx + 1] = (vid >> 8) & 0xFF;

		// Mark chunk dirty
		int cx = x >> 4, cy = y >> 4, cz = z >> 4;
		if (cx >= 0 && cx < chunks_x && cy >= 0 && cy < chunks_y && cz >= 0 && cz < chunks_z) {
			dirty[cx + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		}
		// Boundary neighbors
		if ((x & 0xF) == 0 && cx - 1 >= 0)
			dirty[(cx-1) + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		else if ((x & 0xF) == 15 && cx + 1 < chunks_x)
			dirty[(cx+1) + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		if ((y & 0xF) == 0 && cy - 1 >= 0)
			dirty[cx + (cy-1) * chunks_x + cz * chunks_x * chunks_y] = true;
		else if ((y & 0xF) == 15 && cy + 1 < chunks_y)
			dirty[cx + (cy+1) * chunks_x + cz * chunks_x * chunks_y] = true;
		if ((z & 0xF) == 0 && cz - 1 >= 0)
			dirty[cx + cy * chunks_x + (cz-1) * chunks_x * chunks_y] = true;
		else if ((z & 0xF) == 15 && cz + 1 < chunks_z)
			dirty[cx + cy * chunks_x + (cz+1) * chunks_x * chunks_y] = true;
	}

	// Collect dirty chunk indices
	PackedInt32Array dirty_chunks;
	for (int i = 0; i < total_chunks; i++) {
		if (dirty[i]) dirty_chunks.push_back(i);
	}

	result["voxel_data"] = voxel_data;
	result["dirty_chunks"] = dirty_chunks;
	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Mode-based shape apply — full pipeline in C++
// ═══════════════════════════════════════════════════════════════════════════

Dictionary VoxelEditorNative::apply_mode_changes(
		PackedByteArray voxel_data,
		const PackedInt32Array &positions,
		const PackedInt32Array &voxel_ids,
		int mode,
		int tile_x, int tile_y, int tile_z) {

	Dictionary result;
	int pos_count = positions.size() / 3;
	if (pos_count == 0 || voxel_ids.size() < pos_count) {
		result["voxel_data"] = voxel_data;
		result["dirty_chunks"] = PackedInt32Array();
		result["undo_diffs"] = PackedInt32Array();
		return result;
	}

	int data_size = voxel_data.size();
	if (data_size == 0) {
		result["voxel_data"] = voxel_data;
		result["dirty_chunks"] = PackedInt32Array();
		result["undo_diffs"] = PackedInt32Array();
		return result;
	}

	uint8_t *data = voxel_data.ptrw();
	const int *pos_ptr = positions.ptr();
	const int *vid_ptr = voxel_ids.ptr();

	int chunks_x = (tile_x + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int chunks_y = (tile_y + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int chunks_z = (tile_z + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int total_chunks = chunks_x * chunks_y * chunks_z;
	std::vector<bool> dirty(total_chunks, false);

	// Pre-allocate max undo diffs: 5 ints per entry [x, y, z, old_id, new_id]
	PackedInt32Array undo_diffs;
	undo_diffs.resize(pos_count * 5);
	int *diff_ptr = undo_diffs.ptrw();
	int diff_count = 0;

	for (int i = 0; i < pos_count; i++) {
		int x = pos_ptr[i * 3];
		int y = pos_ptr[i * 3 + 1];
		int z = pos_ptr[i * 3 + 2];

		if (!_in_bounds(x, y, z, tile_x, tile_y, tile_z)) continue;

		int idx = _voxel_index(x, y, z, tile_x, tile_y);
		if (idx + 1 >= data_size) continue;

		uint16_t old_id = data[idx] | (data[idx + 1] << 8);
		uint16_t new_id = old_id;
		uint16_t target_vid = (uint16_t)vid_ptr[i];

		switch (mode) {
			case 0: // ADD
				new_id = target_vid;
				break;
			case 1: // SUBTRACT
				new_id = 0;
				break;
			case 2: // PAINT
				if (old_id != 0) new_id = target_vid;
				break;
		}

		if (new_id == old_id) continue;

		// Write voxel
		data[idx] = new_id & 0xFF;
		data[idx + 1] = (new_id >> 8) & 0xFF;

		// Record undo diff
		int d = diff_count * 5;
		diff_ptr[d] = x;
		diff_ptr[d + 1] = y;
		diff_ptr[d + 2] = z;
		diff_ptr[d + 3] = old_id;
		diff_ptr[d + 4] = new_id;
		diff_count++;

		// Mark chunk dirty + boundary neighbors
		int cx = x >> 4, cy = y >> 4, cz = z >> 4;
		if (cx >= 0 && cx < chunks_x && cy >= 0 && cy < chunks_y && cz >= 0 && cz < chunks_z) {
			dirty[cx + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		}
		if ((x & 0xF) == 0 && cx - 1 >= 0)
			dirty[(cx-1) + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		else if ((x & 0xF) == 15 && cx + 1 < chunks_x)
			dirty[(cx+1) + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		if ((y & 0xF) == 0 && cy - 1 >= 0)
			dirty[cx + (cy-1) * chunks_x + cz * chunks_x * chunks_y] = true;
		else if ((y & 0xF) == 15 && cy + 1 < chunks_y)
			dirty[cx + (cy+1) * chunks_x + cz * chunks_x * chunks_y] = true;
		if ((z & 0xF) == 0 && cz - 1 >= 0)
			dirty[cx + cy * chunks_x + (cz-1) * chunks_x * chunks_y] = true;
		else if ((z & 0xF) == 15 && cz + 1 < chunks_z)
			dirty[cx + cy * chunks_x + (cz+1) * chunks_x * chunks_y] = true;
	}

	// Trim to actual count
	undo_diffs.resize(diff_count * 5);

	PackedInt32Array dirty_chunks;
	for (int i = 0; i < total_chunks; i++) {
		if (dirty[i]) dirty_chunks.push_back(i);
	}

	result["voxel_data"] = voxel_data;
	result["dirty_chunks"] = dirty_chunks;
	result["undo_diffs"] = undo_diffs;
	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Apply packed undo diffs (for undo/redo)
// ═══════════════════════════════════════════════════════════════════════════

Dictionary VoxelEditorNative::apply_undo_diffs(
		PackedByteArray voxel_data,
		const PackedInt32Array &packed_diffs,
		bool use_new_id,
		int tile_x, int tile_y, int tile_z) {

	Dictionary result;
	int count = packed_diffs.size() / 5;
	if (count == 0) {
		result["voxel_data"] = voxel_data;
		result["dirty_chunks"] = PackedInt32Array();
		return result;
	}

	int data_size = voxel_data.size();
	if (data_size == 0) {
		result["voxel_data"] = voxel_data;
		result["dirty_chunks"] = PackedInt32Array();
		return result;
	}

	uint8_t *data = voxel_data.ptrw();
	const int *dp = packed_diffs.ptr();

	int chunks_x = (tile_x + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int chunks_y = (tile_y + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int chunks_z = (tile_z + CHUNK_SIZE - 1) / CHUNK_SIZE;
	int total_chunks = chunks_x * chunks_y * chunks_z;
	std::vector<bool> dirty(total_chunks, false);

	// offset 3 = old_id, offset 4 = new_id
	int id_offset = use_new_id ? 4 : 3;

	for (int i = 0; i < count; i++) {
		int base = i * 5;
		int x = dp[base];
		int y = dp[base + 1];
		int z = dp[base + 2];
		uint16_t vid = (uint16_t)dp[base + id_offset];

		if (!_in_bounds(x, y, z, tile_x, tile_y, tile_z)) continue;

		int idx = _voxel_index(x, y, z, tile_x, tile_y);
		if (idx + 1 >= data_size) continue;

		data[idx] = vid & 0xFF;
		data[idx + 1] = (vid >> 8) & 0xFF;

		int cx = x >> 4, cy = y >> 4, cz = z >> 4;
		if (cx >= 0 && cx < chunks_x && cy >= 0 && cy < chunks_y && cz >= 0 && cz < chunks_z) {
			dirty[cx + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		}
		if ((x & 0xF) == 0 && cx - 1 >= 0)
			dirty[(cx-1) + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		else if ((x & 0xF) == 15 && cx + 1 < chunks_x)
			dirty[(cx+1) + cy * chunks_x + cz * chunks_x * chunks_y] = true;
		if ((y & 0xF) == 0 && cy - 1 >= 0)
			dirty[cx + (cy-1) * chunks_x + cz * chunks_x * chunks_y] = true;
		else if ((y & 0xF) == 15 && cy + 1 < chunks_y)
			dirty[cx + (cy+1) * chunks_x + cz * chunks_x * chunks_y] = true;
		if ((z & 0xF) == 0 && cz - 1 >= 0)
			dirty[cx + cy * chunks_x + (cz-1) * chunks_x * chunks_y] = true;
		else if ((z & 0xF) == 15 && cz + 1 < chunks_z)
			dirty[cx + cy * chunks_x + (cz+1) * chunks_x * chunks_y] = true;
	}

	PackedInt32Array dirty_chunks;
	for (int i = 0; i < total_chunks; i++) {
		if (dirty[i]) dirty_chunks.push_back(i);
	}

	result["voxel_data"] = voxel_data;
	result["dirty_chunks"] = dirty_chunks;
	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Procedural Shape Evaluation
// ═══════════════════════════════════════════════════════════════════════════

bool VoxelEditorNative::_eval_shape(int shape_id,
		int x, int y, int z,
		int ox, int oy, int oz,
		int sx, int sy, int sz,
		double cx, double cy, double cz) {

	switch (shape_id) {
		case SHAPE_SPHERE: {
			double r = std::min({sx, sy, sz}) * 0.5;
			double dx = x - cx, dy = y - cy, dz = z - cz;
			return std::sqrt(dx*dx + dy*dy + dz*dz) <= r;
		}
		case SHAPE_HOLLOW_SPHERE: {
			double r = std::min({sx, sy, sz}) * 0.5;
			double dx = x - cx, dy = y - cy, dz = z - cz;
			double d = std::sqrt(dx*dx + dy*dy + dz*dz);
			return d <= r && d >= r - 1.5;
		}
		case SHAPE_CYLINDER_Y: {
			double r = std::min(sx, sz) * 0.5;
			double dx = x - cx, dz = z - cz;
			return std::sqrt(dx*dx + dz*dz) <= r;
		}
		case SHAPE_TORUS_Y: {
			double R = std::min(sx, sz) * 0.35;
			double r = std::min(sx, sz) * 0.15;
			double dx = x - cx, dz = z - cz;
			double ring = std::sqrt(dx*dx + dz*dz);
			double d = std::sqrt((ring - R)*(ring - R) + (y - cy)*(y - cy));
			return d <= r;
		}
		case SHAPE_ARCH_Z: {
			// Half-torus arch: tube bent in a semicircle, like two pillars
			// connected by a curved tube overhead.
			// Arch spans the longer horizontal axis, depth along the shorter.
			double arch_h, arch_v, depth;
			int span_dim, height_dim, depth_dim;
			if (sx >= sz) {
				// Arch spans X, depth along Z
				arch_h = x - cx;
				arch_v = y - (double)oy;
				depth = z - cz;
				span_dim = sx; height_dim = sy; depth_dim = sz;
			} else {
				// Arch spans Z, depth along X
				arch_h = z - cz;
				arch_v = y - (double)oy;
				depth = x - cx;
				span_dim = sz; height_dim = sy; depth_dim = sx;
			}
			double R = std::min(span_dim, height_dim) * 0.4;
			double r = std::max(std::min({span_dim, height_dim, depth_dim}) * 0.2, 2.0);
			double ring = std::sqrt(arch_h * arch_h + arch_v * arch_v);
			double d = std::sqrt((ring - R) * (ring - R) + depth * depth);
			return d <= r && arch_v >= 0;
		}
		case SHAPE_DOME: {
			double r = std::min({sx, sy * 2, sz}) * 0.5;
			double dx = x - cx, dy = y - (double)oy, dz = z - cz;
			return std::sqrt(dx*dx + dy*dy + dz*dz) <= r && y >= oy;
		}
		case SHAPE_NOISE_TERRAIN: {
			double h = sy * 0.3 + sy * 0.3 * std::sin(x * 0.15) * std::cos(z * 0.15)
					 + sy * 0.15 * std::sin(x * 0.3 + 1.7) * std::cos(z * 0.25 + 0.8);
			return y < oy + h;
		}
		case SHAPE_PYRAMID: {
			int layer = y - oy;
			double half_x = (sx - 1.0) / 2.0 - layer;
			double half_z = (sz - 1.0) / 2.0 - layer;
			return half_x >= 0 && half_z >= 0
				&& std::abs(x - cx) <= half_x
				&& std::abs(z - cz) <= half_z;
		}
		case SHAPE_CONE_Y: {
			double progress = (double)(y - oy) / std::max(sy - 1, 1);
			double r = (1.0 - progress) * std::min(sx, sz) * 0.5;
			double dx = x - cx, dz = z - cz;
			return std::sqrt(dx*dx + dz*dz) <= r;
		}
		case SHAPE_STAIRS_Z: {
			int step_depth = std::max(sz / 8, 1);
			int step_idx = (z - oz) / step_depth;
			int step_height = step_idx + 1;
			return (y - oy) < step_height;
		}
		case SHAPE_SPIRAL_Y: {
			double progress = (double)(y - oy) / std::max(sy - 1, 1);
			double angle = progress * 6.283185307 * 3.0; // TAU * 3
			double r = std::min(sx, sz) * 0.4;
			double cx2 = cx + std::cos(angle) * r * 0.5;
			double cz2 = cz + std::sin(angle) * r * 0.5;
			double dx = x - cx2, dz = z - cz2;
			return std::sqrt(dx*dx + dz*dz) <= r * 0.25;
		}
		case SHAPE_CHECKERBOARD: {
			return (x + y + z) % 2 == 0;
		}
		case SHAPE_CLEAR: {
			return true; // Fill everything (caller handles setting to air)
		}
		default:
			return false;
	}
}

Ref<ArrayMesh> VoxelEditorNative::_build_surface_mesh(
		const std::vector<bool> &filled,
		const Vector3i &origin, const Vector3i &region_size,
		const Color &color) {

	int sx = region_size.x, sy = region_size.y, sz = region_size.z;

	// Neighbor offsets and face vertex offsets (4 corners per face, CCW from outside)
	static const int face_dir[6][3] = {
		{ 1, 0, 0}, {-1, 0, 0},
		{ 0, 1, 0}, { 0,-1, 0},
		{ 0, 0, 1}, { 0, 0,-1},
	};
	// Each face has 4 corner offsets (x, y, z) relative to the voxel origin
	static const float face_corners[6][4][3] = {
		// +X
		{{1,0,0}, {1,0,1}, {1,1,1}, {1,1,0}},
		// -X
		{{0,0,1}, {0,0,0}, {0,1,0}, {0,1,1}},
		// +Y
		{{0,1,0}, {1,1,0}, {1,1,1}, {0,1,1}},
		// -Y
		{{0,0,1}, {1,0,1}, {1,0,0}, {0,0,0}},
		// +Z
		{{0,0,1}, {0,1,1}, {1,1,1}, {1,0,1}},
		// -Z
		{{1,0,0}, {1,1,0}, {0,1,0}, {0,0,0}},
	};

	PackedVector3Array verts;
	PackedColorArray colors;

	auto idx = [sx, sy](int lx, int ly, int lz) -> int {
		return lx + ly * sx + lz * sx * sy;
	};

	for (int lz = 0; lz < sz; lz++) {
		for (int ly = 0; ly < sy; ly++) {
			for (int lx = 0; lx < sx; lx++) {
				if (!filled[idx(lx, ly, lz)]) continue;

				float wx = (float)(origin.x + lx);
				float wy = (float)(origin.y + ly);
				float wz = (float)(origin.z + lz);

				for (int f = 0; f < 6; f++) {
					int nx = lx + face_dir[f][0];
					int ny = ly + face_dir[f][1];
					int nz = lz + face_dir[f][2];

					// If neighbor is out of bounds or not filled, this face is exposed
					bool neighbor_filled = (nx >= 0 && nx < sx && ny >= 0 && ny < sy && nz >= 0 && nz < sz)
							&& filled[idx(nx, ny, nz)];
					if (neighbor_filled) continue;

					const float (*c)[3] = face_corners[f];
					// Two triangles: 0-1-2, 0-2-3
					verts.push_back(Vector3(wx + c[0][0], wy + c[0][1], wz + c[0][2]));
					verts.push_back(Vector3(wx + c[1][0], wy + c[1][1], wz + c[1][2]));
					verts.push_back(Vector3(wx + c[2][0], wy + c[2][1], wz + c[2][2]));
					verts.push_back(Vector3(wx + c[0][0], wy + c[0][1], wz + c[0][2]));
					verts.push_back(Vector3(wx + c[2][0], wy + c[2][1], wz + c[2][2]));
					verts.push_back(Vector3(wx + c[3][0], wy + c[3][1], wz + c[3][2]));

					for (int v = 0; v < 6; v++) {
						colors.push_back(color);
					}
				}
			}
		}
	}

	if (verts.size() == 0) {
		return Ref<ArrayMesh>();
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = verts;
	arrays[Mesh::ARRAY_COLOR] = colors;

	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}

Ref<ArrayMesh> VoxelEditorNative::procedural_preview_mesh(
		int shape_id,
		const Vector3i &origin, const Vector3i &region_size,
		const Color &color) {

	if (shape_id < 0 || shape_id >= SHAPE_COUNT) {
		return Ref<ArrayMesh>();
	}

	int sx = region_size.x, sy = region_size.y, sz = region_size.z;
	if (sx <= 0 || sy <= 0 || sz <= 0) return Ref<ArrayMesh>();

	int ox = origin.x, oy = origin.y, oz = origin.z;
	double cx = ox + sx * 0.5;
	double cy = oy + sy * 0.5;
	double cz = oz + sz * 0.5;

	int vol = sx * sy * sz;
	std::vector<bool> filled(vol, false);

	for (int lz = 0; lz < sz; lz++) {
		for (int ly = 0; ly < sy; ly++) {
			for (int lx = 0; lx < sx; lx++) {
				int wx = ox + lx, wy = oy + ly, wz = oz + lz;
				if (_eval_shape(shape_id, wx, wy, wz, ox, oy, oz, sx, sy, sz, cx, cy, cz)) {
					filled[lx + ly * sx + lz * sx * sy] = true;
				}
			}
		}
	}

	return _build_surface_mesh(filled, origin, region_size, color);
}

Dictionary VoxelEditorNative::procedural_execute(
		int shape_id,
		const PackedByteArray &voxel_data,
		const Vector3i &origin, const Vector3i &region_size,
		int vid,
		int tile_x, int tile_y, int tile_z) {

	Dictionary result;
	if (shape_id < 0 || shape_id >= SHAPE_COUNT) return result;

	const uint8_t *data = voxel_data.ptr();
	int data_size = voxel_data.size();

	int sx = region_size.x, sy = region_size.y, sz = region_size.z;
	int ox = origin.x, oy = origin.y, oz = origin.z;
	double cx = ox + sx * 0.5;
	double cy = oy + sy * 0.5;
	double cz = oz + sz * 0.5;

	int place_id = (shape_id == SHAPE_CLEAR) ? 0 : vid;

	for (int lz = 0; lz < sz; lz++) {
		for (int ly = 0; ly < sy; ly++) {
			for (int lx = 0; lx < sx; lx++) {
				int wx = ox + lx, wy = oy + ly, wz = oz + lz;
				if (!_in_bounds(wx, wy, wz, tile_x, tile_y, tile_z)) continue;

				if (_eval_shape(shape_id, wx, wy, wz, ox, oy, oz, sx, sy, sz, cx, cy, cz)) {
					uint16_t current = _get_voxel(data, data_size, wx, wy, wz, tile_x, tile_y, tile_z);
					if ((int)current != place_id) {
						result[Vector3i(wx, wy, wz)] = place_id;
					}
				}
			}
		}
	}

	return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Arch Tool — 3-click half-torus with explicit parameters
// ═══════════════════════════════════════════════════════════════════════════

bool VoxelEditorNative::_eval_arch(int x, int y, int z,
		const Vector3i &a, const Vector3i &b, double r) {
	// Horizontal direction from A to B (in XZ plane)
	double dx = b.x - a.x;
	double dz = b.z - a.z;
	double len = std::sqrt(dx * dx + dz * dz);
	if (len < 0.5) {
		// A and B are at the same XZ position — vertical arch, use XZ plane
		// Fall back to Y-difference for the arch span
		double dy = b.y - a.y;
		len = std::abs(dy);
		if (len < 0.5) return false;
		double R = len * 0.5;
		double my = (a.y + b.y) * 0.5;
		double mx = a.x;
		double mz = a.z;
		double h = y - my;
		// Pick a horizontal axis for "up" (use X)
		double v = x - mx;
		double depth = z - mz;
		double ring = std::sqrt(h * h + v * v);
		double d = std::sqrt((ring - R) * (ring - R) + depth * depth);
		return d <= r;
	}

	double dir_x = dx / len;
	double dir_z = dz / len;

	// Midpoint and base Y
	double mx = (a.x + b.x) * 0.5;
	double mz = (a.z + b.z) * 0.5;
	double base_y = std::min(a.y, b.y);
	double R = len * 0.5;

	// Project voxel position
	double rel_x = x - mx;
	double rel_z = z - mz;
	double h = rel_x * dir_x + rel_z * dir_z;     // along A→B direction
	double v = y - base_y;                          // vertical (upward)
	double depth = -rel_x * dir_z + rel_z * dir_x; // perpendicular to A→B in XZ

	double ring = std::sqrt(h * h + v * v);
	double d = std::sqrt((ring - R) * (ring - R) + depth * depth);
	return d <= r && v >= 0;
}


Ref<ArrayMesh> VoxelEditorNative::arch_preview_mesh(
		const Vector3i &point_a, const Vector3i &point_b,
		double thickness, const Color &color) {

	// Compute bounding box
	double dx = point_b.x - point_a.x;
	double dz = point_b.z - point_a.z;
	double len = std::sqrt(dx * dx + dz * dz);
	double R = len * 0.5;
	double pad = R + thickness + 2;
	int base_y = std::min(point_a.y, point_b.y);

	int mx = (point_a.x + point_b.x) / 2;
	int mz = (point_a.z + point_b.z) / 2;

	int min_x = (int)std::floor(mx - pad);
	int max_x = (int)std::ceil(mx + pad);
	int min_y = base_y;
	int max_y = (int)std::ceil(base_y + R + thickness + 2);
	int min_z = (int)std::floor(mz - pad);
	int max_z = (int)std::ceil(mz + pad);

	int sx = max_x - min_x + 1;
	int sy = max_y - min_y + 1;
	int sz = max_z - min_z + 1;

	// Build filled volume
	std::vector<bool> filled(sx * sy * sz, false);
	for (int lz = 0; lz < sz; lz++) {
		for (int ly = 0; ly < sy; ly++) {
			for (int lx = 0; lx < sx; lx++) {
				if (_eval_arch(min_x + lx, min_y + ly, min_z + lz,
						point_a, point_b, thickness)) {
					filled[lx + ly * sx + lz * sx * sy] = true;
				}
			}
		}
	}

	Vector3i origin(min_x, min_y, min_z);
	Vector3i region(sx, sy, sz);
	return _build_surface_mesh(filled, origin, region, color);
}


Dictionary VoxelEditorNative::arch_execute(
		const Vector3i &point_a, const Vector3i &point_b,
		double thickness,
		const PackedByteArray &voxel_data, int vid,
		int tile_x, int tile_y, int tile_z) {

	Dictionary result;

	double dx = point_b.x - point_a.x;
	double dz = point_b.z - point_a.z;
	double len = std::sqrt(dx * dx + dz * dz);
	double R = len * 0.5;
	double pad = R + thickness + 2;
	int base_y = std::min(point_a.y, point_b.y);

	int mx = (point_a.x + point_b.x) / 2;
	int mz = (point_a.z + point_b.z) / 2;

	int min_x = std::max(0, (int)std::floor(mx - pad));
	int max_x = std::min(tile_x - 1, (int)std::ceil(mx + pad));
	int min_y = std::max(0, base_y);
	int max_y = std::min(tile_y - 1, (int)std::ceil(base_y + R + thickness + 2));
	int min_z = std::max(0, (int)std::floor(mz - pad));
	int max_z = std::min(tile_z - 1, (int)std::ceil(mz + pad));

	int data_size = voxel_data.size();
	const uint8_t *data = voxel_data.ptr();

	for (int z = min_z; z <= max_z; z++) {
		for (int y = min_y; y <= max_y; y++) {
			for (int x = min_x; x <= max_x; x++) {
				if (!_eval_arch(x, y, z, point_a, point_b, thickness))
					continue;
				uint16_t old_id = _get_voxel(data, data_size, x, y, z,
						tile_x, tile_y, tile_z);
				if ((int)old_id != vid) {
					result[Vector3i(x, y, z)] = vid;
				}
			}
		}
	}

	return result;
}

} // namespace godot
