#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0, r8ui) uniform uimage3D tex_current;
layout(set = 0, binding = 1, r8ui) uniform uimage3D tex_next;

layout(set = 0, binding = 2) buffer GeometryChanges {
	uint change_count;
	uvec2 changes[32768];
} geo;

layout(set = 0, binding = 3, r8ui) uniform uimage3D tex_mirror;

layout(push_constant) uniform Params {
	uint tick_parity;
	uint tick_count;
	uint mode; // 0 = simulate, 1 = diff
	uint pad;
} pc;

const int SIM_X = 256;
const int SIM_Y = 16;
const int SIM_Z = 256;

const uint MAT_AIR     = 0u;
const uint MAT_STONE   = 1u;
const uint MAT_BEDROCK = 2u;
const uint MAT_WATER   = 3u;
const uint MAT_DIRT    = 4u;
const uint MAT_MUD     = 5u;
const uint MAT_LAVA    = 6u;
const uint MAT_ACID    = 7u;
const uint MAT_GAS     = 8u;
const uint NOT_LOADED  = 0x7Fu;
const uint NO_REACTION = 0xFFu;
const uint GEO_MAX     = 32768u;

// ── helpers ──

uint read_raw(ivec3 p) {
	if (any(lessThan(p, ivec3(0))) || p.x >= SIM_X || p.y >= SIM_Y || p.z >= SIM_Z)
		return MAT_BEDROCK;
	return imageLoad(tex_current, p).r;
}

void wrt(ivec3 p, uint v) {
	if (any(lessThan(p, ivec3(0))) || p.x >= SIM_X || p.y >= SIM_Y || p.z >= SIM_Z)
		return;
	imageStore(tex_next, p, uvec4(v, 0u, 0u, 0u));
}

bool is_fluid(uint id) { return id == MAT_WATER || id == MAT_LAVA || id == MAT_ACID; }
bool is_gas(uint id)   { return id == MAT_GAS; }
bool is_solid(uint id) { return id != MAT_AIR && !is_fluid(id) && !is_gas(id); }

// Simple hash for deterministic random
uint hash_pos(ivec3 p, uint tick) {
	return uint(p.x * 73856093) ^ uint(p.y * 19349663) ^ uint(p.z * 83492791) ^ (tick * 2654435761u);
}

// ── reactions ──

uint react(ivec3 pos, uint my_id) {
	ivec3 dirs[6] = ivec3[6](
		ivec3(1,0,0), ivec3(-1,0,0),
		ivec3(0,1,0), ivec3(0,-1,0),
		ivec3(0,0,1), ivec3(0,0,-1)
	);

	for (int i = 0; i < 6; i++) {
		uint ni = read_raw(pos + dirs[i]);
		if (ni == MAT_AIR) continue;

		if (my_id == MAT_WATER && ni == MAT_LAVA) {
			wrt(pos + dirs[i], MAT_STONE);
			return MAT_AIR;
		}
		if (my_id == MAT_LAVA && ni == MAT_WATER) {
			wrt(pos + dirs[i], MAT_AIR);
			return MAT_STONE;
		}
		if (my_id == MAT_WATER && ni == MAT_ACID) {
			wrt(pos + dirs[i], MAT_GAS);
			return MAT_GAS;
		}
		if (my_id == MAT_ACID && ni == MAT_WATER) {
			wrt(pos + dirs[i], MAT_GAS);
			return MAT_GAS;
		}
		if (my_id == MAT_DIRT && ni == MAT_WATER) {
			return MAT_MUD;
		}
	}
	return NO_REACTION;
}

// ── fluid simulation ──

void sim_fluid(ivec3 pos, uint id) {
	// Lava ticks slower
	if (id == MAT_LAVA && pc.tick_count % 3u != 0u) {
		wrt(pos, id);
		return;
	}

	// Check reactions
	uint rx = react(pos, id);
	if (rx != NO_REACTION) {
		wrt(pos, rx);
		return;
	}

	// Check below
	ivec3 below = pos + ivec3(0, -1, 0);
	uint bi = read_raw(below);

	// Fall into air
	if (bi == MAT_AIR) {
		wrt(below, id);
		wrt(pos, MAT_AIR);
		return;
	}

	// Fall through gas (swap)
	if (is_gas(bi)) {
		wrt(below, id);
		wrt(pos, bi);
		return;
	}

	// On solid ground: stay
	if (is_solid(bi)) {
		wrt(pos, id);
		return;
	}

	// On fluid: try random horizontal move
	if (is_fluid(bi)) {
		uint h = hash_pos(pos, pc.tick_count);
		uint start_dir = h & 3u;

		ivec3 cd[4] = ivec3[4](ivec3(1,0,0), ivec3(-1,0,0), ivec3(0,0,1), ivec3(0,0,-1));
		for (uint i = 0u; i < 4u; i++) {
			uint di = (start_dir + i) & 3u;
			ivec3 np = pos + cd[di];
			uint neighbor = read_raw(np);
			if (neighbor != MAT_AIR) continue;

			uint target_below = read_raw(np + ivec3(0, -1, 0));
			if (is_solid(target_below) || target_below == id) {
				wrt(np, id);
				wrt(pos, MAT_AIR);
				return;
			}
		}

		// Can't move: stay
		wrt(pos, id);
		return;
	}

	// Default: stay
	wrt(pos, id);
}

// ── gas simulation ──

void sim_gas(ivec3 pos, uint id) {
	if (pc.tick_count % 2u != 0u) {
		wrt(pos, id);
		return;
	}

	// Dissipate randomly
	uint h = hash_pos(pos, pc.tick_count);
	if ((h & 0xFu) == 0u) {
		wrt(pos, MAT_AIR);
		return;
	}

	// Rise
	ivec3 above = pos + ivec3(0, 1, 0);
	uint ai = read_raw(above);

	if (ai == MAT_AIR) {
		wrt(above, id);
		wrt(pos, MAT_AIR);
		return;
	}
	if (is_fluid(ai)) {
		wrt(above, id);
		wrt(pos, ai);
		return;
	}

	// Spread horizontally
	uint start_dir = (h >> 4u) & 3u;
	ivec3 cd[4] = ivec3[4](ivec3(1,0,0), ivec3(-1,0,0), ivec3(0,0,1), ivec3(0,0,-1));
	for (uint i = 0u; i < 4u; i++) {
		uint di = (start_dir + i) & 3u;
		ivec3 np = pos + cd[di];
		if (read_raw(np) == MAT_AIR) {
			wrt(np, id);
			wrt(pos, MAT_AIR);
			return;
		}
	}

	wrt(pos, id);
}

// ── diff mode ──

void run_diff(ivec3 pos) {
	uint mirror_raw = imageLoad(tex_mirror, pos).r;
	uint next_raw   = imageLoad(tex_next, pos).r;

	if (mirror_raw != next_raw) {
		uint idx = atomicAdd(geo.change_count, 1u);
		if (idx < GEO_MAX) {
			geo.changes[idx] = uvec2(
				uint(pos.x) | (uint(pos.y) << 10u) | (uint(pos.z) << 20u),
				next_raw
			);
			imageStore(tex_mirror, pos, uvec4(next_raw, 0u, 0u, 0u));
		}
	}
}

// ── main ──

void main() {
	ivec3 pos = ivec3(gl_GlobalInvocationID);
	if (pos.x >= SIM_X || pos.y >= SIM_Y || pos.z >= SIM_Z) return;

	if (pc.mode == 1u) {
		run_diff(pos);
		return;
	}

	// mode 0: simulate
	uint parity = uint((pos.x + pos.y + pos.z) % 2);
	if (parity != pc.tick_parity)
		return;

	uint id = imageLoad(tex_current, pos).r;

	if (id == MAT_AIR || id == MAT_BEDROCK || id == NOT_LOADED) {
		wrt(pos, id);
		return;
	}

	if (is_solid(id)) {
		uint rx = react(pos, id);
		if (rx != NO_REACTION) {
			wrt(pos, rx);
		} else {
			wrt(pos, id);
		}
		return;
	}

	if (is_gas(id))
		sim_gas(pos, id);
	else if (is_fluid(id))
		sim_fluid(pos, id);
	else
		wrt(pos, id);
}
