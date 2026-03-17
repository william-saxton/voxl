class_name StressTestHUD
extends Label

var _material_sim: MaterialSimulatorNative


func initialize(material_sim: MaterialSimulatorNative) -> void:
	_material_sim = material_sim


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 8.0
	offset_top = 8.0
	offset_right = 400.0
	offset_bottom = 140.0

	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_shadow_color", Color.BLACK)
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	visible = false


func _process(_delta: float) -> void:
	if not visible or not _material_sim:
		return

	var fps := Engine.get_frames_per_second()
	var active := _material_sim.get_active_cell_count()
	var sources := _material_sim.get_source_block_count()
	var tick_ms := _material_sim.get_last_tick_ms()
	var changes := _material_sim.get_last_changes_count()

	text = "FPS: %d\nActive Cells: %d\nSource Blocks: %d\nTick: %.2f ms\nChanges/Tick: %d" % [
		fps, active, sources, tick_ms, changes
	]
