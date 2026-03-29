class_name EditorCamera
extends Node3D

## Orbit/pan/zoom camera for the voxel editor.
## Attach a Camera3D as a child — this script controls the pivot.

const ORBIT_SPEED := 0.005
const PAN_SPEED := 0.05
const ZOOM_SPEED := 2.0
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 400.0

var _yaw := -PI / 4.0
var _pitch := PI / 6.0
var _distance := 100.0
var _target := Vector3(64.0, 16.0, 64.0)  # Center of tile at ground level

var _orbiting := false
var _panning := false
var _camera: Camera3D


func _ready() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if not _camera:
		_camera = Camera3D.new()
		_camera.far = 1000.0
		_camera.near = 0.5
		add_child(_camera)
	_update_transform()


func get_camera() -> Camera3D:
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.shift_pressed:
				_panning = mb.pressed
				_orbiting = false
			else:
				_orbiting = mb.pressed
				_panning = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - ZOOM_SPEED * (_distance * 0.1), MIN_DISTANCE)
			_update_transform()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + ZOOM_SPEED * (_distance * 0.1), MAX_DISTANCE)
			_update_transform()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch + mm.relative.y * ORBIT_SPEED, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)
			_update_transform()
			get_viewport().set_input_as_handled()
		elif _panning:
			var right := _camera.global_transform.basis.x
			var up := _camera.global_transform.basis.y
			var pan_scale := _distance * PAN_SPEED * 0.01
			_target -= right * mm.relative.x * pan_scale
			_target += up * mm.relative.y * pan_scale
			_update_transform()
			get_viewport().set_input_as_handled()


func focus_on(pos: Vector3) -> void:
	_target = pos
	_update_transform()


## Snap to a Rift Delver-style isometric view (30° pitch, 45° yaw, perspective).
func set_isometric(target: Vector3, dist: float) -> void:
	_target = target
	_yaw = -PI / 4.0       # 45° — classic isometric corner view
	_pitch = PI / 6.0       # 30° — Rift Delver's top-down-ish angle
	_distance = dist
	_update_transform()


func _update_transform() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance

	global_position = _target + offset
	if _camera:
		_camera.global_position = global_position
		_camera.look_at(_target, Vector3.UP)
