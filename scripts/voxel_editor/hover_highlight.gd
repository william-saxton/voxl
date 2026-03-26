class_name HoverHighlight
extends MeshInstance3D

## Transparent filled cube that follows the cursor position in the voxel editor.
## Color changes based on the active tool mode:
##   ADD = blue, SUBTRACT = red, PAINT = palette color.

var _current_pos := Vector3i(-1, -1, -1)
var _material: StandardMaterial3D

const COLOR_ADD := Color(0.3, 0.5, 1.0, 0.35)
const COLOR_SUBTRACT := Color(1.0, 0.25, 0.25, 0.35)
const COLOR_PAINT := Color(0.3, 1.0, 0.3, 0.35)


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR_ADD
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true

	var cube := BoxMesh.new()
	cube.size = Vector3(1.01, 1.01, 1.01)
	cube.material = _material
	mesh = cube

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func set_voxel_pos(pos: Vector3i) -> void:
	if pos == _current_pos:
		return
	_current_pos = pos
	# Offset by 0.5 so the cube is centered on the voxel
	position = Vector3(pos) + Vector3(0.5, 0.5, 0.5)


## Set the highlight color based on primary mode.
## 0 = ADD (blue), 1 = SUBTRACT (red), 2 = PAINT (green / custom).
func set_mode_color(mode: int, custom_color: Color = Color.TRANSPARENT) -> void:
	match mode:
		0: _material.albedo_color = COLOR_ADD
		1: _material.albedo_color = COLOR_SUBTRACT
		2:
			if custom_color.a > 0.0:
				_material.albedo_color = Color(custom_color, 0.4)
			else:
				_material.albedo_color = COLOR_PAINT
		_: _material.albedo_color = COLOR_ADD
