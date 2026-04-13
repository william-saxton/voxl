class_name SelectionRenderer
extends Node3D

## Renders selected voxels as wireframe bounding boxes with translucent fill
## around connected clusters. Separate groups get their own box.

const EDGE_COLOR := Color(0.2, 0.5, 1.0, 0.8)
const FILL_COLOR := Color(0.2, 0.5, 1.0, 0.3)

const NEIGHBORS_6: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var _edge_instance: MeshInstance3D
var _fill_instance: MeshInstance3D
var _edge_material: StandardMaterial3D
var _fill_material: StandardMaterial3D


func _ready() -> void:
	_edge_material = StandardMaterial3D.new()
	_edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_material.albedo_color = EDGE_COLOR
	_edge_material.no_depth_test = true
	_edge_material.render_priority = 10
	_edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.albedo_color = FILL_COLOR
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill_material.no_depth_test = true
	_fill_material.render_priority = 9
	_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_edge_instance = MeshInstance3D.new()
	_edge_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge_instance)

	_fill_instance = MeshInstance3D.new()
	_fill_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill_instance)


func update_selection(selection: VoxelSelection) -> void:
	if selection.is_empty():
		clear()
		return

	var positions := selection.get_positions()
	var clusters := _find_clusters(positions)
	_build_mesh(clusters)


func clear() -> void:
	_edge_instance.mesh = null
	_fill_instance.mesh = null


## Group positions into connected clusters using BFS.
func _find_clusters(positions: Array[Vector3i]) -> Array[AABB]:
	var pos_set := {}
	for p in positions:
		pos_set[p] = true

	var visited := {}
	var clusters: Array[AABB] = []

	for p in positions:
		if visited.has(p):
			continue
		var min_p := p
		var max_p := p
		var queue: Array[Vector3i] = [p]
		visited[p] = true

		while not queue.is_empty():
			var cur: Vector3i = queue.pop_front()
			min_p = Vector3i(mini(min_p.x, cur.x), mini(min_p.y, cur.y), mini(min_p.z, cur.z))
			max_p = Vector3i(maxi(max_p.x, cur.x), maxi(max_p.y, cur.y), maxi(max_p.z, cur.z))

			for offset in NEIGHBORS_6:
				var neighbor := cur + offset
				if not visited.has(neighbor) and pos_set.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)

		clusters.append(AABB(
			Vector3(min_p),
			Vector3(max_p - min_p + Vector3i.ONE)))

	return clusters


func _build_mesh(clusters: Array[AABB]) -> void:
	var edge_mesh := ImmediateMesh.new()
	var fill_mesh := ImmediateMesh.new()

	for aabb in clusters:
		_add_box_edges(edge_mesh, aabb)
		_add_box_faces(fill_mesh, aabb)

	edge_mesh.surface_set_material(0, _edge_material)
	fill_mesh.surface_set_material(0, _fill_material)
	_edge_instance.mesh = edge_mesh
	_fill_instance.mesh = fill_mesh


func _add_box_edges(im: ImmediateMesh, aabb: AABB) -> void:
	var a := aabb.position
	var b := aabb.position + aabb.size

	var c := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z),
		Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]

	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(EDGE_COLOR)
	for edge in edges:
		im.surface_add_vertex(c[edge[0]])
		im.surface_add_vertex(c[edge[1]])
	im.surface_end()


func _add_box_faces(im: ImmediateMesh, aabb: AABB) -> void:
	var a := aabb.position
	var b := aabb.position + aabb.size

	var c := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z),
		Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]

	# 6 faces, each as 2 triangles
	var faces := [
		[0, 1, 2, 0, 2, 3],  # bottom (-Y)
		[4, 6, 5, 4, 7, 6],  # top (+Y)
		[0, 4, 5, 0, 5, 1],  # front (-Z)
		[2, 6, 7, 2, 7, 3],  # back (+Z)
		[0, 3, 7, 0, 7, 4],  # left (-X)
		[1, 5, 6, 1, 6, 2],  # right (+X)
	]

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(FILL_COLOR)
	for face in faces:
		for idx in face:
			im.surface_add_vertex(c[idx])
	im.surface_end()
