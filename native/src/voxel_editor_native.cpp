#include "voxel_editor_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

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
}

// ═══════════════════════════════════════════════════════════════════════════
// Palette color resolution
// ═══════════════════════════════════════════════════════════════════════════

Color VoxelEditorNative::_resolve_palette_color(const PackedColorArray &palette_colors, uint16_t voxel_id) {
	if (voxel_id == 0) return Color(0, 0, 0, 0);
	// Visual variant is high byte — used as palette index
	int visual = (voxel_id >> 8) & 0xFF;
	if (visual < palette_colors.size()) {
		return palette_colors[visual];
	}
	// Fallback: hash-based color for unmapped IDs
	float r = static_cast<float>((voxel_id * 7 + 13) % 256) / 255.0f;
	float g = static_cast<float>((voxel_id * 31 + 7) % 256) / 255.0f;
	float b = static_cast<float>((voxel_id * 53 + 29) % 256) / 255.0f;
	return Color(r, g, b, 1.0f);
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
			_greedy_face(data, data_size, palette_colors, ox, oy, oz, axis, dir,
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

void VoxelEditorNative::_greedy_face(const uint8_t *data, int data_size,
		const PackedColorArray &palette_colors,
		int ox, int oy, int oz,
		int axis, int dir,
		PackedVector3Array &verts, PackedColorArray &colors,
		PackedVector3Array &normals,
		int tile_x, int tile_y, int tile_z) {

	Vector3 normal = Vector3(0, 0, 0);
	normal[axis] = -1.0f + dir * 2.0f;

	int u_axis, v_axis;
	if (axis == 0) { u_axis = 2; v_axis = 1; }
	else if (axis == 1) { u_axis = 0; v_axis = 2; }
	else { u_axis = 0; v_axis = 1; }

	int step = dir == 0 ? -1 : 1;
	uint16_t mask[CHUNK_SIZE * CHUNK_SIZE];

	for (int d = 0; d < CHUNK_SIZE; d++) {
		memset(mask, 0, sizeof(mask));

		for (int v = 0; v < CHUNK_SIZE; v++) {
			for (int u = 0; u < CHUNK_SIZE; u++) {
				int wx, wy, wz;
				if (axis == 0) { wx = ox + d; wz = oz + u; wy = oy + v; }
				else if (axis == 1) { wy = oy + d; wx = ox + u; wz = oz + v; }
				else { wz = oz + d; wx = ox + u; wy = oy + v; }

				uint16_t voxel = _get_voxel(data, data_size, wx, wy, wz, tile_x, tile_y, tile_z);
				if (voxel == 0) continue;

				int nx = wx, ny = wy, nz = wz;
				if (axis == 0) nx += step;
				else if (axis == 1) ny += step;
				else nz += step;

				uint16_t neighbor = _get_voxel(data, data_size, nx, ny, nz, tile_x, tile_y, tile_z);
				if (neighbor == 0) {
					mask[u + v * CHUNK_SIZE] = voxel;
				}
			}
		}

		// Greedy merge
		for (int v = 0; v < CHUNK_SIZE; v++) {
			int u = 0;
			while (u < CHUNK_SIZE) {
				uint16_t voxel_id = mask[u + v * CHUNK_SIZE];
				if (voxel_id == 0) { u++; continue; }

				int w = 1;
				while (u + w < CHUNK_SIZE && mask[u + w + v * CHUNK_SIZE] == voxel_id) w++;

				int h = 1;
				bool done = false;
				while (v + h < CHUNK_SIZE && !done) {
					for (int k = 0; k < w; k++) {
						if (mask[u + k + (v + h) * CHUNK_SIZE] != voxel_id) {
							done = true;
							break;
						}
					}
					if (!done) h++;
				}

				// Emit quad
				Color color = _resolve_palette_color(palette_colors, voxel_id);

				Vector3 corners[4];
				for (int i = 0; i < 4; i++) {
					Vector3 corner(0, 0, 0);
					corner[axis] = static_cast<float>(d + dir);
					float cu = static_cast<float>(u + (i & 1) * w);
					float cv = static_cast<float>(v + ((i >> 1) & 1) * h);
					corner[u_axis] = cu;
					corner[v_axis] = cv;
					corners[i] = corner;
				}

				bool flip = (axis < 2) == (dir == 1);

				if (!flip) {
					verts.push_back(corners[0]); verts.push_back(corners[1]); verts.push_back(corners[2]);
					verts.push_back(corners[2]); verts.push_back(corners[1]); verts.push_back(corners[3]);
				} else {
					verts.push_back(corners[0]); verts.push_back(corners[2]); verts.push_back(corners[1]);
					verts.push_back(corners[1]); verts.push_back(corners[2]); verts.push_back(corners[3]);
				}

				for (int i = 0; i < 6; i++) {
					colors.push_back(color);
					normals.push_back(normal);
				}

				for (int dv = 0; dv < h; dv++) {
					for (int du = 0; du < w; du++) {
						mask[u + du + (v + dv) * CHUNK_SIZE] = 0;
					}
				}

				u += w;
			}
		}
	}
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

} // namespace godot
