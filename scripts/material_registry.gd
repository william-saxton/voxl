class_name MaterialRegistry

const VOXEL_SCALE := 0.25
const INV_VOXEL_SCALE := 4

# Base material IDs (low byte of uint16 voxel ID)
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


## Extract the base material (low byte) from a full uint16 voxel ID.
static func base_material(voxel_id: int) -> int:
	return voxel_id & 0xFF


## Extract the visual variant (high byte) from a full uint16 voxel ID.
static func visual_variant(voxel_id: int) -> int:
	return (voxel_id >> 8) & 0xFF


## Combine a base material and visual variant into a uint16 voxel ID.
static func make_voxel_id(base: int, visual: int = 0) -> int:
	return (visual << 8) | base


static func is_fluid(id: int) -> bool:
	var b := id & 0xFF
	return b == WATER or b == LAVA or b == ACID


static func is_gas(id: int) -> bool:
	return (id & 0xFF) == GAS


static func is_simulatable(id: int) -> bool:
	return is_fluid(id) or is_gas(id)


static func is_solid(id: int) -> bool:
	var b := id & 0xFF
	return b != AIR and not is_fluid(id) and not is_gas(id)


static func is_passable(id: int) -> bool:
	var b := id & 0xFF
	return b == AIR or is_fluid(id) or is_gas(id)


static func get_reaction(id_a: int, id_b: int) -> Variant:
	var key := _pair(id_a & 0xFF, id_b & 0xFF)

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


## Returns all registered material types as an array of Dictionaries:
## [{ id: int, name: String, category: String }]
static func get_all_materials() -> Array[Dictionary]:
	return [
		{ "id": AIR, "name": "Air", "category": "void" },
		{ "id": STONE, "name": "Stone", "category": "solid" },
		{ "id": BEDROCK, "name": "Bedrock", "category": "solid" },
		{ "id": WATER, "name": "Water", "category": "fluid" },
		{ "id": DIRT, "name": "Dirt", "category": "solid" },
		{ "id": MUD, "name": "Mud", "category": "solid" },
		{ "id": LAVA, "name": "Lava", "category": "fluid" },
		{ "id": ACID, "name": "Acid", "category": "fluid" },
		{ "id": GAS, "name": "Gas", "category": "gas" },
	]


static func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floorf(world_pos.x * INV_VOXEL_SCALE)),
		int(floorf(world_pos.y * INV_VOXEL_SCALE)),
		int(floorf(world_pos.z * INV_VOXEL_SCALE))
	)


static func voxel_to_world(voxel_pos: Vector3i) -> Vector3:
	return Vector3(voxel_pos) * VOXEL_SCALE
