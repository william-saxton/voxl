class_name MaterialRegistry

const VOXEL_SCALE := 0.25
const INV_VOXEL_SCALE := 4

const AIR := 0
const STONE := 1
const BEDROCK := 2
const WATER := 3
const DIRT := 4
const MUD := 5
const LAVA := 6
const ACID := 7
const GAS := 8

const FLUID_IDS: Array[int] = [WATER, LAVA, ACID]
const GAS_IDS: Array[int] = [GAS]


static func is_fluid(id: int) -> bool:
	return id == WATER or id == LAVA or id == ACID


static func is_gas(id: int) -> bool:
	return id == GAS


static func is_simulatable(id: int) -> bool:
	return is_fluid(id) or is_gas(id)


static func is_solid(id: int) -> bool:
	return id != AIR and not is_fluid(id) and not is_gas(id)


static func is_passable(id: int) -> bool:
	return id == AIR or is_fluid(id) or is_gas(id)


static func get_reaction(id_a: int, id_b: int) -> Variant:
	var key := _pair(id_a, id_b)

	if key == Vector2i(WATER, LAVA):
		return {"a": AIR, "b": STONE}
	if key == Vector2i(WATER, ACID):
		return {"a": GAS, "b": GAS}
	if key == Vector2i(DIRT, WATER):
		return {"a": MUD, "b": AIR}

	return null


static func _pair(a: int, b: int) -> Vector2i:
	if a <= b:
		return Vector2i(a, b)
	return Vector2i(b, a)


static func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floorf(world_pos.x * INV_VOXEL_SCALE)),
		int(floorf(world_pos.y * INV_VOXEL_SCALE)),
		int(floorf(world_pos.z * INV_VOXEL_SCALE))
	)


static func voxel_to_world(voxel_pos: Vector3i) -> Vector3:
	return Vector3(voxel_pos) * VOXEL_SCALE
