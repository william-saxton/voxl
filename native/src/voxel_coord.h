#ifndef VOXL_VOXEL_COORD_H
#define VOXL_VOXEL_COORD_H

#include <godot_cpp/core/math.hpp>

#include <cstdint>

namespace godot {
namespace voxl {

static constexpr int CHUNK_X = 32;
static constexpr int CHUNK_Y = 112;
static constexpr int CHUNK_Z = 32;
static constexpr int CHUNK_VOL = CHUNK_X * CHUNK_Y * CHUNK_Z;
static constexpr int CHUNK_X_SHIFT = 5;
static constexpr int CHUNK_X_MASK = 0x1F;
static constexpr int CHUNK_Z_SHIFT = 5;
static constexpr int CHUNK_Z_MASK = 0x1F;

static constexpr float VOXEL_SCALE = 0.25f;
static constexpr float INV_VOXEL_SCALE = 4.0f;

static constexpr uint16_t NOT_LOADED = 0x7F7F;
static constexpr uint16_t NO_REACTION = 0xFFFF;

inline int chunk_coord_x(int wx) { return wx >> CHUNK_X_SHIFT; }
inline int chunk_coord_z(int wz) { return wz >> CHUNK_Z_SHIFT; }
inline int local_coord_x(int wx) { return wx & CHUNK_X_MASK; }
inline int local_coord_z(int wz) { return wz & CHUNK_Z_MASK; }

inline int world_to_voxel(float w) {
	return int(Math::floor(w * INV_VOXEL_SCALE));
}

inline int voxel_index(int lx, int ly, int lz) {
	return lx + ly * CHUNK_X + lz * CHUNK_X * CHUNK_Y;
}

} // namespace voxl
} // namespace godot

#endif // VOXL_VOXEL_COORD_H
