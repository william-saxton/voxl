class_name MaterialRegistry

const AIR := 0
const STONE := 1
const BEDROCK := 2
const WATER_BASE := 3
const DIRT := 11
const MUD := 12
const LAVA_BASE := 13
const ACID_BASE := 21
const GAS_BASE := 29

const FLUID_LEVELS := 8

const FLUID_BASES: Array[int] = [WATER_BASE, LAVA_BASE, ACID_BASE]
const GAS_BASES: Array[int] = [GAS_BASE]

const FLUID_CONFIG := {
	WATER_BASE: {"tick_divisor": 1, "spread_loss": 1},
	LAVA_BASE:  {"tick_divisor": 3, "spread_loss": 2},
	ACID_BASE:  {"tick_divisor": 1, "spread_loss": 1},
}

const GAS_CONFIG := {
	GAS_BASE: {"tick_divisor": 2, "spread_loss": 2, "dissipate_rate": 1},
}


static func is_fluid(id: int) -> bool:
	for base: int in FLUID_BASES:
		if id >= base and id < base + FLUID_LEVELS:
			return true
	return false


static func is_gas(id: int) -> bool:
	for base: int in GAS_BASES:
		if id >= base and id < base + FLUID_LEVELS:
			return true
	return false


static func is_simulatable(id: int) -> bool:
	return is_fluid(id) or is_gas(id)


static func fluid_base(id: int) -> int:
	for base: int in FLUID_BASES:
		if id >= base and id < base + FLUID_LEVELS:
			return base
	for base: int in GAS_BASES:
		if id >= base and id < base + FLUID_LEVELS:
			return base
	return -1


static func fluid_level(id: int) -> int:
	var base := fluid_base(id)
	if base < 0:
		return -1
	return id - base


static func fluid_id(base: int, level: int) -> int:
	return base + clampi(level, 0, FLUID_LEVELS - 1)


static func is_solid(id: int) -> bool:
	return id != AIR and not is_fluid(id) and not is_gas(id)


static func is_passable(id: int) -> bool:
	return id == AIR or is_fluid(id) or is_gas(id)


static func get_reaction(id_a: int, id_b: int) -> Variant:
	var type_a := fluid_base(id_a) if (is_fluid(id_a) or is_gas(id_a)) else id_a
	var type_b := fluid_base(id_b) if (is_fluid(id_b) or is_gas(id_b)) else id_b
	var key := _pair(type_a, type_b)

	if key == Vector2i(WATER_BASE, LAVA_BASE):
		return {"a": AIR, "b": STONE}
	if key == Vector2i(WATER_BASE, ACID_BASE):
		return {"a": GAS_BASE, "b": GAS_BASE}
	if key == Vector2i(WATER_BASE, DIRT):
		return {"a": -1, "b": MUD}

	return null


static func _pair(a: int, b: int) -> Vector2i:
	if a <= b:
		return Vector2i(a, b)
	return Vector2i(b, a)


const GPU_SOURCE_FLAG := 0x80
const GPU_ID_MASK := 0x7F

static func encode_gpu(id: int, is_source: bool) -> int:
	return (id & GPU_ID_MASK) | (GPU_SOURCE_FLAG if is_source else 0)

static func decode_gpu_id(byte: int) -> int:
	return byte & GPU_ID_MASK

static func decode_gpu_source(byte: int) -> bool:
	return (byte & GPU_SOURCE_FLAG) != 0
