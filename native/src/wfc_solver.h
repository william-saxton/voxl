#ifndef WFC_SOLVER_H
#define WFC_SOLVER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>
#include <cstdint>
#include <random>

namespace godot {

class WFCSolver : public RefCounted {
	GDCLASS(WFCSolver, RefCounted)

public:
	WFCSolver();
	~WFCSolver();

	void set_grid_size(int width, int height);
	void set_biome_map(const PackedByteArray &biome_data, int width);
	void set_fixed_cells(const Dictionary &fixed);
	void add_tile(int tile_id, int edge_n, int edge_s, int edge_e, int edge_w,
			float weight, const String &biome);
	void add_structure(int struct_id, const Vector2i &size,
			const Dictionary &external_edges, const String &biome);
	void set_seed(int seed);

	bool solve();
	int get_tile_at(int gx, int gz) const;
	PackedInt32Array get_layout() const;

protected:
	static void _bind_methods();

private:
	// ── Tile definition ──

	struct TileDef {
		int id;
		int edges[4]; // N, S, E, W
		float weight;
		String biome;
	};

	// ── Structure definition ──

	struct StructureDef {
		int id;
		Vector2i size;
		Dictionary external_edges;
		String biome;
		// Sub-tile IDs generated during solve
		std::vector<int> sub_tile_ids;
	};

	// ── Grid cell ──

	struct Cell {
		bool collapsed;
		int tile_id;          // Valid only when collapsed
		std::vector<int> options; // Indices into _tiles
		uint8_t biome_id;
	};

	// ── Direction helpers ──

	// Directions: 0=N(z-1), 1=S(z+1), 2=E(x+1), 3=W(x-1)
	static constexpr int DX[4] = { 0, 0, 1, -1 };
	static constexpr int DZ[4] = { -1, 1, 0, 0 };
	// Opposite direction index
	static constexpr int OPP[4] = { 1, 0, 3, 2 };

	// ── State ──

	int _grid_w = 0;
	int _grid_h = 0;
	std::vector<Cell> _cells;
	std::vector<TileDef> _tiles;
	std::vector<StructureDef> _structures;
	std::vector<uint8_t> _biome_data;
	Dictionary _fixed_cells;
	int _rng_seed = 0;
	std::mt19937 _rng;

	// ── Internal methods ──

	int _cell_index(int gx, int gz) const { return gx + gz * _grid_w; }
	bool _in_bounds(int gx, int gz) const {
		return gx >= 0 && gx < _grid_w && gz >= 0 && gz < _grid_h;
	}

	void _init_cells();
	void _apply_fixed_cells();
	void _place_structures();
	bool _place_structure_at(StructureDef &s, int gx, int gz);

	int _find_min_entropy_cell() const;
	bool _collapse_cell(int idx);
	bool _propagate(int start_idx);
	bool _is_option_valid(int tile_idx, int gx, int gz) const;

	bool _check_connectivity() const;
};

} // namespace godot

#endif
