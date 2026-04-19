#include "voxel_mesher_pool.h"

#include "voxel_chunk_store.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstring>

namespace godot {

// Padded snapshot dims: chunk + 1-voxel skin on each side in X/Z.
// Y is padded too, with a SOLID sentinel so we do not emit world-top/bottom faces.
static constexpr int PAD_X = voxl::CHUNK_X + 2;   // 34
static constexpr int PAD_Y = voxl::CHUNK_Y + 2;   // 114
static constexpr int PAD_Z = voxl::CHUNK_Z + 2;   // 34
static constexpr int PAD_VOL = PAD_X * PAD_Y * PAD_Z;
// Y-skin pads with AIR so solid voxels at y=0 / y=CHUNK_Y-1 emit world-cap faces.
static constexpr uint16_t Y_SKIN_SENTINEL = 0;

static inline int pad_idx(int px, int py, int pz) {
	return px + py * PAD_X + pz * PAD_X * PAD_Y;
}

VoxelMesherPool::VoxelMesherPool() {}

VoxelMesherPool::~VoxelMesherPool() {
	stop();
}

void VoxelMesherPool::start(int num_threads) {
	stop();
	if (num_threads < 1) num_threads = 1;
	_running.store(true);
	_workers.reserve(num_threads);
	for (int i = 0; i < num_threads; i++) {
		_workers.emplace_back(&VoxelMesherPool::_worker_fn, this, i);
	}
}

void VoxelMesherPool::stop() {
	_running.store(false);
	_queue_cv.notify_all();
	for (auto &t : _workers) {
		if (t.joinable()) t.join();
	}
	_workers.clear();
	{
		std::lock_guard<std::mutex> lock(_queue_mtx);
		while (!_queue.empty()) _queue.pop();
	}
	{
		std::lock_guard<std::mutex> lock(_result_mtx);
		_results.clear();
	}
}

void VoxelMesherPool::submit(VoxelChunkStore *store, int wcx, int wcz,
		Ref<MaterialPalette> palette, int origin_y) {
	if (!store) return;
	int64_t key = (static_cast<int64_t>(wcx) << 32) | static_cast<uint32_t>(wcz);
	{
		std::lock_guard<std::mutex> lock(_queue_mtx);
		if (_queued_chunks.count(key)) return; // already pending
		_queued_chunks.insert(key);
		_queue.push({store, wcx, wcz, palette, origin_y});
	}
	_queue_cv.notify_one();
}

std::vector<MeshJobResult> VoxelMesherPool::drain_results() {
	std::vector<MeshJobResult> out;
	std::lock_guard<std::mutex> lock(_result_mtx);
	out.swap(_results);
	return out;
}

void VoxelMesherPool::_worker_fn(int /*id*/) {
	while (_running.load()) {
		Job job;
		{
			std::unique_lock<std::mutex> lock(_queue_mtx);
			_queue_cv.wait(lock, [this]() {
				return !_queue.empty() || !_running.load();
			});
			if (!_running.load()) break;
			if (_queue.empty()) continue;
			job = _queue.front();
			_queue.pop();
			int64_t key = (static_cast<int64_t>(job.wcx) << 32) | static_cast<uint32_t>(job.wcz);
			_queued_chunks.erase(key);
		}

		MeshJobResult result;
		result.wcx = job.wcx;
		result.wcz = job.wcz;
		_execute_job(job, result);

		std::lock_guard<std::mutex> lock(_result_mtx);
		_results.push_back(std::move(result));
	}
}

void VoxelMesherPool::_execute_job(const Job &job, MeshJobResult &out) {
	using Chunk = VoxelChunkStore::Chunk;

	Chunk *center = job.store->chunk_at(job.wcx, job.wcz);
	if (!center || center->state.load(std::memory_order_acquire) != Chunk::LOADED) {
		out.discarded = true;
		return;
	}

	// Snapshot generation before copy; recheck after — mimics a lock-free RCU read.
	uint32_t gen_before = center->generation.load(std::memory_order_acquire);

	std::vector<uint16_t> pad(PAD_VOL, voxl::NOT_LOADED);

	// Y skin: top/bottom rows of the padded buffer → non-air sentinel so no world-cap faces emit.
	for (int pz = 0; pz < PAD_Z; pz++) {
		for (int px = 0; px < PAD_X; px++) {
			pad[pad_idx(px, 0, pz)] = Y_SKIN_SENTINEL;
			pad[pad_idx(px, PAD_Y - 1, pz)] = Y_SKIN_SENTINEL;
		}
	}

	// Copy center chunk body into padded interior [1..32, 1..112, 1..32].
	{
		const uint16_t *src = center->current;
		for (int lz = 0; lz < voxl::CHUNK_Z; lz++) {
			for (int ly = 0; ly < voxl::CHUNK_Y; ly++) {
				const uint16_t *row = &src[voxl::voxel_index(0, ly, lz)];
				uint16_t *dst = &pad[pad_idx(1, ly + 1, lz + 1)];
				std::memcpy(dst, row, voxl::CHUNK_X * sizeof(uint16_t));
			}
		}
	}

	// Horizontal neighbor skins. When a neighbor is not loaded, pad with AIR so the
	// edge chunks emit their outward faces — they are visible at the streaming horizon.
	// (NOT_LOADED would have suppressed those faces, leaving the terrain invisible from
	// the side.) When the neighbor loads later, the subscribe_dirty callback re-queues
	// this chunk, replacing the outward face with the correct cross-chunk culling.
	auto copy_neighbor_x = [&](int dir) {
		int nwcx = job.wcx + dir;
		Chunk *n = job.store->chunk_at(nwcx, job.wcz);
		int dst_px = (dir > 0) ? (PAD_X - 1) : 0;
		if (!n || n->state.load(std::memory_order_acquire) != Chunk::LOADED) {
			for (int lz = 0; lz < voxl::CHUNK_Z; lz++) {
				for (int ly = 0; ly < voxl::CHUNK_Y; ly++) {
					pad[pad_idx(dst_px, ly + 1, lz + 1)] = 0;
				}
			}
			return;
		}
		int src_lx = (dir > 0) ? 0 : (voxl::CHUNK_X - 1);
		for (int lz = 0; lz < voxl::CHUNK_Z; lz++) {
			for (int ly = 0; ly < voxl::CHUNK_Y; ly++) {
				pad[pad_idx(dst_px, ly + 1, lz + 1)] =
						n->current[voxl::voxel_index(src_lx, ly, lz)];
			}
		}
	};
	auto copy_neighbor_z = [&](int dir) {
		int nwcz = job.wcz + dir;
		Chunk *n = job.store->chunk_at(job.wcx, nwcz);
		int dst_pz = (dir > 0) ? (PAD_Z - 1) : 0;
		if (!n || n->state.load(std::memory_order_acquire) != Chunk::LOADED) {
			for (int lx = 0; lx < voxl::CHUNK_X; lx++) {
				for (int ly = 0; ly < voxl::CHUNK_Y; ly++) {
					pad[pad_idx(lx + 1, ly + 1, dst_pz)] = 0;
				}
			}
			return;
		}
		int src_lz = (dir > 0) ? 0 : (voxl::CHUNK_Z - 1);
		for (int lx = 0; lx < voxl::CHUNK_X; lx++) {
			for (int ly = 0; ly < voxl::CHUNK_Y; ly++) {
				pad[pad_idx(lx + 1, ly + 1, dst_pz)] =
						n->current[voxl::voxel_index(lx, ly, src_lz)];
			}
		}
	};
	copy_neighbor_x(-1);
	copy_neighbor_x(+1);
	copy_neighbor_z(-1);
	copy_neighbor_z(+1);

	uint32_t gen_after = center->generation.load(std::memory_order_acquire);
	if (gen_after != gen_before) {
		// Data changed mid-copy — discard; the dirty_version bump will re-queue us.
		out.discarded = true;
		out.generation_snapshot = gen_after;
		return;
	}
	out.generation_snapshot = gen_before;

	// Palette snapshot for lock-free fast lookup inside the hot loop.
	Color albedo_lut[MaterialPalette::PALETTE_SIZE];
	uint8_t flags_lut[MaterialPalette::PALETTE_SIZE];
	for (int i = 0; i < MaterialPalette::PALETTE_SIZE; i++) {
		if (job.palette.is_valid()) {
			albedo_lut[i] = job.palette->albedo_fast(static_cast<uint8_t>(i));
			flags_lut[i] = job.palette->flags_fast(static_cast<uint8_t>(i));
		} else {
			albedo_lut[i] = Color(0.5, 0.5, 0.5, 1.0);
			flags_lut[i] = (i == 0) ? 0 : MaterialPalette::FLAG_SOLID;
		}
	}

	// World-space origin (in voxels) of this chunk.
	int ox_w = job.wcx * voxl::CHUNK_X;
	int oz_w = job.wcz * voxl::CHUNK_Z;
	int oy_w = job.origin_y;

	// Chunk-local origin in padded coordinates.
	const int OX = 1, OY = 1, OZ = 1;
	const int CX = voxl::CHUNK_X, CY = voxl::CHUNK_Y, CZ = voxl::CHUNK_Z;

	// Greedy mesher per axis/direction.
	// Visual verts emit for every non-air voxel with air (voxel_id==0) neighbor.
	// Collision verts emit for every FLAG_SOLID voxel with non-solid neighbor.
	std::vector<uint16_t> mask(CX > CZ ? (CX * CY > CY * CZ ? CX * CY : CY * CZ) : CY * CZ, 0);

	auto emit_quad = [&](PackedVector3Array &verts, PackedColorArray *colors, PackedVector3Array *normals,
			float corner_x[4], float corner_y[4], float corner_z[4],
			bool flip, const Color &color, const Vector3 &normal) {
		Vector3 c[4] = {
			Vector3(corner_x[0], corner_y[0], corner_z[0]),
			Vector3(corner_x[1], corner_y[1], corner_z[1]),
			Vector3(corner_x[2], corner_y[2], corner_z[2]),
			Vector3(corner_x[3], corner_y[3], corner_z[3])
		};
		if (!flip) {
			verts.push_back(c[0]); verts.push_back(c[1]); verts.push_back(c[2]);
			verts.push_back(c[2]); verts.push_back(c[1]); verts.push_back(c[3]);
		} else {
			verts.push_back(c[0]); verts.push_back(c[2]); verts.push_back(c[1]);
			verts.push_back(c[1]); verts.push_back(c[2]); verts.push_back(c[3]);
		}
		if (colors) for (int i = 0; i < 6; i++) colors->push_back(color);
		if (normals) for (int i = 0; i < 6; i++) normals->push_back(normal);
	};

	// Helpers: sample padded buffer given center-chunk-local (u, v, d) per axis.
	auto read_pad = [&](int px, int py, int pz) -> uint16_t {
		return pad[pad_idx(px, py, pz)];
	};

	for (int axis = 0; axis < 3; axis++) {
		int u_axis, v_axis;
		int CU, CV, CD;
		if (axis == 0) { u_axis = 2; v_axis = 1; CU = CZ; CV = CY; CD = CX; }
		else if (axis == 1) { u_axis = 0; v_axis = 2; CU = CX; CV = CZ; CD = CY; }
		else { u_axis = 0; v_axis = 1; CU = CX; CV = CY; CD = CZ; }

		for (int dir = 0; dir < 2; dir++) {
			Vector3 normal(0, 0, 0);
			normal[axis] = -1.0f + dir * 2.0f;
			int step = dir == 0 ? -1 : 1;
			// Inverted vs the editor's blocky mesher: the editor places meshes in local
			// chunk space whereas we emit vertices in world space after VOXEL_SCALE, so
			// the effective winding convention flips.
			bool flip = !((axis < 2) == (dir == 1));

			// Two passes: one for visual faces, one for collision.
			for (int pass = 0; pass < 2; pass++) {
				const bool is_visual = (pass == 0);

				for (int d = 0; d < CD; d++) {
					mask.assign(CU * CV, 0);

					for (int v = 0; v < CV; v++) {
						for (int u = 0; u < CU; u++) {
							int cx, cy, cz; // chunk-local
							if (axis == 0) { cx = d; cz = u; cy = v; }
							else if (axis == 1) { cy = d; cx = u; cz = v; }
							else { cz = d; cx = u; cy = v; }

							uint16_t voxel = read_pad(cx + OX, cy + OY, cz + OZ);
							uint8_t base = voxel & 0xFF;
							if (base == 0) continue;

							int ncx = cx, ncy = cy, ncz = cz;
							if (axis == 0) ncx += step;
							else if (axis == 1) ncy += step;
							else ncz += step;

							uint16_t neighbor = read_pad(ncx + OX, ncy + OY, ncz + OZ);
							uint8_t nbase = neighbor & 0xFF;

							if (is_visual) {
								if (nbase == 0) {
									// Neighbor is air → always emit.
								} else {
									bool v_trans = (flags_lut[base] & MaterialPalette::FLAG_TRANSPARENT) != 0;
									bool n_trans = (flags_lut[nbase] & MaterialPalette::FLAG_TRANSPARENT) != 0;
									if (v_trans && n_trans) {
										if (nbase == base) continue; // same transparent type → hide interior
									} else if (!v_trans && !n_trans) {
										continue; // both opaque → hide interior
									}
									// else one opaque + one transparent → emit face
								}
							} else {
								// Collision pass: only solid voxels, neighbor not solid.
								if (!(flags_lut[base] & MaterialPalette::FLAG_SOLID)) continue;
								if (flags_lut[nbase] & MaterialPalette::FLAG_SOLID) continue;
							}
							mask[u + v * CU] = voxel;
						}
					}

					// Greedy merge on mask.
					for (int v = 0; v < CV; v++) {
						int u = 0;
						while (u < CU) {
							uint16_t voxel_id = mask[u + v * CU];
							if (voxel_id == 0) { u++; continue; }

							int w = 1;
							while (u + w < CU && mask[u + w + v * CU] == voxel_id) w++;

							int h = 1;
							bool done = false;
							while (v + h < CV && !done) {
								for (int k = 0; k < w; k++) {
									if (mask[u + k + (v + h) * CU] != voxel_id) {
										done = true;
										break;
									}
								}
								if (!done) h++;
							}

							uint8_t base = voxel_id & 0xFF;
							Color color = albedo_lut[base];

							float cx[4], cy[4], cz[4];
							for (int i = 0; i < 4; i++) {
								float cu_pos = static_cast<float>(u + (i & 1) * w);
								float cv_pos = static_cast<float>(v + ((i >> 1) & 1) * h);
								float cd_pos = static_cast<float>(d + dir);
								float p[3] = {0, 0, 0};
								p[axis] = cd_pos;
								p[u_axis] = cu_pos;
								p[v_axis] = cv_pos;
								// World-space position = chunk origin + local voxel * voxel_scale.
								cx[i] = (ox_w + p[0]) * voxl::VOXEL_SCALE;
								cy[i] = (oy_w + p[1]) * voxl::VOXEL_SCALE;
								cz[i] = (oz_w + p[2]) * voxl::VOXEL_SCALE;
							}

							if (is_visual) {
								emit_quad(out.verts, &out.colors, &out.normals,
										cx, cy, cz, flip, color, normal);
							} else {
								emit_quad(out.collision_faces, nullptr, nullptr,
										cx, cy, cz, flip, color, normal);
							}

							for (int dv = 0; dv < h; dv++) {
								for (int du = 0; du < w; du++) {
									mask[u + du + (v + dv) * CU] = 0;
								}
							}
							u += w;
						}
					}
				}
			}
		}
	}
}

} // namespace godot
