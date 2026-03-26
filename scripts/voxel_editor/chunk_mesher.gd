class_name ChunkMesher
extends RefCounted

## Greedy mesh builder for a 16³ chunk of voxels.
## Produces an ArrayMesh with vertex colors from a VoxelPalette.
## Supports multi-surface output: faces are grouped by shader_material
## so each unique material gets its own mesh surface.

const CHUNK_SIZE := 16


## Build an ArrayMesh for a 16³ region starting at (cx, cy, cz) in chunk coords.
## tile: the WFCTileDef containing voxel data
## palette: VoxelPalette for color lookup
## use_material_colors: if true, color by base_material instead of palette color
## Returns null if the chunk is entirely air.
static func build_mesh(tile: WFCTileDef, palette: VoxelPalette,
		cx: int, cy: int, cz: int,
		use_material_colors: bool = false) -> ArrayMesh:
	# Groups: Dictionary[Material (or null for default), {verts, colors, normals}]
	var groups := {}

	var ox := cx * CHUNK_SIZE
	var oy := cy * CHUNK_SIZE
	var oz := cz * CHUNK_SIZE

	# For each of 6 faces, do greedy meshing
	for axis in 3:
		for dir in 2:
			_greedy_face(tile, palette, ox, oy, oz, axis, dir,
					groups, use_material_colors)

	if groups.is_empty():
		return null

	var mesh := ArrayMesh.new()
	for mat: Variant in groups:
		var g: Dictionary = groups[mat]
		if g.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if mat != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat as Material)

	return mesh if mesh.get_surface_count() > 0 else null


## Build wireframe triangles for exposed voxel edges in a 16³ chunk.
## Uses thin box geometry for visible line thickness.
## Returns null if no edges to draw.
static func build_wireframe(tile: WFCTileDef, cx: int, cy: int, cz: int) -> ArrayMesh:
	var tri_verts := PackedVector3Array()
	var ox := cx * CHUNK_SIZE
	var oy := cy * CHUNK_SIZE
	var oz := cz * CHUNK_SIZE

	for lz in CHUNK_SIZE:
		for ly in CHUNK_SIZE:
			for lx in CHUNK_SIZE:
				var wx := ox + lx
				var wy := oy + ly
				var wz := oz + lz
				var vid := tile.get_voxel(wx, wy, wz)
				if vid == 0:
					continue

				var p := Vector3(float(lx), float(ly), float(lz))

				# +X face
				if tile.get_voxel(wx + 1, wy, wz) == 0:
					_add_face_edges(tri_verts, p + Vector3(1, 0, 0),
						Vector3(0, 1, 0), Vector3(0, 0, 1))
				# -X face
				if tile.get_voxel(wx - 1, wy, wz) == 0:
					_add_face_edges(tri_verts, p,
						Vector3(0, 1, 0), Vector3(0, 0, 1))
				# +Y face
				if tile.get_voxel(wx, wy + 1, wz) == 0:
					_add_face_edges(tri_verts, p + Vector3(0, 1, 0),
						Vector3(1, 0, 0), Vector3(0, 0, 1))
				# -Y face
				if tile.get_voxel(wx, wy - 1, wz) == 0:
					_add_face_edges(tri_verts, p,
						Vector3(1, 0, 0), Vector3(0, 0, 1))
				# +Z face
				if tile.get_voxel(wx, wy, wz + 1) == 0:
					_add_face_edges(tri_verts, p + Vector3(0, 0, 1),
						Vector3(1, 0, 0), Vector3(0, 1, 0))
				# -Z face
				if tile.get_voxel(wx, wy, wz - 1) == 0:
					_add_face_edges(tri_verts, p,
						Vector3(1, 0, 0), Vector3(0, 1, 0))

	if tri_verts.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tri_verts

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


const WIRE_THICKNESS := 0.1  ## Half-thickness of wireframe edges

static func _add_face_edges(verts: PackedVector3Array,
		corner: Vector3, u: Vector3, v: Vector3) -> void:
	var c0 := corner
	var c1 := corner + u
	var c2 := corner + u + v
	var c3 := corner + v
	_add_thick_line(verts, c0, c1, u, v)
	_add_thick_line(verts, c1, c2, u, v)
	_add_thick_line(verts, c2, c3, u, v)
	_add_thick_line(verts, c3, c0, u, v)


static func _add_thick_line(verts: PackedVector3Array,
		a: Vector3, b: Vector3, face_u: Vector3, face_v: Vector3) -> void:
	var t := WIRE_THICKNESS
	# Face normal = cross of face axes, used to offset outward
	var n := face_u.cross(face_v).normalized() * t
	# Edge direction and perpendicular within the face plane
	var edge_dir := (b - a).normalized()
	var perp := n.cross(edge_dir) * t

	# Single quad centered on the edge, no normal offset
	var a0 := a - perp; var a1 := a + perp
	var b0 := b - perp; var b1 := b + perp
	verts.append(a0); verts.append(a1); verts.append(b1)
	verts.append(a0); verts.append(b1); verts.append(b0)


## Get or create a surface group for a given material key.
static func _get_group(groups: Dictionary, mat: Variant) -> Dictionary:
	if not groups.has(mat):
		groups[mat] = {
			"verts": PackedVector3Array(),
			"colors": PackedColorArray(),
			"normals": PackedVector3Array(),
		}
	return groups[mat]


static func _greedy_face(tile: WFCTileDef, palette: VoxelPalette,
		ox: int, oy: int, oz: int,
		axis: int, dir: int,
		groups: Dictionary, use_material_colors: bool) -> void:

	# axis: 0=X, 1=Y, 2=Z
	# dir: 0=negative face, 1=positive face

	var normal := Vector3.ZERO
	normal[axis] = -1.0 + dir * 2.0

	var u_axis: int
	var v_axis: int
	if axis == 0:
		u_axis = 2; v_axis = 1
	elif axis == 1:
		u_axis = 0; v_axis = 2
	else:
		u_axis = 0; v_axis = 1

	for d in CHUNK_SIZE:
		var mask: Array[int] = []
		mask.resize(CHUNK_SIZE * CHUNK_SIZE)
		mask.fill(0)

		for v in CHUNK_SIZE:
			for u in CHUNK_SIZE:
				var wx := ox; var wy := oy; var wz := oz
				if axis == 0:
					wx += d; wz += u; wy += v
				elif axis == 1:
					wy += d; wx += u; wz += v
				else:
					wz += d; wx += u; wy += v

				var voxel := tile.get_voxel(wx, wy, wz)
				if voxel == 0:
					continue

				var nx := wx; var ny := wy; var nz := wz
				if axis == 0:
					nx += (-1 + dir * 2)
				elif axis == 1:
					ny += (-1 + dir * 2)
				else:
					nz += (-1 + dir * 2)

				var neighbor := tile.get_voxel(nx, ny, nz)
				if neighbor == 0:
					mask[u + v * CHUNK_SIZE] = voxel

		# Greedy merge the mask
		for v in CHUNK_SIZE:
			var u := 0
			while u < CHUNK_SIZE:
				var voxel_id := mask[u + v * CHUNK_SIZE]
				if voxel_id == 0:
					u += 1
					continue

				var w := 1
				while u + w < CHUNK_SIZE and mask[u + w + v * CHUNK_SIZE] == voxel_id:
					w += 1

				var h := 1
				var done := false
				while v + h < CHUNK_SIZE and not done:
					for k in w:
						if mask[u + k + (v + h) * CHUNK_SIZE] != voxel_id:
							done = true
							break
					if not done:
						h += 1

				# Resolve color and material for this voxel
				var color: Color
				if use_material_colors:
					color = palette.resolve_material_color(voxel_id)
				else:
					color = palette.resolve_color(voxel_id)

				var mat: Variant = palette.get_entry_material(voxel_id)
				var group := _get_group(groups, mat)

				_emit_quad(group.verts, group.colors, group.normals,
					ox, oy, oz, axis, dir, u_axis, v_axis,
					d, u, v, w, h, normal, color)

				# Clear mask
				for dv in h:
					for du in w:
						mask[u + du + (v + dv) * CHUNK_SIZE] = 0

				u += w


static func _emit_quad(verts: PackedVector3Array, colors: PackedColorArray,
		normals: PackedVector3Array,
		_ox: int, _oy: int, _oz: int,
		axis: int, dir: int, u_axis: int, v_axis: int,
		d: int, u: int, v: int, w: int, h: int,
		normal: Vector3, color: Color) -> void:

	var corners: Array[Vector3] = []
	corners.resize(4)

	for i in 4:
		var corner := Vector3.ZERO
		corner[axis] = float(d + dir)
		var cu: float = float(u + (i & 1) * w)
		var cv: float = float(v + ((i >> 1) & 1) * h)
		corner[u_axis] = cu
		corner[v_axis] = cv
		corners[i] = corner

	var flip: bool = (axis < 2) == (dir == 1)

	if not flip:
		verts.append(corners[0]); verts.append(corners[1]); verts.append(corners[2])
		verts.append(corners[2]); verts.append(corners[1]); verts.append(corners[3])
	else:
		verts.append(corners[0]); verts.append(corners[2]); verts.append(corners[1])
		verts.append(corners[1]); verts.append(corners[2]); verts.append(corners[3])

	for i in 6:
		colors.append(color)
		normals.append(normal)
