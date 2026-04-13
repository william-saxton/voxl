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
		{ "id": AIR, "name": "Air", "category": "void", "tooltip": "Empty space" },
		# Universal Terrain
		{ "id": STONE, "name": "Stone", "category": "solid", "tooltip": "Visual variants for grey, tan, blue-grey, dark" },
		{ "id": BEDROCK, "name": "Bedrock", "category": "solid", "tooltip": "Indestructible" },
		{ "id": WATER, "name": "Water", "category": "fluid", "tooltip": "Base liquid. +LAVA=OBSIDIAN+STEAM" },
		{ "id": DIRT, "name": "Dirt", "category": "solid", "tooltip": "+WATER becomes MUD" },
		{ "id": MUD, "name": "Mud", "category": "powder", "tooltip": "Soft, falls slowly" },
		{ "id": LAVA, "name": "Lava", "category": "fluid", "tooltip": "Hot, damages. +WATER=OBSIDIAN+STEAM" },
		{ "id": ACID, "name": "Acid", "category": "fluid", "tooltip": "Dissolves solids over time. +METAL=RUST" },
		{ "id": STEAM, "name": "Steam", "category": "gas", "tooltip": "Rises, dissipates. Result of water+heat" },
		{ "id": SAND, "name": "Sand", "category": "powder", "tooltip": "Falls. +LAVA becomes GLASS" },
		{ "id": GRAVEL, "name": "Gravel", "category": "powder", "tooltip": "Falls, heavier than sand, no horizontal spread" },
		{ "id": ICE, "name": "Ice", "category": "solid", "tooltip": "Melts to WATER near heat. SALT melts it" },
		{ "id": GLASS, "name": "Glass", "category": "solid", "tooltip": "Transparent, fragile" },
		{ "id": COAL, "name": "Coal", "category": "powder", "tooltip": "Burns to ASH+SMOKE, fuel source" },
		{ "id": GUNPOWDER, "name": "Gunpowder", "category": "powder", "tooltip": "Explosive chain reaction when ignited" },
		{ "id": SNOW, "name": "Snow", "category": "powder", "tooltip": "Light, melts to WATER near heat" },
		{ "id": SALT, "name": "Salt", "category": "powder", "tooltip": "Melts ICE on contact, preserves meat" },
		{ "id": ASH, "name": "Ash", "category": "powder", "tooltip": "Light, result of burning organic materials" },
		{ "id": SMOKE, "name": "Smoke", "category": "gas", "tooltip": "Rises, obscures vision. Result of burning" },
		{ "id": TOXIC_GAS, "name": "Toxic Gas", "category": "gas", "tooltip": "Damages player, heavier than STEAM" },
		# Structural / Crafted
		{ "id": WOOD, "name": "Wood", "category": "solid", "tooltip": "Burns to ASH+SMOKE" },
		{ "id": METAL, "name": "Metal", "category": "solid", "tooltip": "Variants: iron, copper, brass, gold. +ACID=RUST" },
		{ "id": BRICK, "name": "Brick", "category": "solid", "tooltip": "Variants: red, grey, mossy" },
		{ "id": MARBLE, "name": "Marble", "category": "solid", "tooltip": "Decorative, Citadel depth material" },
		{ "id": CRYSTAL, "name": "Crystal", "category": "solid", "tooltip": "Transparent, variants for gem colors" },
		{ "id": OBSIDIAN, "name": "Obsidian", "category": "solid", "tooltip": "Very hard. LAVA+WATER result" },
		{ "id": RUST, "name": "Rust", "category": "solid", "tooltip": "Weak. METAL+ACID result" },
		{ "id": CLAY, "name": "Clay", "category": "solid", "tooltip": "Visual variants: red, grey, white" },
		# Biological Universal
		{ "id": BONE, "name": "Bone", "category": "solid", "tooltip": "Structural remains, crumbles to BONE_DUST" },
		{ "id": BONE_DUST, "name": "Bone Dust", "category": "powder", "tooltip": "Result of BONE breaking" },
		{ "id": BLOOD, "name": "Blood", "category": "fluid", "tooltip": "Consume: brief HP regen. Flows like water" },
		{ "id": MEAT, "name": "Meat", "category": "solid", "tooltip": "Consume: small HP. Decays to ROTTEN_MEAT, +heat=COOKED_MEAT" },
		{ "id": ROTTEN_MEAT, "name": "Rotten Meat", "category": "solid", "tooltip": "Consume: poison. MEAT decays into this over time" },
		{ "id": COOKED_MEAT, "name": "Cooked Meat", "category": "solid", "tooltip": "Consume: larger HP restore. MEAT+heat result" },
		{ "id": VOMIT, "name": "Vomit", "category": "fluid", "tooltip": "Result of consuming bad materials. Slippery" },
		# Depth 1: Biomechanical Jungle
		{ "id": BIOMASS, "name": "Biomass", "category": "solid", "tooltip": "Jungle: living organic wall/flesh. Variants: pink, green, purple" },
		{ "id": CHITIN, "name": "Chitin", "category": "solid", "tooltip": "Jungle: hard insect shell. Spider/fly drops" },
		{ "id": SAP, "name": "Sap", "category": "fluid", "tooltip": "Jungle: consume for slow regen. Thick, sticky, slows player" },
		{ "id": SPORE_GAS, "name": "Spore Gas", "category": "gas", "tooltip": "Jungle: consume causes confusion/screen distort. Spawned by fungi" },
		{ "id": VINE, "name": "Vine", "category": "solid", "tooltip": "Jungle: grows downward from BIOMASS, burnable" },
		{ "id": MOSS, "name": "Moss", "category": "solid", "tooltip": "Jungle: spreads on STONE near WATER, decorative" },
		{ "id": POLLEN, "name": "Pollen", "category": "powder", "tooltip": "Jungle: consume causes sneeze (brief stun). Light, floats" },
		{ "id": NECTAR, "name": "Nectar", "category": "fluid", "tooltip": "Jungle: consume for mana regen boost. Rare, found in flowers" },
		# Depth 2: Crumbling Citadel
		{ "id": ARCANE_ICHOR, "name": "Arcane Ichor", "category": "fluid", "tooltip": "Citadel: consume for reduced spell cost. Glowing blue-purple, construct blood" },
		{ "id": RUBBLE, "name": "Rubble", "category": "powder", "tooltip": "Citadel: falls. Result of destroyed BRICK/MARBLE" },
		{ "id": DUST, "name": "Dust", "category": "gas", "tooltip": "Citadel: rises slowly, obscures vision" },
		{ "id": COBWEB, "name": "Cobweb", "category": "solid", "tooltip": "Citadel: weak, burnable, slows player" },
		{ "id": LICHEN, "name": "Lichen", "category": "solid", "tooltip": "Citadel: spreads on stone surfaces, decorative" },
		{ "id": ECTOPLASM, "name": "Ectoplasm", "category": "fluid", "tooltip": "Citadel: consume for brief phasing. Ghost/magical creature drops" },
		# Depth 3: Molten Core
		{ "id": MAGMA_ROCK, "name": "Magma Rock", "category": "solid", "tooltip": "Molten Core: hot stone with glowing cracks" },
		{ "id": SLAG, "name": "Slag", "category": "powder", "tooltip": "Molten Core: elemental flesh, crumbles. Metallic hue variants" },
		{ "id": MOLTEN_METAL, "name": "Molten Metal", "category": "fluid", "tooltip": "Molten Core: cools to METAL, hotter than lava" },
		{ "id": SULFUR, "name": "Sulfur", "category": "powder", "tooltip": "Molten Core: flammable, +heat becomes TOXIC_GAS" },
		{ "id": EMBER, "name": "Ember", "category": "powder", "tooltip": "Molten Core: short-lived, glows, ignites flammables, decays to ASH" },
		{ "id": MOLTEN_BLOOD, "name": "Molten Blood", "category": "fluid", "tooltip": "Molten Core: consume for fire resist + damage boost. Lava elemental drops" },
		{ "id": ITE_MINERAL, "name": "Ite Mineral", "category": "solid", "tooltip": "Molten Core: crystallized mineral from molten constructs" },
		# Depth 4: Clockwork Labyrinth
		{ "id": GEAR_BLOCK, "name": "Gear Block", "category": "solid", "tooltip": "Clockwork: mechanical terrain. Variants: copper, brass, steel" },
		{ "id": CONDUIT, "name": "Conduit", "category": "solid", "tooltip": "Clockwork: energy-transmitting material" },
		{ "id": OIL, "name": "Oil", "category": "fluid", "tooltip": "Clockwork: consume causes poison + slippery. Flammable, burns to SMOKE" },
		{ "id": SCRAP_METAL, "name": "Scrap Metal", "category": "powder", "tooltip": "Clockwork: drone/knight drops, falls like gravel" },
		{ "id": SPARK, "name": "Spark", "category": "gas", "tooltip": "Clockwork: short-lived, ignites OIL/GUNPOWDER/WOOD/SULFUR" },
		{ "id": COOLANT, "name": "Coolant", "category": "fluid", "tooltip": "Clockwork: consume for attack speed boost. Blue-green liquid" },
		{ "id": GEAR_FRAGMENT, "name": "Gear Fragment", "category": "powder", "tooltip": "Clockwork: small mechanical bits, clockwork bone equivalent" },
		# Depth 5: Obsidian Core
		{ "id": VOID_STONE, "name": "Void Stone", "category": "solid", "tooltip": "Obsidian Core: absorbs light, very hard" },
		{ "id": RIFT_CRYSTAL, "name": "Rift Crystal", "category": "solid", "tooltip": "Obsidian Core: emits light, shifting color variants" },
		{ "id": SHADOW_FLUID, "name": "Shadow Fluid", "category": "fluid", "tooltip": "Obsidian Core: consume for brief invisibility. Extinguishes light" },
		{ "id": NULL_GAS, "name": "Null Gas", "category": "gas", "tooltip": "Obsidian Core: suppresses nearby fluid/gas simulation" },
		{ "id": CORRUPTED, "name": "Corrupted", "category": "solid", "tooltip": "Obsidian Core: spreads slowly, converts adjacent STONE" },
		{ "id": VOID_FLESH, "name": "Void Flesh", "category": "solid", "tooltip": "Obsidian Core: consume for random short teleport. Entity projection drops" },
		{ "id": VOID_BLOOD, "name": "Void Blood", "category": "fluid", "tooltip": "Obsidian Core: consume for massive damage boost + HP drain. Black with purple shimmer" },
		# Magical — Offensive
		{ "id": BERSERKER_BILE, "name": "Berserker Bile", "category": "fluid", "tooltip": "Stained entity deals more damage but can hurt itself. Red-black viscous" },
		{ "id": PHEROMONE, "name": "Pheromone", "category": "fluid", "tooltip": "Stained entity's attacks deal 0 dmg; killing hits permanently charm target. Pink-gold" },
		{ "id": GILDING_SOLUTION, "name": "Gilding Solution", "category": "fluid", "tooltip": "Stained enemies drop increased currency on death. Gold-tinted" },
		{ "id": VULNERABILITY_SAP, "name": "Vulnerability Sap", "category": "fluid", "tooltip": "Stained entity takes increased damage from all sources. Yellow-green" },
		{ "id": THORN_EXTRACT, "name": "Thorn Extract", "category": "fluid", "tooltip": "When stained entity takes damage, attacker takes damage back. Crimson" },
		{ "id": POISON, "name": "Poison", "category": "fluid", "tooltip": "DoT to stained entities. Slower but longer than ACID. Dark green, only hurts living things" },
		# Magical — Utility
		{ "id": AMMO_ELIXIR, "name": "Ammo Elixir", "category": "fluid", "tooltip": "Reduces ammo consumed per shot while stained. Bright cyan, rare" },
		{ "id": QUICKSILVER, "name": "Quicksilver", "category": "fluid", "tooltip": "Increases fire rate while stained. Silvery, mercury-like" },
		{ "id": HASTE_OIL, "name": "Haste Oil", "category": "fluid", "tooltip": "Increases reload speed while stained. Light golden oil" },
		{ "id": SWIFTNESS_TONIC, "name": "Swiftness Tonic", "category": "fluid", "tooltip": "Movement speed increase while stained. Pale green" },
		{ "id": PHASE_FLUID, "name": "Phase Fluid", "category": "fluid", "tooltip": "Entity can pass through solids horizontally. Shimmering translucent, timer-based" },
		{ "id": AEGIS_FLUID, "name": "Aegis Fluid", "category": "fluid", "tooltip": "Stained entity is immune to all damage. Very rare, short duration. White-gold" },
		{ "id": VITAE, "name": "Vitae", "category": "fluid", "tooltip": "Heals stained entity over time. Warm amber with soft glow" },
		{ "id": CONFUSION_MIST, "name": "Confusion Mist", "category": "gas", "tooltip": "Stained entity moves in random directions. Swirling iridescent gas" },
		# Magical — Exotic
		{ "id": TEMPORAL_FLUID, "name": "Temporal Fluid", "category": "fluid", "tooltip": "Creates afterimages; on damage, reverts to afterimage position. Deep blue with gold particles" },
		{ "id": POLYMORPHINE, "name": "Polymorphine", "category": "fluid", "tooltip": "Transforms entity into random enemy from current depth. Purple-green swirling" },
		{ "id": CHAOTIC_POLYMORPHINE, "name": "Chaotic Polymorphine", "category": "fluid", "tooltip": "Transforms entity into random enemy from ANY depth. Deep purple with rainbow highlights" },
		{ "id": NANITE_SWARM, "name": "Nanite Swarm", "category": "fluid", "tooltip": "Eats RUST/ROTTEN_MEAT/BONE/RUBBLE, grows in volume. Dark grey metallic, self-limiting" },
		{ "id": WARP_FLUID, "name": "Warp Fluid", "category": "fluid", "tooltip": "Teleports stained entity to random nearby location periodically. Purple-blue shifting" },
		{ "id": GENESIS_FLUID, "name": "Genesis Fluid", "category": "fluid", "tooltip": "Spawns small hostile creatures over time, then dissipates. Bioluminescent green" },
		{ "id": ETHANOL, "name": "Ethanol", "category": "fluid", "tooltip": "Mildly intoxicating: blurs vision, randomizes aim, small damage resist. Amber" },
		# Contact Damage
		{ "id": CURSED_SLUDGE, "name": "Cursed Sludge", "category": "fluid", "tooltip": "Dark/arcane contact damage, stains persistently. Black-purple ooze" },
		{ "id": MOLTEN_SLAG, "name": "Molten Slag", "category": "fluid", "tooltip": "Fire contact damage, ignites flammables. Orange-white, heavier/slower than LAVA" },
		{ "id": BLIGHT, "name": "Blight", "category": "fluid", "tooltip": "Poison contact damage, spreads through organic materials. Black-green, self-propagating" },
		{ "id": RAZOR_DUST, "name": "Razor Dust", "category": "powder", "tooltip": "Damages entities walking through it. Glittering metallic silver particles" },
		# Metals
		{ "id": IRON, "name": "Iron", "category": "solid", "tooltip": "Grey, common. Default structural metal. Forge: no modifier" },
		{ "id": COPPER, "name": "Copper", "category": "solid", "tooltip": "Orange-brown. Forge: Electric Shot (chains through WATER). Jungle/Clockwork" },
		{ "id": BRASS, "name": "Brass", "category": "solid", "tooltip": "Golden-yellow. Forge: Ricochet. Clockwork primary structural metal" },
		{ "id": SILVER, "name": "Silver", "category": "solid", "tooltip": "Bright white-grey, rare. Forge: Blessed (bonus vs magical/corrupted)" },
		{ "id": GOLD, "name": "Gold", "category": "solid", "tooltip": "Bright gold, rare in terrain. Forge: Gilded (more currency drops)" },
		{ "id": DARK_STEEL, "name": "Dark Steel", "category": "solid", "tooltip": "Near-black. Forge: Piercing (ignores damage resist). Obsidian Core" },
		{ "id": ARCANE_ALLOY, "name": "Arcane Alloy", "category": "solid", "tooltip": "Blue-tinged with faint glow. Forge: Amplified (chained spell bonus). Citadel" },
		{ "id": MOLTEN_GLASS, "name": "Molten Glass", "category": "fluid", "tooltip": "Transparent orange. Cools to GLASS. Created when GLASS/SAND meets extreme heat" },
		# Arcane Crystals — Currency
		{ "id": CRYSTAL_SHARD, "name": "Crystal Shard", "category": "solid", "tooltip": "Currency (1). Small, dull white-blue. Most common drop" },
		{ "id": CRYSTAL_AMBER, "name": "Crystal Amber", "category": "solid", "tooltip": "Currency (5). Warm orange glow. Uncommon drop" },
		{ "id": CRYSTAL_EMERALD, "name": "Crystal Emerald", "category": "solid", "tooltip": "Currency (25). Green with bright glow. Rare, hidden caches" },
		{ "id": CRYSTAL_RUBY, "name": "Crystal Ruby", "category": "solid", "tooltip": "Currency (100). Deep red, pulsing glow. Very rare, mini-boss drops" },
		{ "id": CRYSTAL_VOID, "name": "Crystal Void", "category": "solid", "tooltip": "Currency (500). Black crystal with purple core. Extremely rare, Obsidian Core boss drops" },
		# Plants
		{ "id": GRASS, "name": "Grass", "category": "solid", "tooltip": "Decorative. Grows on DIRT near light. Biome visual variants" },
		{ "id": MUSHROOM, "name": "Mushroom", "category": "solid", "tooltip": "Consume: random minor effect (heal/speed/confusion). Grows in dark on DIRT/MOSS" },
		{ "id": CACTUS, "name": "Cactus", "category": "solid", "tooltip": "Consume: berserker effect (weaker). Grows on SAND. Contact damage (thorns)" },
		{ "id": ALOE, "name": "Aloe", "category": "solid", "tooltip": "Consume: healing over time (weaker VITAE). Grows on SAND near WATER" },
		{ "id": GLOWCAP, "name": "Glowcap", "category": "solid", "tooltip": "Consume: brief night vision. Bioluminescent, emits light. Jungle/Citadel" },
		{ "id": MANAFRUIT, "name": "Manafruit", "category": "solid", "tooltip": "Consume: mana/ammo regen (weaker AMMO_ELIXIR). Grows on VINE, rare jungle fruit" },
		{ "id": DRAGON_PEPPER, "name": "Dragon Pepper", "category": "solid", "tooltip": "Consume: polymorph into fire creature (predictable). Grows near LAVA. Rare Molten Core plant" },
		{ "id": STARFRUIT, "name": "Starfruit", "category": "solid", "tooltip": "Consume: random magical effect at reduced potency. Grows on RIFT_CRYSTAL. Very rare, Obsidian Core" },
		{ "id": THORNVINE, "name": "Thornvine", "category": "solid", "tooltip": "Consume: thorn effect (weaker). Contact damage. Grows on BRICK/STONE, spreads. Citadel" },
		{ "id": HEALROOT, "name": "Healroot", "category": "solid", "tooltip": "Consume: moderate HP restore. Grows on DIRT near WATER. Common healing plant" },
	]


static func world_to_voxel(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floorf(world_pos.x * INV_VOXEL_SCALE)),
		int(floorf(world_pos.y * INV_VOXEL_SCALE)),
		int(floorf(world_pos.z * INV_VOXEL_SCALE))
	)


static func voxel_to_world(voxel_pos: Vector3i) -> Vector3:
	return Vector3(voxel_pos) * VOXEL_SCALE
