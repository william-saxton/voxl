class_name PaletteEntry
extends Resource

@export var entry_name: String = ""
@export var color: Color = Color.WHITE
@export var base_material: int = MaterialRegistry.STONE
@export var shader_material: Material  ## Optional Godot material for lit rendering
