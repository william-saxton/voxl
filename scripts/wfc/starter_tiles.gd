class_name StarterTiles
extends RefCounted

## Generates basic programmatic WFCTileDef resources for testing.
## All tiles use base material IDs (uint16 low byte only, visual variant 0).


## Flat ground: bedrock y=0, stone y=1-14, dirt y=15, air above.
## All edges: OPEN_GROUND
static func ground_flat(biome: String = "") -> WFCTileDef:
	var tile := WFCTileDef.new()
	tile.tile_name = "ground_flat"
	tile.biome = biome
	tile.edge_north = WFCTileDef.EdgeType.OPEN_GROUND
	tile.edge_south = WFCTileDef.EdgeType.OPEN_GROUND
	tile.edge_east = WFCTileDef.EdgeType.OPEN_GROUND
	tile.edge_west = WFCTileDef.EdgeType.OPEN_GROUND
	tile.weight = 3.0  # Higher weight — most common tile
	tile.surface_material = MaterialRegistry.DIRT
	tile._ensure_data()

	for lz in WFCTileDef.TILE_Z:
		for lx in WFCTileDef.TILE_X:
			tile.set_voxel(lx, 0, lz, MaterialRegistry.BEDROCK)
			for ly in range(1, 15):
				tile.set_voxel(lx, ly, lz, MaterialRegistry.STONE)
			tile.set_voxel(lx, 15, lz, MaterialRegistry.DIRT)

	return tile


## Ground with walls on all 4 sides (y=16..23).
## All edges: SOLID_WALL
static func ground_with_wall(biome: String = "") -> WFCTileDef:
	var tile := ground_flat(biome)
	tile.tile_name = "ground_with_wall"
	tile.edge_north = WFCTileDef.EdgeType.SOLID_WALL
	tile.edge_south = WFCTileDef.EdgeType.SOLID_WALL
	tile.edge_east = WFCTileDef.EdgeType.SOLID_WALL
	tile.edge_west = WFCTileDef.EdgeType.SOLID_WALL
	tile.weight = 0.5

	for ly in range(16, 24):
		for lx in WFCTileDef.TILE_X:
			tile.set_voxel(lx, ly, 0, MaterialRegistry.STONE)
			tile.set_voxel(lx, ly, WFCTileDef.TILE_Z - 1, MaterialRegistry.STONE)
		for lz in WFCTileDef.TILE_Z:
			tile.set_voxel(0, ly, lz, MaterialRegistry.STONE)
			tile.set_voxel(WFCTileDef.TILE_X - 1, ly, lz, MaterialRegistry.STONE)

	return tile


## Ground with walls on east/west, open corridor on north/south.
## North/South: CORRIDOR, East/West: SOLID_WALL
static func ground_with_corridor_ns(biome: String = "") -> WFCTileDef:
	var tile := ground_flat(biome)
	tile.tile_name = "ground_with_corridor_ns"
	tile.edge_north = WFCTileDef.EdgeType.CORRIDOR
	tile.edge_south = WFCTileDef.EdgeType.CORRIDOR
	tile.edge_east = WFCTileDef.EdgeType.SOLID_WALL
	tile.edge_west = WFCTileDef.EdgeType.SOLID_WALL
	tile.weight = 1.0

	var corridor_start := WFCTileDef.TILE_X / 2 - 8
	var corridor_end := WFCTileDef.TILE_X / 2 + 8

	for ly in range(16, 24):
		for lz in WFCTileDef.TILE_Z:
			# East wall
			tile.set_voxel(WFCTileDef.TILE_X - 1, ly, lz, MaterialRegistry.STONE)
			# West wall
			tile.set_voxel(0, ly, lz, MaterialRegistry.STONE)
		# North/south walls with corridor opening
		for lx in WFCTileDef.TILE_X:
			if lx < corridor_start or lx >= corridor_end:
				tile.set_voxel(lx, ly, 0, MaterialRegistry.STONE)
				tile.set_voxel(lx, ly, WFCTileDef.TILE_Z - 1, MaterialRegistry.STONE)

	return tile


## Ground with walls on north/south, open corridor on east/west.
## North/South: SOLID_WALL, East/West: CORRIDOR
static func ground_with_corridor_ew(biome: String = "") -> WFCTileDef:
	var tile := ground_flat(biome)
	tile.tile_name = "ground_with_corridor_ew"
	tile.edge_north = WFCTileDef.EdgeType.SOLID_WALL
	tile.edge_south = WFCTileDef.EdgeType.SOLID_WALL
	tile.edge_east = WFCTileDef.EdgeType.CORRIDOR
	tile.edge_west = WFCTileDef.EdgeType.CORRIDOR
	tile.weight = 1.0

	var corridor_start := WFCTileDef.TILE_Z / 2 - 8
	var corridor_end := WFCTileDef.TILE_Z / 2 + 8

	for ly in range(16, 24):
		for lx in WFCTileDef.TILE_X:
			# North wall
			tile.set_voxel(lx, ly, 0, MaterialRegistry.STONE)
			# South wall
			tile.set_voxel(lx, ly, WFCTileDef.TILE_Z - 1, MaterialRegistry.STONE)
		# East/west walls with corridor opening
		for lz in WFCTileDef.TILE_Z:
			if lz < corridor_start or lz >= corridor_end:
				tile.set_voxel(0, ly, lz, MaterialRegistry.STONE)
				tile.set_voxel(WFCTileDef.TILE_X - 1, ly, lz, MaterialRegistry.STONE)

	return tile


## Ground with a shallow pool carved out at y=13-15, filled with water.
## All edges: OPEN_GROUND
static func ground_with_pool(biome: String = "") -> WFCTileDef:
	var tile := ground_flat(biome)
	tile.tile_name = "ground_with_pool"
	tile.weight = 0.5
	tile.surface_material = MaterialRegistry.WATER

	# Carve pool in center (leave 16-voxel border)
	var margin := 16
	for lz in range(margin, WFCTileDef.TILE_Z - margin):
		for lx in range(margin, WFCTileDef.TILE_X - margin):
			tile.set_voxel(lx, 13, lz, MaterialRegistry.WATER)
			tile.set_voxel(lx, 14, lz, MaterialRegistry.WATER)
			tile.set_voxel(lx, 15, lz, MaterialRegistry.AIR)

	return tile


## Generate all starter tiles and return them as an array.
static func generate_all(biome: String = "") -> Array[WFCTileDef]:
	return [
		ground_flat(biome),
		ground_with_wall(biome),
		ground_with_corridor_ns(biome),
		ground_with_corridor_ew(biome),
		ground_with_pool(biome),
	]
