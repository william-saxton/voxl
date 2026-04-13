class_name TransformGizmo
extends Node3D

## Interactive 3-axis gizmo for transform mode.
## Supports three visual modes:
##   MOVE: arrow cones at axis ends, plane quads, center sphere
##   ROTATE: rotation rings around each axis
##   SCALE: cube handles at axis ends, plane quads, center sphere
##
## Call test_hit(camera, mouse_pos) to check which handle was clicked.

enum Handle {
	NONE,
	AXIS_X, AXIS_NEG_X,
	AXIS_Y, AXIS_NEG_Y,
	AXIS_Z, AXIS_NEG_Z,
	PLANE_XY, PLANE_XZ, PLANE_YZ,
	FREE,
	# Rotate-specific handles
	RING_X, RING_Y, RING_Z,
}

enum GizmoMode { MOVE, ROTATE, SCALE }

const AXIS_LENGTH := 4.0
const CONE_LENGTH := 0.8
const CONE_RADIUS := 0.25
const CUBE_SIZE := 0.4
const PLANE_SIZE := 1.2
const PLANE_OFFSET := 1.5
const CENTER_RADIUS := 0.3
const RING_RADIUS := 3.5
const RING_TUBE_RADIUS := 0.08
const RING_SEGMENTS := 48
const HIT_RADIUS_CONE := 0.6
const HIT_RADIUS_PLANE := 0.8
const HIT_RADIUS_CENTER := 0.5
const HIT_RADIUS_RING := 0.8

var _highlight_handle: Handle = Handle.NONE
var _gizmo_mode: GizmoMode = GizmoMode.MOVE

# Mesh instances for each part
var _parts: Dictionary = {}  # Handle → MeshInstance3D
var _axis_lines: Array[MeshInstance3D] = []

# Ring mesh instances (rotate mode)
var _ring_parts: Dictionary = {}  # Handle → MeshInstance3D

# Scale cube mesh instances
var _scale_parts: Dictionary = {}  # Handle → MeshInstance3D

# Rotate drag visual feedback
var _rotate_arc: MeshInstance3D
var _rotate_line: MeshInstance3D

# Colors
const COLOR_X := Color(0.9, 0.2, 0.2)
const COLOR_Y := Color(0.2, 0.9, 0.2)
const COLOR_Z := Color(0.3, 0.3, 0.9)
const COLOR_X_HIGHLIGHT := Color(1.0, 0.5, 0.5)
const COLOR_Y_HIGHLIGHT := Color(0.5, 1.0, 0.5)
const COLOR_Z_HIGHLIGHT := Color(0.6, 0.6, 1.0)
const COLOR_FREE := Color(0.9, 0.9, 0.9)
const COLOR_FREE_HIGHLIGHT := Color(1.0, 1.0, 1.0)


func _ready() -> void:
	# Axis lines (shared across all modes)
	_axis_lines.append(_create_line(Vector3(-AXIS_LENGTH, 0, 0),
		Vector3(AXIS_LENGTH, 0, 0), COLOR_X))
	_axis_lines.append(_create_line(Vector3(0, -AXIS_LENGTH, 0),
		Vector3(0, AXIS_LENGTH, 0), COLOR_Y))
	_axis_lines.append(_create_line(Vector3(0, 0, -AXIS_LENGTH),
		Vector3(0, 0, AXIS_LENGTH), COLOR_Z))

	# ── MOVE parts ──
	# Arrow cones (+ and - for each axis)
	_parts[Handle.AXIS_X] = _create_cone(
		Vector3(AXIS_LENGTH, 0, 0), Vector3(1, 0, 0), COLOR_X)
	_parts[Handle.AXIS_NEG_X] = _create_cone(
		Vector3(-AXIS_LENGTH, 0, 0), Vector3(-1, 0, 0), COLOR_X)
	_parts[Handle.AXIS_Y] = _create_cone(
		Vector3(0, AXIS_LENGTH, 0), Vector3(0, 1, 0), COLOR_Y)
	_parts[Handle.AXIS_NEG_Y] = _create_cone(
		Vector3(0, -AXIS_LENGTH, 0), Vector3(0, -1, 0), COLOR_Y)
	_parts[Handle.AXIS_Z] = _create_cone(
		Vector3(0, 0, AXIS_LENGTH), Vector3(0, 0, 1), COLOR_Z)
	_parts[Handle.AXIS_NEG_Z] = _create_cone(
		Vector3(0, 0, -AXIS_LENGTH), Vector3(0, 0, -1), COLOR_Z)

	# Plane quads (shared between move and scale)
	_parts[Handle.PLANE_XY] = _create_plane_quad(
		Vector3(PLANE_OFFSET, PLANE_OFFSET, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Color(COLOR_Z, 0.4))
	_parts[Handle.PLANE_XZ] = _create_plane_quad(
		Vector3(PLANE_OFFSET, 0, PLANE_OFFSET), Vector3(1, 0, 0), Vector3(0, 0, 1),
		Color(COLOR_Y, 0.4))
	_parts[Handle.PLANE_YZ] = _create_plane_quad(
		Vector3(0, PLANE_OFFSET, PLANE_OFFSET), Vector3(0, 1, 0), Vector3(0, 0, 1),
		Color(COLOR_X, 0.4))

	# Center sphere (free movement — shared between move and scale)
	_parts[Handle.FREE] = _create_sphere(Vector3.ZERO, CENTER_RADIUS, COLOR_FREE)

	# ── SCALE parts ──
	# Cube handles at axis ends
	_scale_parts[Handle.AXIS_X] = _create_cube(
		Vector3(AXIS_LENGTH, 0, 0), CUBE_SIZE, COLOR_X)
	_scale_parts[Handle.AXIS_NEG_X] = _create_cube(
		Vector3(-AXIS_LENGTH, 0, 0), CUBE_SIZE, COLOR_X)
	_scale_parts[Handle.AXIS_Y] = _create_cube(
		Vector3(0, AXIS_LENGTH, 0), CUBE_SIZE, COLOR_Y)
	_scale_parts[Handle.AXIS_NEG_Y] = _create_cube(
		Vector3(0, -AXIS_LENGTH, 0), CUBE_SIZE, COLOR_Y)
	_scale_parts[Handle.AXIS_Z] = _create_cube(
		Vector3(0, 0, AXIS_LENGTH), CUBE_SIZE, COLOR_Z)
	_scale_parts[Handle.AXIS_NEG_Z] = _create_cube(
		Vector3(0, 0, -AXIS_LENGTH), CUBE_SIZE, COLOR_Z)

	# ── ROTATE parts ──
	# Rotation rings around each axis
	_ring_parts[Handle.RING_X] = _create_ring(Vector3.RIGHT, COLOR_X)
	_ring_parts[Handle.RING_Y] = _create_ring(Vector3.UP, COLOR_Y)
	_ring_parts[Handle.RING_Z] = _create_ring(Vector3.BACK, COLOR_Z)

	# Rotate feedback visuals (hidden by default)
	_rotate_arc = MeshInstance3D.new()
	_rotate_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotate_arc.visible = false
	add_child(_rotate_arc)

	_rotate_line = MeshInstance3D.new()
	_rotate_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotate_line.visible = false
	add_child(_rotate_line)

	# Start in move mode
	set_gizmo_mode(GizmoMode.MOVE)


func set_gizmo_mode(mode: GizmoMode) -> void:
	_gizmo_mode = mode
	clear_rotate_feedback()

	# Show/hide axis lines (visible for move and scale, hidden for rotate)
	var show_lines := mode != GizmoMode.ROTATE
	for line in _axis_lines:
		line.visible = show_lines

	# Show/hide move cone parts
	var show_move := mode == GizmoMode.MOVE
	for h in _parts:
		if h in [Handle.AXIS_X, Handle.AXIS_NEG_X, Handle.AXIS_Y,
				Handle.AXIS_NEG_Y, Handle.AXIS_Z, Handle.AXIS_NEG_Z]:
			_parts[h].visible = show_move

	# Show/hide plane quads and center sphere (move and scale)
	var show_planes := mode == GizmoMode.MOVE or mode == GizmoMode.SCALE
	for h in [Handle.PLANE_XY, Handle.PLANE_XZ, Handle.PLANE_YZ, Handle.FREE]:
		if _parts.has(h):
			_parts[h].visible = show_planes

	# Show/hide scale cube parts
	var show_scale := mode == GizmoMode.SCALE
	for h in _scale_parts:
		_scale_parts[h].visible = show_scale

	# Show/hide rotate ring parts
	var show_rotate := mode == GizmoMode.ROTATE
	for h in _ring_parts:
		_ring_parts[h].visible = show_rotate

	_update_colors()


func update_position(sel_positions: Array[Vector3i]) -> void:
	if sel_positions.is_empty():
		visible = false
		return

	visible = true
	var center := Vector3.ZERO
	for pos in sel_positions:
		center += Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	center /= sel_positions.size()
	global_position = center


## Test which handle (if any) is under the mouse position.
## Returns the Handle enum value. Uses screen-space distance testing.
func test_hit(camera: Camera3D, mouse_pos: Vector2) -> Handle:
	if not visible:
		return Handle.NONE

	var gp := global_position
	var best_handle := Handle.NONE
	var best_dist := 999999.0

	if _gizmo_mode == GizmoMode.ROTATE:
		# Test rotation rings
		var ring_handles: Array[Array] = [
			[Handle.RING_X, Vector3.RIGHT],
			[Handle.RING_Y, Vector3.UP],
			[Handle.RING_Z, Vector3.BACK],
		]
		for entry in ring_handles:
			var handle: Handle = entry[0]
			var axis: Vector3 = entry[1]
			var d := _test_ring_hit(camera, mouse_pos, gp, axis)
			if d >= 0.0 and d < best_dist:
				best_dist = d
				best_handle = handle
		return best_handle

	# Test center sphere first (highest priority if overlapping)
	var center_screen := camera.unproject_position(gp)
	if not camera.is_position_behind(gp):
		var d := center_screen.distance_to(mouse_pos)
		var screen_radius := _world_to_screen_size(camera, gp, CENTER_RADIUS)
		if d < screen_radius * 2.0 and d < best_dist:
			best_dist = d
			best_handle = Handle.FREE

	# Test axis handles (cones for move, cubes for scale — same positions)
	var cone_handles: Array[Array] = [
		[Handle.AXIS_X, Vector3(AXIS_LENGTH, 0, 0)],
		[Handle.AXIS_NEG_X, Vector3(-AXIS_LENGTH, 0, 0)],
		[Handle.AXIS_Y, Vector3(0, AXIS_LENGTH, 0)],
		[Handle.AXIS_NEG_Y, Vector3(0, -AXIS_LENGTH, 0)],
		[Handle.AXIS_Z, Vector3(0, 0, AXIS_LENGTH)],
		[Handle.AXIS_NEG_Z, Vector3(0, 0, -AXIS_LENGTH)],
	]
	for entry in cone_handles:
		var handle: Handle = entry[0]
		var offset: Vector3 = entry[1]
		var world_pos := gp + offset
		if camera.is_position_behind(world_pos):
			continue
		var screen_pos := camera.unproject_position(world_pos)
		var d := screen_pos.distance_to(mouse_pos)
		var screen_radius := _world_to_screen_size(camera, world_pos, HIT_RADIUS_CONE)
		if d < screen_radius * 2.0 and d < best_dist:
			best_dist = d
			best_handle = handle

	# Test plane quads
	var plane_handles: Array[Array] = [
		[Handle.PLANE_XY, Vector3(PLANE_OFFSET, PLANE_OFFSET, 0)],
		[Handle.PLANE_XZ, Vector3(PLANE_OFFSET, 0, PLANE_OFFSET)],
		[Handle.PLANE_YZ, Vector3(0, PLANE_OFFSET, PLANE_OFFSET)],
	]
	for entry in plane_handles:
		var handle: Handle = entry[0]
		var offset: Vector3 = entry[1]
		var world_pos := gp + offset
		if camera.is_position_behind(world_pos):
			continue
		var screen_pos := camera.unproject_position(world_pos)
		var d := screen_pos.distance_to(mouse_pos)
		var screen_radius := _world_to_screen_size(camera, world_pos, HIT_RADIUS_PLANE)
		if d < screen_radius * 2.0 and d < best_dist:
			best_dist = d
			best_handle = handle

	return best_handle


## Test if mouse is near a rotation ring. Returns screen distance or -1.
func _test_ring_hit(camera: Camera3D, mouse_pos: Vector2,
		center: Vector3, axis: Vector3) -> float:
	# Sample points around the ring and find the closest screen-space point
	var min_dist := 999999.0
	for i in RING_SEGMENTS:
		var angle := TAU * i / RING_SEGMENTS
		var point := _ring_point(center, axis, angle)
		if camera.is_position_behind(point):
			continue
		var screen_pos := camera.unproject_position(point)
		var d := screen_pos.distance_to(mouse_pos)
		if d < min_dist:
			min_dist = d
	var threshold := _world_to_screen_size(camera, center, HIT_RADIUS_RING)
	if min_dist < threshold:
		return min_dist
	return -1.0


func _ring_point(center: Vector3, axis: Vector3, angle: float) -> Vector3:
	# Get two vectors perpendicular to axis
	var u: Vector3
	var v: Vector3
	if axis.is_equal_approx(Vector3.UP) or axis.is_equal_approx(Vector3.DOWN):
		u = Vector3.RIGHT
		v = Vector3.BACK
	elif axis.is_equal_approx(Vector3.RIGHT) or axis.is_equal_approx(Vector3.LEFT):
		u = Vector3.UP
		v = Vector3.BACK
	else:
		u = Vector3.RIGHT
		v = Vector3.UP
	return center + (u * cos(angle) + v * sin(angle)) * RING_RADIUS


## Set which handle is highlighted (for hover feedback).
func set_highlight(handle: Handle) -> void:
	if handle == _highlight_handle:
		return
	_highlight_handle = handle
	_update_colors()


func _update_colors() -> void:
	# Update move/scale parts
	for h in _parts:
		var mi: MeshInstance3D = _parts[h]
		var mat: StandardMaterial3D = mi.material_override
		if not mat:
			continue
		match h:
			Handle.AXIS_X, Handle.AXIS_NEG_X:
				mat.albedo_color = COLOR_X_HIGHLIGHT if _is_highlighted(h) else COLOR_X
			Handle.AXIS_Y, Handle.AXIS_NEG_Y:
				mat.albedo_color = COLOR_Y_HIGHLIGHT if _is_highlighted(h) else COLOR_Y
			Handle.AXIS_Z, Handle.AXIS_NEG_Z:
				mat.albedo_color = COLOR_Z_HIGHLIGHT if _is_highlighted(h) else COLOR_Z
			Handle.PLANE_XY:
				mat.albedo_color = Color(
					COLOR_Z_HIGHLIGHT if _is_highlighted(h) else COLOR_Z, 0.4)
			Handle.PLANE_XZ:
				mat.albedo_color = Color(
					COLOR_Y_HIGHLIGHT if _is_highlighted(h) else COLOR_Y, 0.4)
			Handle.PLANE_YZ:
				mat.albedo_color = Color(
					COLOR_X_HIGHLIGHT if _is_highlighted(h) else COLOR_X, 0.4)
			Handle.FREE:
				mat.albedo_color = COLOR_FREE_HIGHLIGHT if _is_highlighted(h) else COLOR_FREE

	# Update scale cube parts
	for h in _scale_parts:
		var mi: MeshInstance3D = _scale_parts[h]
		var mat: StandardMaterial3D = mi.material_override
		if not mat:
			continue
		match h:
			Handle.AXIS_X, Handle.AXIS_NEG_X:
				mat.albedo_color = COLOR_X_HIGHLIGHT if _is_highlighted(h) else COLOR_X
			Handle.AXIS_Y, Handle.AXIS_NEG_Y:
				mat.albedo_color = COLOR_Y_HIGHLIGHT if _is_highlighted(h) else COLOR_Y
			Handle.AXIS_Z, Handle.AXIS_NEG_Z:
				mat.albedo_color = COLOR_Z_HIGHLIGHT if _is_highlighted(h) else COLOR_Z

	# Update ring parts
	for h in _ring_parts:
		var mi: MeshInstance3D = _ring_parts[h]
		var mat: StandardMaterial3D = mi.material_override
		if not mat:
			continue
		match h:
			Handle.RING_X:
				mat.albedo_color = COLOR_X_HIGHLIGHT if _is_highlighted(h) else COLOR_X
			Handle.RING_Y:
				mat.albedo_color = COLOR_Y_HIGHLIGHT if _is_highlighted(h) else COLOR_Y
			Handle.RING_Z:
				mat.albedo_color = COLOR_Z_HIGHLIGHT if _is_highlighted(h) else COLOR_Z


func _is_highlighted(handle: Handle) -> bool:
	if _highlight_handle == handle:
		return true
	# Highlight both +/- arrows when either is hovered
	match _highlight_handle:
		Handle.AXIS_X, Handle.AXIS_NEG_X:
			return handle == Handle.AXIS_X or handle == Handle.AXIS_NEG_X
		Handle.AXIS_Y, Handle.AXIS_NEG_Y:
			return handle == Handle.AXIS_Y or handle == Handle.AXIS_NEG_Y
		Handle.AXIS_Z, Handle.AXIS_NEG_Z:
			return handle == Handle.AXIS_Z or handle == Handle.AXIS_NEG_Z
	return false


func _world_to_screen_size(camera: Camera3D, world_pos: Vector3,
		world_size: float) -> float:
	var p1 := camera.unproject_position(world_pos)
	var p2 := camera.unproject_position(world_pos + camera.global_basis.x * world_size)
	return p1.distance_to(p2)


func _create_line(from: Vector3, to: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _create_cone(tip_pos: Vector3, direction: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = CONE_RADIUS
	cone.height = CONE_LENGTH

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	mi.material_override = mat
	mi.mesh = cone
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Add to tree first so look_at() works (requires being inside the tree)
	add_child(mi)

	# Position cone so the tip is at tip_pos, pointing along direction
	var base_pos := tip_pos - direction.normalized() * CONE_LENGTH * 0.5
	mi.position = base_pos
	# Rotate to align with direction (default cone points +Y)
	if direction.normalized() != Vector3.UP and direction.normalized() != Vector3.DOWN:
		mi.look_at(mi.position + direction, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	elif direction.y < 0:
		mi.rotation_degrees = Vector3(180, 0, 0)

	return mi


func _create_cube(pos: Vector3, size: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size, size, size)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	mi.material_override = mat
	mi.mesh = box
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _create_plane_quad(center: Vector3, u: Vector3, v: Vector3,
		color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 9
	mi.material_override = mat

	var half := PLANE_SIZE * 0.5
	var c0 := center - u * half - v * half
	var c1 := center + u * half - v * half
	var c2 := center + u * half + v * half
	var c3 := center - u * half + v * half

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	im.surface_add_vertex(c0)
	im.surface_add_vertex(c1)
	im.surface_add_vertex(c2)
	im.surface_add_vertex(c0)
	im.surface_add_vertex(c2)
	im.surface_add_vertex(c3)
	im.surface_end()

	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _create_sphere(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 11
	mi.material_override = mat
	mi.mesh = sphere
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _create_ring(axis: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	mi.material_override = mat

	# Build ring as line strip
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in RING_SEGMENTS + 1:
		var angle := TAU * i / RING_SEGMENTS
		var point := _ring_point(Vector3.ZERO, axis, angle)
		im.surface_add_vertex(point)
	im.surface_end()

	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Map a ring handle to its rotation axis index (0=X, 1=Y, 2=Z). Returns -1 if not a ring.
func ring_handle_to_axis(handle: Handle) -> int:
	match handle:
		Handle.RING_X: return 0
		Handle.RING_Y: return 1
		Handle.RING_Z: return 2
	return -1


## Show arc + line visual during rotate drag.
## start_deg and end_deg are absolute angles on the ring plane.
func set_rotate_feedback(axis: int, start_deg: float, end_deg: float) -> void:
	var axis_vec: Vector3
	var color: Color
	match axis:
		0:
			axis_vec = Vector3.RIGHT
			color = COLOR_X_HIGHLIGHT
		1:
			axis_vec = Vector3.UP
			color = COLOR_Y_HIGHLIGHT
		_:
			axis_vec = Vector3.BACK
			color = COLOR_Z_HIGHLIGHT

	var start_rad := deg_to_rad(start_deg)
	var end_rad := deg_to_rad(end_deg)
	var sweep := end_rad - start_rad
	while sweep > PI:
		sweep -= TAU
	while sweep < -PI:
		sweep += TAU

	# Build arc mesh (filled sector from center to ring edge)
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = Color(color, 0.25)
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mat.no_depth_test = true
	arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc_mat.render_priority = 12

	var arc_im := ImmediateMesh.new()
	var arc_steps := maxi(8, int(absf(sweep) / TAU * RING_SEGMENTS))
	arc_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, arc_mat)
	for i in arc_steps:
		var a0 := start_rad + sweep * float(i) / arc_steps
		var a1 := start_rad + sweep * float(i + 1) / arc_steps
		var p0 := _ring_point(Vector3.ZERO, axis_vec, a0)
		var p1 := _ring_point(Vector3.ZERO, axis_vec, a1)
		arc_im.surface_add_vertex(Vector3.ZERO)
		arc_im.surface_add_vertex(p0)
		arc_im.surface_add_vertex(p1)
	arc_im.surface_end()
	_rotate_arc.mesh = arc_im
	_rotate_arc.visible = true

	# Build lines from center to start and end angle points
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = color
	line_mat.no_depth_test = true
	line_mat.render_priority = 12

	var line_im := ImmediateMesh.new()
	line_im.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	line_im.surface_add_vertex(Vector3.ZERO)
	line_im.surface_add_vertex(_ring_point(Vector3.ZERO, axis_vec, end_rad))
	line_im.surface_add_vertex(Vector3.ZERO)
	line_im.surface_add_vertex(_ring_point(Vector3.ZERO, axis_vec, start_rad))
	line_im.surface_end()
	_rotate_line.mesh = line_im
	_rotate_line.visible = true


## Hide rotate drag visuals.
func clear_rotate_feedback() -> void:
	_rotate_arc.visible = false
	_rotate_line.visible = false
