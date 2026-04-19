#ifndef VOXL_MATERIAL_PALETTE_H
#define VOXL_MATERIAL_PALETTE_H

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>

#include <cstdint>

namespace godot {

class MaterialPalette : public Resource {
	GDCLASS(MaterialPalette, Resource)

public:
	// Flag bits for per-material mesher/sim behavior.
	enum Flags : uint8_t {
		FLAG_SOLID       = 1 << 0,  // Emits collision faces.
		FLAG_FLUID       = 1 << 1,
		FLAG_GAS         = 1 << 2,
		FLAG_POWDER      = 1 << 3,
		FLAG_TRANSPARENT = 1 << 4,  // Face culling against same-kind neighbors.
		FLAG_EMISSIVE    = 1 << 5,
	};

	static constexpr int PALETTE_SIZE = 256;

	MaterialPalette();

	void set_albedo_colors(const PackedColorArray &p);
	PackedColorArray get_albedo_colors() const { return _albedo; }

	void set_flags_bytes(const PackedByteArray &p);
	PackedByteArray get_flags_bytes() const { return _flags; }

	// Per-entry setters (convenience from GDScript).
	void set_entry(int base_id, const Color &albedo, int flags);
	Color get_albedo(int base_id) const;
	int get_flags(int base_id) const;

	// C++ hot-path accessors (no allocation).
	inline Color albedo_fast(uint8_t base_id) const {
		return base_id < _albedo.size() ? _albedo[base_id] : Color(0, 0, 0, 1);
	}
	inline uint8_t flags_fast(uint8_t base_id) const {
		return base_id < _flags.size() ? static_cast<uint8_t>(_flags[base_id]) : 0;
	}

	// Default 9-material palette matching the pre-branch VoxelBlockyLibrary colors.
	static Ref<MaterialPalette> make_default();

protected:
	static void _bind_methods();

private:
	PackedColorArray _albedo;
	PackedByteArray _flags;

	void _ensure_sized();
};

} // namespace godot

#endif // VOXL_MATERIAL_PALETTE_H
