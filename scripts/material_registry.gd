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


# ══════════════════════════════════════════════════════════════════════════════
# Centralized reaction table
# Each entry: { "a": mat_id, "b": mat_id, "result_a": mat_id, "result_b": mat_id }
# When material A meets material B, A becomes result_a and B becomes result_b.
# Add new reactions here — they are automatically surfaced in tooltips and
# available via get_reaction() and get_reactions_for().
# ══════════════════════════════════════════════════════════════════════════════

const _REACTIONS: Array[Dictionary] = [
	# Universal
	{ "a": WATER, "b": LAVA, "result_a": OBSIDIAN, "result_b": STEAM },
	{ "a": WATER, "b": ACID, "result_a": STEAM, "result_b": STEAM },
	{ "a": DIRT, "b": WATER, "result_a": MUD, "result_b": AIR },
	{ "a": SAND, "b": LAVA, "result_a": GLASS, "result_b": AIR },
	{ "a": METAL, "b": ACID, "result_a": RUST, "result_b": AIR },
	{ "a": SALT, "b": ICE, "result_a": AIR, "result_b": WATER },
	# Burning
	{ "a": WOOD, "b": LAVA, "result_a": ASH, "result_b": SMOKE },
	{ "a": WOOD, "b": EMBER, "result_a": ASH, "result_b": SMOKE },
	{ "a": WOOD, "b": SPARK, "result_a": ASH, "result_b": SMOKE },
	{ "a": COAL, "b": LAVA, "result_a": ASH, "result_b": SMOKE },
	{ "a": COAL, "b": EMBER, "result_a": ASH, "result_b": SMOKE },
	{ "a": COAL, "b": SPARK, "result_a": ASH, "result_b": SMOKE },
	{ "a": OIL, "b": LAVA, "result_a": SMOKE, "result_b": EMBER },
	{ "a": OIL, "b": EMBER, "result_a": SMOKE, "result_b": EMBER },
	{ "a": OIL, "b": SPARK, "result_a": SMOKE, "result_b": SPARK },
	{ "a": GUNPOWDER, "b": LAVA, "result_a": STEAM, "result_b": LAVA },
	{ "a": GUNPOWDER, "b": EMBER, "result_a": STEAM, "result_b": EMBER },
	{ "a": GUNPOWDER, "b": SPARK, "result_a": STEAM, "result_b": SPARK },
	{ "a": SULFUR, "b": LAVA, "result_a": TOXIC_GAS, "result_b": LAVA },
	{ "a": SULFUR, "b": EMBER, "result_a": TOXIC_GAS, "result_b": EMBER },
	{ "a": VINE, "b": LAVA, "result_a": ASH, "result_b": SMOKE },
	{ "a": VINE, "b": EMBER, "result_a": ASH, "result_b": SMOKE },
	{ "a": VINE, "b": SPARK, "result_a": ASH, "result_b": SMOKE },
	{ "a": COBWEB, "b": LAVA, "result_a": ASH, "result_b": LAVA },
	{ "a": COBWEB, "b": EMBER, "result_a": ASH, "result_b": EMBER },
	{ "a": COBWEB, "b": SPARK, "result_a": ASH, "result_b": SPARK },
	# Melting
	{ "a": ICE, "b": LAVA, "result_a": WATER, "result_b": LAVA },
	{ "a": ICE, "b": EMBER, "result_a": WATER, "result_b": EMBER },
	{ "a": SNOW, "b": LAVA, "result_a": WATER, "result_b": LAVA },
	{ "a": SNOW, "b": EMBER, "result_a": WATER, "result_b": EMBER },
	{ "a": METAL, "b": LAVA, "result_a": MOLTEN_METAL, "result_b": LAVA },
	{ "a": GLASS, "b": LAVA, "result_a": MOLTEN_GLASS, "result_b": LAVA },
	# Biological
	{ "a": MEAT, "b": LAVA, "result_a": COOKED_MEAT, "result_b": LAVA },
	{ "a": MEAT, "b": EMBER, "result_a": COOKED_MEAT, "result_b": EMBER },
	# Depth-specific
	{ "a": POISON, "b": WATER, "result_a": TOXIC_GAS, "result_b": TOXIC_GAS },
	{ "a": MOLTEN_BLOOD, "b": WATER, "result_a": SLAG, "result_b": STEAM },
	# Magical reactions
	{ "a": AEGIS_FLUID, "b": VULNERABILITY_SAP, "result_a": AIR, "result_b": AIR },
	{ "a": GILDING_SOLUTION, "b": ACID, "result_a": AIR, "result_b": ACID },
	{ "a": GENESIS_FLUID, "b": SALT, "result_a": AIR, "result_b": SALT },
	{ "a": BLIGHT, "b": SALT, "result_a": AIR, "result_b": SALT },
	{ "a": POLYMORPHINE, "b": WATER, "result_a": POLYMORPHINE, "result_b": WATER },
	{ "a": TEMPORAL_FLUID, "b": NULL_GAS, "result_a": AIR, "result_b": NULL_GAS },
]


static func _pair(a: int, b: int) -> Vector2i:
	if a <= b:
		return Vector2i(a, b)
	return Vector2i(b, a)


## Look up the reaction between two materials. Returns null if none.
## Result dict: { "a": result_for_first, "b": result_for_second }
static func get_reaction(id_a: int, id_b: int) -> Variant:
	var a := id_a & 0xFF
	var b := id_b & 0xFF
	for r in _REACTIONS:
		if (r["a"] == a and r["b"] == b):
			return {"a": r["result_a"], "b": r["result_b"]}
		if (r["a"] == b and r["b"] == a):
			return {"a": r["result_b"], "b": r["result_a"]}
	return null


## Get all reactions involving a specific material, with human-readable names.
## Returns: [{ "with": String, "produces": String }]
static func get_reactions_for(material_id: int) -> Array[Dictionary]:
	var mid := material_id & 0xFF
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}  # Deduplicate identical display strings
	for r in _REACTIONS:
		var entry: Dictionary = {}
		if r["a"] == mid:
			entry = {"with": _id_to_name(r["b"]), "produces": _reaction_products(r["result_a"], r["result_b"])}
		elif r["b"] == mid:
			entry = {"with": _id_to_name(r["a"]), "produces": _reaction_products(r["result_b"], r["result_a"])}
		else:
			continue
		var key := "%s→%s" % [entry["with"], entry["produces"]]
		if not seen.has(key):
			seen[key] = true
			result.append(entry)
	return result


static func _reaction_products(result_self: int, result_other: int) -> String:
	var self_name := _id_to_name(result_self)
	var other_name := _id_to_name(result_other)
	if result_self == result_other:
		return self_name
	return "%s + %s" % [self_name, other_name]


static var _name_cache: Dictionary = {}

static func _id_to_name(id: int) -> String:
	if _name_cache.is_empty():
		for m in get_all_materials():
			_name_cache[m["id"]] = m["name"]
	return _name_cache.get(id, "Unknown")


## Build a full tooltip for a material, combining its base tooltip, category,
## and any reactions from the centralized reaction table.
static func build_tooltip(mat_info: Dictionary) -> String:
	var parts: PackedStringArray = []
	# Category tag
	var cat: String = mat_info.get("category", "")
	if cat != "" and cat != "void":
		parts.append("[%s]" % cat.capitalize())
	# Base description
	var tip: String = mat_info.get("tooltip", "")
	if tip != "":
		parts.append(tip)
	# Reactions
	var reactions := get_reactions_for(mat_info["id"])
	if not reactions.is_empty():
		parts.append("Reactions:")
		for r in reactions:
			parts.append("  + %s → %s" % [r["with"], r["produces"]])
	return "\n".join(parts)


## Ordered list of material groups for display in the palette panel.
static func get_material_groups() -> Array[String]:
	return [
		"Core",
		"Universal Terrain",
		"Structural / Crafted",
		"Biological",
		"Depth 1: Biomechanical Jungle",
		"Depth 2: Crumbling Citadel",
		"Depth 3: Molten Core",
		"Depth 4: Clockwork Labyrinth",
		"Depth 5: Obsidian Core",
		"Magical — Offensive",
		"Magical — Utility",
		"Magical — Exotic",
		"Contact Damage",
		"Metals",
		"Arcane Crystals",
		"Plants",
	]


## Returns all registered material types as an array of Dictionaries:
## [{ id: int, name: String, category: String, group: String, tooltip: String }]
static func get_all_materials() -> Array[Dictionary]:
	return [
		# Core
		{ "id": AIR, "name": "Air", "category": "void", "group": "Core", "tooltip": "Empty space" },
		# Universal Terrain
		{ "id": STONE, "name": "Stone", "category": "solid", "group": "Universal Terrain", "tooltip": "Visual variants for grey, tan, blue-grey, dark" },
		{ "id": BEDROCK, "name": "Bedrock", "category": "solid", "group": "Universal Terrain", "tooltip": "Indestructible" },
		{ "id": WATER, "name": "Water", "category": "fluid", "group": "Universal Terrain", "tooltip": "Base liquid" },
		{ "id": DIRT, "name": "Dirt", "category": "solid", "group": "Universal Terrain", "tooltip": "Compactable terrain" },
		{ "id": MUD, "name": "Mud", "category": "powder", "group": "Universal Terrain", "tooltip": "Soft, falls slowly" },
		{ "id": LAVA, "name": "Lava", "category": "fluid", "group": "Universal Terrain", "tooltip": "Hot, damages entities on contact" },
		{ "id": ACID, "name": "Acid", "category": "fluid", "group": "Universal Terrain", "tooltip": "Dissolves solids over time" },
		{ "id": STEAM, "name": "Steam", "category": "gas", "group": "Universal Terrain", "tooltip": "Rises, dissipates. Result of water+heat" },
		{ "id": SAND, "name": "Sand", "category": "powder", "group": "Universal Terrain", "tooltip": "Falls, granular" },
		{ "id": GRAVEL, "name": "Gravel", "category": "powder", "group": "Universal Terrain", "tooltip": "Falls, heavier than sand, no horizontal spread" },
		{ "id": ICE, "name": "Ice", "category": "solid", "group": "Universal Terrain", "tooltip": "Melts near heat sources" },
		{ "id": GLASS, "name": "Glass", "category": "solid", "group": "Universal Terrain", "tooltip": "Transparent, fragile" },
		{ "id": COAL, "name": "Coal", "category": "powder", "group": "Universal Terrain", "tooltip": "Fuel source, burns" },
		{ "id": GUNPOWDER, "name": "Gunpowder", "category": "powder", "group": "Universal Terrain", "tooltip": "Explosive chain reaction when ignited" },
		{ "id": SNOW, "name": "Snow", "category": "powder", "group": "Universal Terrain", "tooltip": "Light, melts near heat" },
		{ "id": SALT, "name": "Salt", "category": "powder", "group": "Universal Terrain", "tooltip": "Preserves meat, purifies" },
		{ "id": ASH, "name": "Ash", "category": "powder", "group": "Universal Terrain", "tooltip": "Light, result of burning organic materials" },
		{ "id": SMOKE, "name": "Smoke", "category": "gas", "group": "Universal Terrain", "tooltip": "Rises, obscures vision. Result of burning" },
		{ "id": TOXIC_GAS, "name": "Toxic Gas", "category": "gas", "group": "Universal Terrain", "tooltip": "Damages player, heavier than Steam" },
		# Structural / Crafted
		{ "id": WOOD, "name": "Wood", "category": "solid", "group": "Structural / Crafted", "tooltip": "Burnable structural material" },
		{ "id": METAL, "name": "Metal", "category": "solid", "group": "Structural / Crafted", "tooltip": "Generic metal. Variants: iron, copper, brass, gold" },
		{ "id": BRICK, "name": "Brick", "category": "solid", "group": "Structural / Crafted", "tooltip": "Variants: red, grey, mossy" },
		{ "id": MARBLE, "name": "Marble", "category": "solid", "group": "Structural / Crafted", "tooltip": "Decorative, Citadel depth material" },
		{ "id": CRYSTAL, "name": "Crystal", "category": "solid", "group": "Structural / Crafted", "tooltip": "Transparent, variants for gem colors" },
		{ "id": OBSIDIAN, "name": "Obsidian", "category": "solid", "group": "Structural / Crafted", "tooltip": "Very hard" },
		{ "id": RUST, "name": "Rust", "category": "solid", "group": "Structural / Crafted", "tooltip": "Weak, corroded metal" },
		{ "id": CLAY, "name": "Clay", "category": "solid", "group": "Structural / Crafted", "tooltip": "Visual variants: red, grey, white" },
		# Biological
		{ "id": BONE, "name": "Bone", "category": "solid", "group": "Biological", "tooltip": "Structural remains, crumbles to Bone Dust" },
		{ "id": BONE_DUST, "name": "Bone Dust", "category": "powder", "group": "Biological", "tooltip": "Result of Bone breaking" },
		{ "id": BLOOD, "name": "Blood", "category": "fluid", "group": "Biological", "tooltip": "Consume: brief HP regen. Flows like water" },
		{ "id": MEAT, "name": "Meat", "category": "solid", "group": "Biological", "tooltip": "Consume: small HP. Decays over time" },
		{ "id": ROTTEN_MEAT, "name": "Rotten Meat", "category": "solid", "group": "Biological", "tooltip": "Consume: poison. Meat decays into this over time" },
		{ "id": COOKED_MEAT, "name": "Cooked Meat", "category": "solid", "group": "Biological", "tooltip": "Consume: larger HP restore" },
		{ "id": VOMIT, "name": "Vomit", "category": "fluid", "group": "Biological", "tooltip": "Result of consuming bad materials. Slippery" },
		# Depth 1: Biomechanical Jungle
		{ "id": BIOMASS, "name": "Biomass", "category": "solid", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Living organic wall/flesh. Variants: pink, green, purple" },
		{ "id": CHITIN, "name": "Chitin", "category": "solid", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Hard insect shell. Spider/fly drops" },
		{ "id": SAP, "name": "Sap", "category": "fluid", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Consume: slow regen. Thick, sticky, slows player" },
		{ "id": SPORE_GAS, "name": "Spore Gas", "category": "gas", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Consume: confusion/screen distort. Spawned by fungi" },
		{ "id": VINE, "name": "Vine", "category": "solid", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Grows downward from Biomass, burnable" },
		{ "id": MOSS, "name": "Moss", "category": "solid", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Spreads on Stone near Water, decorative" },
		{ "id": POLLEN, "name": "Pollen", "category": "powder", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Consume: sneeze (brief stun). Light, floats" },
		{ "id": NECTAR, "name": "Nectar", "category": "fluid", "group": "Depth 1: Biomechanical Jungle", "tooltip": "Consume: mana regen boost. Rare, found in flowers" },
		# Depth 2: Crumbling Citadel
		{ "id": ARCANE_ICHOR, "name": "Arcane Ichor", "category": "fluid", "group": "Depth 2: Crumbling Citadel", "tooltip": "Consume: reduced spell cost. Glowing blue-purple, construct blood" },
		{ "id": RUBBLE, "name": "Rubble", "category": "powder", "group": "Depth 2: Crumbling Citadel", "tooltip": "Falls. Result of destroyed Brick/Marble" },
		{ "id": DUST, "name": "Dust", "category": "gas", "group": "Depth 2: Crumbling Citadel", "tooltip": "Rises slowly, obscures vision" },
		{ "id": COBWEB, "name": "Cobweb", "category": "solid", "group": "Depth 2: Crumbling Citadel", "tooltip": "Weak, burnable, slows player" },
		{ "id": LICHEN, "name": "Lichen", "category": "solid", "group": "Depth 2: Crumbling Citadel", "tooltip": "Spreads on stone surfaces, decorative" },
		{ "id": ECTOPLASM, "name": "Ectoplasm", "category": "fluid", "group": "Depth 2: Crumbling Citadel", "tooltip": "Consume: brief phasing. Ghost/magical creature drops" },
		# Depth 3: Molten Core
		{ "id": MAGMA_ROCK, "name": "Magma Rock", "category": "solid", "group": "Depth 3: Molten Core", "tooltip": "Hot stone with glowing cracks" },
		{ "id": SLAG, "name": "Slag", "category": "powder", "group": "Depth 3: Molten Core", "tooltip": "Elemental flesh, crumbles. Metallic hue variants" },
		{ "id": MOLTEN_METAL, "name": "Molten Metal", "category": "fluid", "group": "Depth 3: Molten Core", "tooltip": "Cools to Metal, hotter than Lava" },
		{ "id": SULFUR, "name": "Sulfur", "category": "powder", "group": "Depth 3: Molten Core", "tooltip": "Flammable" },
		{ "id": EMBER, "name": "Ember", "category": "powder", "group": "Depth 3: Molten Core", "tooltip": "Short-lived, glows, ignites flammables, decays to Ash" },
		{ "id": MOLTEN_BLOOD, "name": "Molten Blood", "category": "fluid", "group": "Depth 3: Molten Core", "tooltip": "Consume: fire resist + damage boost. Lava elemental drops" },
		{ "id": ITE_MINERAL, "name": "Ite Mineral", "category": "solid", "group": "Depth 3: Molten Core", "tooltip": "Crystallized mineral from molten constructs" },
		# Depth 4: Clockwork Labyrinth
		{ "id": GEAR_BLOCK, "name": "Gear Block", "category": "solid", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Mechanical terrain. Variants: copper, brass, steel" },
		{ "id": CONDUIT, "name": "Conduit", "category": "solid", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Energy-transmitting material" },
		{ "id": OIL, "name": "Oil", "category": "fluid", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Consume: poison + slippery. Flammable" },
		{ "id": SCRAP_METAL, "name": "Scrap Metal", "category": "powder", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Drone/knight drops, falls like gravel" },
		{ "id": SPARK, "name": "Spark", "category": "gas", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Short-lived, ignites flammables" },
		{ "id": COOLANT, "name": "Coolant", "category": "fluid", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Consume: attack speed boost. Blue-green liquid" },
		{ "id": GEAR_FRAGMENT, "name": "Gear Fragment", "category": "powder", "group": "Depth 4: Clockwork Labyrinth", "tooltip": "Small mechanical bits, clockwork bone equivalent" },
		# Depth 5: Obsidian Core
		{ "id": VOID_STONE, "name": "Void Stone", "category": "solid", "group": "Depth 5: Obsidian Core", "tooltip": "Absorbs light, very hard" },
		{ "id": RIFT_CRYSTAL, "name": "Rift Crystal", "category": "solid", "group": "Depth 5: Obsidian Core", "tooltip": "Emits light, shifting color variants" },
		{ "id": SHADOW_FLUID, "name": "Shadow Fluid", "category": "fluid", "group": "Depth 5: Obsidian Core", "tooltip": "Consume: brief invisibility. Extinguishes light" },
		{ "id": NULL_GAS, "name": "Null Gas", "category": "gas", "group": "Depth 5: Obsidian Core", "tooltip": "Suppresses nearby fluid/gas simulation" },
		{ "id": CORRUPTED, "name": "Corrupted", "category": "solid", "group": "Depth 5: Obsidian Core", "tooltip": "Spreads slowly, converts adjacent Stone" },
		{ "id": VOID_FLESH, "name": "Void Flesh", "category": "solid", "group": "Depth 5: Obsidian Core", "tooltip": "Consume: random short teleport. Entity projection drops" },
		{ "id": VOID_BLOOD, "name": "Void Blood", "category": "fluid", "group": "Depth 5: Obsidian Core", "tooltip": "Consume: massive damage boost + HP drain. Black with purple shimmer" },
		# Magical — Offensive
		{ "id": BERSERKER_BILE, "name": "Berserker Bile", "category": "fluid", "group": "Magical — Offensive", "tooltip": "Stained entity deals more damage but can hurt itself. Red-black viscous" },
		{ "id": PHEROMONE, "name": "Pheromone", "category": "fluid", "group": "Magical — Offensive", "tooltip": "Stained entity's attacks deal 0 dmg; killing hits permanently charm target. Pink-gold" },
		{ "id": GILDING_SOLUTION, "name": "Gilding Solution", "category": "fluid", "group": "Magical — Offensive", "tooltip": "Stained enemies drop increased currency on death. Gold-tinted" },
		{ "id": VULNERABILITY_SAP, "name": "Vulnerability Sap", "category": "fluid", "group": "Magical — Offensive", "tooltip": "Stained entity takes increased damage from all sources. Yellow-green" },
		{ "id": THORN_EXTRACT, "name": "Thorn Extract", "category": "fluid", "group": "Magical — Offensive", "tooltip": "When stained entity takes damage, attacker takes damage back. Crimson" },
		{ "id": POISON, "name": "Poison", "category": "fluid", "group": "Magical — Offensive", "tooltip": "DoT to stained entities. Slower but longer than Acid. Dark green, only hurts living things" },
		# Magical — Utility
		{ "id": AMMO_ELIXIR, "name": "Ammo Elixir", "category": "fluid", "group": "Magical — Utility", "tooltip": "Reduces ammo consumed per shot while stained. Bright cyan, rare" },
		{ "id": QUICKSILVER, "name": "Quicksilver", "category": "fluid", "group": "Magical — Utility", "tooltip": "Increases fire rate while stained. Silvery, mercury-like" },
		{ "id": HASTE_OIL, "name": "Haste Oil", "category": "fluid", "group": "Magical — Utility", "tooltip": "Increases reload speed while stained. Light golden oil" },
		{ "id": SWIFTNESS_TONIC, "name": "Swiftness Tonic", "category": "fluid", "group": "Magical — Utility", "tooltip": "Movement speed increase while stained. Pale green" },
		{ "id": PHASE_FLUID, "name": "Phase Fluid", "category": "fluid", "group": "Magical — Utility", "tooltip": "Entity can pass through solids horizontally. Shimmering translucent, timer-based" },
		{ "id": AEGIS_FLUID, "name": "Aegis Fluid", "category": "fluid", "group": "Magical — Utility", "tooltip": "Stained entity is immune to all damage. Very rare, short duration. White-gold" },
		{ "id": VITAE, "name": "Vitae", "category": "fluid", "group": "Magical — Utility", "tooltip": "Heals stained entity over time. Warm amber with soft glow" },
		{ "id": CONFUSION_MIST, "name": "Confusion Mist", "category": "gas", "group": "Magical — Utility", "tooltip": "Stained entity moves in random directions. Swirling iridescent gas" },
		# Magical — Exotic
		{ "id": TEMPORAL_FLUID, "name": "Temporal Fluid", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Creates afterimages; on damage, reverts to afterimage position. Deep blue with gold particles" },
		{ "id": POLYMORPHINE, "name": "Polymorphine", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Transforms entity into random enemy from current depth. Purple-green swirling" },
		{ "id": CHAOTIC_POLYMORPHINE, "name": "Chaotic Polymorphine", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Transforms entity into random enemy from ANY depth. Deep purple with rainbow highlights" },
		{ "id": NANITE_SWARM, "name": "Nanite Swarm", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Eats Rust/Rotten Meat/Bone/Rubble, grows in volume. Dark grey metallic, self-limiting" },
		{ "id": WARP_FLUID, "name": "Warp Fluid", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Teleports stained entity to random nearby location periodically. Purple-blue shifting" },
		{ "id": GENESIS_FLUID, "name": "Genesis Fluid", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Spawns small hostile creatures over time, then dissipates. Bioluminescent green" },
		{ "id": ETHANOL, "name": "Ethanol", "category": "fluid", "group": "Magical — Exotic", "tooltip": "Mildly intoxicating: blurs vision, randomizes aim, small damage resist. Amber" },
		# Contact Damage
		{ "id": CURSED_SLUDGE, "name": "Cursed Sludge", "category": "fluid", "group": "Contact Damage", "tooltip": "Dark/arcane contact damage, stains persistently. Black-purple ooze" },
		{ "id": MOLTEN_SLAG, "name": "Molten Slag", "category": "fluid", "group": "Contact Damage", "tooltip": "Fire contact damage, ignites flammables. Orange-white, heavier/slower than Lava" },
		{ "id": BLIGHT, "name": "Blight", "category": "fluid", "group": "Contact Damage", "tooltip": "Poison contact damage, spreads through organic materials. Black-green, self-propagating" },
		{ "id": RAZOR_DUST, "name": "Razor Dust", "category": "powder", "group": "Contact Damage", "tooltip": "Damages entities walking through it. Glittering metallic silver particles" },
		# Metals
		{ "id": IRON, "name": "Iron", "category": "solid", "group": "Metals", "tooltip": "Grey, common. Default structural metal. Forge: no modifier" },
		{ "id": COPPER, "name": "Copper", "category": "solid", "group": "Metals", "tooltip": "Orange-brown. Forge: Electric Shot (chains through Water). Jungle/Clockwork" },
		{ "id": BRASS, "name": "Brass", "category": "solid", "group": "Metals", "tooltip": "Golden-yellow. Forge: Ricochet. Clockwork primary structural metal" },
		{ "id": SILVER, "name": "Silver", "category": "solid", "group": "Metals", "tooltip": "Bright white-grey, rare. Forge: Blessed (bonus vs magical/corrupted)" },
		{ "id": GOLD, "name": "Gold", "category": "solid", "group": "Metals", "tooltip": "Bright gold, rare in terrain. Forge: Gilded (more currency drops)" },
		{ "id": DARK_STEEL, "name": "Dark Steel", "category": "solid", "group": "Metals", "tooltip": "Near-black. Forge: Piercing (ignores damage resist). Obsidian Core" },
		{ "id": ARCANE_ALLOY, "name": "Arcane Alloy", "category": "solid", "group": "Metals", "tooltip": "Blue-tinged with faint glow. Forge: Amplified (chained spell bonus). Citadel" },
		{ "id": MOLTEN_GLASS, "name": "Molten Glass", "category": "fluid", "group": "Metals", "tooltip": "Transparent orange. Cools to Glass" },
		# Arcane Crystals
		{ "id": CRYSTAL_SHARD, "name": "Crystal Shard", "category": "solid", "group": "Arcane Crystals", "tooltip": "Currency (1). Small, dull white-blue. Most common drop" },
		{ "id": CRYSTAL_AMBER, "name": "Crystal Amber", "category": "solid", "group": "Arcane Crystals", "tooltip": "Currency (5). Warm orange glow. Uncommon drop" },
		{ "id": CRYSTAL_EMERALD, "name": "Crystal Emerald", "category": "solid", "group": "Arcane Crystals", "tooltip": "Currency (25). Green with bright glow. Rare, hidden caches" },
		{ "id": CRYSTAL_RUBY, "name": "Crystal Ruby", "category": "solid", "group": "Arcane Crystals", "tooltip": "Currency (100). Deep red, pulsing glow. Very rare, mini-boss drops" },
		{ "id": CRYSTAL_VOID, "name": "Crystal Void", "category": "solid", "group": "Arcane Crystals", "tooltip": "Currency (500). Black crystal with purple core. Extremely rare, Obsidian Core boss drops" },
		# Plants
		{ "id": GRASS, "name": "Grass", "category": "solid", "group": "Plants", "tooltip": "Decorative. Grows on Dirt near light. Biome visual variants" },
		{ "id": MUSHROOM, "name": "Mushroom", "category": "solid", "group": "Plants", "tooltip": "Consume: random minor effect (heal/speed/confusion). Grows in dark on Dirt/Moss" },
		{ "id": CACTUS, "name": "Cactus", "category": "solid", "group": "Plants", "tooltip": "Consume: berserker effect (weaker). Grows on Sand. Contact damage (thorns)" },
		{ "id": ALOE, "name": "Aloe", "category": "solid", "group": "Plants", "tooltip": "Consume: healing over time (weaker Vitae). Grows on Sand near Water" },
		{ "id": GLOWCAP, "name": "Glowcap", "category": "solid", "group": "Plants", "tooltip": "Consume: brief night vision. Bioluminescent, emits light. Jungle/Citadel" },
		{ "id": MANAFRUIT, "name": "Manafruit", "category": "solid", "group": "Plants", "tooltip": "Consume: mana/ammo regen (weaker Ammo Elixir). Grows on Vine, rare jungle fruit" },
		{ "id": DRAGON_PEPPER, "name": "Dragon Pepper", "category": "solid", "group": "Plants", "tooltip": "Consume: polymorph into fire creature (predictable). Grows near Lava. Rare Molten Core plant" },
		{ "id": STARFRUIT, "name": "Starfruit", "category": "solid", "group": "Plants", "tooltip": "Consume: random magical effect at reduced potency. Grows on Rift Crystal. Very rare, Obsidian Core" },
		{ "id": THORNVINE, "name": "Thornvine", "category": "solid", "group": "Plants", "tooltip": "Consume: thorn effect (weaker). Contact damage. Grows on Brick/Stone, spreads. Citadel" },
		{ "id": HEALROOT, "name": "Healroot", "category": "solid", "group": "Plants", "tooltip": "Consume: moderate HP restore. Grows on Dirt near Water. Common healing plant" },
	]


static func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floorf(world_pos.x * INV_VOXEL_SCALE)),
		int(floorf(world_pos.y * INV_VOXEL_SCALE)),
		int(floorf(world_pos.z * INV_VOXEL_SCALE))
	)


static func voxel_to_world(voxel_pos: Vector3i) -> Vector3:
	return Vector3(voxel_pos) * VOXEL_SCALE
