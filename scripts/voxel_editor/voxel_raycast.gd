class_name VoxelRaycast
extends RefCounted

## Amanatides-Woo DDA grid traversal for mouse-to-voxel picking.
## Works directly against WFCTileDef voxel data — no physics bodies needed.

const MAX_STEPS := 300

## Native backend (set once by TileRenderer/EditorToolManager at startup)
static var native: RefCounted  # VoxelEditorNative when available

## Result of a raycast. null fields if no hit.
var hit: bool = false
var position: Vector3i   ## The voxel that was hit
var previous: Vector3i   ## The air voxel before the hit (placement spot)
var voxel_id: int = 0    ## The voxel ID at the hit position
var distance: float = 0.0


## Cast a ray from origin in direction dir against the tile's voxel data.
## Returns a new VoxelRaycast with the result.
static func cast(tile: WFCTileDef, ray_origin: Vector3, ray_dir: Vector3) -> VoxelRaycast:
	var result := VoxelRaycast.new()
	if not tile or ray_dir.is_zero_approx():
		return result

	var tx: int = tile.tile_size_x
	var ty: int = tile.tile_size_y
	var tz: int = tile.tile_size_z

	# Use C++ native backend if available
	if native:
		var d: Dictionary = native.raycast(tile.voxel_data, ray_origin, ray_dir, 300.0,
				tx, ty, tz)
		result.hit = d.get("hit", false)
		if result.hit:
			result.position = d["position"]
			result.previous = d["previous"]
			result.voxel_id = d["voxel_id"]
			result.distance = d["distance"]
		return result

	ray_dir = ray_dir.normalized()

	# Find entry point into the tile bounding box
	var t_enter := _ray_aabb_enter(ray_origin, ray_dir,
		Vector3.ZERO, Vector3(tx, ty, tz))

	var start: Vector3
	if t_enter > 0.0:
		start = ray_origin + ray_dir * (t_enter + 0.001)
	else:
		start = ray_origin

	# Starting voxel
	var vx := int(floorf(start.x))
	var vy := int(floorf(start.y))
	var vz := int(floorf(start.z))

	# Step direction
	var step_x := 1 if ray_dir.x >= 0 else -1
	var step_y := 1 if ray_dir.y >= 0 else -1
	var step_z := 1 if ray_dir.z >= 0 else -1

	# tMax — distance along ray to next voxel boundary
	var t_max_x := _t_to_boundary(start.x, ray_dir.x, step_x)
	var t_max_y := _t_to_boundary(start.y, ray_dir.y, step_y)
	var t_max_z := _t_to_boundary(start.z, ray_dir.z, step_z)

	# tDelta — distance along ray to cross one full voxel
	var t_delta_x := absf(1.0 / ray_dir.x) if ray_dir.x != 0.0 else 1e30
	var t_delta_y := absf(1.0 / ray_dir.y) if ray_dir.y != 0.0 else 1e30
	var t_delta_z := absf(1.0 / ray_dir.z) if ray_dir.z != 0.0 else 1e30

	var prev := Vector3i(vx, vy, vz)

	for _step in MAX_STEPS:
		# Bounds check
		if vx < 0 or vx >= tx or \
				vy < 0 or vy >= ty or \
				vz < 0 or vz >= tz:
			# If we started inside and went out, no hit
			if _step > 0:
				break
			# We might not have entered yet — advance
		else:
			var vid := tile.get_voxel(vx, vy, vz)
			if vid != 0:
				result.hit = true
				result.position = Vector3i(vx, vy, vz)
				result.previous = prev
				result.voxel_id = vid
				result.distance = maxf(t_enter, 0.0) + minf(t_max_x, minf(t_max_y, t_max_z))
				return result

		prev = Vector3i(vx, vy, vz)

		# Step to next voxel
		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				vx += step_x; t_max_x += t_delta_x
			else:
				vz += step_z; t_max_z += t_delta_z
		else:
			if t_max_y < t_max_z:
				vy += step_y; t_max_y += t_delta_y
			else:
				vz += step_z; t_max_z += t_delta_z

	return result


static func _t_to_boundary(pos: float, dir: float, step: int) -> float:
	if dir == 0.0:
		return 1e30
	var boundary: float
	if step > 0:
		boundary = floorf(pos) + 1.0
	else:
		boundary = floorf(pos)
		if pos == boundary:
			boundary -= 1.0
	return (boundary - pos) / dir


## Returns the t parameter where the ray enters the AABB, or -1 if no intersection.
static func _ray_aabb_enter(origin: Vector3, dir: Vector3,
		aabb_min: Vector3, aabb_max: Vector3) -> float:
	var t_min := -1e30
	var t_max := 1e30

	for i in 3:
		if absf(dir[i]) < 1e-8:
			if origin[i] < aabb_min[i] or origin[i] > aabb_max[i]:
				return -1.0
		else:
			var inv_d := 1.0 / dir[i]
			var t1 := (aabb_min[i] - origin[i]) * inv_d
			var t2 := (aabb_max[i] - origin[i]) * inv_d
			if t1 > t2:
				var tmp := t1; t1 = t2; t2 = tmp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return -1.0

	return t_min
