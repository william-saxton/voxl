#include "wfc_solver.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <queue>
#include <unordered_set>
#include <climits>
#include <cfloat>

using namespace godot;

constexpr int WFCSolver::DX[4];
constexpr int WFCSolver::DZ[4];
constexpr int WFCSolver::OPP[4];

WFCSolver::WFCSolver() {}
WFCSolver::~WFCSolver() {}

void WFCSolver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_grid_size", "width", "height"), &WFCSolver::set_grid_size);
	ClassDB::bind_method(D_METHOD("set_biome_map", "biome_data", "width"), &WFCSolver::set_biome_map);
	ClassDB::bind_method(D_METHOD("set_fixed_cells", "fixed"), &WFCSolver::set_fixed_cells);
	ClassDB::bind_method(D_METHOD("add_tile", "tile_id", "edge_n", "edge_s", "edge_e", "edge_w", "weight", "biome"),
			&WFCSolver::add_tile);
	ClassDB::bind_method(D_METHOD("add_structure", "struct_id", "size", "external_edges", "biome"),
			&WFCSolver::add_structure);
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &WFCSolver::set_seed);
	ClassDB::bind_method(D_METHOD("solve"), &WFCSolver::solve);
	ClassDB::bind_method(D_METHOD("get_tile_at", "gx", "gz"), &WFCSolver::get_tile_at);
	ClassDB::bind_method(D_METHOD("get_layout"), &WFCSolver::get_layout);
}

void WFCSolver::set_grid_size(int width, int height) {
	_grid_w = width;
	_grid_h = height;
}

void WFCSolver::set_biome_map(const PackedByteArray &biome_data, int width) {
	_biome_data.resize(biome_data.size());
	memcpy(_biome_data.data(), biome_data.ptr(), biome_data.size());
}

void WFCSolver::set_fixed_cells(const Dictionary &fixed) {
	_fixed_cells = fixed;
}

void WFCSolver::add_tile(int tile_id, int edge_n, int edge_s, int edge_e, int edge_w,
		float weight, const String &biome) {
	TileDef t;
	t.id = tile_id;
	t.edges[0] = edge_n;
	t.edges[1] = edge_s;
	t.edges[2] = edge_e;
	t.edges[3] = edge_w;
	t.weight = weight;
	t.biome = biome;
	_tiles.push_back(t);
}

void WFCSolver::add_structure(int struct_id, const Vector2i &size,
		const Dictionary &external_edges, const String &biome) {
	StructureDef s;
	s.id = struct_id;
	s.size = size;
	s.external_edges = external_edges;
	s.biome = biome;
	_structures.push_back(s);
}

void WFCSolver::set_seed(int seed) {
	_rng_seed = seed;
}

// ── Solve ──

bool WFCSolver::solve() {
	if (_grid_w <= 0 || _grid_h <= 0 || _tiles.empty()) {
		UtilityFunctions::push_error("[WFCSolver] Invalid grid or no tiles defined");
		return false;
	}

	// Try up to 3 times with incrementing seeds for connectivity
	for (int attempt = 0; attempt < 3; attempt++) {
		_rng.seed(_rng_seed + attempt);
		_init_cells();
		_place_structures();
		_apply_fixed_cells();

		// Initial propagation from all collapsed cells
		for (int i = 0; i < (int)_cells.size(); i++) {
			if (_cells[i].collapsed) {
				if (!_propagate(i)) {
					goto next_attempt;
				}
			}
		}

		// WFC main loop
		{
			int max_iterations = _grid_w * _grid_h;
			for (int iter = 0; iter < max_iterations; iter++) {
				int idx = _find_min_entropy_cell();
				if (idx < 0) {
					break; // All collapsed
				}

				if (!_collapse_cell(idx)) {
					goto next_attempt; // Contradiction
				}

				if (!_propagate(idx)) {
					goto next_attempt; // Contradiction during propagation
				}
			}
		}

		// Verify all cells are collapsed
		{
			bool all_collapsed = true;
			for (const auto &cell : _cells) {
				if (!cell.collapsed) {
					all_collapsed = false;
					break;
				}
			}
			if (!all_collapsed) {
				goto next_attempt;
			}
		}

		// Check connectivity
		if (_check_connectivity()) {
			UtilityFunctions::print("[WFCSolver] Solved on attempt ", attempt + 1);
			return true;
		}

		next_attempt:
		continue;
	}

	UtilityFunctions::push_warning("[WFCSolver] Failed to solve after 3 attempts");
	return false;
}

int WFCSolver::get_tile_at(int gx, int gz) const {
	if (!_in_bounds(gx, gz)) return -1;
	const Cell &c = _cells[_cell_index(gx, gz)];
	return c.collapsed ? c.tile_id : -1;
}

PackedInt32Array WFCSolver::get_layout() const {
	PackedInt32Array result;
	result.resize(_grid_w * _grid_h);
	for (int i = 0; i < (int)_cells.size(); i++) {
		result[i] = _cells[i].collapsed ? _cells[i].tile_id : -1;
	}
	return result;
}

// ── Internal methods ──

void WFCSolver::_init_cells() {
	_cells.resize(_grid_w * _grid_h);

	for (int gz = 0; gz < _grid_h; gz++) {
		for (int gx = 0; gx < _grid_w; gx++) {
			int idx = _cell_index(gx, gz);
			Cell &cell = _cells[idx];
			cell.collapsed = false;
			cell.tile_id = -1;
			cell.options.clear();

			// Get biome for this cell
			cell.biome_id = 0;
			if (idx < (int)_biome_data.size()) {
				cell.biome_id = _biome_data[idx];
			}

			// Populate options: tiles matching this cell's biome (or all if biome is 0/unassigned)
			for (int ti = 0; ti < (int)_tiles.size(); ti++) {
				// Skip structure-internal tiles — they're placed by structure placement
				bool has_internal = false;
				for (int d = 0; d < 4; d++) {
					if (_tiles[ti].edges[d] == 5) { // STRUCTURE_INTERNAL
						has_internal = true;
						break;
					}
				}
				if (has_internal) continue;

				if (cell.biome_id == 0 || _tiles[ti].biome == "" ||
						_tiles[ti].biome == String::num_int64(cell.biome_id)) {
					cell.options.push_back(ti);
				}
			}
		}
	}
}

void WFCSolver::_apply_fixed_cells() {
	Array keys = _fixed_cells.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i pos = keys[i];
		int tile_id = _fixed_cells[keys[i]];
		if (!_in_bounds(pos.x, pos.y)) continue;

		int idx = _cell_index(pos.x, pos.y);
		_cells[idx].collapsed = true;
		_cells[idx].tile_id = tile_id;
		_cells[idx].options.clear();
	}
}

void WFCSolver::_place_structures() {
	if (_structures.empty()) return;

	// Shuffle structure order for variety
	std::vector<int> order(_structures.size());
	for (int i = 0; i < (int)order.size(); i++) order[i] = i;
	std::shuffle(order.begin(), order.end(), _rng);

	for (int si : order) {
		StructureDef &s = _structures[si];

		// Collect candidate positions where the structure fits
		std::vector<std::pair<int, int>> candidates;
		for (int gz = 0; gz <= _grid_h - s.size.y; gz++) {
			for (int gx = 0; gx <= _grid_w - s.size.x; gx++) {
				bool fits = true;
				for (int sz = 0; sz < s.size.y && fits; sz++) {
					for (int sx = 0; sx < s.size.x && fits; sx++) {
						int idx = _cell_index(gx + sx, gz + sz);
						if (_cells[idx].collapsed) {
							fits = false;
						}
					}
				}
				if (fits) {
					candidates.push_back({gx, gz});
				}
			}
		}

		if (!candidates.empty()) {
			std::uniform_int_distribution<int> dist(0, (int)candidates.size() - 1);
			auto [cx, cz] = candidates[dist(_rng)];
			_place_structure_at(s, cx, cz);
		}
	}
}

bool WFCSolver::_place_structure_at(StructureDef &s, int gx, int gz) {
	// Generate sub-tile IDs from the structure's base ID
	s.sub_tile_ids.clear();
	int sub_id = s.id * 1000; // Offset to avoid collisions

	for (int sz = 0; sz < s.size.y; sz++) {
		for (int sx = 0; sx < s.size.x; sx++) {
			int tile_id = sub_id + sx + sz * s.size.x;
			int idx = _cell_index(gx + sx, gz + sz);
			_cells[idx].collapsed = true;
			_cells[idx].tile_id = tile_id;
			_cells[idx].options.clear();
			s.sub_tile_ids.push_back(tile_id);
		}
	}
	return true;
}

int WFCSolver::_find_min_entropy_cell() const {
	int best_idx = -1;
	int best_count = INT_MAX;

	for (int i = 0; i < (int)_cells.size(); i++) {
		if (_cells[i].collapsed) continue;
		int count = (int)_cells[i].options.size();
		if (count == 0) continue; // Contradiction — will be caught later
		if (count < best_count) {
			best_count = count;
			best_idx = i;
		}
	}
	return best_idx;
}

bool WFCSolver::_collapse_cell(int idx) {
	Cell &cell = _cells[idx];
	if (cell.options.empty()) return false;

	// Weighted random selection
	float total_weight = 0.0f;
	for (int ti : cell.options) {
		total_weight += _tiles[ti].weight;
	}

	std::uniform_real_distribution<float> dist(0.0f, total_weight);
	float pick = dist(_rng);
	float accum = 0.0f;

	int chosen = cell.options[0];
	for (int ti : cell.options) {
		accum += _tiles[ti].weight;
		if (accum >= pick) {
			chosen = ti;
			break;
		}
	}

	cell.collapsed = true;
	cell.tile_id = _tiles[chosen].id;
	cell.options.clear();
	return true;
}

bool WFCSolver::_propagate(int start_idx) {
	std::queue<int> worklist;
	worklist.push(start_idx);

	while (!worklist.empty()) {
		int idx = worklist.front();
		worklist.pop();

		int gx = idx % _grid_w;
		int gz = idx / _grid_w;

		for (int dir = 0; dir < 4; dir++) {
			int nx = gx + DX[dir];
			int nz = gz + DZ[dir];
			if (!_in_bounds(nx, nz)) continue;

			int nidx = _cell_index(nx, nz);
			Cell &neighbor = _cells[nidx];
			if (neighbor.collapsed) continue;
			if (neighbor.options.empty()) continue;

			// Filter neighbor options based on compatibility with this cell
			std::vector<int> valid;
			for (int nti : neighbor.options) {
				if (_is_option_valid(nti, nx, nz)) {
					valid.push_back(nti);
				}
			}

			if (valid.size() < neighbor.options.size()) {
				if (valid.empty()) {
					return false; // Contradiction
				}
				neighbor.options = valid;
				worklist.push(nidx);
			}
		}
	}
	return true;
}

bool WFCSolver::_is_option_valid(int tile_idx, int gx, int gz) const {
	const TileDef &tile = _tiles[tile_idx];

	for (int dir = 0; dir < 4; dir++) {
		int nx = gx + DX[dir];
		int nz = gz + DZ[dir];

		if (!_in_bounds(nx, nz)) {
			// Border — tile must have BEDROCK_WALL (4) or SOLID_WALL (0) on this edge
			if (tile.edges[dir] != 4 && tile.edges[dir] != 0) {
				return false;
			}
			continue;
		}

		int nidx = _cell_index(nx, nz);
		const Cell &neighbor = _cells[nidx];

		if (neighbor.collapsed) {
			// Find the collapsed tile's edge facing us
			int opp_dir = OPP[dir];

			// If neighbor is a fixed/structure cell, find its tile def
			int neighbor_edge = -1;
			for (const auto &t : _tiles) {
				if (t.id == neighbor.tile_id) {
					neighbor_edge = t.edges[opp_dir];
					break;
				}
			}

			// If we couldn't find the tile def (structure sub-tile), allow it
			if (neighbor_edge < 0) continue;

			if (tile.edges[dir] != neighbor_edge) {
				return false;
			}
		}
		// If neighbor is uncollapsed, we check if at least one of its options
		// is compatible with our edge
		else if (!neighbor.options.empty()) {
			bool any_compatible = false;
			int opp_dir = OPP[dir];
			for (int nti : neighbor.options) {
				if (_tiles[nti].edges[opp_dir] == tile.edges[dir]) {
					any_compatible = true;
					break;
				}
			}
			if (!any_compatible) {
				return false;
			}
		}
	}
	return true;
}

bool WFCSolver::_check_connectivity() const {
	if (_cells.empty()) return true;

	// Find first collapsed cell with an OPEN_GROUND or CORRIDOR edge as start
	int start = -1;
	for (int i = 0; i < (int)_cells.size(); i++) {
		if (!_cells[i].collapsed) return false;
		// Find the tile def
		for (const auto &t : _tiles) {
			if (t.id == _cells[i].tile_id) {
				for (int d = 0; d < 4; d++) {
					if (t.edges[d] == 1 || t.edges[d] == 2 || t.edges[d] == 3) {
						start = i;
						break;
					}
				}
				break;
			}
		}
		if (start >= 0) break;
	}

	if (start < 0) {
		// No passable tiles at all — trivially "connected"
		return true;
	}

	// BFS flood fill
	std::vector<bool> visited(_cells.size(), false);
	std::queue<int> bfs;
	bfs.push(start);
	visited[start] = true;

	while (!bfs.empty()) {
		int idx = bfs.front();
		bfs.pop();
		int gx = idx % _grid_w;
		int gz = idx / _grid_w;

		// Find this cell's tile edges
		const TileDef *my_tile = nullptr;
		for (const auto &t : _tiles) {
			if (t.id == _cells[idx].tile_id) {
				my_tile = &t;
				break;
			}
		}
		if (!my_tile) continue;

		for (int dir = 0; dir < 4; dir++) {
			// Only traverse through passable edges
			if (my_tile->edges[dir] != 1 && my_tile->edges[dir] != 2 && my_tile->edges[dir] != 3) {
				continue;
			}

			int nx = gx + DX[dir];
			int nz = gz + DZ[dir];
			if (!_in_bounds(nx, nz)) continue;

			int nidx = _cell_index(nx, nz);
			if (visited[nidx]) continue;

			// Check neighbor has matching passable edge facing back
			const TileDef *n_tile = nullptr;
			for (const auto &t : _tiles) {
				if (t.id == _cells[nidx].tile_id) {
					n_tile = &t;
					break;
				}
			}
			if (!n_tile) continue;

			int opp = OPP[dir];
			if (n_tile->edges[opp] == my_tile->edges[dir]) {
				visited[nidx] = true;
				bfs.push(nidx);
			}
		}
	}

	// Count all passable cells and check if we reached them all
	int total_passable = 0;
	int reached_passable = 0;
	for (int i = 0; i < (int)_cells.size(); i++) {
		bool is_passable = false;
		for (const auto &t : _tiles) {
			if (t.id == _cells[i].tile_id) {
				for (int d = 0; d < 4; d++) {
					if (t.edges[d] == 1 || t.edges[d] == 2 || t.edges[d] == 3) {
						is_passable = true;
						break;
					}
				}
				break;
			}
		}
		if (is_passable) {
			total_passable++;
			if (visited[i]) reached_passable++;
		}
	}

	return reached_passable == total_passable;
}
