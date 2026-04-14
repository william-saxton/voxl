class_name SelectionRenderer
extends Node3D

## Renders selected voxels as a per-voxel shell: only faces between a selected
## voxel and an unselected neighbor are drawn, so interior holes (e.g. from
## alt-deselect) are visible as indentations in the surface.

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
	_build_surface_mesh(positions)

## Build a shell mesh around selected voxels: only faces between a selected
## voxel and an unselected neighbor are drawn. This makes interior gaps
## (from alt-deselect) visible as indentations in the surface.
func _build_surface_mesh(positions: Array[Vector3i]) -> void:
	var pos_set := {}
	for p in positions:
		pos_set[p] = true

	var edge_mesh := ImmediateMesh.new()
	var fill_mesh := ImmediateMesh.new()
	edge_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	edge_mesh.surface_set_color(EDGE_COLOR)
	fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	fill_mesh.surface_set_color(FILL_COLOR)

	for p in positions:
		for i in 6:
			var offset: Vector3i = NEIGHBORS_6[i]
			if pos_set.has(p + offset):
				continue
			_add_boundary_face(edge_mesh, fill_mesh, p, offset)

	edge_mesh.surface_end()
	fill_mesh.surface_end()
	edge_mesh.surface_set_material(0, _edge_material)
	fill_mesh.surface_set_material(0, _fill_material)
	_edge_instance.mesh = edge_mesh
	_fill_instance.mesh = fill_mesh

## Emit triangles (fill) and line segments (edges) for the cube face of
## voxel `p` that points along `normal` (one of the 6 unit offsets).
func _add_boundary_face(edge_mesh: ImmediateMesh, fill_mesh: ImmediateMesh,
		p: Vector3i, normal: Vector3i) -> void:
	var base := Vector3(p)
	# Determine the four corners of the face based on normal direction
	var corners: Array
	match normal:
		Vector3i(1, 0, 0):  # +X
			corners = [
				base + Vector3(1, 0, 0), base + Vector3(1, 1, 0),
				base + Vector3(1, 1, 1), base + Vector3(1, 0, 1),
			]
		Vector3i(-1, 0, 0):  # -X
			corners = [
				base + Vector3(0, 0, 1), base + Vector3(0, 1, 1),
				base + Vector3(0, 1, 0), base + Vector3(0, 0, 0),
			]
		Vector3i(0, 1, 0):  # +Y
			corners = [
				base + Vector3(0, 1, 0), base + Vector3(0, 1, 1),
				base + Vector3(1, 1, 1), base + Vector3(1, 1, 0),
			]
		Vector3i(0, -1, 0):  # -Y
			corners = [
				base + Vector3(0, 0, 0), base + Vector3(1, 0, 0),
				base + Vector3(1, 0, 1), base + Vector3(0, 0, 1),
			]
		Vector3i(0, 0, 1):  # +Z
			corners = [
				base + Vector3(1, 0, 1), base + Vector3(1, 1, 1),
				base + Vector3(0, 1, 1), base + Vector3(0, 0, 1),
			]
		_:  # -Z
			corners = [
				base + Vector3(0, 0, 0), base + Vector3(0, 1, 0),
				base + Vector3(1, 1, 0), base + Vector3(1, 0, 0),
			]

	var c0: Vector3 = corners[0]
	var c1: Vector3 = corners[1]
	var c2: Vector3 = corners[2]
	var c3: Vector3 = corners[3]

	fill_mesh.surface_add_vertex(c0)
	fill_mesh.surface_add_vertex(c1)
	fill_mesh.surface_add_vertex(c2)
	fill_mesh.surface_add_vertex(c0)
	fill_mesh.surface_add_vertex(c2)
	fill_mesh.surface_add_vertex(c3)

	edge_mesh.surface_add_vertex(c0)
	edge_mesh.surface_add_vertex(c1)
	edge_mesh.surface_add_vertex(c1)
	edge_mesh.surface_add_vertex(c2)
	edge_mesh.surface_add_vertex(c2)
	edge_mesh.surface_add_vertex(c3)
	edge_mesh.surface_add_vertex(c3)
	edge_mesh.surface_add_vertex(c0)

func clear() -> void:
	_edge_instance.mesh = null
	_fill_instance.mesh = null

