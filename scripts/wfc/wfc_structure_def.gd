class_name WFCStructureDef
extends Resource

@export var structure_name: String = ""
## Size in tiles (e.g., Vector2i(3, 2) = 3 tiles wide, 2 tiles deep)
@export var size: Vector2i = Vector2i(1, 1)
## Full voxel data for the entire structure — uint16 LE
## Size = (size.x * 128) * 112 * (size.y * 128) * 2 bytes
@export var full_voxel_data: PackedByteArray = []
## External edges — Dictionary of "x,z,side" → EdgeType
## e.g., "0,0,west" → EdgeType.SOLID_WALL
@export var external_edges: Dictionary = {}
@export var tags: PackedStringArray = []
@export var biome: String = ""
## Metadata points using world-relative coords within the structure
@export var metadata_points: Dictionary = {}


## Split the structure into individual WFCTileDef sub-tiles.
## Internal edges get STRUCTURE_INTERNAL, external edges from external_edges dict.
func split_into_tiles() -> Array[WFCTileDef]:
	var tiles: Array[WFCTileDef] = []
	var tw := size.x
	var th := size.y
	var full_w := tw * WFCTileDef.TILE_X
	var full_h := WFCTileDef.TILE_Y
	var full_d := th * WFCTileDef.TILE_Z

	for tz in th:
		for tx in tw:
			var tile := WFCTileDef.new()
			tile.tile_name = "%s_%d_%d" % [structure_name, tx, tz]
			tile.biome = biome

			# Determine edges
			tile.edge_west = _get_external_edge(tx, tz, "west") if tx == 0 else WFCTileDef.EdgeType.STRUCTURE_INTERNAL
			tile.edge_east = _get_external_edge(tx, tz, "east") if tx == tw - 1 else WFCTileDef.EdgeType.STRUCTURE_INTERNAL
			tile.edge_north = _get_external_edge(tx, tz, "north") if tz == 0 else WFCTileDef.EdgeType.STRUCTURE_INTERNAL
			tile.edge_south = _get_external_edge(tx, tz, "south") if tz == th - 1 else WFCTileDef.EdgeType.STRUCTURE_INTERNAL

			# Copy voxel sub-region
			tile._ensure_data()
			for lz in WFCTileDef.TILE_Z:
				for ly in WFCTileDef.TILE_Y:
					for lx in WFCTileDef.TILE_X:
						var gx := tx * WFCTileDef.TILE_X + lx
						var gz := tz * WFCTileDef.TILE_Z + lz
						var src_idx := (gx + ly * full_w + gz * full_w * full_h) * 2
						var val := 0
						if src_idx + 1 < full_voxel_data.size():
							val = full_voxel_data.decode_u16(src_idx)
						tile.set_voxel(lx, ly, lz, val)

			# Copy relevant metadata points
			var offset_x := tx * WFCTileDef.TILE_X
			var offset_z := tz * WFCTileDef.TILE_Z
			for point_key in metadata_points:
				var pt: Vector3i = point_key
				if pt.x >= offset_x and pt.x < offset_x + WFCTileDef.TILE_X \
						and pt.z >= offset_z and pt.z < offset_z + WFCTileDef.TILE_Z:
					var local_pt := Vector3i(pt.x - offset_x, pt.y, pt.z - offset_z)
					tile.metadata_points[local_pt] = metadata_points[point_key]

			tiles.append(tile)

	return tiles


func _get_external_edge(tx: int, tz: int, side: String) -> int:
	var key := "%d,%d,%s" % [tx, tz, side]
	return external_edges.get(key, WFCTileDef.EdgeType.SOLID_WALL)
