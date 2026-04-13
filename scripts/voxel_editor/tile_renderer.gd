class_name TileRenderer
extends Node3D

## Manages chunk MeshInstance3D nodes for rendering a WFCTileDef in the voxel editor.
## Supports variable tile dimensions. Tracks dirty chunks and re-meshes a limited number per frame.
## Provides multiple view modes: Unshaded, Lit, Normals, Material, and Textured.

const CHUNK_SIZE := 16
const REMESH_PER_FRAME := 32

enum ViewMode { UNSHADED, LIT, NORMALS, MATERIAL, TEXTURED }

var _tile: WFCTileDef
var _palette: VoxelPalette
var _mesh_instances: Array[MeshInstance3D] = []
var _wire_instances: Array[MeshInstance3D] = []
var _dirty: Array[bool] = []
var _native: RefCounted  # VoxelEditorNative when available

# Materials for each view mode
var _mat_unshaded: StandardMaterial3D
var _mat_lit: ShaderMaterial
var _mat_normals: ShaderMaterial
var _mat_default_surface: StandardMaterial3D  ## For default surfaces in Textured mode

var _wire_material: StandardMaterial3D

# Dynamic chunk counts based on tile dimensions
var _chunks_x: int = 8
var _chunks_y: int = 7
var _chunks_z: int = 8
var _total_chunks: int = 448

var view_mode: ViewMode = ViewMode.LIT:
	set(value):
		var old := view_mode
		view_mode = value
		_apply_view_mode()
		# Material view uses different vertex colors — requires full remesh
		if old == ViewMode.MATERIAL or value == ViewMode.MATERIAL:
			mark_all_dirty()

var show_wireframe := true:
	set(value):
		show_wireframe = value
		for wi in _wire_instances:
			wi.visible = value
		if value:
			mark_all_dirty()

## Y-slice clipping (0 = no clip, >0 = hide voxels above this Y)
var clip_y: int = 0:
	set(value):
		clip_y = value
		_update_clip()


func _ready() -> void:
	# Unshaded: flat vertex colors, no lighting
	_mat_unshaded = StandardMaterial3D.new()
	_mat_unshaded.vertex_color_use_as_albedo = true
	_mat_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_unshaded.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Lit: vertex colors with per-pixel shading, double-sided with correct normals
	var lit_shader := Shader.new()
	lit_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 vtx_color;
varying vec3 world_normal;

void vertex() {
	vtx_color = COLOR.rgb;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 light_dir = normalize(vec3(0.4, 0.7, 0.5));
	float ndl = dot(normalize(world_normal), light_dir);
	// Half-lambert: wraps lighting so back faces get ~0.25 instead of 0
	float shade = ndl * 0.5 + 0.5;
	shade = shade * 0.6 + 0.4; // remap to 0.4..1.0 range
	ALBEDO = vtx_color * shade;
}
"""
	_mat_lit = ShaderMaterial.new()
	_mat_lit.shader = lit_shader

	# Normals: debug view showing face normals as RGB
	_mat_normals = ShaderMaterial.new()
	var normals_shader := Shader.new()
	normals_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

void fragment() {
	ALBEDO = NORMAL * 0.5 + 0.5;
}
"""
	_mat_normals.shader = normals_shader

	# Default surface material for Textured mode (entries without custom materials)
	_mat_default_surface = StandardMaterial3D.new()
	_mat_default_surface.vertex_color_use_as_albedo = true
	_mat_default_surface.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mat_default_surface.cull_mode = BaseMaterial3D.CULL_BACK

	# Wireframe overlay
	_wire_material = StandardMaterial3D.new()
	_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_material.albedo_color = Color(0.0, 0.0, 0.0, 0.35)
	_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wire_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wire_material.render_priority = 2

	if ClassDB.class_exists(&"VoxelEditorNative"):
		_native = ClassDB.instantiate(&"VoxelEditorNative")
		VoxelRaycast.native = _native
		VoxelQuery.native = _native

	_rebuild_chunk_nodes()


func set_tile(tile: WFCTileDef, palette: VoxelPalette) -> void:
	_tile = tile
	_palette = palette
	_update_chunk_layout()
	_apply_view_mode()
	mark_all_dirty()


func get_tile() -> WFCTileDef:
	return _tile


func get_palette() -> VoxelPalette:
	return _palette


## Recalculate chunk counts from tile dimensions and rebuild nodes if needed.
func _update_chunk_layout() -> void:
	if not _tile:
		return
	var cx: int = ceili(float(_tile.tile_size_x) / CHUNK_SIZE)
	var cy: int = ceili(float(_tile.tile_size_y) / CHUNK_SIZE)
	var cz: int = ceili(float(_tile.tile_size_z) / CHUNK_SIZE)
	if cx == _chunks_x and cy == _chunks_y and cz == _chunks_z:
		return
	_chunks_x = cx
	_chunks_y = cy
	_chunks_z = cz
	_total_chunks = cx * cy * cz
	_rebuild_chunk_nodes()


## Remove all chunk nodes and recreate for current chunk counts.
func _rebuild_chunk_nodes() -> void:
	for mi in _mesh_instances:
		mi.queue_free()
	for wi in _wire_instances:
		wi.queue_free()
	_mesh_instances.clear()
	_wire_instances.clear()
	_dirty.clear()

	_mesh_instances.resize(_total_chunks)
	_wire_instances.resize(_total_chunks)
	_dirty.resize(_total_chunks)
	_dirty.fill(false)

	for i in _total_chunks:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mesh_instances[i] = mi

		var wi := MeshInstance3D.new()
		wi.material_override = _wire_material
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wi)
		_wire_instances[i] = wi

	_apply_view_mode()


## Apply the current view mode's material to all mesh instances.
func _apply_view_mode() -> void:
	var has_custom := _palette and _palette.has_any_custom_materials()

	for mi in _mesh_instances:
		if has_custom:
			# Custom shader materials are set per-surface by the mesher.
			# material_override would stomp them, so leave it null.
			mi.material_override = null
			if mi.mesh:
				_apply_surface_materials(mi.mesh)
		else:
			var override_mat: Material = null
			match view_mode:
				ViewMode.UNSHADED:
					override_mat = _mat_unshaded
				ViewMode.LIT:
					override_mat = _mat_lit
				ViewMode.NORMALS:
					override_mat = _mat_normals
				ViewMode.MATERIAL:
					override_mat = _mat_unshaded
				ViewMode.TEXTURED:
					override_mat = null
			mi.material_override = override_mat
			if view_mode == ViewMode.TEXTURED and mi.mesh:
				_apply_default_surface_materials(mi.mesh)


## Set the default lit material on mesh surfaces that have no custom material.
func _apply_default_surface_materials(mesh: ArrayMesh) -> void:
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) == null:
			mesh.surface_set_material(s, _mat_default_surface)


## Apply per-surface materials: keep custom shader materials, apply the current
## view mode's base material to surfaces that have none.
func _apply_surface_materials(mesh: ArrayMesh) -> void:
	var base_mat: Material
	match view_mode:
		ViewMode.UNSHADED, ViewMode.MATERIAL:
			base_mat = _mat_unshaded
		ViewMode.LIT:
			base_mat = _mat_lit
		ViewMode.NORMALS:
			base_mat = _mat_normals
		ViewMode.TEXTURED:
			base_mat = _mat_default_surface
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) == null:
			mesh.surface_set_material(s, base_mat)


## Mark a specific chunk dirty by chunk coordinates.
func mark_chunk_dirty(cx: int, cy: int, cz: int) -> void:
	if cx < 0 or cx >= _chunks_x or cy < 0 or cy >= _chunks_y or cz < 0 or cz >= _chunks_z:
		return
	_dirty[cx + cy * _chunks_x + cz * _chunks_x * _chunks_y] = true


## Mark a chunk dirty by flat index (used by native bulk_set_voxels).
func mark_chunk_dirty_by_index(idx: int) -> void:
	if idx >= 0 and idx < _dirty.size():
		_dirty[idx] = true


## Mark the chunk containing voxel (vx, vy, vz) as dirty, plus neighbors if on boundary.
func mark_voxel_dirty(vx: int, vy: int, vz: int) -> void:
	var cx := vx >> 4
	var cy := vy >> 4
	var cz := vz >> 4
	mark_chunk_dirty(cx, cy, cz)

	if vx & 0xF == 0:
		mark_chunk_dirty(cx - 1, cy, cz)
	elif vx & 0xF == 15:
		mark_chunk_dirty(cx + 1, cy, cz)
	if vy & 0xF == 0:
		mark_chunk_dirty(cx, cy - 1, cz)
	elif vy & 0xF == 15:
		mark_chunk_dirty(cx, cy + 1, cz)
	if vz & 0xF == 0:
		mark_chunk_dirty(cx, cy, cz - 1)
	elif vz & 0xF == 15:
		mark_chunk_dirty(cx, cy, cz + 1)


## Mark all chunks as needing re-mesh.
func mark_all_dirty() -> void:
	_dirty.fill(true)


func _process(_delta: float) -> void:
	if not _tile or not _palette:
		return
	_remesh_dirty()


func _remesh_dirty() -> void:
	var use_material_colors := view_mode == ViewMode.MATERIAL
	var has_custom := _palette and _palette.has_any_custom_materials()
	var count := 0
	for i in _total_chunks:
		if count >= REMESH_PER_FRAME:
			break
		if not _dirty[i]:
			continue
		_dirty[i] = false
		count += 1

		var cx := i % _chunks_x
		var cy := (i / _chunks_x) % _chunks_y
		var cz := i / (_chunks_x * _chunks_y)

		var chunk_pos := Vector3(cx, cy, cz) * CHUNK_SIZE
		var mesh: ArrayMesh
		if has_custom or use_material_colors:
			# GDScript mesher groups faces by shader_material into separate surfaces
			mesh = ChunkMesher.build_mesh(_tile, _palette, cx, cy, cz,
					use_material_colors)
		elif _native:
			mesh = _native.build_chunk_mesh(_tile.voxel_data, cx, cy, cz,
					_palette.get_color_table(),
					_tile.tile_size_x, _tile.tile_size_y, _tile.tile_size_z)
		else:
			mesh = ChunkMesher.build_mesh(_tile, _palette, cx, cy, cz, false)
		_mesh_instances[i].mesh = mesh
		_mesh_instances[i].position = chunk_pos

		if mesh and has_custom:
			_apply_surface_materials(mesh)
		elif mesh and view_mode == ViewMode.TEXTURED:
			_apply_default_surface_materials(mesh)

		if show_wireframe:
			var wire: ArrayMesh = ChunkMesher.build_wireframe(_tile, cx, cy, cz)
			_wire_instances[i].mesh = wire
			_wire_instances[i].position = chunk_pos
		else:
			_wire_instances[i].mesh = null


func _update_clip() -> void:
	if clip_y <= 0:
		for mi in _mesh_instances:
			mi.visible = true
		for wi in _wire_instances:
			wi.visible = show_wireframe
		return

	for i in _total_chunks:
		var cy := (i / _chunks_x) % _chunks_y
		var chunk_min_y := cy * CHUNK_SIZE
		var vis := chunk_min_y < clip_y
		_mesh_instances[i].visible = vis
		_wire_instances[i].visible = vis and show_wireframe
