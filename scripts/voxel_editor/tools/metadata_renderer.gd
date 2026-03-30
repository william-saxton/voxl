class_name MetadataRenderer
extends Node3D

## Renders colored markers in the 3D viewport at metadata point positions.
## Each marker has:
##   - A large symbol representing the type (diamond, cross, star, etc.)
##   - A vertical line connecting the marker to the voxel surface below
##   - A text label (type name) positioned above the marker

var _markers: Array[Node3D] = []
var _particle_previews: Array[Node3D] = []
var _metadata_tool: MetadataTool
const BASE_MARKER_SIZE := 0.8
const BASE_FLOAT_HEIGHT := 2.0  # How far above the voxel the marker floats
var marker_scale := 1.0
var MARKER_SIZE: float:
	get: return BASE_MARKER_SIZE * marker_scale
var MARKER_FLOAT_HEIGHT: float:
	get: return BASE_FLOAT_HEIGHT * marker_scale
const LINE_COLOR := Color(1, 1, 1, 0.3)

## Symbol characters for each type category
const TYPE_SYMBOLS := {
	"spawn_point": "spawn",       # cross
	"enemy_spawn": "enemy",       # X
	"item_spawn": "item",         # diamond
	"weapon_spawn": "weapon",     # arrow
	"trigger": "trigger",         # lightning
	"loot_chest": "chest",        # box
	"waypoint": "waypoint",       # circle
	"particle": "particle",       # starburst
	"shader_plane": "shader",     # plane outline
	"custom": "custom",           # diamond
}

var _shader_planes: Array[MeshInstance3D] = []
var _marker_positions: Dictionary = {}  # Vector3i -> Node3D (marker root)
var _highlight_ring: MeshInstance3D
var _highlighted_pos := Vector3i(-9999, -9999, -9999)


func set_metadata_tool(tool: MetadataTool) -> void:
	_metadata_tool = tool


## Highlight the marker at the given position (or clear if pos is invalid).
func highlight_marker(pos: Vector3i) -> void:
	if pos == _highlighted_pos:
		return
	_highlighted_pos = pos
	if not _highlight_ring:
		_highlight_ring = _create_highlight_ring()
		add_child(_highlight_ring)
	if _marker_positions.has(pos):
		_highlight_ring.visible = true
		var center := Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5)
		_highlight_ring.position = center
	else:
		_highlight_ring.visible = false


func _create_highlight_ring() -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh_inst.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 5
	var ring_r := 0.55
	var segs := 20
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in segs + 1:
		var angle := TAU * i / segs
		im.surface_add_vertex(Vector3(cos(angle) * ring_r, 0, sin(angle) * ring_r))
	im.surface_end()
	# Second ring at marker height
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in segs + 1:
		var angle := TAU * i / segs
		im.surface_add_vertex(Vector3(cos(angle) * ring_r, MARKER_FLOAT_HEIGHT, sin(angle) * ring_r))
	im.surface_end()
	mesh_inst.visible = false
	return mesh_inst


func update_markers(tile: WFCTileDef) -> void:
	# Clear old markers, particle previews, and shader planes
	for m in _markers:
		m.queue_free()
	_markers.clear()
	for p in _particle_previews:
		p.queue_free()
	_particle_previews.clear()
	for sp in _shader_planes:
		sp.queue_free()
	_shader_planes.clear()
	_marker_positions.clear()
	_highlighted_pos = Vector3i(-9999, -9999, -9999)
	if _highlight_ring:
		_highlight_ring.visible = false

	if not tile or not _metadata_tool:
		return

	for key in tile.metadata_points:
		var pos: Vector3i = key
		var data: Dictionary = tile.metadata_points[key]
		var type_name: String = data.get("type", "custom")
		var color: Color = _metadata_tool.get_type_color(type_name)

		var marker_root := Node3D.new()
		var center := Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5)
		var marker_pos := center + Vector3(0, MARKER_FLOAT_HEIGHT, 0)

		# Draw the symbol mesh at the floating position
		var symbol_mesh := _create_symbol(marker_pos, color, type_name)
		marker_root.add_child(symbol_mesh)

		# Draw a vertical line from the voxel to the marker
		var line_mesh := _create_line(center, marker_pos, LINE_COLOR)
		marker_root.add_child(line_mesh)

		# Draw a small ground indicator at the voxel position
		var ground_mesh := _create_ground_ring(center, color)
		marker_root.add_child(ground_mesh)

		add_child(marker_root)
		_markers.append(marker_root)
		_marker_positions[pos] = marker_root

		# Instance particle scene preview
		if type_name == "particle":
			var scene_path: String = str(data.get("scene", ""))
			if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
				var scene: PackedScene = ResourceLoader.load(scene_path)
				if scene:
					var instance := scene.instantiate()
					if instance is Node3D:
						instance.position = center
						add_child(instance)
						_particle_previews.append(instance)
					else:
						instance.queue_free()

		# Shader plane preview quad
		if type_name == "shader_plane":
			var plane_mesh := _create_shader_plane_preview(center, data, color)
			if plane_mesh:
				add_child(plane_mesh)
				_shader_planes.append(plane_mesh)


func _create_symbol(pos: Vector3, color: Color, type_name: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh_inst.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 3

	var s := MARKER_SIZE

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)

	match type_name:
		"spawn_point":
			_draw_cross_marker(im, pos, s)
		"enemy_spawn":
			_draw_x_marker(im, pos, s)
		"item_spawn", "custom":
			_draw_diamond_marker(im, pos, s)
		"weapon_spawn":
			_draw_arrow_marker(im, pos, s)
		"trigger":
			_draw_lightning_marker(im, pos, s)
		"loot_chest":
			_draw_box_marker(im, pos, s)
		"waypoint":
			_draw_circle_marker(im, pos, s)
		"particle":
			_draw_starburst_marker(im, pos, s)
		"shader_plane":
			_draw_plane_marker(im, pos, s)
		_:
			_draw_diamond_marker(im, pos, s)

	im.surface_end()
	return mesh_inst


func _create_line(from: Vector3, to: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh_inst.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	# Dashed line effect — draw segments
	var segments := 6
	for i in segments:
		if i % 2 == 0:  # Only draw even segments for dashed effect
			var t0 := float(i) / segments
			var t1 := float(i + 1) / segments
			im.surface_add_vertex(from.lerp(to, t0))
			im.surface_add_vertex(from.lerp(to, t1))
	im.surface_end()
	return mesh_inst


func _create_ground_ring(center: Vector3, color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh_inst.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.6)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 2

	var ring_r := 0.35
	var segs := 16
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for i in segs + 1:
		var angle := TAU * i / segs
		im.surface_add_vertex(center + Vector3(cos(angle) * ring_r, 0, sin(angle) * ring_r))
	im.surface_end()
	return mesh_inst


## Cross marker (+) — spawn_point
func _draw_cross_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	im.surface_add_vertex(c + Vector3(-s, 0, 0))
	im.surface_add_vertex(c + Vector3(s, 0, 0))
	im.surface_add_vertex(c + Vector3(0, -s, 0))
	im.surface_add_vertex(c + Vector3(0, s, 0))
	im.surface_add_vertex(c + Vector3(0, 0, -s))
	im.surface_add_vertex(c + Vector3(0, 0, s))
	# Circle around cross
	var segs := 12
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		im.surface_add_vertex(c + Vector3(cos(a0) * s, sin(a0) * s, 0))
		im.surface_add_vertex(c + Vector3(cos(a1) * s, sin(a1) * s, 0))


## X marker — enemy_spawn
func _draw_x_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var d := s * 0.7
	# X shape in XY plane
	im.surface_add_vertex(c + Vector3(-d, -d, 0))
	im.surface_add_vertex(c + Vector3(d, d, 0))
	im.surface_add_vertex(c + Vector3(-d, d, 0))
	im.surface_add_vertex(c + Vector3(d, -d, 0))
	# X shape in XZ plane
	im.surface_add_vertex(c + Vector3(-d, 0, -d))
	im.surface_add_vertex(c + Vector3(d, 0, d))
	im.surface_add_vertex(c + Vector3(-d, 0, d))
	im.surface_add_vertex(c + Vector3(d, 0, -d))
	# Outer diamond
	im.surface_add_vertex(c + Vector3(0, s, 0))
	im.surface_add_vertex(c + Vector3(s, 0, 0))
	im.surface_add_vertex(c + Vector3(s, 0, 0))
	im.surface_add_vertex(c + Vector3(0, -s, 0))
	im.surface_add_vertex(c + Vector3(0, -s, 0))
	im.surface_add_vertex(c + Vector3(-s, 0, 0))
	im.surface_add_vertex(c + Vector3(-s, 0, 0))
	im.surface_add_vertex(c + Vector3(0, s, 0))


## Diamond marker — item_spawn, custom
func _draw_diamond_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var top := c + Vector3(0, s, 0)
	var bot := c + Vector3(0, -s, 0)
	var north := c + Vector3(0, 0, -s)
	var south := c + Vector3(0, 0, s)
	var east := c + Vector3(s, 0, 0)
	var west := c + Vector3(-s, 0, 0)
	# Top edges
	im.surface_add_vertex(top); im.surface_add_vertex(north)
	im.surface_add_vertex(top); im.surface_add_vertex(south)
	im.surface_add_vertex(top); im.surface_add_vertex(east)
	im.surface_add_vertex(top); im.surface_add_vertex(west)
	# Bottom edges
	im.surface_add_vertex(bot); im.surface_add_vertex(north)
	im.surface_add_vertex(bot); im.surface_add_vertex(south)
	im.surface_add_vertex(bot); im.surface_add_vertex(east)
	im.surface_add_vertex(bot); im.surface_add_vertex(west)
	# Middle ring
	im.surface_add_vertex(north); im.surface_add_vertex(east)
	im.surface_add_vertex(east); im.surface_add_vertex(south)
	im.surface_add_vertex(south); im.surface_add_vertex(west)
	im.surface_add_vertex(west); im.surface_add_vertex(north)


## Arrow marker (upward pointing) — weapon_spawn
func _draw_arrow_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	# Shaft
	im.surface_add_vertex(c + Vector3(0, -s, 0))
	im.surface_add_vertex(c + Vector3(0, s, 0))
	# Arrowhead
	var tip := c + Vector3(0, s, 0)
	var h := s * 0.4
	im.surface_add_vertex(tip)
	im.surface_add_vertex(tip + Vector3(-h, -h, 0))
	im.surface_add_vertex(tip)
	im.surface_add_vertex(tip + Vector3(h, -h, 0))
	im.surface_add_vertex(tip)
	im.surface_add_vertex(tip + Vector3(0, -h, -h))
	im.surface_add_vertex(tip)
	im.surface_add_vertex(tip + Vector3(0, -h, h))


## Lightning bolt — trigger
func _draw_lightning_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var p0 := c + Vector3(-s * 0.3, s, 0)
	var p1 := c + Vector3(s * 0.1, s * 0.2, 0)
	var p2 := c + Vector3(-s * 0.1, s * 0.1, 0)
	var p3 := c + Vector3(s * 0.3, -s, 0)
	im.surface_add_vertex(p0); im.surface_add_vertex(p1)
	im.surface_add_vertex(p1); im.surface_add_vertex(p2)
	im.surface_add_vertex(p2); im.surface_add_vertex(p3)
	# Second bolt rotated 90 degrees
	var q0 := c + Vector3(0, s, -s * 0.3)
	var q1 := c + Vector3(0, s * 0.2, s * 0.1)
	var q2 := c + Vector3(0, s * 0.1, -s * 0.1)
	var q3 := c + Vector3(0, -s, s * 0.3)
	im.surface_add_vertex(q0); im.surface_add_vertex(q1)
	im.surface_add_vertex(q1); im.surface_add_vertex(q2)
	im.surface_add_vertex(q2); im.surface_add_vertex(q3)


## Box marker — loot_chest
func _draw_box_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var hs := s * 0.6
	# Bottom face
	im.surface_add_vertex(c + Vector3(-hs, -hs, -hs)); im.surface_add_vertex(c + Vector3(hs, -hs, -hs))
	im.surface_add_vertex(c + Vector3(hs, -hs, -hs)); im.surface_add_vertex(c + Vector3(hs, -hs, hs))
	im.surface_add_vertex(c + Vector3(hs, -hs, hs)); im.surface_add_vertex(c + Vector3(-hs, -hs, hs))
	im.surface_add_vertex(c + Vector3(-hs, -hs, hs)); im.surface_add_vertex(c + Vector3(-hs, -hs, -hs))
	# Top face
	im.surface_add_vertex(c + Vector3(-hs, hs, -hs)); im.surface_add_vertex(c + Vector3(hs, hs, -hs))
	im.surface_add_vertex(c + Vector3(hs, hs, -hs)); im.surface_add_vertex(c + Vector3(hs, hs, hs))
	im.surface_add_vertex(c + Vector3(hs, hs, hs)); im.surface_add_vertex(c + Vector3(-hs, hs, hs))
	im.surface_add_vertex(c + Vector3(-hs, hs, hs)); im.surface_add_vertex(c + Vector3(-hs, hs, -hs))
	# Vertical edges
	im.surface_add_vertex(c + Vector3(-hs, -hs, -hs)); im.surface_add_vertex(c + Vector3(-hs, hs, -hs))
	im.surface_add_vertex(c + Vector3(hs, -hs, -hs)); im.surface_add_vertex(c + Vector3(hs, hs, -hs))
	im.surface_add_vertex(c + Vector3(hs, -hs, hs)); im.surface_add_vertex(c + Vector3(hs, hs, hs))
	im.surface_add_vertex(c + Vector3(-hs, -hs, hs)); im.surface_add_vertex(c + Vector3(-hs, hs, hs))


## Circle marker — waypoint
func _draw_circle_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var segs := 16
	# Horizontal ring
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		im.surface_add_vertex(c + Vector3(cos(a0) * s, 0, sin(a0) * s))
		im.surface_add_vertex(c + Vector3(cos(a1) * s, 0, sin(a1) * s))
	# Vertical ring (XY)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		im.surface_add_vertex(c + Vector3(cos(a0) * s, sin(a0) * s, 0))
		im.surface_add_vertex(c + Vector3(cos(a1) * s, sin(a1) * s, 0))


## Starburst marker — particle
func _draw_starburst_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var ray_len := s * 1.2
	# Axis rays
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(ray_len, 0, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(-ray_len, 0, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, ray_len, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, -ray_len, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, 0, ray_len))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, 0, -ray_len))
	# Diagonal rays
	var d := ray_len * 0.6
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(d, d, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(-d, d, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(d, -d, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(-d, -d, 0))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, d, d))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, -d, d))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, d, -d))
	im.surface_add_vertex(c); im.surface_add_vertex(c + Vector3(0, -d, -d))


## Plane marker (rectangle outline) — shader_plane
func _draw_plane_marker(im: ImmediateMesh, c: Vector3, s: float) -> void:
	var hs := s * 0.7
	# Rectangle in XZ plane
	im.surface_add_vertex(c + Vector3(-hs, 0, -hs))
	im.surface_add_vertex(c + Vector3(hs, 0, -hs))
	im.surface_add_vertex(c + Vector3(hs, 0, -hs))
	im.surface_add_vertex(c + Vector3(hs, 0, hs))
	im.surface_add_vertex(c + Vector3(hs, 0, hs))
	im.surface_add_vertex(c + Vector3(-hs, 0, hs))
	im.surface_add_vertex(c + Vector3(-hs, 0, hs))
	im.surface_add_vertex(c + Vector3(-hs, 0, -hs))
	# Diagonal cross
	im.surface_add_vertex(c + Vector3(-hs, 0, -hs))
	im.surface_add_vertex(c + Vector3(hs, 0, hs))
	im.surface_add_vertex(c + Vector3(hs, 0, -hs))
	im.surface_add_vertex(c + Vector3(-hs, 0, hs))
	# Small normal indicator (up arrow)
	im.surface_add_vertex(c)
	im.surface_add_vertex(c + Vector3(0, s, 0))
	im.surface_add_vertex(c + Vector3(0, s, 0))
	im.surface_add_vertex(c + Vector3(-s * 0.2, s * 0.7, 0))
	im.surface_add_vertex(c + Vector3(0, s, 0))
	im.surface_add_vertex(c + Vector3(s * 0.2, s * 0.7, 0))


## Create a surface-conforming polygon mesh for a shader_plane metadata point.
## Builds one quad per surface voxel face, with configurable offset and boundary inset.
func _create_shader_plane_preview(center: Vector3, data: Dictionary,
		color: Color) -> MeshInstance3D:
	var sp: Variant = data.get("surface_positions")
	if not sp is PackedInt32Array or (sp as PackedInt32Array).size() < 3:
		return null

	var positions: PackedInt32Array = sp
	var face_normal := Vector3i(
		int(data.get("face_normal_x", 0)),
		int(data.get("face_normal_y", 1)),
		int(data.get("face_normal_z", 0)))
	var offset: float = float(data.get("offset", 0.05))
	var inset: float = float(data.get("inset", 0.1))
	var double_sided: bool = bool(data.get("double_sided", true))

	var count := positions.size() / 3
	# Build a set for fast neighbor lookup
	var pos_set := {}
	for i in count:
		var p := Vector3i(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
		pos_set[p] = true

	# Determine the two planar axes and the normal axis
	var fn := Vector3(face_normal)
	var face_offset := fn * (0.5 + offset)

	# For each face normal, determine the two tangent directions
	# These define the quad corners relative to voxel position
	var tangent_a: Vector3i  # first edge direction
	var tangent_b: Vector3i  # second edge direction
	if face_normal.y != 0:
		tangent_a = Vector3i(1, 0, 0)
		tangent_b = Vector3i(0, 0, 1)
	elif face_normal.x != 0:
		tangent_a = Vector3i(0, 1, 0)
		tangent_b = Vector3i(0, 0, 1)
	else:
		tangent_a = Vector3i(1, 0, 0)
		tangent_b = Vector3i(0, 1, 0)

	var ta := Vector3(tangent_a)
	var tb := Vector3(tangent_b)

	# Build mesh: one quad per voxel, with inset on boundary edges
	var verts := PackedVector3Array()
	var uvs := PackedFloat32Array()
	var normals := PackedVector3Array()

	for i in count:
		var p := Vector3i(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
		var vc := Vector3(p) + Vector3(0.5, 0.5, 0.5) + face_offset

		# Check 4 neighbors on the plane
		var has_neg_a := pos_set.has(p - tangent_a)
		var has_pos_a := pos_set.has(p + tangent_a)
		var has_neg_b := pos_set.has(p - tangent_b)
		var has_pos_b := pos_set.has(p + tangent_b)

		# Quad corners: (-a-b), (+a-b), (+a+b), (-a+b)
		var inset_neg_a := inset if not has_neg_a else 0.0
		var inset_pos_a := inset if not has_pos_a else 0.0
		var inset_neg_b := inset if not has_neg_b else 0.0
		var inset_pos_b := inset if not has_pos_b else 0.0

		var c0 := vc + ta * (-0.5 + inset_neg_a) + tb * (-0.5 + inset_neg_b)
		var c1 := vc + ta * (0.5 - inset_pos_a) + tb * (-0.5 + inset_neg_b)
		var c2 := vc + ta * (0.5 - inset_pos_a) + tb * (0.5 - inset_pos_b)
		var c3 := vc + ta * (-0.5 + inset_neg_a) + tb * (0.5 - inset_pos_b)

		# Two triangles: 0-1-2, 0-2-3
		verts.append(c0); verts.append(c1); verts.append(c2)
		verts.append(c0); verts.append(c2); verts.append(c3)
		for _j in 6:
			normals.append(fn)

	if verts.is_empty():
		return null

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arr_mesh

	# Apply shader if path is valid, otherwise use a translucent preview material
	var shader_path: String = str(data.get("shader_path", ""))
	var mat: Material
	if not shader_path.is_empty() and ResourceLoader.exists(shader_path):
		var loaded := ResourceLoader.load(shader_path)
		if loaded is ShaderMaterial:
			mat = (loaded as ShaderMaterial).duplicate()
		elif loaded is Shader:
			var sm := ShaderMaterial.new()
			sm.shader = loaded
			mat = sm
		# Apply saved shader parameters
		if mat is ShaderMaterial:
			var params: Variant = data.get("shader_params")
			if params is Dictionary:
				for param_name: String in params:
					(mat as ShaderMaterial).set_shader_parameter(param_name, params[param_name])

	if not mat:
		var std_mat := StandardMaterial3D.new()
		std_mat.albedo_color = Color(color, 0.3)
		std_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		std_mat.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
		std_mat.no_depth_test = false
		mat = std_mat

	mesh_inst.material_override = mat

	# Draw wireframe outline on boundary edges only
	var outline := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	outline.mesh = im
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = color
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.no_depth_test = true
	line_mat.render_priority = 3
	im.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	for i in count:
		var p := Vector3i(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2])
		var vc := Vector3(p) + Vector3(0.5, 0.5, 0.5) + face_offset

		var has_neg_a := pos_set.has(p - tangent_a)
		var has_pos_a := pos_set.has(p + tangent_a)
		var has_neg_b := pos_set.has(p - tangent_b)
		var has_pos_b := pos_set.has(p + tangent_b)

		var inset_neg_a := inset if not has_neg_a else 0.0
		var inset_pos_a := inset if not has_pos_a else 0.0
		var inset_neg_b := inset if not has_neg_b else 0.0
		var inset_pos_b := inset if not has_pos_b else 0.0

		var c0 := vc + ta * (-0.5 + inset_neg_a) + tb * (-0.5 + inset_neg_b)
		var c1 := vc + ta * (0.5 - inset_pos_a) + tb * (-0.5 + inset_neg_b)
		var c2 := vc + ta * (0.5 - inset_pos_a) + tb * (0.5 - inset_pos_b)
		var c3 := vc + ta * (-0.5 + inset_neg_a) + tb * (0.5 - inset_pos_b)

		# Only draw edges where the neighbor is missing (boundary)
		if not has_neg_a:
			im.surface_add_vertex(c0); im.surface_add_vertex(c3)
		if not has_pos_a:
			im.surface_add_vertex(c1); im.surface_add_vertex(c2)
		if not has_neg_b:
			im.surface_add_vertex(c0); im.surface_add_vertex(c1)
		if not has_pos_b:
			im.surface_add_vertex(c3); im.surface_add_vertex(c2)
	im.surface_end()
	mesh_inst.add_child(outline)

	return mesh_inst
