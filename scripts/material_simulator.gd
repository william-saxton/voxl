class_name MaterialSimulator
extends Node

const SIM_RATE := 0.05
const SIM_X := 256
const SIM_Y := 32
const SIM_Z := 256
const SHIFT_STEP := 64
const SHIFT_MARGIN := 32

const GEO_BUF_MAX := 32768
const GEO_BUF_HEADER := 8
const GEO_BUF_ENTRY := 8
const GEO_BUF_SIZE := GEO_BUF_HEADER + GEO_BUF_MAX * GEO_BUF_ENTRY

const PUSH_CONST_SIZE := 16
const WORKGROUPS_X := SIM_X / 8
const WORKGROUPS_Y := SIM_Y / 4
const WORKGROUPS_Z := SIM_Z / 8

var _voxel_tool: VoxelTool
var _terrain: VoxelTerrain
var _player: Node3D
var _sim_origin := Vector3i.ZERO
var _sim_timer: float = 0.0
var _tick_count: int = 0
var _source_positions: Dictionary = {}

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _tex_a: RID
var _tex_b: RID
var _tex_mirror: RID
var _geo_buffer: RID
var _uniform_set: RID

var _tex_current: RID
var _tex_next: RID

var _pending_indices: PackedInt32Array = PackedInt32Array()
var _pending_values: PackedByteArray = PackedByteArray()

var _last_tick_usec: int = 0
var _last_changes_count: int = 0
var _gpu_ready := false

var _edge_fill_z: int = -1
var _edge_fill_dx: int = 0
var _edge_fill_nx_lo: int = 0
var _edge_fill_nx_hi: int = 0
var _edge_fill_nz_lo: int = 0
var _edge_fill_nz_hi: int = 0

signal voxel_changed(pos: Vector3i, new_voxel: int)


func get_active_cell_count() -> int:
	return SIM_X * SIM_Y * SIM_Z if _gpu_ready else 0

func get_source_block_count() -> int:
	return _source_positions.size()

func get_last_tick_ms() -> float:
	return _last_tick_usec / 1000.0

func get_last_changes_count() -> int:
	return _last_changes_count


func initialize(terrain: VoxelTerrain, player: Node3D = null) -> void:
	_terrain = terrain
	_player = player
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_wait_for_terrain()


func place_fluid(pos: Vector3i, fluid_base: int, level: int = MaterialRegistry.FLUID_LEVELS - 1) -> void:
	if not _voxel_tool:
		return
	var fluid_id := MaterialRegistry.fluid_id(fluid_base, level)
	_voxel_tool.set_voxel(pos, fluid_id)
	_source_positions[pos] = true
	if _gpu_ready:
		_queue_gpu_write(pos, MaterialRegistry.encode_gpu(fluid_id, true))


func remove_voxel(pos: Vector3i) -> void:
	if not _voxel_tool:
		return
	_voxel_tool.set_voxel(pos, MaterialRegistry.AIR)
	_source_positions.erase(pos)
	if _gpu_ready:
		_queue_gpu_write(pos, MaterialRegistry.AIR)


func sync_voxel(pos: Vector3i, voxel_id: int) -> void:
	if _gpu_ready:
		_queue_gpu_write(pos, MaterialRegistry.encode_gpu(voxel_id, false))


func _wake_region(_center: Vector3i, _radius: int) -> void:
	pass


# ── GPU setup ──

func _wait_for_terrain() -> void:
	_sim_origin = _snap_origin_to_player()
	for attempt in 30:
		await get_tree().create_timer(0.5).timeout
		var sample := _voxel_tool.get_voxel(Vector3i(SIM_X / 2, 0, SIM_Z / 2) + _sim_origin)
		if sample != MaterialRegistry.AIR:
			print("[MaterialSimulator] terrain ready after %.1fs" % [(attempt + 1) * 0.5])
			_setup_gpu()
			return
	push_error("MaterialSimulator: terrain never loaded, giving up")


func _snap_origin_to_player() -> Vector3i:
	if _player:
		var pp := _player.global_position
		var cx := int(floorf(pp.x / SHIFT_STEP)) * SHIFT_STEP - SIM_X / 2
		var cz := int(floorf(pp.z / SHIFT_STEP)) * SHIFT_STEP - SIM_Z / 2
		return Vector3i(cx, -16, cz)
	return Vector3i(-SIM_X / 2, -16, -SIM_Z / 2)


func _setup_gpu() -> void:
	_sim_origin = _snap_origin_to_player()

	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_error("MaterialSimulator: Failed to create local RenderingDevice")
		return

	var shader_file := load("res://shaders/material_sim.glsl") as RDShaderFile
	if not shader_file:
		push_error("MaterialSimulator: Failed to load material_sim.glsl")
		return

	var spirv := shader_file.get_spirv()
	var compile_err := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if compile_err != "":
		push_error("MaterialSimulator: GLSL compile error: " + compile_err)
		return

	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		push_error("MaterialSimulator: shader_create_from_spirv failed")
		return
	_pipeline = _rd.compute_pipeline_create(_shader)

	_create_textures()
	_create_geo_buffer()
	_tex_current = _tex_a
	_tex_next = _tex_b
	_build_uniform_set()
	_sync_terrain_to_gpu()
	_gpu_ready = true
	print("[MaterialSimulator] GPU sim ready (origin=%s, %d sources)" % [_sim_origin, _source_positions.size()])


func _create_textures() -> void:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UINT
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.width = SIM_X
	fmt.height = SIM_Y
	fmt.depth = SIM_Z
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)

	var empty_data := PackedByteArray()
	empty_data.resize(SIM_X * SIM_Y * SIM_Z)
	empty_data.fill(0)

	_tex_a = _rd.texture_create(fmt, RDTextureView.new(), [empty_data])
	_tex_b = _rd.texture_create(fmt, RDTextureView.new(), [empty_data])
	_tex_mirror = _rd.texture_create(fmt, RDTextureView.new(), [empty_data])


func _create_geo_buffer() -> void:
	_geo_buffer = _rd.storage_buffer_create(GEO_BUF_SIZE)


func _build_uniform_set() -> void:
	var u_current := RDUniform.new()
	u_current.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_current.binding = 0
	u_current.add_id(_tex_current)

	var u_next := RDUniform.new()
	u_next.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_next.binding = 1
	u_next.add_id(_tex_next)

	var u_geo := RDUniform.new()
	u_geo.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_geo.binding = 2
	u_geo.add_id(_geo_buffer)

	var u_mirror := RDUniform.new()
	u_mirror.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_mirror.binding = 3
	u_mirror.add_id(_tex_mirror)

	_uniform_set = _rd.uniform_set_create([u_current, u_next, u_geo, u_mirror], _shader, 0)


func _sync_terrain_to_gpu() -> void:
	var data := PackedByteArray()
	data.resize(SIM_X * SIM_Y * SIM_Z)
	var non_air := 0

	for sz in SIM_Z:
		for sy in SIM_Y:
			for sx in SIM_X:
				var world_pos := Vector3i(sx, sy, sz) + _sim_origin
				var voxel := _voxel_tool.get_voxel(world_pos)
				var is_src := _source_positions.has(world_pos)
				var idx := sx + sy * SIM_X + sz * SIM_X * SIM_Y
				data[idx] = MaterialRegistry.encode_gpu(voxel, is_src)
				if voxel != MaterialRegistry.AIR:
					non_air += 1

	_rd.texture_update(_tex_current, 0, data)
	_rd.texture_update(_tex_next, 0, data)
	_rd.texture_update(_tex_mirror, 0, data)
	print("[MaterialSimulator] synced terrain: %d non-air voxels out of %d" % [non_air, SIM_X * SIM_Y * SIM_Z])


# ── pending writes (batched per dispatch) ──

func _queue_gpu_write(world_pos: Vector3i, gpu_byte: int) -> void:
	var sp := world_pos - _sim_origin
	if sp.x < 0 or sp.x >= SIM_X or sp.y < 0 or sp.y >= SIM_Y or sp.z < 0 or sp.z >= SIM_Z:
		return
	_pending_indices.append(sp.x + sp.y * SIM_X + sp.z * SIM_X * SIM_Y)
	_pending_values.append(gpu_byte)


func _flush_pending_writes() -> void:
	if _pending_indices.is_empty():
		return
	var data := _rd.texture_get_data(_tex_current, 0)
	for i in _pending_indices.size():
		data[_pending_indices[i]] = _pending_values[i]
	_rd.texture_update(_tex_current, 0, data)
	_rd.texture_update(_tex_mirror, 0, data)
	_pending_indices.clear()
	_pending_values.clear()


# ── simulation dispatch ──

func _physics_process(delta: float) -> void:
	if not _gpu_ready:
		return
	if _edge_fill_z >= 0:
		_continue_edge_fill()
	_sim_timer += delta
	if _sim_timer < SIM_RATE:
		return
	_sim_timer -= SIM_RATE
	_tick_count += 1
	_dispatch_tick()


func _check_shift() -> void:
	if not _player:
		return
	var pp := _player.global_position
	var px := int(floorf(pp.x))
	var pz := int(floorf(pp.z))

	var edge_min_x := _sim_origin.x + SHIFT_MARGIN
	var edge_max_x := _sim_origin.x + SIM_X - SHIFT_MARGIN
	var edge_min_z := _sim_origin.z + SHIFT_MARGIN
	var edge_max_z := _sim_origin.z + SIM_Z - SHIFT_MARGIN

	if px >= edge_min_x and px < edge_max_x and pz >= edge_min_z and pz < edge_max_z:
		return

	var new_origin := _snap_origin_to_player()
	if new_origin != _sim_origin:
		_shift_volume(new_origin)


func _shift_volume(new_origin: Vector3i) -> void:
	var t0 := Time.get_ticks_usec()
	_pending_indices.clear()
	_pending_values.clear()
	_edge_fill_z = -1

	var delta := new_origin - _sim_origin
	var dx := delta.x
	var dz := delta.z
	_sim_origin = new_origin

	if dx == 0 and dz == 0:
		return

	var src_pos := Vector3(maxi(0, dx), 0, maxi(0, dz))
	var dst_pos := Vector3(maxi(0, -dx), 0, maxi(0, -dz))
	var copy_size := Vector3(SIM_X - absi(dx), SIM_Y, SIM_Z - absi(dz))

	var zero_data := PackedByteArray()
	zero_data.resize(SIM_X * SIM_Y * SIM_Z)

	_rd.texture_update(_tex_next, 0, zero_data)
	_rd.texture_update(_tex_mirror, 0, zero_data)
	_rd.submit()
	_rd.sync()

	if copy_size.x > 0 and copy_size.z > 0:
		_rd.texture_copy(_tex_current, _tex_next, src_pos, dst_pos, copy_size, 0, 0, 0, 0)
		_rd.texture_copy(_tex_current, _tex_mirror, src_pos, dst_pos, copy_size, 0, 0, 0, 0)
		_rd.submit()
		_rd.sync()

	var tmp := _tex_current
	_tex_current = _tex_next
	_tex_next = tmp
	_rebuild_uniform_set()

	_edge_fill_dx = dx
	_edge_fill_nx_lo = maxi(0, -dx)
	_edge_fill_nx_hi = mini(SIM_X, SIM_X - dx)
	_edge_fill_nz_lo = maxi(0, -dz)
	_edge_fill_nz_hi = mini(SIM_Z, SIM_Z - dz)
	_edge_fill_z = 0

	var elapsed := (Time.get_ticks_usec() - t0) / 1000.0
	print("[MaterialSimulator] shifted volume to %s (%.1f ms, filling edges)" % [_sim_origin, elapsed])


func _continue_edge_fill() -> void:
	var t0 := Time.get_ticks_usec()
	var budget_usec := 4000
	var slice_size := SIM_X * SIM_Y

	while _edge_fill_z < SIM_Z:
		var nz := _edge_fill_z
		_edge_fill_z += 1
		var is_z_edge := nz < _edge_fill_nz_lo or nz >= _edge_fill_nz_hi
		var has_x_edge := _edge_fill_dx != 0 and not is_z_edge

		if not is_z_edge and not has_x_edge:
			continue

		if is_z_edge:
			for ny in SIM_Y:
				for nx in SIM_X:
					var world_pos := Vector3i(nx, ny, nz) + _sim_origin
					var voxel := _voxel_tool.get_voxel(world_pos)
					if voxel == MaterialRegistry.AIR:
						continue
					var is_src := _source_positions.has(world_pos)
					_queue_gpu_write(world_pos, MaterialRegistry.encode_gpu(voxel, is_src))
		else:
			for ny in SIM_Y:
				if _edge_fill_dx > 0:
					for nx in range(_edge_fill_nx_hi, SIM_X):
						var world_pos := Vector3i(nx, ny, nz) + _sim_origin
						var voxel := _voxel_tool.get_voxel(world_pos)
						if voxel == MaterialRegistry.AIR:
							continue
						var is_src := _source_positions.has(world_pos)
						_queue_gpu_write(world_pos, MaterialRegistry.encode_gpu(voxel, is_src))
				else:
					for nx in range(0, _edge_fill_nx_lo):
						var world_pos := Vector3i(nx, ny, nz) + _sim_origin
						var voxel := _voxel_tool.get_voxel(world_pos)
						if voxel == MaterialRegistry.AIR:
							continue
						var is_src := _source_positions.has(world_pos)
						_queue_gpu_write(world_pos, MaterialRegistry.encode_gpu(voxel, is_src))

		if Time.get_ticks_usec() - t0 > budget_usec:
			break

	if _edge_fill_z >= SIM_Z:
		_edge_fill_z = -1


func _dispatch_tick() -> void:
	var t0 := Time.get_ticks_usec()

	_check_shift()
	_flush_pending_writes()

	var zero_bytes := PackedByteArray()
	zero_bytes.resize(4)
	zero_bytes.fill(0)
	_rd.buffer_update(_geo_buffer, 0, 4, zero_bytes)

	_rd.texture_copy(
		_tex_current, _tex_next,
		Vector3.ZERO, Vector3.ZERO,
		Vector3(SIM_X, SIM_Y, SIM_Z),
		0, 0, 0, 0)
	_rd.submit()
	_rd.sync()

	var sim_push := PackedByteArray()
	sim_push.resize(PUSH_CONST_SIZE)
	sim_push.encode_u32(0, _tick_count % 2)
	sim_push.encode_u32(4, _tick_count)
	sim_push.encode_u32(8, 0)
	sim_push.encode_u32(12, 0)

	var diff_push := PackedByteArray()
	diff_push.resize(PUSH_CONST_SIZE)
	diff_push.encode_u32(0, 0)
	diff_push.encode_u32(4, 0)
	diff_push.encode_u32(8, 1)
	diff_push.encode_u32(12, 0)

	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)

	_rd.compute_list_set_push_constant(cl, sim_push, PUSH_CONST_SIZE)
	_rd.compute_list_dispatch(cl, WORKGROUPS_X, WORKGROUPS_Y, WORKGROUPS_Z)

	_rd.compute_list_add_barrier(cl)

	_rd.compute_list_set_push_constant(cl, diff_push, PUSH_CONST_SIZE)
	_rd.compute_list_dispatch(cl, WORKGROUPS_X, WORKGROUPS_Y, WORKGROUPS_Z)

	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()

	var tmp := _tex_current
	_tex_current = _tex_next
	_tex_next = tmp
	_rebuild_uniform_set()

	_apply_changes()

	_last_tick_usec = Time.get_ticks_usec() - t0

	if _tick_count <= 3:
		print("[MaterialSimulator] tick %d: %d changes, %.2f ms" % [_tick_count, _last_changes_count, get_last_tick_ms()])


func _rebuild_uniform_set() -> void:
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	_build_uniform_set()


func _apply_changes() -> void:
	if not _voxel_tool:
		return
	var count_bytes := _rd.buffer_get_data(_geo_buffer, 0, 4)
	var count := count_bytes.decode_u32(0)
	if count == 0:
		_last_changes_count = 0
		return
	count = mini(count, GEO_BUF_MAX)

	var entries := _rd.buffer_get_data(_geo_buffer, GEO_BUF_HEADER, count * GEO_BUF_ENTRY)

	for i in count:
		var packed_pos := entries.decode_u32(i * 8)
		var new_type := entries.decode_u32(i * 8 + 4)
		var sx := int(packed_pos & 0x3FF)
		var sy := int((packed_pos >> 10) & 0x3FF)
		var sz := int((packed_pos >> 20) & 0x3FF)
		var world_pos := Vector3i(sx, sy, sz) + _sim_origin

		_voxel_tool.set_voxel(world_pos, new_type)
		voxel_changed.emit(world_pos, new_type)

	_last_changes_count = count


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_gpu()


func _cleanup_gpu() -> void:
	if not _rd:
		return
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
	if _tex_a.is_valid():
		_rd.free_rid(_tex_a)
	if _tex_b.is_valid():
		_rd.free_rid(_tex_b)
	if _tex_mirror.is_valid():
		_rd.free_rid(_tex_mirror)
	if _geo_buffer.is_valid():
		_rd.free_rid(_geo_buffer)
	_rd.free()
	_rd = null
