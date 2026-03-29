class_name MaterialRegistry

const VOXEL_SCALE := 0.25
const INV_VOXEL_SCALE := 4

# ══════════════════════════════════════════════════════════════════════════════
# Base material IDs (low byte of uint16 voxel ID)
# ══════════════════════════════════════════════════════════════════════════════

# Core (0)
const AIR := 0

# Universal Terrain (1-19)
const STONE := 1
const BEDROCK := 2
const WATER := 3
const DIRT := 4
const MUD := 5
const LAVA := 6
const ACID := 7
const STEAM := 8
const SAND := 9
const GRAVEL := 10
const ICE := 11
const GLASS := 12
const COAL := 13
const GUNPOWDER := 14
const SNOW := 15
const SALT := 16
const ASH := 17
const SMOKE := 18
const TOXIC_GAS := 19

# Structural / Crafted (20-29)
const WOOD := 20
const METAL := 21
const BRICK := 22
const MARBLE := 23
const CRYSTAL := 24
const OBSIDIAN := 25
const RUST := 26
const CLAY := 27

# Biological Universal (30-39)
const BONE := 30
const BONE_DUST := 31
const BLOOD := 32
const MEAT := 33
const ROTTEN_MEAT := 34
const COOKED_MEAT := 35
const VOMIT := 36

# Depth 1: Biomechanical Jungle (40-49)
const BIOMASS := 40
const CHITIN := 41
const SAP := 42
const SPORE_GAS := 43
const VINE := 44
const MOSS := 45
const POLLEN := 46
const NECTAR := 47

# Depth 2: Crumbling Citadel (50-56)
const ARCANE_ICHOR := 50
const RUBBLE := 51
const DUST := 52
const COBWEB := 53
const LICHEN := 54
const ECTOPLASM := 55

# Depth 3: Molten Core (60-69)
const MAGMA_ROCK := 60
const SLAG := 61
const MOLTEN_METAL := 62
const SULFUR := 63
const EMBER := 64
const MOLTEN_BLOOD := 65
const ITE_MINERAL := 66

# Depth 4: Clockwork Labyrinth (70-79)
const GEAR_BLOCK := 70
const CONDUIT := 71
const OIL := 72
const SCRAP_METAL := 73
const SPARK := 74
const COOLANT := 75
const GEAR_FRAGMENT := 76

# Depth 5: Obsidian Core (80-89)
const VOID_STONE := 80
const RIFT_CRYSTAL := 81
const SHADOW_FLUID := 82
const NULL_GAS := 83
const CORRUPTED := 84
const VOID_FLESH := 85
const VOID_BLOOD := 86

# Magical Materials — Offensive (90-95)
const BERSERKER_BILE := 90
const PHEROMONE := 91
const GILDING_SOLUTION := 92
const VULNERABILITY_SAP := 93
const THORN_EXTRACT := 94
const POISON := 95

# Magical Materials — Utility (96-103)
const AMMO_ELIXIR := 96
const QUICKSILVER := 97
const HASTE_OIL := 98
const SWIFTNESS_TONIC := 99
const PHASE_FLUID := 100
const AEGIS_FLUID := 101
const VITAE := 102
const CONFUSION_MIST := 103

# Magical Materials — Exotic (104-110)
const TEMPORAL_FLUID := 104
const POLYMORPHINE := 105
const CHAOTIC_POLYMORPHINE := 106
const NANITE_SWARM := 107
const WARP_FLUID := 108
const GENESIS_FLUID := 109
const ETHANOL := 110

# Contact Damage Materials (111-114)
const CURSED_SLUDGE := 111
const MOLTEN_SLAG := 112
const BLIGHT := 113
const RAZOR_DUST := 114

# Metals (115-122)
const IRON := 115
const COPPER := 116
const BRASS := 117
const SILVER := 118
const GOLD := 119
const DARK_STEEL := 120
const ARCANE_ALLOY := 121
const MOLTEN_GLASS := 122

# Arcane Crystals — Currency (123-127)
const CRYSTAL_SHARD := 123
const CRYSTAL_AMBER := 124
const CRYSTAL_EMERALD := 125
const CRYSTAL_RUBY := 126
const CRYSTAL_VOID := 127

# Plants (128-137)
const GRASS := 128
const MUSHROOM := 129
const CACTUS := 130
const ALOE := 131
const GLOWCAP := 132
const MANAFRUIT := 133
const DRAGON_PEPPER := 134
const STARFRUIT := 135
const THORNVINE := 136
const HEALROOT := 137

# ══════════════════════════════════════════════════════════════════════════════
# Category sets
# ══════════════════════════════════════════════════════════════════════════════

const FLUID_IDS: Array[int] = [
	WATER, LAVA, ACID, BLOOD, SAP, NECTAR, ARCANE_ICHOR, ECTOPLASM,
	MOLTEN_METAL, MOLTEN_BLOOD, OIL, COOLANT, SHADOW_FLUID, VOID_BLOOD,
	BERSERKER_BILE, PHEROMONE, GILDING_SOLUTION, VULNERABILITY_SAP,
	THORN_EXTRACT, POISON, AMMO_ELIXIR, QUICKSILVER, HASTE_OIL,
	SWIFTNESS_TONIC, PHASE_FLUID, AEGIS_FLUID, VITAE,
	TEMPORAL_FLUID, POLYMORPHINE, CHAOTIC_POLYMORPHINE, NANITE_SWARM,
	WARP_FLUID, GENESIS_FLUID, ETHANOL,
	CURSED_SLUDGE, MOLTEN_SLAG, BLIGHT, MOLTEN_GLASS, VOMIT,
]

const GAS_IDS: Array[int] = [
	STEAM, SMOKE, TOXIC_GAS, SPORE_GAS, DUST, SPARK, NULL_GAS,
	CONFUSION_MIST,
]

const POWDER_IDS: Array[int] = [
	MUD, SAND, GRAVEL, COAL, GUNPOWDER, SNOW, SALT, ASH,
	BONE_DUST, POLLEN, RUBBLE, SLAG, SULFUR, EMBER,
	SCRAP_METAL, GEAR_FRAGMENT, RAZOR_DUST,
]


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

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
	return (id & 0xFF) in FLUID_IDS


static func is_gas(id: int) -> bool:
	return (id & 0xFF) in GAS_IDS


static func is_powder(id: int) -> bool:
	return (id & 0xFF) in POWDER_IDS


static func is_simulatable(id: int) -> bool:
	return is_fluid(id) or is_gas(id) or is_powder(id)


static func is_solid(id: int) -> bool:
	var b := id & 0xFF
	return b != AIR and not is_fluid(id) and not is_gas(id) and not is_powder(id)


static func is_passable(id: int) -> bool:
	var b := id & 0xFF
	return b == AIR or is_fluid(id) or is_gas(id)


static func get_reaction(id_a: int, id_b: int) -> Variant:
	var key := _pair(id_a & 0xFF, id_b & 0xFF)

	# Universal reactions
	if key == Vector2i(WATER, LAVA):
		return {"a": OBSIDIAN, "b": STEAM}
	if key == Vector2i(WATER, ACID):
		return {"a": STEAM, "b": STEAM}
	if key == Vector2i(DIRT, WATER):
		return {"a": MUD, "b": AIR}
	if key == Vector2i(SAND, LAVA):
		return {"a": GLASS, "b": AIR}
	if key == Vector2i(METAL, ACID):
		return {"a": RUST, "b": AIR}
	if key == Vector2i(SALT, ICE):
		return {"a": AIR, "b": WATER}

	return null


static func _pair(a: int, b: int) -> Vector2i:
	if a <= b:
		return Vector2i(a, b)
	return Vector2i(b, a)


## Returns all registered material types as an array of Dictionaries:
## [{ id: int, name: String, category: String }]
static func get_all_materials() -> Array[Dictionary]:
	return [
		# Core
		{ "id": AIR, "name": "Air", "category": "void" },
		# Universal Terrain
		{ "id": STONE, "name": "Stone", "category": "solid" },
		{ "id": BEDROCK, "name": "Bedrock", "category": "solid" },
		{ "id": WATER, "name": "Water", "category": "fluid" },
		{ "id": DIRT, "name": "Dirt", "category": "solid" },
		{ "id": MUD, "name": "Mud", "category": "powder" },
		{ "id": LAVA, "name": "Lava", "category": "fluid" },
		{ "id": ACID, "name": "Acid", "category": "fluid" },
		{ "id": STEAM, "name": "Steam", "category": "gas" },
		{ "id": SAND, "name": "Sand", "category": "powder" },
		{ "id": GRAVEL, "name": "Gravel", "category": "powder" },
		{ "id": ICE, "name": "Ice", "category": "solid" },
		{ "id": GLASS, "name": "Glass", "category": "solid" },
		{ "id": COAL, "name": "Coal", "category": "powder" },
		{ "id": GUNPOWDER, "name": "Gunpowder", "category": "powder" },
		{ "id": SNOW, "name": "Snow", "category": "powder" },
		{ "id": SALT, "name": "Salt", "category": "powder" },
		{ "id": ASH, "name": "Ash", "category": "powder" },
		{ "id": SMOKE, "name": "Smoke", "category": "gas" },
		{ "id": TOXIC_GAS, "name": "Toxic Gas", "category": "gas" },
		# Structural / Crafted
		{ "id": WOOD, "name": "Wood", "category": "solid" },
		{ "id": METAL, "name": "Metal", "category": "solid" },
		{ "id": BRICK, "name": "Brick", "category": "solid" },
		{ "id": MARBLE, "name": "Marble", "category": "solid" },
		{ "id": CRYSTAL, "name": "Crystal", "category": "solid" },
		{ "id": OBSIDIAN, "name": "Obsidian", "category": "solid" },
		{ "id": RUST, "name": "Rust", "category": "solid" },
		{ "id": CLAY, "name": "Clay", "category": "solid" },
		# Biological Universal
		{ "id": BONE, "name": "Bone", "category": "solid" },
		{ "id": BONE_DUST, "name": "Bone Dust", "category": "powder" },
		{ "id": BLOOD, "name": "Blood", "category": "fluid" },
		{ "id": MEAT, "name": "Meat", "category": "solid" },
		{ "id": ROTTEN_MEAT, "name": "Rotten Meat", "category": "solid" },
		{ "id": COOKED_MEAT, "name": "Cooked Meat", "category": "solid" },
		{ "id": VOMIT, "name": "Vomit", "category": "fluid" },
		# Depth 1: Biomechanical Jungle
		{ "id": BIOMASS, "name": "Biomass", "category": "solid" },
		{ "id": CHITIN, "name": "Chitin", "category": "solid" },
		{ "id": SAP, "name": "Sap", "category": "fluid" },
		{ "id": SPORE_GAS, "name": "Spore Gas", "category": "gas" },
		{ "id": VINE, "name": "Vine", "category": "solid" },
		{ "id": MOSS, "name": "Moss", "category": "solid" },
		{ "id": POLLEN, "name": "Pollen", "category": "powder" },
		{ "id": NECTAR, "name": "Nectar", "category": "fluid" },
		# Depth 2: Crumbling Citadel
		{ "id": ARCANE_ICHOR, "name": "Arcane Ichor", "category": "fluid" },
		{ "id": RUBBLE, "name": "Rubble", "category": "powder" },
		{ "id": DUST, "name": "Dust", "category": "gas" },
		{ "id": COBWEB, "name": "Cobweb", "category": "solid" },
		{ "id": LICHEN, "name": "Lichen", "category": "solid" },
		{ "id": ECTOPLASM, "name": "Ectoplasm", "category": "fluid" },
		# Depth 3: Molten Core
		{ "id": MAGMA_ROCK, "name": "Magma Rock", "category": "solid" },
		{ "id": SLAG, "name": "Slag", "category": "powder" },
		{ "id": MOLTEN_METAL, "name": "Molten Metal", "category": "fluid" },
		{ "id": SULFUR, "name": "Sulfur", "category": "powder" },
		{ "id": EMBER, "name": "Ember", "category": "powder" },
		{ "id": MOLTEN_BLOOD, "name": "Molten Blood", "category": "fluid" },
		{ "id": ITE_MINERAL, "name": "Ite Mineral", "category": "solid" },
		# Depth 4: Clockwork Labyrinth
		{ "id": GEAR_BLOCK, "name": "Gear Block", "category": "solid" },
		{ "id": CONDUIT, "name": "Conduit", "category": "solid" },
		{ "id": OIL, "name": "Oil", "category": "fluid" },
		{ "id": SCRAP_METAL, "name": "Scrap Metal", "category": "powder" },
		{ "id": SPARK, "name": "Spark", "category": "gas" },
		{ "id": COOLANT, "name": "Coolant", "category": "fluid" },
		{ "id": GEAR_FRAGMENT, "name": "Gear Fragment", "category": "powder" },
		# Depth 5: Obsidian Core
		{ "id": VOID_STONE, "name": "Void Stone", "category": "solid" },
		{ "id": RIFT_CRYSTAL, "name": "Rift Crystal", "category": "solid" },
		{ "id": SHADOW_FLUID, "name": "Shadow Fluid", "category": "fluid" },
		{ "id": NULL_GAS, "name": "Null Gas", "category": "gas" },
		{ "id": CORRUPTED, "name": "Corrupted", "category": "solid" },
		{ "id": VOID_FLESH, "name": "Void Flesh", "category": "solid" },
		{ "id": VOID_BLOOD, "name": "Void Blood", "category": "fluid" },
		# Magical — Offensive
		{ "id": BERSERKER_BILE, "name": "Berserker Bile", "category": "fluid" },
		{ "id": PHEROMONE, "name": "Pheromone", "category": "fluid" },
		{ "id": GILDING_SOLUTION, "name": "Gilding Solution", "category": "fluid" },
		{ "id": VULNERABILITY_SAP, "name": "Vulnerability Sap", "category": "fluid" },
		{ "id": THORN_EXTRACT, "name": "Thorn Extract", "category": "fluid" },
		{ "id": POISON, "name": "Poison", "category": "fluid" },
		# Magical — Utility
		{ "id": AMMO_ELIXIR, "name": "Ammo Elixir", "category": "fluid" },
		{ "id": QUICKSILVER, "name": "Quicksilver", "category": "fluid" },
		{ "id": HASTE_OIL, "name": "Haste Oil", "category": "fluid" },
		{ "id": SWIFTNESS_TONIC, "name": "Swiftness Tonic", "category": "fluid" },
		{ "id": PHASE_FLUID, "name": "Phase Fluid", "category": "fluid" },
		{ "id": AEGIS_FLUID, "name": "Aegis Fluid", "category": "fluid" },
		{ "id": VITAE, "name": "Vitae", "category": "fluid" },
		{ "id": CONFUSION_MIST, "name": "Confusion Mist", "category": "gas" },
		# Magical — Exotic
		{ "id": TEMPORAL_FLUID, "name": "Temporal Fluid", "category": "fluid" },
		{ "id": POLYMORPHINE, "name": "Polymorphine", "category": "fluid" },
		{ "id": CHAOTIC_POLYMORPHINE, "name": "Chaotic Polymorphine", "category": "fluid" },
		{ "id": NANITE_SWARM, "name": "Nanite Swarm", "category": "fluid" },
		{ "id": WARP_FLUID, "name": "Warp Fluid", "category": "fluid" },
		{ "id": GENESIS_FLUID, "name": "Genesis Fluid", "category": "fluid" },
		{ "id": ETHANOL, "name": "Ethanol", "category": "fluid" },
		# Contact Damage
		{ "id": CURSED_SLUDGE, "name": "Cursed Sludge", "category": "fluid" },
		{ "id": MOLTEN_SLAG, "name": "Molten Slag", "category": "fluid" },
		{ "id": BLIGHT, "name": "Blight", "category": "fluid" },
		{ "id": RAZOR_DUST, "name": "Razor Dust", "category": "powder" },
		# Metals
		{ "id": IRON, "name": "Iron", "category": "solid" },
		{ "id": COPPER, "name": "Copper", "category": "solid" },
		{ "id": BRASS, "name": "Brass", "category": "solid" },
		{ "id": SILVER, "name": "Silver", "category": "solid" },
		{ "id": GOLD, "name": "Gold", "category": "solid" },
		{ "id": DARK_STEEL, "name": "Dark Steel", "category": "solid" },
		{ "id": ARCANE_ALLOY, "name": "Arcane Alloy", "category": "solid" },
		{ "id": MOLTEN_GLASS, "name": "Molten Glass", "category": "fluid" },
		# Arcane Crystals — Currency
		{ "id": CRYSTAL_SHARD, "name": "Crystal Shard", "category": "solid" },
		{ "id": CRYSTAL_AMBER, "name": "Crystal Amber", "category": "solid" },
		{ "id": CRYSTAL_EMERALD, "name": "Crystal Emerald", "category": "solid" },
		{ "id": CRYSTAL_RUBY, "name": "Crystal Ruby", "category": "solid" },
		{ "id": CRYSTAL_VOID, "name": "Crystal Void", "category": "solid" },
		# Plants
		{ "id": GRASS, "name": "Grass", "category": "solid" },
		{ "id": MUSHROOM, "name": "Mushroom", "category": "solid" },
		{ "id": CACTUS, "name": "Cactus", "category": "solid" },
		{ "id": ALOE, "name": "Aloe", "category": "solid" },
		{ "id": GLOWCAP, "name": "Glowcap", "category": "solid" },
		{ "id": MANAFRUIT, "name": "Manafruit", "category": "solid" },
		{ "id": DRAGON_PEPPER, "name": "Dragon Pepper", "category": "solid" },
		{ "id": STARFRUIT, "name": "Starfruit", "category": "solid" },
		{ "id": THORNVINE, "name": "Thornvine", "category": "solid" },
		{ "id": HEALROOT, "name": "Healroot", "category": "solid" },
	]


static func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floorf(world_pos.x * INV_VOXEL_SCALE)),
		int(floorf(world_pos.y * INV_VOXEL_SCALE)),
		int(floorf(world_pos.z * INV_VOXEL_SCALE))
	)


static func voxel_to_world(voxel_pos: Vector3i) -> Vector3:
	return Vector3(voxel_pos) * VOXEL_SCALE
