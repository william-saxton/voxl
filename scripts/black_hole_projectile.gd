class_name BlackHoleProjectile
extends Node3D

@export var pull_radius: float = 5.0
@export var speed: float = 12.0
@export var lifetime: float = 4.0
@export var drop_duration: float = 3.0
@export var max_debris: int = 1000
@export var orbit_speed: float = 2.5
@export var explode_force: float = 20.0
@export var explode_upward: float = 12.0

const EXPLODE_GRAVITY := 25.0

var _direction: Vector3
var _voxel_tool: VoxelTool
var _material_sim: MaterialSimulatorNative
var _age: float = 0.0
var _dropping := false
var _drop_timer: float = 0.0
var _pull_timer: float = 0.0

var _debris: Array[Dictionary] = []
var _land_cursor: int = 0
var _resolve_cursor: int = 0

const RESOLVE_BATCH := 200
var _core_mesh: MeshInstance3D
var _core_material: StandardMaterial3D
var _multi_mesh_instance: MultiMeshInstance3D
var _multi_mesh: MultiMesh

const PULL_INTERVAL := 0.15

# Pull radius in voxel units (world pull_radius converted)
var _pull_radius_voxels: float


func initialize(voxel_tool: VoxelTool, material_sim: MaterialSimulatorNative, direction: Vector3) -> void:
	_voxel_tool = voxel_tool
	_material_sim = material_sim
	_direction = direction.normalized()
	_pull_radius_voxels = pull_radius * MaterialRegistry.INV_VOXEL_SCALE


func _ready() -> void:
	_setup_core_visual()
	_setup_debris_visual()


func _setup_core_visual() -> void:
	_core_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_core_mesh.mesh = sphere

	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = Color(0.05, 0.0, 0.1)
	_core_material.emission_enabled = true
	_core_material.emission = Color(0.4, 0.0, 0.6)
	_core_material.emission_energy_multiplier = 3.0
	_core_mesh.material_override = _core_material
	add_child(_core_mesh)


func _setup_debris_visual() -> void:
	_multi_mesh_instance = MultiMeshInstance3D.new()
	_multi_mesh = MultiMesh.new()
	_multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_multi_mesh.use_colors = true

	var cube := BoxMesh.new()
	cube.size = Vector3(0.7, 0.7, 0.7)
	_multi_mesh.mesh = cube
	_multi_mesh.instance_count = max_debris
	_multi_mesh.visible_instance_count = 0
	_multi_mesh_instance.multimesh = _multi_mesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	_multi_mesh_instance.material_override = mat
	add_child(_multi_mesh_instance)


func _physics_process(delta: float) -> void:
	if not _voxel_tool:
		return

	_age += delta

	if _dropping:
		_process_drop(delta)
		return

	if _age >= lifetime:
		_begin_drop()
		return

	global_position += _direction * speed * delta

	_pull_timer += delta
	if _pull_timer >= PULL_INTERVAL:
		_pull_timer -= PULL_INTERVAL
		_pull_nearby_voxels()

	_update_orbits(delta)
	_update_core_pulse()


func _pull_nearby_voxels() -> void:
	var center := global_position
	var center_v := MaterialRegistry.world_to_voxel(center)
	var ri := int(ceil(_pull_radius_voxels))
	var radius_sq := _pull_radius_voxels * _pull_radius_voxels

	for dx in range(-ri, ri + 1):
		for dy in range(-ri, ri + 1):
			for dz in range(-ri, ri + 1):
				if _debris.size() >= max_debris:
					return

				var offset := Vector3(dx, dy, dz)
				if offset.length_squared() > radius_sq:
					continue

				var vpos := center_v + Vector3i(dx, dy, dz)
				var voxel := _voxel_tool.get_voxel(vpos)

				if voxel == MaterialRegistry.AIR or voxel == MaterialRegistry.BEDROCK:
					continue
				if MaterialRegistry.is_gas(voxel):
					continue

				_voxel_tool.set_voxel(vpos, MaterialRegistry.AIR)
				_material_sim.sync_voxel(vpos, MaterialRegistry.AIR)

				_debris.append({
					"id": voxel,
					"angle": randf() * TAU,
					"radius": randf_range(1.5, pull_radius * 0.7),
					"y": randf_range(-2.5, 2.5),
					"speed_mult": randf_range(0.7, 1.3),
					"color": _get_voxel_color(voxel),
					"scale": randf_range(0.5, 1.0),
				})

	_multi_mesh.visible_instance_count = _debris.size()


func _update_orbits(delta: float) -> void:
	for i in _debris.size():
		var d := _debris[i]
		d["angle"] = fmod(d["angle"] + orbit_speed * d["speed_mult"] * delta, TAU)
		d["radius"] = move_toward(d["radius"], 1.2, 0.5 * delta)
		d["y"] = d["y"] * 0.99 + sin(_age * 2.0 + d["angle"]) * 0.02

		var s: float = d["scale"]
		var local_pos := Vector3(
			cos(d["angle"]) * d["radius"],
			d["y"],
			sin(d["angle"]) * d["radius"]
		)
		var basis := Basis.IDENTITY.scaled(Vector3(s, s, s))
		_multi_mesh.set_instance_transform(i, Transform3D(basis, local_pos))
		_multi_mesh.set_instance_color(i, d["color"])


func _update_core_pulse() -> void:
	var pulse := 1.0 + sin(_age * 4.0) * 0.1
	_core_mesh.scale = Vector3.ONE * pulse
	_core_material.emission_energy_multiplier = 3.0 + sin(_age * 3.0) * 1.0


func _begin_drop() -> void:
	_dropping = true
	_drop_timer = 0.0
	_land_cursor = 0
	_resolve_cursor = 0

	_core_material.emission = Color(0.8, 0.3, 1.0)
	_core_material.emission_energy_multiplier = 8.0

	for d: Dictionary in _debris:
		var angle: float = d["angle"]
		var r: float = d["radius"]
		var y_off: float = d["y"]
		var start_pos := global_position + Vector3(cos(angle) * r, y_off, sin(angle) * r)

		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var force := randf_range(0.5, 1.0) * explode_force
		var vel := (
			outward * force
			+ Vector3.UP * explode_upward * randf_range(0.3, 1.0)
			+ Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		)

		d["start_pos"] = start_pos
		d["vel"] = vel

		var disc := vel.y * vel.y + 2.0 * EXPLODE_GRAVITY * (start_pos.y - 1.0)
		var land_time := drop_duration
		if disc >= 0.0:
			land_time = clampf((vel.y + sqrt(disc)) / EXPLODE_GRAVITY, 0.1, drop_duration)

		d["land_time"] = land_time
		d["land_pos"] = Vector3i(-9999, -9999, -9999)

	_debris.sort_custom(func(a_d: Dictionary, b_d: Dictionary) -> bool:
		return float(a_d["land_time"]) < float(b_d["land_time"])
	)


func _process_drop(delta: float) -> void:
	_drop_timer += delta

	var fade := minf(_drop_timer / (drop_duration * 0.25), 1.0)
	_core_mesh.scale = Vector3.ONE * maxf(1.0 - fade, 0.0)
	_core_material.emission_energy_multiplier = maxf(1.0 - fade, 0.0) * 8.0

	_resolve_landing_batch()

	while _land_cursor < _debris.size():
		var d := _debris[_land_cursor]
		if _drop_timer < float(d["land_time"]):
			break
		_ensure_resolved(_land_cursor)
		var lp: Vector3i = d["land_pos"]
		if lp != Vector3i.ZERO:
			_place_debris_voxel(d["id"], lp)
		_land_cursor += 1

	var visible_count := _debris.size() - _land_cursor
	_multi_mesh.visible_instance_count = visible_count

	var t := _drop_timer
	for i in visible_count:
		var d := _debris[_land_cursor + i]
		var start: Vector3 = d["start_pos"]
		var vel: Vector3 = d["vel"]
		var pos := start + vel * t + Vector3(0.0, -0.5 * EXPLODE_GRAVITY * t * t, 0.0)

		var local_pos := pos - global_position
		var s: float = d["scale"]
		var basis := Basis.IDENTITY.scaled(Vector3(s, s, s))
		_multi_mesh.set_instance_transform(i, Transform3D(basis, local_pos))
		_multi_mesh.set_instance_color(i, d["color"])

	if _drop_timer >= drop_duration or _land_cursor >= _debris.size():
		_force_place_remaining()
		queue_free()


func _resolve_landing_batch() -> void:
	var resolve_end := mini(_resolve_cursor + RESOLVE_BATCH, _debris.size())
	for idx in range(_resolve_cursor, resolve_end):
		_resolve_landing(idx)
	_resolve_cursor = resolve_end


func _ensure_resolved(idx: int) -> void:
	var d := _debris[idx]
	var lp: Vector3i = d["land_pos"]
	if lp.x == -9999:
		_resolve_landing(idx)


func _resolve_landing(idx: int) -> void:
	var d := _debris[idx]
	var vel: Vector3 = d["vel"]
	var start: Vector3 = d["start_pos"]
	var lt: float = d["land_time"]
	var land_world := Vector3(start.x + vel.x * lt, start.y + 2.0, start.z + vel.z * lt)
	var land_v := MaterialRegistry.world_to_voxel(land_world)
	d["land_pos"] = _find_landing_spot(land_v)


func _place_debris_voxel(voxel_id: int, place_pos: Vector3i) -> void:
	_voxel_tool.set_voxel(place_pos, voxel_id)
	_material_sim.sync_voxel(place_pos, voxel_id)


func _force_place_remaining() -> void:
	for i in range(_land_cursor, _debris.size()):
		_ensure_resolved(i)
		var d := _debris[i]
		var lp: Vector3i = d["land_pos"]
		if lp != Vector3i.ZERO:
			_place_debris_voxel(d["id"], lp)
	_debris.clear()


func _find_landing_spot(pos: Vector3i) -> Vector3i:
	# Fast path: flat terrain has dirt at voxel y=0, air at y=1
	var ground := Vector3i(pos.x, 15, pos.z)
	var air := Vector3i(pos.x, 16, pos.z)
	if MaterialRegistry.is_solid(_voxel_tool.get_voxel(ground)) and MaterialRegistry.is_passable(_voxel_tool.get_voxel(air)):
		return air

	for y in range(pos.y + 32, pos.y - 80, -1):
		var check := Vector3i(pos.x, y, pos.z)
		var above := Vector3i(pos.x, y + 1, pos.z)
		if MaterialRegistry.is_solid(_voxel_tool.get_voxel(check)) and MaterialRegistry.is_passable(_voxel_tool.get_voxel(above)):
			return above
	return Vector3i.ZERO


static func _get_voxel_color(voxel_id: int) -> Color:
	if voxel_id == MaterialRegistry.STONE:
		return Color(0.6, 0.58, 0.55)
	if voxel_id == MaterialRegistry.DIRT:
		return Color(0.55, 0.35, 0.18)
	if voxel_id == MaterialRegistry.MUD:
		return Color(0.18, 0.12, 0.08)
	if voxel_id == MaterialRegistry.WATER:
		return Color(0.2, 0.4, 0.8)
	if voxel_id == MaterialRegistry.LAVA:
		return Color(1.0, 0.3, 0.0)
	if voxel_id == MaterialRegistry.ACID:
		return Color(0.3, 0.9, 0.1)
	return Color(0.5, 0.5, 0.5)
