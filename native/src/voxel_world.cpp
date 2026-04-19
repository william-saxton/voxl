#include "voxel_world.h"

#include "voxel_chunk_store.h"
#include "voxel_coord.h"
#include "voxel_mesher_pool.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

void VoxelWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_anchor_path", "path"), &VoxelWorld::set_anchor_path);
	ClassDB::bind_method(D_METHOD("get_anchor_path"), &VoxelWorld::get_anchor_path);
	ClassDB::bind_method(D_METHOD("set_sim_radius", "radius"), &VoxelWorld::set_sim_radius);
	ClassDB::bind_method(D_METHOD("get_sim_radius"), &VoxelWorld::get_sim_radius);
	ClassDB::bind_method(D_METHOD("set_origin_y", "y"), &VoxelWorld::set_origin_y);
	ClassDB::bind_method(D_METHOD("get_origin_y"), &VoxelWorld::get_origin_y);
	ClassDB::bind_method(D_METHOD("set_palette", "palette"), &VoxelWorld::set_palette);
	ClassDB::bind_method(D_METHOD("get_palette"), &VoxelWorld::get_palette);
	ClassDB::bind_method(D_METHOD("set_mesher_thread_count", "n"), &VoxelWorld::set_mesher_thread_count);
	ClassDB::bind_method(D_METHOD("get_mesher_thread_count"), &VoxelWorld::get_mesher_thread_count);

	ClassDB::bind_method(D_METHOD("get_voxel", "pos"), &VoxelWorld::gd_get_voxel);
	ClassDB::bind_method(D_METHOD("set_voxel", "pos", "value"), &VoxelWorld::gd_set_voxel);
	ClassDB::bind_method(D_METHOD("set_voxels", "positions", "values"), &VoxelWorld::gd_set_voxels);
	ClassDB::bind_method(D_METHOD("raycast", "origin", "direction", "max_distance"),
			&VoxelWorld::gd_raycast);
	ClassDB::bind_method(D_METHOD("get_store"), &VoxelWorld::get_store);

	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "anchor_path"), "set_anchor_path", "get_anchor_path");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "sim_radius", PROPERTY_HINT_RANGE, "1,32,1"),
			"set_sim_radius", "get_sim_radius");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "origin_y"), "set_origin_y", "get_origin_y");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "palette", PROPERTY_HINT_RESOURCE_TYPE, "MaterialPalette"),
			"set_palette", "get_palette");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mesher_thread_count", PROPERTY_HINT_RANGE, "1,32,1"),
			"set_mesher_thread_count", "get_mesher_thread_count");
}

VoxelWorld::VoxelWorld() {
	_mesher = std::make_unique<VoxelMesherPool>();
}

VoxelWorld::~VoxelWorld() {
	if (_mesher) _mesher->stop();
}

void VoxelWorld::set_anchor_path(const NodePath &p) { _anchor_path = p; }
void VoxelWorld::set_sim_radius(int r) { _sim_radius = r > 0 ? r : 1; }
void VoxelWorld::set_origin_y(int y) { _origin_y = y; }
void VoxelWorld::set_palette(const Ref<MaterialPalette> &p) { _palette = p; }
void VoxelWorld::set_mesher_thread_count(int n) { _mesher_threads = n > 0 ? n : 1; }

void VoxelWorld::_notification(int p_what) {
	if (p_what == NOTIFICATION_EXIT_TREE || p_what == NOTIFICATION_PREDELETE) {
		if (_mesher) _mesher->stop();
		if (_store) _store->stop();
	}
}

void VoxelWorld::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) return;

	if (!_palette.is_valid()) {
		_palette = MaterialPalette::make_default();
	}

	if (!_anchor_path.is_empty()) {
		Node *n = get_node_or_null(_anchor_path);
		_anchor_node = Object::cast_to<Node3D>(n);
	}

	_shared_material.instantiate();
	_shared_material->set_flag(StandardMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
	_shared_material->set_flag(StandardMaterial3D::FLAG_SRGB_VERTEX_COLOR, true);
	_shared_material->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);

	_store = memnew(VoxelChunkStore);
	_store->set_name("Store");
	_store->set_origin_y(_origin_y);
	add_child(_store);

	// Subscribe before initialize so the initial-load dirty-cb pulse hits us.
	_store->subscribe_dirty([this](int wcx, int wcz) { _on_chunk_dirty(wcx, wcz); });

	_mesher->start(_mesher_threads);
	_store->initialize(_anchor_node, _sim_radius);

	set_process(true);
}

void VoxelWorld::_process(double /*delta*/) {
	if (Engine::get_singleton()->is_editor_hint()) return;
	if (!_store) return;

	_store->tick();
	_poll_dirty_chunks();
	_apply_mesh_results();
	_cleanup_orphan_render_nodes();
}

// Check each loaded chunk's dirty_version against the last-queued version; queue a
// re-mesh for any chunk that was modified (by the sim or an external writer) since
// the mesher last saw it.
void VoxelWorld::_poll_dirty_chunks() {
	if (!_store) return;
	// Cap submissions per frame to avoid flooding the mesher during heavy sim activity.
	// Chunks that miss this frame get picked up next frame (dirty_version stays bumped).
	static constexpr int MAX_SUBMITS_PER_FRAME = 8;
	int submitted = 0;
	auto loaded = _store->loaded_chunks();
	for (auto *c : loaded) {
		if (submitted >= MAX_SUBMITS_PER_FRAME) break;
		uint32_t dv = c->dirty_version.load(std::memory_order_acquire);
		auto &rs = _ensure_render_state(c->wcx, c->wcz);
		if (dv != rs.last_queued_dirty_version) {
			rs.last_queued_dirty_version = dv;
			_queue_mesh_job(c->wcx, c->wcz);
			submitted++;
		}
	}
}

int VoxelWorld::gd_get_voxel(const Vector3i &pos) const {
	if (!_store) return 0;
	return _store->read_voxel(pos.x, pos.y, pos.z);
}

Variant VoxelWorld::gd_raycast(const Vector3 &origin, const Vector3 &direction, float max_distance) const {
	if (!_store || direction.length_squared() < 1e-10f || max_distance <= 0.0f) {
		return Variant();
	}

	Vector3 ray_dir = direction.normalized();

	// Work in voxel space: scale origin by INV_VOXEL_SCALE so one voxel == one unit.
	// ray_dir stays normalized; integrate t in voxel units.
	Vector3 origin_v = origin * voxl::INV_VOXEL_SCALE;
	float max_t = max_distance * voxl::INV_VOXEL_SCALE;

	int vx = static_cast<int>(Math::floor(origin_v.x));
	int vy = static_cast<int>(Math::floor(origin_v.y));
	int vz = static_cast<int>(Math::floor(origin_v.z));

	int step_x = ray_dir.x >= 0 ? 1 : -1;
	int step_y = ray_dir.y >= 0 ? 1 : -1;
	int step_z = ray_dir.z >= 0 ? 1 : -1;

	// Distance along ray to next voxel boundary on each axis.
	auto t_to_boundary = [](float pos, float dir, int step) -> float {
		if (dir == 0.0f) return 1e30f;
		float boundary;
		if (step > 0) {
			boundary = Math::floor(pos) + 1.0f;
		} else {
			boundary = Math::floor(pos);
			if (pos == boundary) boundary -= 1.0f;
		}
		return (boundary - pos) / dir;
	};
	float t_max_x = t_to_boundary(origin_v.x, ray_dir.x, step_x);
	float t_max_y = t_to_boundary(origin_v.y, ray_dir.y, step_y);
	float t_max_z = t_to_boundary(origin_v.z, ray_dir.z, step_z);

	float t_delta_x = ray_dir.x != 0.0f ? Math::abs(1.0f / ray_dir.x) : 1e30f;
	float t_delta_y = ray_dir.y != 0.0f ? Math::abs(1.0f / ray_dir.y) : 1e30f;
	float t_delta_z = ray_dir.z != 0.0f ? Math::abs(1.0f / ray_dir.z) : 1e30f;

	Vector3i prev(vx, vy, vz);
	float t = 0.0f;
	// Tracks which axis was last stepped so we can report the hit face normal.
	int last_axis = -1;
	int last_step_sign = 0;

	// First step checks the origin cell itself.
	constexpr int MAX_STEPS = 4096;
	for (int i = 0; i < MAX_STEPS; i++) {
		int vid_raw = _store->read_voxel(vx, vy, vz);
		uint16_t vid = static_cast<uint16_t>(vid_raw);
		// Treat NOT_LOADED as empty so rays pass into streamed-out chunks cleanly; callers
		// already gate on max_distance, so the ray eventually terminates.
		if (vid != 0 && vid != voxl::NOT_LOADED) {
			Dictionary result;
			result["hit"] = true;
			result["position"] = Vector3i(vx, vy, vz);
			result["previous_position"] = prev;
			result["voxel_id"] = static_cast<int>(vid);
			result["distance"] = t * voxl::VOXEL_SCALE;
			Vector3 normal(0, 0, 0);
			if (last_axis == 0) normal.x = static_cast<float>(-last_step_sign);
			else if (last_axis == 1) normal.y = static_cast<float>(-last_step_sign);
			else if (last_axis == 2) normal.z = static_cast<float>(-last_step_sign);
			result["normal"] = normal;
			return result;
		}

		// Advance DDA: step along whichever axis reaches the next boundary first.
		prev = Vector3i(vx, vy, vz);
		if (t_max_x < t_max_y) {
			if (t_max_x < t_max_z) {
				vx += step_x;
				t = t_max_x;
				t_max_x += t_delta_x;
				last_axis = 0;
				last_step_sign = step_x;
			} else {
				vz += step_z;
				t = t_max_z;
				t_max_z += t_delta_z;
				last_axis = 2;
				last_step_sign = step_z;
			}
		} else {
			if (t_max_y < t_max_z) {
				vy += step_y;
				t = t_max_y;
				t_max_y += t_delta_y;
				last_axis = 1;
				last_step_sign = step_y;
			} else {
				vz += step_z;
				t = t_max_z;
				t_max_z += t_delta_z;
				last_axis = 2;
				last_step_sign = step_z;
			}
		}

		if (t > max_t) break;
	}

	return Variant();
}

int VoxelWorld::gd_set_voxels(const PackedInt32Array &positions, const PackedInt32Array &values) {
	if (!_store) return 0;
	int n = values.size();
	if (positions.size() < n * 3) return 0;
	const int *p = positions.ptr();
	const int *v = values.ptr();
	int written = 0;
	for (int i = 0; i < n; i++) {
		int wx = p[i * 3 + 0];
		int wy = p[i * 3 + 1];
		int wz = p[i * 3 + 2];
		if (!_store->write_voxel(wx, wy, wz, static_cast<uint16_t>(v[i]))) continue;
		written++;
		// Bump neighbor chunks on edge writes (same rule as gd_set_voxel).
		int lx = voxl::local_coord_x(wx);
		int lz = voxl::local_coord_z(wz);
		int cx = voxl::chunk_coord_x(wx);
		int cz = voxl::chunk_coord_z(wz);
		if (lx == 0) {
			if (auto *n0 = _store->chunk_at(cx - 1, cz)) n0->dirty_version.fetch_add(1, std::memory_order_relaxed);
		}
		if (lx == voxl::CHUNK_X - 1) {
			if (auto *n0 = _store->chunk_at(cx + 1, cz)) n0->dirty_version.fetch_add(1, std::memory_order_relaxed);
		}
		if (lz == 0) {
			if (auto *n0 = _store->chunk_at(cx, cz - 1)) n0->dirty_version.fetch_add(1, std::memory_order_relaxed);
		}
		if (lz == voxl::CHUNK_Z - 1) {
			if (auto *n0 = _store->chunk_at(cx, cz + 1)) n0->dirty_version.fetch_add(1, std::memory_order_relaxed);
		}
	}
	return written;
}

bool VoxelWorld::gd_set_voxel(const Vector3i &pos, int value) {
	if (!_store) return false;
	bool ok = _store->write_voxel(pos.x, pos.y, pos.z, static_cast<uint16_t>(value));
	if (!ok) return false;
	// write_voxel bumps the center chunk's dirty_version. For edge writes, the
	// neighbouring chunk's padding changes too — bump its dirty_version so the
	// per-frame _poll_dirty_chunks re-meshes it. We do NOT submit mesh jobs inline:
	// bulk writes (e.g. black-hole debris) would otherwise flood the queue; the
	// frame poll dedupes to one job per dirtied chunk per frame.
	int cx = voxl::chunk_coord_x(pos.x);
	int cz = voxl::chunk_coord_z(pos.z);
	int lx = voxl::local_coord_x(pos.x);
	int lz = voxl::local_coord_z(pos.z);
	auto bump_neighbor = [this](int ncx, int ncz) {
		VoxelChunkStore::Chunk *n = _store->chunk_at(ncx, ncz);
		if (n) n->dirty_version.fetch_add(1, std::memory_order_relaxed);
	};
	if (lx == 0) bump_neighbor(cx - 1, cz);
	if (lx == voxl::CHUNK_X - 1) bump_neighbor(cx + 1, cz);
	if (lz == 0) bump_neighbor(cx, cz - 1);
	if (lz == voxl::CHUNK_Z - 1) bump_neighbor(cx, cz + 1);
	return true;
}

// Called from store's dirty callback, which may fire from the main thread (after
// loader-result drain in tick()). When a chunk loads, also re-queue its 4 neighbors
// since their edge faces may have been suppressed or need to emerge.
void VoxelWorld::_on_chunk_dirty(int wcx, int wcz) {
	_queue_mesh_job(wcx, wcz);
	_queue_mesh_job(wcx - 1, wcz);
	_queue_mesh_job(wcx + 1, wcz);
	_queue_mesh_job(wcx, wcz - 1);
	_queue_mesh_job(wcx, wcz + 1);
}

void VoxelWorld::_queue_mesh_job(int wcx, int wcz) {
	if (!_store) return;
	VoxelChunkStore::Chunk *c = _store->chunk_at(wcx, wcz);
	if (!c) return; // Out of streaming radius.
	_mesher->submit(_store, wcx, wcz, _palette, _origin_y);
}

VoxelWorld::ChunkRenderState &VoxelWorld::_ensure_render_state(int wcx, int wcz) {
	auto it = _render_state.find(_chunk_key(wcx, wcz));
	if (it != _render_state.end()) return it->second;

	ChunkRenderState rs;
	rs.mesh_node = memnew(MeshInstance3D);
	String nm = String("Chunk_{0}_{1}").format(Array::make(wcx, wcz));
	rs.mesh_node->set_name(nm);
	add_child(rs.mesh_node);

	rs.body_node = memnew(StaticBody3D);
	rs.body_node->set_name(nm + "_body");
	add_child(rs.body_node);

	rs.shape_node = memnew(CollisionShape3D);
	rs.shape_node->set_name("shape");
	rs.body_node->add_child(rs.shape_node);

	_render_state[_chunk_key(wcx, wcz)] = rs;
	return _render_state[_chunk_key(wcx, wcz)];
}

void VoxelWorld::_apply_mesh_results() {
	// Drain newly-completed jobs into the pending buffer.
	{
		std::vector<MeshJobResult> fresh = _mesher->drain_results();
		for (auto &r : fresh) {
			_pending_mesh_results.push_back(std::move(r));
		}
	}

	// Cap per-frame uploads. During heavy churn (large pending backlog) skip
	// collision shape rebuilds — BVH construction dominates upload cost.
	static constexpr int MAX_UPLOADS_PER_FRAME = 8;
	bool skip_collision = _pending_mesh_results.size() > static_cast<size_t>(MAX_UPLOADS_PER_FRAME * 2);
	int uploaded = 0;
	std::vector<MeshJobResult> keep;
	keep.reserve(_pending_mesh_results.size());

	for (size_t i = 0; i < _pending_mesh_results.size(); i++) {
		MeshJobResult &r = _pending_mesh_results[i];
		if (r.discarded) continue;
		VoxelChunkStore::Chunk *c = _store ? _store->chunk_at(r.wcx, r.wcz) : nullptr;
		if (!c || c->wcx != r.wcx || c->wcz != r.wcz) continue;

		if (uploaded >= MAX_UPLOADS_PER_FRAME) {
			keep.push_back(std::move(r));
			continue;
		}

		ChunkRenderState &rs = _ensure_render_state(r.wcx, r.wcz);

		Ref<ArrayMesh> mesh;
		if (r.verts.size() > 0) {
			mesh.instantiate();
			Array arrays;
			arrays.resize(Mesh::ARRAY_MAX);
			arrays[Mesh::ARRAY_VERTEX] = r.verts;
			arrays[Mesh::ARRAY_COLOR] = r.colors;
			arrays[Mesh::ARRAY_NORMAL] = r.normals;
			mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
			mesh->surface_set_material(0, _shared_material);
		}
		rs.mesh_node->set_mesh(mesh);

		bool needs_collision = !skip_collision || rs.shape_node->get_shape().is_null();
		if (needs_collision) {
			if (r.collision_faces.size() > 0) {
				Ref<ConcavePolygonShape3D> shape;
				shape.instantiate();
				shape->set_faces(r.collision_faces);
				rs.shape_node->set_shape(shape);
			} else {
				rs.shape_node->set_shape(Ref<Shape3D>());
			}
		}

		rs.last_applied_generation = r.generation_snapshot;
		uploaded++;
	}
	_pending_mesh_results.clear();
	for (size_t k = 0; k < keep.size(); k++) {
		_pending_mesh_results.push_back(keep[k]);
	}
}

// Remove render nodes whose chunks have streamed out of the grid.
void VoxelWorld::_cleanup_orphan_render_nodes() {
	if (!_store) return;
	std::vector<int64_t> to_remove;
	for (auto &kv : _render_state) {
		int wcx = static_cast<int>(kv.first >> 32);
		int wcz = static_cast<int>(static_cast<int32_t>(kv.first & 0xFFFFFFFF));
		VoxelChunkStore::Chunk *c = _store->chunk_at(wcx, wcz);
		if (!c || c->wcx != wcx || c->wcz != wcz) {
			to_remove.push_back(kv.first);
		}
	}
	for (int64_t key : to_remove) {
		ChunkRenderState &rs = _render_state[key];
		if (rs.mesh_node) rs.mesh_node->queue_free();
		if (rs.body_node) rs.body_node->queue_free();
		_render_state.erase(key);
	}
}

} // namespace godot
