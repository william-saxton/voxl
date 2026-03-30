class_name ProceduralTool
extends RefCounted

## Executes a GDScript expression over a voxel region to generate/modify voxels.
## The expression receives (x, y, z, current, sx, sy, sz) and returns a voxel ID.
## Returning -1 or the current value means "no change".
##
## Built-in variables available in the expression:
##   x, y, z     — voxel position (int)
##   current     — current voxel ID at this position (int)
##   sx, sy, sz  — region size (int)
##   cx, cy, cz  — region center (float)
##   nx, ny, nz  — normalized position 0..1 (float)
##   PI, TAU     — math constants

## Built-in presets
const PRESETS := {
	"Sphere": {
		"code": "var r = min(sx, min(sy, sz)) * 0.5\nvar d = sqrt((x-cx)*(x-cx) + (y-cy)*(y-cy) + (z-cz)*(z-cz))\nreturn vid if d <= r else -1",
		"description": "Solid sphere filling the region",
	},
	"Hollow Sphere": {
		"code": "var r = min(sx, min(sy, sz)) * 0.5\nvar d = sqrt((x-cx)*(x-cx) + (y-cy)*(y-cy) + (z-cz)*(z-cz))\nreturn vid if d <= r and d >= r - 1.5 else -1",
		"description": "Hollow sphere shell",
	},
	"Cylinder (Y)": {
		"code": "var r = min(sx, sz) * 0.5\nvar d = sqrt((x-cx)*(x-cx) + (z-cz)*(z-cz))\nreturn vid if d <= r else -1",
		"description": "Vertical cylinder",
	},
	"Torus (Y)": {
		"code": "var R = min(sx, sz) * 0.35\nvar r = min(sx, sz) * 0.15\nvar ring = sqrt((x-cx)*(x-cx) + (z-cz)*(z-cz))\nvar d = sqrt((ring - R)*(ring - R) + (y-cy)*(y-cy))\nreturn vid if d <= r else -1",
		"description": "Torus ring — major radius 35%, minor radius 15% of region",
	},
	"Arch (Z)": {
		"code": "var R = min(sx, sy) * 0.4\nvar r = min(sx, sy) * 0.12\nvar arch_x = x - cx\nvar arch_y = y - float(oy)\nvar ring = sqrt(arch_x*arch_x + arch_y*arch_y)\nvar d = sqrt((ring - R)*(ring - R) + (z-cz)*(z-cz))\nreturn vid if d <= r and arch_y >= 0 else -1",
		"description": "Half-torus arch spanning Z, sitting on the floor of the region",
	},
	"Dome": {
		"code": "var r = min(sx, min(sy*2, sz)) * 0.5\nvar d = sqrt((x-cx)*(x-cx) + (y-float(oy))*(y-float(oy)) + (z-cz)*(z-cz))\nreturn vid if d <= r and y >= oy else -1",
		"description": "Upper hemisphere sitting on the floor of the region",
	},
	"Noise Terrain": {
		"code": "var h = sy * 0.3 + sy * 0.3 * sin(x * 0.15) * cos(z * 0.15) + sy * 0.15 * sin(x * 0.3 + 1.7) * cos(z * 0.25 + 0.8)\nreturn vid if y < oy + h else -1",
		"description": "Hilly terrain using layered sine waves",
	},
	"Pyramid": {
		"code": "var layer = y - oy\nvar half_x = (sx - 1.0) / 2.0 - layer\nvar half_z = (sz - 1.0) / 2.0 - layer\nreturn vid if half_x >= 0 and half_z >= 0 and abs(x - cx) <= half_x and abs(z - cz) <= half_z else -1",
		"description": "Stepped pyramid",
	},
	"Cone (Y)": {
		"code": "var progress = float(y - oy) / max(sy - 1, 1)\nvar r = (1.0 - progress) * min(sx, sz) * 0.5\nvar d = sqrt((x-cx)*(x-cx) + (z-cz)*(z-cz))\nreturn vid if d <= r else -1",
		"description": "Cone tapering upward",
	},
	"Stairs (Z)": {
		"code": "var step_depth = max(sz / 8, 1)\nvar step_idx = int(z - oz) / step_depth\nvar step_height = step_idx + 1\nreturn vid if (y - oy) < step_height else -1",
		"description": "Staircase ascending along Z",
	},
	"Spiral (Y)": {
		"code": "var progress = float(y - oy) / max(sy - 1, 1)\nvar angle = progress * TAU * 3\nvar r = min(sx, sz) * 0.4\nvar cx2 = cx + cos(angle) * r * 0.5\nvar cz2 = cz + sin(angle) * r * 0.5\nvar d = sqrt((x-cx2)*(x-cx2) + (z-cz2)*(z-cz2))\nreturn vid if d <= r * 0.25 else -1",
		"description": "Spiral column rising along Y",
	},
	"Checkerboard": {
		"code": "return vid if (int(x) + int(y) + int(z)) % 2 == 0 else -1",
		"description": "3D checkerboard pattern",
	},
	"Clear": {
		"code": "return 0",
		"description": "Set all voxels to air",
	},
}


## Execute a procedural expression over a region.
## Returns a Dictionary of { Vector3i -> int } with new voxel IDs, or null on error.
## origin: bottom-corner of the region. size: region dimensions.
## vid: voxel ID to place. code: GDScript expression string.
static func execute(tile: WFCTileDef, origin: Vector3i, region_size: Vector3i,
		vid: int, code: String) -> Variant:
	# Build a GDScript class at runtime that contains the user's function
	var script_text := _build_script(code)

	var script := GDScript.new()
	script.source_code = script_text
	var err := script.reload()
	if err != OK:
		return "Compile error: check syntax"

	var runner: RefCounted = script.new()
	if not runner.has_method("run"):
		return "Expression must contain a 'return' statement"

	var result: Dictionary = {}  # Vector3i -> int
	var ox := origin.x
	var oy := origin.y
	var oz := origin.z
	var sx := region_size.x
	var sy := region_size.y
	var sz := region_size.z
	var cx := ox + sx * 0.5
	var cy := oy + sy * 0.5
	var cz := oz + sz * 0.5

	for lz in sz:
		for ly in sy:
			for lx in sx:
				var wx := ox + lx
				var wy := oy + ly
				var wz := oz + lz
				if wx < 0 or wx >= tile.tile_size_x or \
						wy < 0 or wy >= tile.tile_size_y or \
						wz < 0 or wz >= tile.tile_size_z:
					continue
				var current := tile.get_voxel(wx, wy, wz)
				var nx := float(lx) / maxf(sx - 1, 1)
				var ny := float(ly) / maxf(sy - 1, 1)
				var nz := float(lz) / maxf(sz - 1, 1)

				var v: Variant = runner.call("run",
					wx, wy, wz, current, sx, sy, sz,
					cx, cy, cz, nx, ny, nz, vid, ox, oy, oz)

				if v is int and v != -1 and v != current:
					result[Vector3i(wx, wy, wz)] = v

	return result


static func _build_script(code: String) -> String:
	# Wrap user code in a function with all the standard variables as parameters
	return """extends RefCounted

@warning_ignore("unused_parameter")
func run(x: int, y: int, z: int, current: int, sx: int, sy: int, sz: int,
		cx: float, cy: float, cz: float, nx: float, ny: float, nz: float,
		vid: int, ox: int, oy: int, oz: int) -> int:
	%s
""" % _indent_code(code)


static func _indent_code(code: String) -> String:
	var lines := code.split("\n")
	var result := ""
	for i in lines.size():
		if i == 0:
			result += lines[i]
		else:
			result += "\n\t" + lines[i]
	return result
