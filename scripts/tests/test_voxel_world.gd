extends Node3D

const SIM_RADIUS: int = 3
const EXPECTED_LOADED_CHUNKS: int = (SIM_RADIUS * 2 + 1) * (SIM_RADIUS * 2 + 1)
const LOAD_TIMEOUT_SEC: float = 10.0

var _world: VoxelWorld
var _anchor: Node3D
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	_anchor = Node3D.new()
	_anchor.name = "Anchor"
	add_child(_anchor)

	_world = VoxelWorld.new()
	_world.name = "World"
	_world.sim_radius = SIM_RADIUS
	_world.origin_y = 0
	_world.anchor_path = _anchor.get_path()
	_world.mesher_thread_count = 4
	add_child(_world)

	# Frame the terrain: camera above-corner, looking at the dirt surface (~3.75 world units up).
	var cam: Camera3D = get_node_or_null("Camera3D")
	if cam:
		cam.global_position = Vector3(20, 15, 20)
		cam.look_at(Vector3(0, 3.5, 0), Vector3.UP)

	# Tilt the directional light for shading.
	var light: DirectionalLight3D = get_node_or_null("DirectionalLight3D")
	if light:
		light.look_at_from_position(Vector3(10, 20, 5), Vector3.ZERO, Vector3.UP)

	print("[test] VoxelWorld created (sim_radius=%d, expected chunks=%d)"
			% [SIM_RADIUS, EXPECTED_LOADED_CHUNKS])


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta

	var store = _world.get("store") if _world.has_method("get") else null
	var loaded: int = 0
	var store_node := _world.find_child("Store", false, false)
	if store_node:
		loaded = store_node.loaded_chunk_count()

	# Count chunks that have a mesh applied.
	var meshed: int = 0
	var collided: int = 0
	for child in _world.get_children():
		if child is MeshInstance3D and child.mesh != null:
			meshed += 1
		if child is StaticBody3D:
			var shape_node = child.get_child(0) if child.get_child_count() > 0 else null
			if shape_node and shape_node is CollisionShape3D and shape_node.shape != null:
				collided += 1

	if loaded >= EXPECTED_LOADED_CHUNKS and meshed >= EXPECTED_LOADED_CHUNKS:
		print("[test] PASS (%.2fs) loaded=%d meshed=%d collided=%d"
				% [_elapsed, loaded, meshed, collided])

		# Diagnostic: total vertex count + AABB across all chunk meshes.
		var total_verts: int = 0
		var world_aabb := AABB()
		var first := true
		for child in _world.get_children():
			if child is MeshInstance3D and child.mesh != null:
				var m: Mesh = child.mesh
				var surf_count: int = m.get_surface_count()
				for s in surf_count:
					var arrays: Array = m.surface_get_arrays(s)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					total_verts += verts.size()
				var mi_aabb: AABB = child.get_aabb()
				# Transform AABB by global transform.
				var world_mi_aabb: AABB = child.global_transform * mi_aabb
				if first:
					world_aabb = world_mi_aabb
					first = false
				else:
					world_aabb = world_aabb.merge(world_mi_aabb)
		print("[test] total_vertices=%d" % total_verts)
		print("[test] world_aabb pos=%s size=%s" % [world_aabb.position, world_aabb.size])

		var cam: Camera3D = get_node_or_null("Camera3D")
		if cam:
			print("[test] camera pos=%s, basis.z=%s (forward = -basis.z)"
					% [cam.global_position, cam.global_transform.basis.z])

		print("[test] scene staying open for visual inspection \u2014 close window to exit")
		_finished = true
		return

	if _elapsed > LOAD_TIMEOUT_SEC:
		push_error("[test] TIMEOUT loaded=%d/%d meshed=%d collided=%d after %.2fs"
				% [loaded, EXPECTED_LOADED_CHUNKS, meshed, collided, _elapsed])
		_finished = true
