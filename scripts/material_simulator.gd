class_name MaterialSimulator
extends Node

const SIM_RATE := 0.05

var _voxel_tool: VoxelTool
var _active_cells: Dictionary = {}
var _sim_timer: float = 0.0
var _tick_count: int = 0
var _reacted_this_tick: Dictionary = {}

signal voxel_changed(pos: Vector3i, new_voxel: int)


func initialize(terrain: VoxelTerrain) -> void:
	_voxel_tool = terrain.get_voxel_tool()
	_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE


func place_fluid(pos: Vector3i, fluid_base: int, level: int = MaterialRegistry.FLUID_LEVELS - 1) -> void:
	if not _voxel_tool:
		return
	_voxel_tool.set_voxel(pos, MaterialRegistry.fluid_id(fluid_base, level))
	_wake_region(pos, 2)


func remove_voxel(pos: Vector3i) -> void:
	if not _voxel_tool:
		return
	_voxel_tool.set_voxel(pos, MaterialRegistry.AIR)
	_wake_region(pos, 2)


func _wake_region(center: Vector3i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				_active_cells[center + Vector3i(dx, dy, dz)] = true


func _physics_process(delta: float) -> void:
	if not _voxel_tool:
		return
	_sim_timer += delta
	if _sim_timer < SIM_RATE:
		return
	_sim_timer -= SIM_RATE
	_tick_count += 1
	_simulate_tick()


func _simulate_tick() -> void:
	if _active_cells.is_empty():
		return

	var changes: Dictionary = {}
	var next_active: Dictionary = {}
	var cells: Array = _active_cells.keys()
	_reacted_this_tick.clear()

	for pos: Vector3i in cells:
		var voxel := _voxel_tool.get_voxel(pos)
		if not MaterialRegistry.is_simulatable(voxel):
			continue

		var base := MaterialRegistry.fluid_base(voxel)
		var is_gas := MaterialRegistry.is_gas(voxel)

		if is_gas:
			var gas_cfg: Dictionary = MaterialRegistry.GAS_CONFIG.get(base, {})
			var tick_div: int = gas_cfg.get("tick_divisor", 1)
			if tick_div > 1 and _tick_count % tick_div != 0:
				next_active[pos] = true
				continue
			_simulate_gas(pos, base, voxel, changes, next_active)
		else:
			var config: Dictionary = MaterialRegistry.FLUID_CONFIG.get(base, {})
			var tick_div: int = config.get("tick_divisor", 1)
			if tick_div > 1 and _tick_count % tick_div != 0:
				next_active[pos] = true
				continue
			_simulate_fluid(pos, base, voxel, changes, next_active)

	for change_pos: Vector3i in changes:
		_voxel_tool.set_voxel(change_pos, changes[change_pos])
		voxel_changed.emit(change_pos, changes[change_pos])

	_active_cells = next_active


func _simulate_fluid(pos: Vector3i, base: int, voxel: int, changes: Dictionary, next_active: Dictionary) -> void:
	var level := MaterialRegistry.fluid_level(voxel)

	if _check_reactions(pos, voxel, changes, next_active):
		return

	if _try_flow_down(pos, base, level, changes, next_active):
		return

	if _try_fill_below(pos, base, level, changes, next_active):
		return

	_try_spread(pos, base, level, changes, next_active)


func _simulate_gas(pos: Vector3i, base: int, voxel: int, changes: Dictionary, next_active: Dictionary) -> void:
	var level := MaterialRegistry.fluid_level(voxel)
	var gas_cfg: Dictionary = MaterialRegistry.GAS_CONFIG.get(base, {})
	var dissipate: int = gas_cfg.get("dissipate_rate", 1)

	var new_level := level - dissipate
	if new_level <= 0:
		_write_change(changes, pos, MaterialRegistry.AIR)
		_activate_neighbors(next_active, pos)
		return

	if _try_rise(pos, base, new_level, changes, next_active):
		_write_change(changes, pos, MaterialRegistry.AIR)
		return

	_write_change(changes, pos, MaterialRegistry.fluid_id(base, new_level))
	_activate_neighbors(next_active, pos)

	_try_gas_spread(pos, base, new_level, changes, next_active)


func _try_rise(pos: Vector3i, base: int, level: int, changes: Dictionary, next_active: Dictionary) -> bool:
	var above := pos + Vector3i.UP
	var above_voxel := _voxel_tool.get_voxel(above)

	if above_voxel == MaterialRegistry.AIR:
		_write_change(changes, above, MaterialRegistry.fluid_id(base, level))
		_activate_neighbors(next_active, pos)
		_activate_neighbors(next_active, above)
		return true

	if MaterialRegistry.is_gas(above_voxel) and MaterialRegistry.fluid_base(above_voxel) == base:
		if MaterialRegistry.fluid_level(above_voxel) < level:
			_write_change(changes, above, MaterialRegistry.fluid_id(base, level))
			_activate_neighbors(next_active, above)
			return true

	return false


func _try_gas_spread(pos: Vector3i, base: int, level: int, changes: Dictionary, next_active: Dictionary) -> void:
	if level <= 0:
		return

	var gas_cfg: Dictionary = MaterialRegistry.GAS_CONFIG.get(base, {})
	var spread_loss: int = gas_cfg.get("spread_loss", 2)
	var spread_level := level - spread_loss
	if spread_level < 0:
		return

	var dirs: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]

	for dir: Vector3i in dirs:
		var neighbor: Vector3i = pos + dir
		var n_voxel := _voxel_tool.get_voxel(neighbor)

		if n_voxel == MaterialRegistry.AIR:
			_write_change(changes, neighbor, MaterialRegistry.fluid_id(base, spread_level))
			_activate_neighbors(next_active, neighbor)


# -- Reactions --

func _check_reactions(pos: Vector3i, voxel: int, changes: Dictionary, next_active: Dictionary) -> bool:
	if _reacted_this_tick.has(pos):
		return false

	var dirs: Array[Vector3i] = [
		Vector3i.RIGHT, Vector3i.LEFT,
		Vector3i.UP, Vector3i.DOWN,
		Vector3i.FORWARD, Vector3i.BACK
	]

	for dir: Vector3i in dirs:
		var neighbor_pos: Vector3i = pos + dir
		if _reacted_this_tick.has(neighbor_pos):
			continue

		var neighbor_voxel := _voxel_tool.get_voxel(neighbor_pos)
		if neighbor_voxel == MaterialRegistry.AIR:
			continue

		var reaction: Variant = MaterialRegistry.get_reaction(voxel, neighbor_voxel)
		if reaction == null:
			continue

		var both_fluid := MaterialRegistry.is_fluid(voxel) and MaterialRegistry.is_fluid(neighbor_voxel)

		if both_fluid:
			_apply_nibble_reaction(pos, voxel, neighbor_pos, neighbor_voxel, reaction, changes, next_active)
		else:
			_apply_instant_reaction(pos, voxel, neighbor_pos, neighbor_voxel, reaction, changes, next_active)

		_reacted_this_tick[pos] = true
		_reacted_this_tick[neighbor_pos] = true
		return true

	return false


func _apply_nibble_reaction(pos: Vector3i, voxel: int, neighbor_pos: Vector3i, neighbor_voxel: int, reaction: Dictionary, changes: Dictionary, next_active: Dictionary) -> void:
	var my_base := MaterialRegistry.fluid_base(voxel)
	var my_level := MaterialRegistry.fluid_level(voxel)
	var nb_base := MaterialRegistry.fluid_base(neighbor_voxel)
	var nb_level := MaterialRegistry.fluid_level(neighbor_voxel)

	var am_a := (my_base <= nb_base)
	var result_self: int = reaction["a"] if am_a else reaction["b"]
	var result_neighbor: int = reaction["a"] if not am_a else reaction["b"]

	var my_new := my_level - 1
	var nb_new := nb_level - 1

	var self_consumed := my_new < 0
	var neighbor_consumed := nb_new < 0

	if self_consumed:
		_apply_final_product(changes, pos, result_self)
	else:
		changes[pos] = MaterialRegistry.fluid_id(my_base, my_new)

	if neighbor_consumed:
		_apply_final_product(changes, neighbor_pos, result_neighbor)
	else:
		changes[neighbor_pos] = MaterialRegistry.fluid_id(nb_base, nb_new)

	_drain_chain(pos, my_base, changes, next_active)
	_drain_chain(neighbor_pos, nb_base, changes, next_active)

	var has_gas_product := _is_gas_product(result_self) or _is_gas_product(result_neighbor)
	if has_gas_product and not (self_consumed and neighbor_consumed):
		var gas_base: int = result_self if _is_gas_product(result_self) else result_neighbor
		_try_spawn_gas_above(pos, neighbor_pos, gas_base, changes, next_active)

	_activate_neighbors(next_active, pos)
	_activate_neighbors(next_active, neighbor_pos)


func _drain_chain(start_pos: Vector3i, fluid_base: int, changes: Dictionary, next_active: Dictionary) -> void:
	var current := start_pos
	var visited: Dictionary = {start_pos: true}
	var dirs: Array[Vector3i] = [
		Vector3i.RIGHT, Vector3i.LEFT,
		Vector3i.UP, Vector3i.DOWN,
		Vector3i.FORWARD, Vector3i.BACK
	]

	while true:
		var best_pos := Vector3i.ZERO
		var best_level := -1
		var found := false

		for dir: Vector3i in dirs:
			var np: Vector3i = current + dir
			if visited.has(np):
				continue
			var nv := _voxel_tool.get_voxel(np)
			if not MaterialRegistry.is_fluid(nv):
				continue
			if MaterialRegistry.fluid_base(nv) != fluid_base:
				continue
			var nl := MaterialRegistry.fluid_level(nv)
			if nl > best_level:
				best_level = nl
				best_pos = np
				found = true

		if not found:
			break

		visited[best_pos] = true
		var new_level := best_level - 1
		if new_level < 0:
			changes[best_pos] = MaterialRegistry.AIR
		else:
			changes[best_pos] = MaterialRegistry.fluid_id(fluid_base, new_level)
		_activate_neighbors(next_active, best_pos)
		current = best_pos


func _apply_instant_reaction(pos: Vector3i, voxel: int, neighbor_pos: Vector3i, neighbor_voxel: int, reaction: Dictionary, changes: Dictionary, next_active: Dictionary) -> void:
	var my_base := MaterialRegistry.fluid_base(voxel) if MaterialRegistry.is_simulatable(voxel) else voxel
	var nb_base := MaterialRegistry.fluid_base(neighbor_voxel) if MaterialRegistry.is_simulatable(neighbor_voxel) else neighbor_voxel
	var rule: Dictionary = reaction

	var am_a := (my_base <= nb_base)
	var result_self: int = rule["a"] if am_a else rule["b"]
	var result_neighbor: int = rule["a"] if not am_a else rule["b"]

	if result_self != -1:
		_apply_final_product(changes, pos, result_self)
	if result_neighbor != -1:
		_apply_final_product(changes, neighbor_pos, result_neighbor)

	_activate_neighbors(next_active, pos)
	_activate_neighbors(next_active, neighbor_pos)


func _apply_final_product(changes: Dictionary, pos: Vector3i, product: int) -> void:
	if _is_gas_product(product):
		_write_change(changes, pos, MaterialRegistry.fluid_id(product, MaterialRegistry.FLUID_LEVELS - 1))
	elif product == MaterialRegistry.AIR:
		_write_change(changes, pos, MaterialRegistry.AIR)
	else:
		_write_change(changes, pos, product)


func _is_gas_product(product: int) -> bool:
	return product in MaterialRegistry.GAS_BASES


func _try_spawn_gas_above(pos: Vector3i, neighbor_pos: Vector3i, gas_base: int, changes: Dictionary, next_active: Dictionary) -> void:
	var above_pos := pos + Vector3i.UP
	var above_voxel := _voxel_tool.get_voxel(above_pos)
	if above_voxel == MaterialRegistry.AIR or MaterialRegistry.is_gas(above_voxel):
		_write_change(changes, above_pos, MaterialRegistry.fluid_id(gas_base, 1))
		_activate_neighbors(next_active, above_pos)
		return

	var above_nb := neighbor_pos + Vector3i.UP
	var above_nb_voxel := _voxel_tool.get_voxel(above_nb)
	if above_nb_voxel == MaterialRegistry.AIR or MaterialRegistry.is_gas(above_nb_voxel):
		_write_change(changes, above_nb, MaterialRegistry.fluid_id(gas_base, 1))
		_activate_neighbors(next_active, above_nb)


# -- Flow --

func _try_flow_down(pos: Vector3i, base: int, level: int, changes: Dictionary, next_active: Dictionary) -> bool:
	var below := pos + Vector3i.DOWN
	var below_voxel := _voxel_tool.get_voxel(below)

	if below_voxel == MaterialRegistry.AIR:
		_write_change(changes, below, MaterialRegistry.fluid_id(base, level))
		_write_change(changes, pos, MaterialRegistry.AIR)
		_activate_neighbors(next_active, pos)
		_activate_neighbors(next_active, below)
		return true

	if MaterialRegistry.is_gas(below_voxel):
		_write_change(changes, below, MaterialRegistry.fluid_id(base, level))
		_write_change(changes, pos, below_voxel)
		_activate_neighbors(next_active, pos)
		_activate_neighbors(next_active, below)
		return true

	return false


func _try_fill_below(pos: Vector3i, base: int, level: int, changes: Dictionary, next_active: Dictionary) -> bool:
	var below := pos + Vector3i.DOWN
	var below_voxel := _voxel_tool.get_voxel(below)

	if not MaterialRegistry.is_fluid(below_voxel):
		return false
	if MaterialRegistry.fluid_base(below_voxel) != base:
		return false
	if MaterialRegistry.fluid_level(below_voxel) >= MaterialRegistry.FLUID_LEVELS - 1:
		return false

	var below_level := MaterialRegistry.fluid_level(below_voxel)
	var transfer := mini(level, MaterialRegistry.FLUID_LEVELS - 1 - below_level)
	if transfer <= 0:
		return false

	_write_change(changes, below, MaterialRegistry.fluid_id(base, below_level + transfer))
	var remaining := level - transfer
	if remaining <= 0:
		_write_change(changes, pos, MaterialRegistry.AIR)
	else:
		_write_change(changes, pos, MaterialRegistry.fluid_id(base, remaining))
	_activate_neighbors(next_active, pos)
	_activate_neighbors(next_active, below)
	return true


func _try_spread(pos: Vector3i, base: int, level: int, changes: Dictionary, next_active: Dictionary) -> void:
	if level <= 0:
		return

	var config: Dictionary = MaterialRegistry.FLUID_CONFIG.get(base, {})
	var spread_loss: int = config.get("spread_loss", 1)
	var spread_level := level - spread_loss
	if spread_level < 0:
		return

	var dirs: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]

	for dir: Vector3i in dirs:
		var neighbor: Vector3i = pos + dir
		var n_voxel := _voxel_tool.get_voxel(neighbor)

		if n_voxel == MaterialRegistry.AIR:
			_write_change(changes, neighbor, MaterialRegistry.fluid_id(base, spread_level))
			_activate_neighbors(next_active, neighbor)
		elif MaterialRegistry.is_fluid(n_voxel) and MaterialRegistry.fluid_base(n_voxel) == base:
			if MaterialRegistry.fluid_level(n_voxel) < spread_level:
				_write_change(changes, neighbor, MaterialRegistry.fluid_id(base, spread_level))
				_activate_neighbors(next_active, neighbor)


# -- Helpers --

func _write_change(changes: Dictionary, pos: Vector3i, new_id: int) -> void:
	if changes.has(pos):
		var existing := changes[pos] as int
		if MaterialRegistry.is_simulatable(new_id) and MaterialRegistry.is_simulatable(existing):
			if MaterialRegistry.fluid_base(new_id) == MaterialRegistry.fluid_base(existing):
				if MaterialRegistry.fluid_level(new_id) > MaterialRegistry.fluid_level(existing):
					changes[pos] = new_id
		elif MaterialRegistry.is_simulatable(new_id) and existing == MaterialRegistry.AIR:
			changes[pos] = new_id
		elif MaterialRegistry.is_solid(new_id):
			changes[pos] = new_id
	else:
		changes[pos] = new_id


func _activate_neighbors(active_set: Dictionary, pos: Vector3i) -> void:
	active_set[pos] = true
	active_set[pos + Vector3i.RIGHT] = true
	active_set[pos + Vector3i.LEFT] = true
	active_set[pos + Vector3i.UP] = true
	active_set[pos + Vector3i.DOWN] = true
	active_set[pos + Vector3i.FORWARD] = true
	active_set[pos + Vector3i.BACK] = true
