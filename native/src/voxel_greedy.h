#ifndef VOXL_VOXEL_GREEDY_H
#define VOXL_VOXEL_GREEDY_H

#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <cstring>

namespace godot {
namespace voxl_greedy {

inline int voxel_index(int x, int y, int z, int tx, int ty) {
	return (x + y * tx + z * tx * ty) * 2;
}

inline bool in_bounds(int x, int y, int z, int tx, int ty, int tz) {
	return x >= 0 && x < tx && y >= 0 && y < ty && z >= 0 && z < tz;
}

inline uint16_t get_voxel(const uint8_t *data, int data_size,
		int x, int y, int z, int tx, int ty, int tz) {
	if (!in_bounds(x, y, z, tx, ty, tz)) return 0;
	int idx = voxel_index(x, y, z, tx, ty);
	if (idx + 1 >= data_size) return 0;
	return data[idx] | (data[idx + 1] << 8);
}

Color resolve_palette_color(const PackedColorArray &palette_colors, uint16_t voxel_id);

template <int CHUNK_SIZE>
void build_face_quads(const uint8_t *data, int data_size,
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

				uint16_t voxel = get_voxel(data, data_size, wx, wy, wz, tile_x, tile_y, tile_z);
				if (voxel == 0) continue;

				int nx = wx, ny = wy, nz = wz;
				if (axis == 0) nx += step;
				else if (axis == 1) ny += step;
				else nz += step;

				uint16_t neighbor = get_voxel(data, data_size, nx, ny, nz, tile_x, tile_y, tile_z);
				if (neighbor == 0) {
					mask[u + v * CHUNK_SIZE] = voxel;
				}
			}
		}

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

				Color color = resolve_palette_color(palette_colors, voxel_id);

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

} // namespace voxl_greedy
} // namespace godot

#endif // VOXL_VOXEL_GREEDY_H
