class_name WFCTileExporter
extends RefCounted

## Export a region of the VoxelTerrain into a WFCTileDef or WFCStructureDef.
## Reads voxel IDs from terrain using a VoxelTool.


## Export a single tile from terrain at the given world-voxel origin.
static func export_tile(
	terrain: Object,
	origin: Vector3i,
	tile_name: String = "exported_tile"
) -> WFCTileDef:
	var tool: Object = terrain.call("get_voxel_tool")
	if not tool:
		push_error("[WFCTileExporter] Could not get voxel tool from terrain")
		return null

	var tile := WFCTileDef.new()
	tile.tile_name = tile_name
	tile._ensure_data()

	for lz in WFCTileDef.TILE_Z:
		for ly in WFCTileDef.TILE_Y:
			for lx in WFCTileDef.TILE_X:
				var world_pos := origin + Vector3i(lx, ly, lz)
				var voxel_id: int = tool.call("get_voxel", world_pos)
				tile.set_voxel(lx, ly, lz, voxel_id)

	print("[WFCTileExporter] Exported tile '%s' from origin %s" % [tile_name, str(origin)])
	return tile


## Export a multi-tile structure from terrain.
## size_in_tiles = Vector2i(width, depth) in tiles.
static func export_structure(
	terrain: Object,
	origin: Vector3i,
	size_in_tiles: Vector2i,
	structure_name: String = "exported_structure"
) -> WFCStructureDef:
	var tool: Object = terrain.call("get_voxel_tool")
	if not tool:
		push_error("[WFCTileExporter] Could not get voxel tool from terrain")
		return null

	var structure := WFCStructureDef.new()
	structure.structure_name = structure_name
	structure.size = size_in_tiles

	var full_w := size_in_tiles.x * WFCTileDef.TILE_X
	var full_h := WFCTileDef.TILE_Y
	var full_d := size_in_tiles.y * WFCTileDef.TILE_Z
	var byte_size := full_w * full_h * full_d * 2
	structure.full_voxel_data.resize(byte_size)
	structure.full_voxel_data.fill(0)

	for lz in full_d:
		for ly in full_h:
			for lx in full_w:
				var world_pos := origin + Vector3i(lx, ly, lz)
				var voxel_id: int = tool.call("get_voxel", world_pos)
				var idx := (lx + ly * full_w + lz * full_w * full_h) * 2
				structure.full_voxel_data.encode_u16(idx, voxel_id)

	print("[WFCTileExporter] Exported structure '%s' (%dx%d tiles) from origin %s" % [
		structure_name, size_in_tiles.x, size_in_tiles.y, str(origin)])
	return structure


## Save a tile or structure resource to disk.
static func save_resource(resource: Resource, path: String) -> Error:
	var err := ResourceSaver.save(resource, path)
	if err == OK:
		print("[WFCTileExporter] Saved to: %s" % path)
	else:
		push_error("[WFCTileExporter] Failed to save: %s (error %d)" % [path, err])
	return err
