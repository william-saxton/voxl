#include "voxel_greedy.h"

namespace godot {
namespace voxl_greedy {

Color resolve_palette_color(const PackedColorArray &palette_colors, uint16_t voxel_id) {
	if (voxel_id == 0) return Color(0, 0, 0, 0);
	int visual = (voxel_id >> 8) & 0xFF;
	if (visual < palette_colors.size()) {
		return palette_colors[visual];
	}
	float r = static_cast<float>((voxel_id * 7 + 13) % 256) / 255.0f;
	float g = static_cast<float>((voxel_id * 31 + 7) % 256) / 255.0f;
	float b = static_cast<float>((voxel_id * 53 + 29) % 256) / 255.0f;
	return Color(r, g, b, 1.0f);
}

} // namespace voxl_greedy
} // namespace godot
