extends Camera3D

@export var target_path: NodePath
@export var offset := Vector3(10.0, 14.0, 10.0)

var _target: Node3D

func _ready() -> void:
	if target_path:
		_target = get_node(target_path)

func _process(_delta: float) -> void:
	if _target:
		global_position = _target.global_position + offset
		look_at(_target.global_position, Vector3.UP)
