#include "material_palette.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void MaterialPalette::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_albedo_colors", "colors"), &MaterialPalette::set_albedo_colors);
	ClassDB::bind_method(D_METHOD("get_albedo_colors"), &MaterialPalette::get_albedo_colors);
	ClassDB::bind_method(D_METHOD("set_flags_bytes", "flags"), &MaterialPalette::set_flags_bytes);
	ClassDB::bind_method(D_METHOD("get_flags_bytes"), &MaterialPalette::get_flags_bytes);
	ClassDB::bind_method(D_METHOD("set_entry", "base_id", "albedo", "flags"), &MaterialPalette::set_entry);
	ClassDB::bind_method(D_METHOD("get_albedo", "base_id"), &MaterialPalette::get_albedo);
	ClassDB::bind_method(D_METHOD("get_flags", "base_id"), &MaterialPalette::get_flags);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "albedo_colors"),
			"set_albedo_colors", "get_albedo_colors");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "flags_bytes"),
			"set_flags_bytes", "get_flags_bytes");

	BIND_CONSTANT(FLAG_SOLID);
	BIND_CONSTANT(FLAG_FLUID);
	BIND_CONSTANT(FLAG_GAS);
	BIND_CONSTANT(FLAG_POWDER);
	BIND_CONSTANT(FLAG_TRANSPARENT);
	BIND_CONSTANT(FLAG_EMISSIVE);
}

MaterialPalette::MaterialPalette() {
	_ensure_sized();
}

void MaterialPalette::_ensure_sized() {
	if (_albedo.size() < PALETTE_SIZE) _albedo.resize(PALETTE_SIZE);
	if (_flags.size() < PALETTE_SIZE) _flags.resize(PALETTE_SIZE);
}

void MaterialPalette::set_albedo_colors(const PackedColorArray &p) {
	_albedo = p;
	_ensure_sized();
}

void MaterialPalette::set_flags_bytes(const PackedByteArray &p) {
	_flags = p;
	_ensure_sized();
}

void MaterialPalette::set_entry(int base_id, const Color &albedo, int flags) {
	if (base_id < 0 || base_id >= PALETTE_SIZE) return;
	_ensure_sized();
	_albedo.set(base_id, albedo);
	_flags.set(base_id, static_cast<uint8_t>(flags));
}

Color MaterialPalette::get_albedo(int base_id) const {
	if (base_id < 0 || base_id >= _albedo.size()) return Color(0, 0, 0, 1);
	return _albedo[base_id];
}

int MaterialPalette::get_flags(int base_id) const {
	if (base_id < 0 || base_id >= _flags.size()) return 0;
	return _flags[base_id];
}

Ref<MaterialPalette> MaterialPalette::make_default() {
	Ref<MaterialPalette> p;
	p.instantiate();

	// Category ID lists (must match MaterialRegistry in GDScript).
	static const uint8_t FLUID[] = {
		3,6,7,32,36,42,47,50,55,62,65,72,75,82,86,
		90,91,92,93,94,95,96,97,98,99,100,101,102,
		104,105,106,107,108,109,110,
		111,112,113,122
	};
	static const uint8_t GAS[] = { 8,18,19,43,52,74,83,103 };
	static const uint8_t POWDER[] = {
		5,9,10,13,14,15,16,17,
		31,46,51,61,63,64,73,76,114
	};

	// Mark categories via flag bitmask table.
	uint8_t cat[PALETTE_SIZE] = {};
	for (uint8_t id : FLUID) cat[id] = FLAG_FLUID | FLAG_TRANSPARENT;
	for (uint8_t id : GAS) cat[id] = FLAG_GAS | FLAG_TRANSPARENT;
	for (uint8_t id : POWDER) cat[id] = FLAG_POWDER;
	// Everything else with id > 0 defaults to FLAG_SOLID.
	for (int id = 1; id < PALETTE_SIZE; id++) {
		if (cat[id] == 0) cat[id] = FLAG_SOLID;
	}
	cat[0] = 0; // AIR

	// Override specific flags.
	cat[6] |= FLAG_EMISSIVE;   // LAVA
	cat[64] |= FLAG_EMISSIVE;  // EMBER
	cat[74] |= FLAG_EMISSIVE;  // SPARK
	cat[81] |= FLAG_EMISSIVE;  // RIFT_CRYSTAL
	cat[132] |= FLAG_EMISSIVE; // GLOWCAP

	// Hand-tuned colors for the core 20 materials, hash-based for the rest.
	// clang-format off
	struct { uint8_t id; Color c; } explicit_colors[] = {
		{  0, Color(0,0,0,0)},              // AIR
		{  1, Color(0.50,0.50,0.50)},       // STONE
		{  2, Color(0.20,0.20,0.22)},       // BEDROCK
		{  3, Color(0.20,0.45,0.85,0.70)},  // WATER
		{  4, Color(0.45,0.30,0.18)},       // DIRT
		{  5, Color(0.35,0.25,0.15)},       // MUD
		{  6, Color(0.95,0.35,0.10)},       // LAVA
		{  7, Color(0.55,0.95,0.20,0.70)},  // ACID
		{  8, Color(0.80,0.80,0.85,0.30)},  // STEAM
		{  9, Color(0.85,0.78,0.55)},       // SAND
		{ 10, Color(0.55,0.52,0.48)},       // GRAVEL
		{ 11, Color(0.75,0.90,0.95)},       // ICE
		{ 12, Color(0.80,0.85,0.90,0.50)},  // GLASS
		{ 13, Color(0.15,0.15,0.15)},       // COAL
		{ 14, Color(0.40,0.35,0.30)},       // GUNPOWDER
		{ 15, Color(0.92,0.92,0.95)},       // SNOW
		{ 16, Color(0.90,0.88,0.82)},       // SALT
		{ 17, Color(0.55,0.52,0.50)},       // ASH
		{ 18, Color(0.45,0.45,0.50,0.40)},  // SMOKE
		{ 19, Color(0.40,0.55,0.25,0.50)},  // TOXIC_GAS
		{ 20, Color(0.55,0.35,0.20)},       // WOOD
		{ 21, Color(0.60,0.60,0.62)},       // METAL
		{ 22, Color(0.65,0.30,0.25)},       // BRICK
		{ 23, Color(0.85,0.83,0.80)},       // MARBLE
		{ 24, Color(0.60,0.80,0.90,0.60)},  // CRYSTAL
		{ 25, Color(0.12,0.08,0.15)},       // OBSIDIAN
		{ 32, Color(0.60,0.10,0.10,0.70)},  // BLOOD
		{ 62, Color(0.90,0.50,0.15,0.80)},  // MOLTEN_METAL
	};
	// clang-format on

	// Fill all slots with golden-ratio hash-based distinguishable colors.
	for (int id = 1; id < PALETTE_SIZE; id++) {
		float hue = fmodf(static_cast<float>(id) * 0.618033988f, 1.0f);
		float sat = 0.55f, val = 0.65f, alpha = 1.0f;
		if (cat[id] & FLAG_FLUID) { sat = 0.6f; val = 0.7f; alpha = 0.7f; }
		if (cat[id] & FLAG_GAS) { sat = 0.3f; val = 0.8f; alpha = 0.35f; }
		if (cat[id] & FLAG_POWDER) { sat = 0.45f; val = 0.6f; }
		p->set_entry(id, Color::from_hsv(hue, sat, val, alpha), cat[id]);
	}

	// Override with explicit hand-tuned colors.
	for (const auto &ec : explicit_colors) {
		int flags = cat[ec.id];
		p->set_entry(ec.id, ec.c, flags);
	}

	return p;
}

} // namespace godot
