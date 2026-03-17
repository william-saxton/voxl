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
const int SIM_Y = 32;
const int SIM_Z = 256;

const uint MAT_AIR        = 0u;
const uint MAT_STONE      = 1u;
const uint MAT_BEDROCK    = 2u;
const uint MAT_WATER_BASE = 3u;
const uint MAT_DIRT       = 19u;
const uint MAT_MUD        = 20u;
const uint MAT_LAVA_BASE  = 21u;
const uint MAT_ACID_BASE  = 37u;
const uint MAT_GAS_BASE   = 53u;
const uint FLUID_LEVELS   = 16u;

const uint SOURCE_FLAG = 0x80u;
const uint ID_MASK     = 0x7Fu;
const uint NO_REACTION = 0xFFu;
const uint GEO_MAX     = 32768u;
const uint NOT_LOADED  = 0x7Fu;

// ── helpers ──

uint read_raw(ivec3 p) {
	if (any(lessThan(p, ivec3(0))) || p.x >= SIM_X || p.y >= SIM_Y || p.z >= SIM_Z)
		return MAT_BEDROCK;
	return imageLoad(tex_current, p).r;
}

uint mid(uint raw)     { return raw & ID_MASK; }
bool src(uint raw)     { return (raw & SOURCE_FLAG) != 0u; }

void wrt(ivec3 p, uint v) {
	if (any(lessThan(p, ivec3(0))) || p.x >= SIM_X || p.y >= SIM_Y || p.z >= SIM_Z)
		return;
	imageStore(tex_next, p, uvec4(v, 0u, 0u, 0u));
}

uint fbase(uint id) {
	if (id >= MAT_WATER_BASE && id < MAT_WATER_BASE + FLUID_LEVELS) return MAT_WATER_BASE;
	if (id >= MAT_LAVA_BASE  && id < MAT_LAVA_BASE  + FLUID_LEVELS) return MAT_LAVA_BASE;
	if (id >= MAT_ACID_BASE  && id < MAT_ACID_BASE  + FLUID_LEVELS) return MAT_ACID_BASE;
	if (id >= MAT_GAS_BASE   && id < MAT_GAS_BASE   + FLUID_LEVELS) return MAT_GAS_BASE;
	return 0u;
}

uint flvl(uint id) {
	uint b = fbase(id);
	return (b > 0u) ? (id - b) : 0u;
}

uint mkfluid(uint base, uint level, bool s) {
	uint id = base + clamp(level, 0u, FLUID_LEVELS - 1u);
	return s ? (id | SOURCE_FLAG) : id;
}

bool is_fluid(uint id) {
	uint b = fbase(id);
	return b == MAT_WATER_BASE || b == MAT_LAVA_BASE || b == MAT_ACID_BASE;
}

bool is_gas(uint id)      { return fbase(id) == MAT_GAS_BASE; }
bool is_solid(uint id)    { return id != MAT_AIR && !is_fluid(id) && !is_gas(id); }
bool is_passable(uint id) { return id == MAT_AIR || is_fluid(id) || is_gas(id); }

uint spread_loss(uint base) {
	if (base == MAT_LAVA_BASE) return 4u;
	return 2u;
}

// ── reactions (pull model) ──

uint react(ivec3 pos, uint my_id, uint my_raw) {
	uint my_b = fbase(my_id);

	ivec3 dirs[6] = ivec3[6](
		ivec3(1,0,0), ivec3(-1,0,0),
		ivec3(0,1,0), ivec3(0,-1,0),
		ivec3(0,0,1), ivec3(0,0,-1)
	);

	for (int i = 0; i < 6; i++) {
		uint nr = read_raw(pos + dirs[i]);
		uint ni = mid(nr);
		if (ni == MAT_AIR) continue;
		uint nb = fbase(ni);

		if (my_b == MAT_WATER_BASE && nb == MAT_LAVA_BASE) {
			uint l = flvl(my_id);
			return (l == 0u) ? MAT_AIR : mkfluid(my_b, l - 1u, src(my_raw));
		}
		if (my_b == MAT_LAVA_BASE && nb == MAT_WATER_BASE) {
			uint l = flvl(my_id);
			return (l == 0u) ? MAT_STONE : mkfluid(my_b, l - 1u, src(my_raw));
		}
		if (my_b == MAT_WATER_BASE && nb == MAT_ACID_BASE) {
			uint l = flvl(my_id);
			return (l == 0u) ? mkfluid(MAT_GAS_BASE, FLUID_LEVELS - 1u, false) : mkfluid(my_b, l - 1u, src(my_raw));
		}
		if (my_b == MAT_ACID_BASE && nb == MAT_WATER_BASE) {
			uint l = flvl(my_id);
			return (l == 0u) ? mkfluid(MAT_GAS_BASE, FLUID_LEVELS - 1u, false) : mkfluid(my_b, l - 1u, src(my_raw));
		}
		if (my_id == MAT_DIRT && nb == MAT_WATER_BASE)
			return MAT_MUD;
	}
	return NO_REACTION;
}

// ── is_fed ──

bool is_fed(ivec3 pos, uint base, uint level) {
	uint above_id = mid(read_raw(pos + ivec3(0, 1, 0)));
	if (is_fluid(above_id) && fbase(above_id) == base)
		return true;

	ivec3 hd[8] = ivec3[8](
		ivec3(1,0,0), ivec3(-1,0,0), ivec3(0,0,1), ivec3(0,0,-1),
		ivec3(1,0,1), ivec3(1,0,-1), ivec3(-1,0,1), ivec3(-1,0,-1)
	);
	for (int i = 0; i < 8; i++) {
		uint nr = read_raw(pos + hd[i]);
		uint ni = mid(nr);
		if (!is_fluid(ni) || fbase(ni) != base) continue;
		uint nl = flvl(ni);
		if (nl > level) return true;
		if (src(nr) && nl >= level) return true;
	}
	return false;
}

// ── fluid simulation ──

void sim_fluid(ivec3 pos, uint raw) {
	uint id   = mid(raw);
	uint base = fbase(id);
	uint lvl  = flvl(id);
	bool s    = src(raw);

	uint td = (base == MAT_LAVA_BASE) ? 3u : 1u;
	if (td > 1u && pc.tick_count % td != 0u) {
		wrt(pos, raw);
		return;
	}

	uint rx = react(pos, id, raw);
	if (rx != NO_REACTION) {
		wrt(pos, rx);
		return;
	}

	if (!s && !is_fed(pos, base, lvl)) {
		wrt(pos, (lvl == 0u) ? MAT_AIR : mkfluid(base, lvl - 1u, false));
		return;
	}

	ivec3 below = pos + ivec3(0, -1, 0);
	uint br = read_raw(below);
	uint bi = mid(br);

	if (bi == MAT_AIR || is_gas(bi)) {
		wrt(below, mkfluid(base, FLUID_LEVELS - 1u, false));
		if (s) {
			wrt(pos, raw);
		} else if (is_gas(bi)) {
			wrt(pos, br);
		} else {
			wrt(pos, MAT_AIR);
		}
		return;
	}

	if (is_fluid(bi) && fbase(bi) == base) {
		uint bl = flvl(bi);
		if (bl < FLUID_LEVELS - 1u) {
			uint tr = min(lvl, FLUID_LEVELS - 1u - bl);
			if (tr > 0u) {
				wrt(below, mkfluid(base, bl + tr, src(br)));
				if (s) {
					wrt(pos, raw);
				} else {
					uint rem = lvl - tr;
					wrt(pos, (rem == 0u) ? MAT_AIR : mkfluid(base, rem, false));
				}
				return;
			}
		}
	}

	if (is_solid(bi)) {
		uint sl = spread_loss(base);

		if (lvl >= sl) {
			uint sp = lvl - sl;
			ivec3 cd[4] = ivec3[4](ivec3(1,0,0), ivec3(-1,0,0), ivec3(0,0,1), ivec3(0,0,-1));
			for (int i = 0; i < 4; i++) {
				ivec3 np = pos + cd[i];
				uint nr = read_raw(np);
				uint ni = mid(nr);
				if (ni == MAT_AIR) {
					wrt(np, mkfluid(base, sp, false));
				} else if (is_fluid(ni) && fbase(ni) == base && flvl(ni) < sp) {
					wrt(np, mkfluid(base, sp, src(nr)));
				}
			}
		}

		uint dsl = sl + 1u;
		if (lvl >= dsl) {
			uint dp = lvl - dsl;
			ivec3 dd[4] = ivec3[4](ivec3(1,0,1), ivec3(1,0,-1), ivec3(-1,0,1), ivec3(-1,0,-1));
			for (int i = 0; i < 4; i++) {
				ivec3 np = pos + dd[i];
				uint nr = read_raw(np);
				uint ni = mid(nr);
				if (ni == MAT_AIR) {
					wrt(np, mkfluid(base, dp, false));
				} else if (is_fluid(ni) && fbase(ni) == base && flvl(ni) < dp) {
					wrt(np, mkfluid(base, dp, src(nr)));
				}
			}
		}
	}

	wrt(pos, raw);
}

// ── gas simulation ──

void sim_gas(ivec3 pos, uint raw) {
	uint id   = mid(raw);
	uint base = fbase(id);
	uint lvl  = flvl(id);

	if (pc.tick_count % 2u != 0u) {
		wrt(pos, raw);
		return;
	}

	if (lvl <= 1u) {
		wrt(pos, MAT_AIR);
		return;
	}
	uint nl = lvl - 1u;

	ivec3 above = pos + ivec3(0, 1, 0);
	uint ar = read_raw(above);
	uint ai = mid(ar);

	if (ai == MAT_AIR) {
		wrt(above, mkfluid(base, nl, false));
		wrt(pos, MAT_AIR);
		return;
	}
	if (is_gas(ai) && fbase(ai) == base && flvl(ai) < nl) {
		wrt(above, mkfluid(base, nl, false));
		wrt(pos, MAT_AIR);
		return;
	}

	wrt(pos, mkfluid(base, nl, false));

	if (nl >= 4u) {
		uint sp = nl - 4u;
		ivec3 cd[4] = ivec3[4](ivec3(1,0,0), ivec3(-1,0,0), ivec3(0,0,1), ivec3(0,0,-1));
		for (int i = 0; i < 4; i++) {
			ivec3 np = pos + cd[i];
			if (mid(read_raw(np)) == MAT_AIR)
				wrt(np, mkfluid(base, sp, false));
		}
	}
}

// ── diff mode: compare mirror vs tex_next, queue changes for CPU ──

void run_diff(ivec3 pos) {
	uint mirror_raw = imageLoad(tex_mirror, pos).r;
	uint next_raw   = imageLoad(tex_next, pos).r;

	uint mirror_id = mirror_raw & ID_MASK;
	uint next_id   = next_raw & ID_MASK;

	if (mirror_id != next_id) {
		uint idx = atomicAdd(geo.change_count, 1u);
		if (idx < GEO_MAX) {
			geo.changes[idx] = uvec2(
				uint(pos.x) | (uint(pos.y) << 10u) | (uint(pos.z) << 20u),
				next_id
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

	// mode 0: simulate (tex_next pre-copied from tex_current, so non-updating cells already correct)
	uint parity = uint((pos.x + pos.y + pos.z) % 2);
	if (parity != pc.tick_parity)
		return;

	uint raw = imageLoad(tex_current, pos).r;
	uint id  = mid(raw);

	if (id == MAT_AIR || id == MAT_BEDROCK || id == NOT_LOADED) {
		wrt(pos, raw);
		return;
	}

	if (is_solid(id)) {
		uint rx = react(pos, id, raw);
		if (rx != NO_REACTION) {
			wrt(pos, rx);
		} else {
			wrt(pos, raw);
		}
		return;
	}

	if (is_gas(id))
		sim_gas(pos, raw);
	else if (is_fluid(id))
		sim_fluid(pos, raw);
	else
		wrt(pos, raw);
}
