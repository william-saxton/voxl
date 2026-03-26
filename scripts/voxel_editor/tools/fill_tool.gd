class_name FillTool
extends RefCounted

## Flood fill tool. Click a voxel to fill all connected matching voxels.
## Behavior depends on the primary mode:
##   ADD: pour fill — fills air like water pouring into a container
##   SUBTRACT: remove all connected matching solid voxels (same type)
##   PAINT: repaint all connected matching solid voxels (same type)

const POUR_FILL_RANGE := 32  ## XZ range for pour fill enclosed detection

var query := VoxelQuery.new()


## Execute a fill operation.
## For ADD: pos should be the air voxel to start filling from.
## For SUBTRACT/PAINT: pos should be the solid voxel that was clicked.
func execute(tile: WFCTileDef, pos: Vector3i,
		mode: int) -> Array[Vector3i]:
	match mode:
		0:  # ADD — pour fill: find floor, fill enclosed levels upward
			if not VoxelQuery._in_bounds(pos):
				return []
			if VoxelQuery.is_air(tile, pos):
				query.search_range = POUR_FILL_RANGE
				var result := query.pour_fill(tile, pos)
				query.search_range = VoxelQuery.DEFAULT_RANGE
				return result
			return []
		1:  # SUBTRACT — remove all connected same-type voxels
			if tile.get_voxel(pos.x, pos.y, pos.z) == 0:
				return []
			# Force color matching for subtract fill
			var old_color := query.filter_color
			query.filter_color = true
			var result := query.flood_fill(tile, pos)
			query.filter_color = old_color
			return result
		2:  # PAINT — repaint all connected same-type voxels
			if tile.get_voxel(pos.x, pos.y, pos.z) == 0:
				return []
			# Force color matching for paint fill
			var old_color := query.filter_color
			query.filter_color = true
			var result := query.flood_fill(tile, pos)
			query.filter_color = old_color
			return result
	return []
