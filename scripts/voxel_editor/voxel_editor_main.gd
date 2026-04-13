class_name VoxelEditorMain
extends Control

## Root controller for the standalone voxel editor.
## Manages file I/O, coordinates sub-systems, and provides the UI shell.
## Layout: top menu + context bar, left sidebar tools, center viewport,
## right palette + properties, bottom controls + status.

# ── Theme colors (Material Design 3 dark, seed #7b4afd) ──
const COLOR_BG := Color(0.11, 0.105, 0.122)           # #1c1a1f
const COLOR_SURFACE := Color(0.13, 0.122, 0.148)       # #211f26
const COLOR_SURFACE_BRIGHT := Color(0.17, 0.16, 0.19)  # #2b2930
const COLOR_PRIMARY := Color(0.49, 0.298, 1.0)         # #7d4cff
const COLOR_ON_PRIMARY := Color(1, 1, 1)
const COLOR_ON_SURFACE := Color(0.9, 0.88, 0.9)        # #e6e0e6
const COLOR_ON_SURFACE_DIM := Color(0.62, 0.60, 0.64)  # #9e99a3
const COLOR_OUTLINE := Color(0.23, 0.21, 0.25)         # #3a3640

# ── Data ──
var _tile: WFCTileDef
var _palette: VoxelPalette
var _palette_set: TilePaletteSet

# ── Scene tree references ──
var _viewport: SubViewport
var _camera_pivot: EditorCamera
var _tile_renderer: TileRenderer
var _editor_grid: EditorGrid
var _highlight: HoverHighlight
var _tool_manager: EditorToolManager
var _viewport_container: SubViewportContainer
var _metadata_tool: MetadataTool
var _metadata_dialog: MetadataEditDialog
var _export_dialog: TileExportDialog

# ── Right panel components ──
var _palette_panel: PalettePanel
var _palette_editor: PaletteEditorPanel
var _gradient_panel: PanelContainer  ## GradientSelectionPanel
var _settings_dialog: AcceptDialog
var _right_vbox: VBoxContainer
var _custom_planes_list: ItemList

# ── Left sidebar ──
var _main_tool_group: ButtonGroup
var _btn_add: Button
var _btn_subtract: Button
var _btn_paint: Button
var _btn_select: Button
var _btn_spawns: Button

# ── Transform bar (right of viewport) ──
var _transform_bar: PanelContainer
var _sub_tools_vbox: VBoxContainer
var _sub_tool_buttons: Array[Button] = []
var _btn_sym_x: Button
var _btn_sym_y: Button
var _btn_sym_z: Button

# ── Context bar ──
var _context_hbox: HBoxContainer
var _context_label: Label
var _hollow_check: CheckBox
var _polygon_sides_spin: SpinBox
var _brush_size_spin: SpinBox
var _brush_flat_check: CheckBox
var _chk_face: CheckBox
var _chk_color: CheckBox
var _chk_material: CheckBox
var _range_slider: HSlider
var _wrap_check: CheckBox

# ── Select sub-tool context controls ──
var _select_criteria_group: ButtonGroup
var _btn_geo: Button
var _btn_mat: Button
var _btn_col: Button
var _select_brush_size_label: Label
var _select_brush_size_spin: SpinBox

# ── Snap controls ──
var _snap_option: OptionButton
var _snap_mode_option: OptionButton

# ── Procedural shader controls ──
var _proc_sep: VSeparator
var _proc_label: Label
var _proc_preset_option: OptionButton
var _proc_edit_btn: Button

# ── Bottom bar ──
var _status_label: Label
var _stats_label: Label
var _y_slice_slider: HSlider
var _y_slice_label: Label

# ── State ──
var _ui_scale: float = 1.0

# ── Procedural shader dialog ──
var _shader_dialog: AcceptDialog  # ShaderEditorDialog

# ── File dialogs ──
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _import_palette_dialog: FileDialog
var _export_palette_dialog: FileDialog
var _import_scene_dialog: FileDialog

# ── Remote sync dialogs ──
var _sync_config_dialog: SyncConfigDialog
var _remote_browser: RemoteBrowserDialog
var _remote_status_label: Label


func _ready() -> void:
	# Grab scene nodes
	_viewport = %EditorViewport
	_camera_pivot = %CameraPivot
	_tile_renderer = %TileRenderer
	_editor_grid = %EditorGrid
	_highlight = %HoverHighlight
	_viewport_container = %ViewportContainer

	_apply_theme()
	_setup_file_dialogs()
	_setup_menu()
	_setup_tools()
	_setup_context_bar()
	_setup_left_sidebar()
	_setup_transform_bar()
	_setup_right_panel()
	_tool_manager.gradient_panel = _gradient_panel
	_setup_bottom_bar()
	_setup_tile_properties()
	_setup_metadata()
	_setup_export()
	_setup_remote()

	new_tile()
	_update_status("Ready")


# ══════════════════════════════════════════════════════════════════════════════
# Theme
# ══════════════════════════════════════════════════════════════════════════════

func _get_icon(icon_name: String) -> Texture2D:
	if theme and theme.has_icon(icon_name, "VoxlIcons"):
		return theme.get_icon(icon_name, "VoxlIcons")
	return null


func _apply_theme() -> void:
	# Root background
	var root_style := StyleBoxFlat.new()
	root_style.bg_color = COLOR_BG
	add_theme_stylebox_override("panel", root_style)

	# Left sidebar
	var sidebar: PanelContainer = %LeftSidebar
	var sidebar_style := StyleBoxFlat.new()
	sidebar_style.bg_color = COLOR_SURFACE
	sidebar_style.border_width_right = 1
	sidebar_style.border_color = COLOR_OUTLINE
	sidebar.add_theme_stylebox_override("panel", sidebar_style)

	# Right panel
	var right: PanelContainer = %RightPanel
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = COLOR_SURFACE
	right_style.border_width_left = 1
	right_style.border_color = COLOR_OUTLINE
	right.add_theme_stylebox_override("panel", right_style)

	# Context bar
	var ctx: PanelContainer = %ContextBar
	var ctx_style := StyleBoxFlat.new()
	ctx_style.bg_color = COLOR_SURFACE_BRIGHT
	ctx_style.border_width_bottom = 1
	ctx_style.border_color = COLOR_OUTLINE
	ctx.add_theme_stylebox_override("panel", ctx_style)

	# Controls bar
	var ctrl: PanelContainer = %ControlsBar
	var ctrl_style := StyleBoxFlat.new()
	ctrl_style.bg_color = COLOR_SURFACE_BRIGHT
	ctrl_style.border_width_top = 1
	ctrl_style.border_color = COLOR_OUTLINE
	ctrl.add_theme_stylebox_override("panel", ctrl_style)

	# Status bar
	var status: PanelContainer = %StatusBar
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = COLOR_BG
	status.add_theme_stylebox_override("panel", status_style)



# ══════════════════════════════════════════════════════════════════════════════
# File Dialogs
# ══════════════════════════════════════════════════════════════════════════════

func _setup_file_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_RESOURCES
	_open_dialog.filters = PackedStringArray(["*.tres ; Tile Resource", "*.res ; Tile Resource"])
	_open_dialog.title = "Open WFC Tile"
	_open_dialog.file_selected.connect(_on_open_file)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.filters = PackedStringArray(["*.tres ; Tile Resource"])
	_save_dialog.title = "Save WFC Tile"
	_save_dialog.file_selected.connect(_on_save_file)
	add_child(_save_dialog)

	_import_palette_dialog = FileDialog.new()
	_import_palette_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_palette_dialog.access = FileDialog.ACCESS_RESOURCES
	_import_palette_dialog.filters = PackedStringArray(["*.tres ; Palette Resource"])
	_import_palette_dialog.title = "Import Palette"
	_import_palette_dialog.file_selected.connect(_on_import_palette)
	add_child(_import_palette_dialog)

	_export_palette_dialog = FileDialog.new()
	_export_palette_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_palette_dialog.access = FileDialog.ACCESS_RESOURCES
	_export_palette_dialog.filters = PackedStringArray(["*.tres ; Palette Resource"])
	_export_palette_dialog.title = "Export Palette"
	_export_palette_dialog.file_selected.connect(_on_export_palette)
	add_child(_export_palette_dialog)

	_import_scene_dialog = FileDialog.new()
	_import_scene_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_scene_dialog.access = FileDialog.ACCESS_RESOURCES
	_import_scene_dialog.filters = PackedStringArray(["*.tres ; Tile Resource", "*.res ; Tile Resource"])
	_import_scene_dialog.title = "Import Scene Into Tile"
	_import_scene_dialog.file_selected.connect(_on_import_scene)
	add_child(_import_scene_dialog)


# ══════════════════════════════════════════════════════════════════════════════
# Menu Bar
# ══════════════════════════════════════════════════════════════════════════════

func _setup_menu() -> void:
	var menu_bar: MenuBar = %MenuBar
	if not menu_bar:
		return

	# FILE
	var file_menu := PopupMenu.new()
	file_menu.name = "File"
	file_menu.add_item("New Tile", 0, KEY_MASK_CTRL | KEY_N)
	file_menu.add_item("Open Tile...", 1, KEY_MASK_CTRL | KEY_O)
	file_menu.add_separator()
	file_menu.add_item("Save Tile", 2, KEY_MASK_CTRL | KEY_S)
	file_menu.add_item("Save Tile As...", 3, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	file_menu.add_separator()
	file_menu.add_item("Export Tile...", 5)
	file_menu.add_separator()
	file_menu.add_item("Import Scene...", 12)
	file_menu.add_separator()
	file_menu.add_item("Import Palette...", 10)
	file_menu.add_item("Export Palette...", 11)
	file_menu.id_pressed.connect(_on_file_menu)
	menu_bar.add_child(file_menu)

	# EDIT
	var edit_menu := PopupMenu.new()
	edit_menu.name = "Edit"
	edit_menu.add_item("Undo", 0, KEY_MASK_CTRL | KEY_Z)
	edit_menu.add_item("Redo", 1, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_Z)
	edit_menu.add_separator()
	edit_menu.add_item("Procedural Shader...", 10)
	edit_menu.id_pressed.connect(_on_edit_menu)
	menu_bar.add_child(edit_menu)

	# VIEWPORT
	var view_menu := PopupMenu.new()
	view_menu.name = "Viewport"
	view_menu.add_item("Reset Camera", 0)
	view_menu.add_item("Focus Center", 1)
	view_menu.add_item("Rift Delver View", 3)
	view_menu.add_separator()
	view_menu.add_check_item("Wireframe (W)", 2)
	view_menu.set_item_checked(view_menu.get_item_index(2), true)
	view_menu.add_separator()
	view_menu.add_item("Unshaded (V)", 20)
	view_menu.add_item("Lit", 21)
	view_menu.add_item("Normals", 22)
	view_menu.add_item("Material", 23)
	view_menu.add_item("Textured", 24)
	view_menu.add_separator()
	view_menu.add_check_item("Player Reference", 30)
	view_menu.set_item_checked(view_menu.get_item_index(30), true)
	view_menu.add_item("Player Ref Size...", 31)
	view_menu.add_separator()
	view_menu.add_item("UI Scale: 75%", 10)
	view_menu.add_item("UI Scale: 100%", 11)
	view_menu.add_item("UI Scale: 125%", 12)
	view_menu.add_item("UI Scale: 150%", 13)
	view_menu.add_item("UI Scale: 200%", 14)
	view_menu.id_pressed.connect(_on_view_menu)
	menu_bar.add_child(view_menu)

	# SELECTION
	var sel_menu := PopupMenu.new()
	sel_menu.name = "Selection"
	sel_menu.add_item("Copy", 10, KEY_MASK_CTRL | KEY_C)
	sel_menu.add_item("Cut", 11, KEY_MASK_CTRL | KEY_X)
	sel_menu.add_item("Paste", 12, KEY_MASK_CTRL | KEY_V)
	sel_menu.add_item("Delete", 13, KEY_DELETE)
	sel_menu.add_separator()
	sel_menu.add_item("Select All", 20, KEY_MASK_CTRL | KEY_A)
	sel_menu.add_separator()
	sel_menu.add_item("Rotate X", 30)
	sel_menu.add_item("Rotate Y", 31)
	sel_menu.add_item("Rotate Z", 32)
	sel_menu.add_separator()
	sel_menu.add_item("Flip X", 40)
	sel_menu.add_item("Flip Y", 41)
	sel_menu.add_item("Flip Z", 42)
	sel_menu.add_separator()
	sel_menu.add_item("Mirror X", 50)
	sel_menu.add_item("Mirror Y", 51)
	sel_menu.add_item("Mirror Z", 52)
	sel_menu.add_separator()
	sel_menu.add_item("Scale 0.5x", 73)
	sel_menu.add_item("Scale 0.75x", 74)
	sel_menu.add_item("Scale 2x", 70)
	sel_menu.add_item("Scale 3x", 71)
	sel_menu.add_item("Scale 4x", 72)
	sel_menu.add_separator()
	sel_menu.add_item("Hollow", 60)
	sel_menu.add_item("Flood Interior", 61)
	sel_menu.add_item("Dilate", 62)
	sel_menu.add_item("Erode", 63)
	sel_menu.id_pressed.connect(_on_selection_menu)
	menu_bar.add_child(sel_menu)

	# REMOTE
	var remote_menu := PopupMenu.new()
	remote_menu.name = "Remote"
	remote_menu.add_item("Browse Remote Assets...", 0)
	remote_menu.add_separator()
	remote_menu.add_item("Push Current Tile", 10)
	remote_menu.add_item("Push Current Palette", 11)
	remote_menu.add_separator()
	remote_menu.add_item("Sync Settings...", 20)
	remote_menu.id_pressed.connect(_on_remote_menu)
	menu_bar.add_child(remote_menu)


# ══════════════════════════════════════════════════════════════════════════════
# Tool Manager
# ══════════════════════════════════════════════════════════════════════════════

func _setup_tools() -> void:
	_tool_manager = EditorToolManager.new()
	_tool_manager.name = "EditorToolManager"
	add_child(_tool_manager)
	_tool_manager.initialize(self, _viewport, _camera_pivot.get_camera(), _highlight, _viewport_container)
	_tool_manager.mode_changed.connect(_on_mode_changed)
	_tool_manager.palette_pick.connect(_on_palette_pick)
	_tool_manager.hollow_changed.connect(_on_hollow_changed_from_key)
	_tool_manager.shape_changed.connect(_on_shape_changed)
	_tool_manager.tool_type_changed.connect(_on_tool_type_changed)
	_tool_manager.selection_changed.connect(_on_selection_changed)
	_tool_manager.select_settings_changed.connect(_on_select_settings_changed)
	_tool_manager.symmetry_changed.connect(_on_symmetry_changed)
	_tool_manager.numeric_input_changed.connect(_on_numeric_input_changed)
	_tool_manager.procedural_preset_changed.connect(_on_procedural_preset_synced)

	_viewport_container.gui_input.connect(_on_viewport_gui_input)


# ══════════════════════════════════════════════════════════════════════════════
# Context Bar (top, below menu — context-sensitive tool options)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_context_bar() -> void:
	# Grab references to scene nodes
	_context_hbox = %ContextHBox
	_context_label = %ContextLabel
	_brush_size_spin = %BrushSizeSpin
	_brush_flat_check = %BrushFlatCheck
	_hollow_check = %HollowCheck
	_polygon_sides_spin = %PolygonSidesSpin
	_chk_face = %FaceCheck
	_chk_color = %ColorCheck
	_chk_material = %MaterialCheck
	_range_slider = %RangeSlider
	_wrap_check = %WrapCheck
	_btn_geo = %GeoBtn
	_btn_mat = %MatBtn
	_btn_col = %ColBtn
	_select_brush_size_label = %SelectBrushSizeLabel
	_select_brush_size_spin = %SelectBrushSizeSpin

	# Wire signals
	_brush_size_spin.value_changed.connect(_on_brush_size_changed)
	_brush_flat_check.toggled.connect(_on_brush_flat_toggled)
	_hollow_check.toggled.connect(_on_hollow_toggled)
	_polygon_sides_spin.value_changed.connect(func(v): _on_props_sides_changed(int(v)))
	_chk_face.toggled.connect(_on_face_toggled)
	_chk_color.toggled.connect(_on_color_toggled)
	_chk_material.toggled.connect(_on_material_toggled)
	_range_slider.value_changed.connect(func(v): _on_props_range_changed(int(v)))
	_wrap_check.toggled.connect(_on_props_wrap_changed)

	# Face select criteria: Geo / Mat / Col (mutually exclusive)
	_select_criteria_group = ButtonGroup.new()
	_btn_geo.button_group = _select_criteria_group
	_btn_geo.button_pressed = true
	_btn_geo.pressed.connect(func(): _on_select_criteria_changed("geo"))
	_btn_mat.button_group = _select_criteria_group
	_btn_mat.pressed.connect(func(): _on_select_criteria_changed("mat"))
	_btn_col.button_group = _select_criteria_group
	_btn_col.pressed.connect(func(): _on_select_criteria_changed("col"))

	# Select brush size signal
	_select_brush_size_spin.value_changed.connect(_on_select_brush_size_changed)

	# Snap controls (added programmatically)
	var snap_sep := VSeparator.new()
	_context_hbox.add_child(snap_sep)

	var snap_lbl := Label.new()
	snap_lbl.text = "Snap:"
	_context_hbox.add_child(snap_lbl)

	_snap_option = OptionButton.new()
	_snap_option.add_item("Off", 0)
	_snap_option.add_item("2", 2)
	_snap_option.add_item("4", 4)
	_snap_option.add_item("8", 8)
	_snap_option.add_item("16", 16)
	_snap_option.item_selected.connect(_on_snap_grid_changed)
	_context_hbox.add_child(_snap_option)

	_snap_mode_option = OptionButton.new()
	_snap_mode_option.add_item("Edge", 0)
	_snap_mode_option.add_item("Center", 1)
	_snap_mode_option.item_selected.connect(_on_snap_mode_changed)
	_snap_mode_option.visible = false
	_context_hbox.add_child(_snap_mode_option)

	# Procedural shader controls
	_proc_sep = VSeparator.new()
	_proc_sep.visible = false
	_context_hbox.add_child(_proc_sep)

	_proc_label = Label.new()
	_proc_label.text = "Shader:"
	_proc_label.visible = false
	_context_hbox.add_child(_proc_label)

	_proc_preset_option = OptionButton.new()
	_proc_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_proc_preset_option.custom_minimum_size.x = 120
	_proc_preset_option.add_item("(custom)")
	for preset_name in ProceduralTool.PRESETS:
		_proc_preset_option.add_item(preset_name)
	_proc_preset_option.item_selected.connect(_on_proc_preset_selected)
	_proc_preset_option.visible = false
	_context_hbox.add_child(_proc_preset_option)
	# Default to first preset (Sphere)
	if ProceduralTool.PRESETS.size() > 0:
		var first_name: String = ProceduralTool.PRESETS.keys()[0]
		_tool_manager.set_procedural_preset(first_name)
		_proc_preset_option.select(1)  # Index 1 = first preset (0 = custom)

	_proc_edit_btn = Button.new()
	_proc_edit_btn.text = "Edit..."
	_proc_edit_btn.pressed.connect(_open_shader_dialog)
	_proc_edit_btn.visible = false
	_context_hbox.add_child(_proc_edit_btn)

	_update_context_bar_visibility()


# ══════════════════════════════════════════════════════════════════════════════
# Left Sidebar (main tools + sub-tools + symmetry)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_left_sidebar() -> void:
	# Grab references to scene nodes
	_btn_add = %BtnAdd
	_btn_subtract = %BtnSubtract
	_btn_paint = %BtnPaint
	_btn_select = %BtnSelect
	_btn_spawns = %BtnSpawns
	_sub_tools_vbox = %SubToolsVBox
	_btn_sym_x = %BtnSymX
	_btn_sym_y = %BtnSymY
	_btn_sym_z = %BtnSymZ

	# Set up ButtonGroup for main tools
	_main_tool_group = ButtonGroup.new()
	_btn_add.button_group = _main_tool_group
	_btn_add.button_pressed = true
	_btn_subtract.button_group = _main_tool_group
	_btn_paint.button_group = _main_tool_group
	_btn_select.button_group = _main_tool_group
	_btn_spawns.button_group = _main_tool_group

	# Wire signals
	_btn_add.pressed.connect(func():
		_tool_manager.current_mode = EditorToolManager.PrimaryMode.ADD
		_tool_manager.current_tool_type = EditorToolManager.ToolType.SHAPE
		_update_sub_tools())
	_btn_subtract.pressed.connect(func():
		_tool_manager.current_mode = EditorToolManager.PrimaryMode.SUBTRACT
		_tool_manager.current_tool_type = EditorToolManager.ToolType.SHAPE
		_update_sub_tools())
	_btn_paint.pressed.connect(func():
		_tool_manager.current_mode = EditorToolManager.PrimaryMode.PAINT
		_tool_manager.current_tool_type = EditorToolManager.ToolType.SHAPE
		_update_sub_tools())
	_btn_select.pressed.connect(func():
		_tool_manager.current_tool_type = EditorToolManager.ToolType.SELECT
		_update_sub_tools())
	_btn_spawns.pressed.connect(func():
		_tool_manager.current_tool_type = EditorToolManager.ToolType.METADATA
		_update_sub_tools())

	# Symmetry signals
	_btn_sym_x.pressed.connect(func(): _tool_manager.symmetry.toggle_x())
	_btn_sym_y.pressed.connect(func(): _tool_manager.symmetry.toggle_y())
	_btn_sym_z.pressed.connect(func(): _tool_manager.symmetry.toggle_z())

	# Mirror plane buttons
	var btn_place: Button = %BtnMirrorPlace
	btn_place.pressed.connect(func(): _tool_manager.begin_mirror_place())
	var btn_clear: Button = %BtnMirrorClear
	btn_clear.pressed.connect(_on_clear_custom_planes)

	# Settings cog — toggle tile properties panel visibility
	var btn_settings: Button = %BtnSettings
	btn_settings.pressed.connect(_on_settings_pressed)

	# Build initial sub-tools
	_update_sub_tools()




func _update_sub_tools() -> void:
	# Clear existing sub-tool buttons
	for child in _sub_tools_vbox.get_children():
		child.queue_free()
	_sub_tool_buttons.clear()

	var tool_type := _tool_manager.current_tool_type

	if tool_type == EditorToolManager.ToolType.SELECT:
		# Select sub-tools: Face, Rectangle, Brush, Object
		var select_names := ["Face", "Rect", "Brush", "Object"]
		var select_icons := ["voxel", "select_rect", "select_brush", "select_object"]
		var select_modes := [
			SelectTool.SelectMode.MAGIC,
			SelectTool.SelectMode.BOX,
			SelectTool.SelectMode.BRUSH,
			SelectTool.SelectMode.OBJECT]
		var select_group := ButtonGroup.new()

		for i in select_names.size():
			var btn := _make_sub_tool_button(select_names[i], "", select_icons[i])
			btn.toggle_mode = true
			btn.button_group = select_group
			if _tool_manager.select_tool.mode == select_modes[i]:
				btn.button_pressed = true
			var m: SelectTool.SelectMode = select_modes[i]
			btn.pressed.connect(func():
				_tool_manager.select_tool.mode = m
				_update_context_bar_visibility())
			_sub_tools_vbox.add_child(btn)
			_sub_tool_buttons.append(btn)

	elif tool_type == EditorToolManager.ToolType.METADATA:
		# Spawn sub-tools: populated from metadata type registry
		var by_category: Dictionary = _tool_manager._metadata_tool_ref.get_types_by_category()
		var first := true
		for cat in by_category:
			if not first:
				_sub_tools_vbox.add_child(HSeparator.new())
			first = false
			var types: Array = by_category[cat]
			for type_name in types:
				var btn := _make_sub_tool_button(type_name.capitalize(), "")
				var tn: String = type_name
				btn.pressed.connect(func(): _set_active_spawn_type(tn))
				_sub_tools_vbox.add_child(btn)
				_sub_tool_buttons.append(btn)

	else:
		# Add/Subtract/Paint: shape tools + extra tools
		var shape_names := ["Brush", "Line", "Box", "Circle", "Poly"]
		var shape_keys := ["1", "2", "3", "4", "5"]
		var shape_icons := ["brush", "timeline", "box", "circle", "polygon"]
		var shape_group := ButtonGroup.new()

		for i in shape_names.size():
			var btn := _make_sub_tool_button(shape_names[i], shape_keys[i], shape_icons[i])
			btn.toggle_mode = true
			btn.button_group = shape_group
			if i == _tool_manager.current_shape_type:
				btn.button_pressed = true
			var idx := i
			btn.pressed.connect(func():
				_tool_manager.current_tool_type = EditorToolManager.ToolType.SHAPE
				_tool_manager.current_shape_type = idx as EditorToolManager.ShapeType)
			_sub_tools_vbox.add_child(btn)
			_sub_tool_buttons.append(btn)

		_sub_tools_vbox.add_child(HSeparator.new())

		# Fill tool
		var btn_fill := _make_sub_tool_button("Fill", "F", "fill")
		btn_fill.pressed.connect(func():
			_tool_manager.current_tool_type = EditorToolManager.ToolType.FILL)
		_sub_tools_vbox.add_child(btn_fill)
		_sub_tool_buttons.append(btn_fill)

		# Extrude tool
		var btn_extrude := _make_sub_tool_button("Extrude", "G", "extrude")
		btn_extrude.pressed.connect(func():
			_tool_manager.current_tool_type = EditorToolManager.ToolType.EXTRUDE)
		_sub_tools_vbox.add_child(btn_extrude)
		_sub_tool_buttons.append(btn_extrude)

		_sub_tools_vbox.add_child(HSeparator.new())

		# Procedural shader tool
		var btn_proc := _make_sub_tool_button("Shader", "P", "shader")
		btn_proc.pressed.connect(func():
			_tool_manager.current_mode = EditorToolManager.PrimaryMode.ADD
			_tool_manager.current_tool_type = EditorToolManager.ToolType.PROCEDURAL)
		_sub_tools_vbox.add_child(btn_proc)
		_sub_tool_buttons.append(btn_proc)

	_update_context_bar_visibility()


## Set the active spawn type for the metadata tool (pre-selects type in dialog).
var _active_spawn_type: String = "spawn_point"

func _set_active_spawn_type(type_name: String) -> void:
	_active_spawn_type = type_name


func get_active_spawn_type() -> String:
	return _active_spawn_type


func _make_sub_tool_button(text: String, shortcut: String, icon_name: String = "") -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(44, 30)
	if not shortcut.is_empty():
		btn.tooltip_text = "%s (%s)" % [text, shortcut]
	else:
		btn.tooltip_text = text
	var icon := _get_icon(icon_name)
	if icon:
		btn.icon = icon
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
	else:
		btn.text = text
	return btn


# ══════════════════════════════════════════════════════════════════════════════
# Transform Bar (right of viewport, left of right panel)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_transform_bar() -> void:
	_transform_bar = %TransformBar
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = COLOR_SURFACE
	bar_style.border_width_left = 1
	bar_style.border_color = COLOR_OUTLINE
	_transform_bar.add_theme_stylebox_override("panel", bar_style)

	# Grab references and wire signals
	var btn_move: Button = %BtnMove
	var btn_rotate: Button = %BtnRotate
	var btn_scale: Button = %BtnScale

	# Move — switch to transform mode with MOVE gizmo
	btn_move.pressed.connect(func():
		_tool_manager.transform_tool.mode = TransformTool.TransformMode.MOVE
		_tool_manager.current_tool_type = EditorToolManager.ToolType.TRANSFORM
		_update_transform_toggle(btn_move, btn_rotate, btn_scale))

	# Rotate — switch to transform mode with ROTATE gizmo (drag rings to rotate, shift snaps 45°)
	btn_rotate.pressed.connect(func():
		_tool_manager.transform_tool.mode = TransformTool.TransformMode.ROTATE
		_tool_manager.current_tool_type = EditorToolManager.ToolType.TRANSFORM
		_update_transform_toggle(btn_move, btn_rotate, btn_scale))

	# Scale — switch to transform mode with SCALE gizmo (drag cube handles to scale)
	btn_scale.pressed.connect(func():
		_tool_manager.transform_tool.mode = TransformTool.TransformMode.SCALE
		_tool_manager.current_tool_type = EditorToolManager.ToolType.TRANSFORM
		_update_transform_toggle(btn_move, btn_rotate, btn_scale))

	# Scale popup (available from Selection menu)
	var scale_popup: PopupMenu = %ScalePopup
	scale_popup.add_item("Scale 0.5x", 0)
	scale_popup.add_item("Scale 0.75x", 1)
	scale_popup.add_item("Scale 2x", 2)
	scale_popup.add_item("Scale 3x", 3)
	scale_popup.add_item("Scale 4x", 4)
	var scale_factors := { 0: 0.5, 1: 0.75, 2: 2.0, 3: 3.0, 4: 4.0 }
	scale_popup.id_pressed.connect(func(id): _tool_manager.scale_selection(scale_factors[id]))

	# Rotate popup (right-click or via Selection menu)
	var rotate_popup: PopupMenu = %RotatePopup
	rotate_popup.add_item("Rotate X", 0)
	rotate_popup.add_item("Rotate Y", 1)
	rotate_popup.add_item("Rotate Z", 2)
	rotate_popup.id_pressed.connect(func(id): _tool_manager.rotate_selection(id))

	# Flip — populate popup and wire signals
	var btn_flip: Button = %BtnFlip
	var flip_popup: PopupMenu = %FlipPopup
	flip_popup.add_item("Flip X", 0)
	flip_popup.add_item("Flip Y", 1)
	flip_popup.add_item("Flip Z", 2)
	flip_popup.id_pressed.connect(func(id): _tool_manager.flip_selection(id))
	btn_flip.pressed.connect(func():
		flip_popup.position = btn_flip.global_position + Vector2(btn_flip.size.x, 0)
		flip_popup.popup())

	# Mirror — populate popup and wire signals
	var btn_mirror: Button = %BtnMirrorXform
	var mirror_popup: PopupMenu = %MirrorXformPopup
	mirror_popup.add_item("Mirror X", 0)
	mirror_popup.add_item("Mirror Y", 1)
	mirror_popup.add_item("Mirror Z", 2)
	mirror_popup.id_pressed.connect(func(id): _tool_manager.mirror_selection(id))
	btn_mirror.pressed.connect(func():
		mirror_popup.position = btn_mirror.global_position + Vector2(btn_mirror.size.x, 0)
		mirror_popup.popup())

	# Hollow / Flood / Dilate / Erode
	var btn_hollow: Button = %BtnHollow
	btn_hollow.pressed.connect(func(): _tool_manager.hollow_selection())

	var btn_flood: Button = %BtnFlood
	btn_flood.pressed.connect(func(): _tool_manager.flood_interior_selection())

	var btn_dilate: Button = %BtnDilate
	btn_dilate.pressed.connect(func(): _tool_manager.dilate_selection())

	var btn_erode: Button = %BtnErode
	btn_erode.pressed.connect(func(): _tool_manager.erode_selection())


func _update_transform_toggle(btn_move: Button, btn_rotate: Button, btn_scale: Button) -> void:
	var mode := _tool_manager.transform_tool.mode
	btn_move.button_pressed = mode == TransformTool.TransformMode.MOVE
	btn_rotate.button_pressed = mode == TransformTool.TransformMode.ROTATE
	btn_scale.button_pressed = mode == TransformTool.TransformMode.SCALE


# ══════════════════════════════════════════════════════════════════════════════
# Right Panel (palette + tile properties)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_right_panel() -> void:
	_right_vbox = %RightVBox

	# Palette panel (color swatches grouped by material) — custom class, must be created in code
	_palette_panel = PalettePanel.new()
	_palette_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_panel.entry_selected.connect(_on_palette_entry_selected)
	_palette_panel.add_entry_requested.connect(_on_palette_add_entry_for_material)
	_palette_panel.multi_selection_changed.connect(_on_palette_multi_selection_changed)
	_right_vbox.add_child(_palette_panel)

	_right_vbox.add_child(HSeparator.new())

	# Gradient selection panel (multi-select weights)
	_gradient_panel = load("res://scripts/voxel_editor/palette/gradient_selection_panel.gd").new()
	_right_vbox.add_child(_gradient_panel)

	_right_vbox.add_child(HSeparator.new())

	# Palette editor (entry properties, add/remove) — custom class
	_palette_editor = PaletteEditorPanel.new()
	_palette_editor.entry_changed.connect(_on_palette_entry_edited)
	_palette_editor.palette_switched.connect(_on_palette_switched)
	_palette_editor.entry_removed.connect(_on_palette_entry_removed)
	_right_vbox.add_child(_palette_editor)

	_right_vbox.add_child(HSeparator.new())

	# Custom mirror planes list
	var planes_label := Label.new()
	planes_label.text = "Custom Mirror Planes"
	planes_label.add_theme_color_override("font_color", COLOR_ON_SURFACE_DIM)
	planes_label.add_theme_font_size_override("font_size", 11)
	_right_vbox.add_child(planes_label)

	_custom_planes_list = ItemList.new()
	_custom_planes_list.custom_minimum_size.y = 48
	_custom_planes_list.max_text_lines = 1
	_custom_planes_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_right_vbox.add_child(_custom_planes_list)

	var planes_btn_row := HBoxContainer.new()
	var btn_remove_plane := Button.new()
	btn_remove_plane.text = "Remove Selected"
	btn_remove_plane.pressed.connect(_on_remove_selected_plane)
	planes_btn_row.add_child(btn_remove_plane)
	_right_vbox.add_child(planes_btn_row)


# ══════════════════════════════════════════════════════════════════════════════
# Bottom Bar (controls + status)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_bottom_bar() -> void:
	# Grab references to scene nodes
	_y_slice_label = %YSliceLabel
	_y_slice_slider = %YSliceSlider
	_status_label = %StatusLabel
	_stats_label = %StatsLabel

	# Wire signals
	_y_slice_slider.value_changed.connect(_on_y_slice_changed)


# ══════════════════════════════════════════════════════════════════════════════
# Tile Properties (added to right panel)
# ══════════════════════════════════════════════════════════════════════════════

func _setup_tile_properties() -> void:
	# Settings dialog is instanced from the scene tree
	_settings_dialog = %SettingsDialog
	_settings_dialog.tile_name_changed.connect(_on_tile_name_changed)
	_settings_dialog.edge_changed.connect(_on_edge_changed)
	_settings_dialog.biome_changed.connect(_on_biome_changed)
	_settings_dialog.weight_changed.connect(_on_weight_changed)
	_settings_dialog.surface_material_changed.connect(_on_surface_material_changed)
	_settings_dialog.tile_size_changed.connect(_on_tile_size_changed)
	_settings_dialog.tags_changed.connect(_on_tags_changed)
	_settings_dialog.marker_scale_changed.connect(_on_marker_scale_changed)


func _setup_metadata() -> void:
	_metadata_tool = MetadataTool.new()
	_metadata_tool.metadata_changed.connect(_on_metadata_changed_refresh)
	_metadata_dialog = MetadataEditDialog.new()
	_metadata_dialog.set_metadata_tool(_metadata_tool)
	_metadata_dialog.point_confirmed.connect(_on_metadata_confirmed)
	_metadata_dialog.point_deleted.connect(_on_metadata_deleted)
	add_child(_metadata_dialog)
	_tool_manager.set_metadata_tool(_metadata_tool)


func _setup_export() -> void:
	_export_dialog = TileExportDialog.new()
	_export_dialog.export_requested.connect(_on_export_tile)
	add_child(_export_dialog)


func _setup_remote() -> void:
	_sync_config_dialog = SyncConfigDialog.new()
	add_child(_sync_config_dialog)

	_remote_browser = RemoteBrowserDialog.new()
	_remote_browser.palette_pull_requested.connect(_on_remote_palette_pulled)
	_remote_browser.tile_pull_requested.connect(_on_remote_tile_pulled)
	add_child(_remote_browser)

	# Connection status indicator in the status bar
	_remote_status_label = Label.new()
	_remote_status_label.text = ""
	var status_bar: PanelContainer = %StatusBar
	if status_bar:
		var hbox := status_bar.get_child(0) if status_bar.get_child_count() > 0 else null
		if hbox is HBoxContainer:
			hbox.add_child(_remote_status_label)

	AssetSyncManager.connection_status_changed.connect(_on_remote_connection_changed)
	AssetSyncManager.asset_uploaded.connect(_on_remote_uploaded)
	AssetSyncManager.asset_downloaded.connect(_on_remote_auto_pulled)
	AssetSyncManager.new_remote_assets.connect(_on_new_remote_assets)


func _schedule_palette_push() -> void:
	AssetSyncManager.mark_palette_dirty(_palette)


func _on_remote_menu(id: int) -> void:
	match id:
		0:
			_remote_browser.show_browser()
		10:
			AssetSyncManager.push_tile(_tile, _palette)
			_update_status("Pushing tile...")
		11:
			AssetSyncManager.push_palette(_palette)
			_update_status("Pushing palette...")
		20:
			_sync_config_dialog.populate()
			_sync_config_dialog.popup_centered()


func _on_remote_connection_changed(ok: bool) -> void:
	if _remote_status_label:
		if ok:
			_remote_status_label.text = "  Remote: Connected"
			_remote_status_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			_remote_status_label.text = "  Remote: Disconnected"
			_remote_status_label.add_theme_color_override("font_color", Color.RED)


func _on_remote_uploaded(_bucket: String, key: String, _etag: String) -> void:
	_update_status("Pushed: %s" % key)


func _on_remote_palette_pulled(palette: VoxelPalette) -> void:
	if not palette:
		return
	_palette_set.palettes.append(palette)
	_palette_set.set_active(_palette_set.count() - 1)
	_palette = _palette_set.get_active()
	_tile_renderer.set_tile(_tile, _palette)
	_palette_panel.refresh()
	_palette_editor.set_palette_set(_palette_set)
	_gradient_panel.set_palette(_palette)
	_update_status("Pulled palette: %s" % palette.palette_name)


func _on_remote_tile_pulled(tile: WFCTileDef, palette: VoxelPalette) -> void:
	if not tile:
		return
	_tile = tile
	if palette:
		_palette_set = TilePaletteSet.new()
		_palette_set.palettes[0] = palette
		_palette = _palette_set.get_active()
		_palette_panel.set_palette_set(_palette_set)
		_palette_editor.set_palette_set(_palette_set)
	_gradient_panel.set_palette(_palette)
	_tile_renderer.set_tile(_tile, _palette)
	_tool_manager.undo_manager.clear()
	_sync_tile_properties()
	_tool_manager.refresh_metadata_markers()
	_update_status("Pulled tile: %s" % tile.tile_name)


func _on_remote_auto_pulled(bucket: String, key: String, _local_path: String) -> void:
	# Auto-pulled assets: load palettes into the set, notify for tiles
	if bucket == AssetSyncManager.PALETTE_BUCKET:
		var palette := AssetSyncManager.palette_from_cache(key)
		if palette:
			_on_remote_palette_pulled(palette)
	# Tiles are not auto-opened (would disrupt current work) — just notify
	elif bucket == AssetSyncManager.TILE_BUCKET:
		_update_status("New remote tile available: %s" % key)


func _on_new_remote_assets(bucket: String, keys: PackedStringArray) -> void:
	var label := "palettes" if bucket == AssetSyncManager.PALETTE_BUCKET else "tiles"
	_update_status("Remote: %d new/updated %s" % [keys.size(), label])


# ══════════════════════════════════════════════════════════════════════════════
# Context Bar Visibility (show/hide controls based on active tool)
# ══════════════════════════════════════════════════════════════════════════════

func _update_context_bar_visibility() -> void:
	if not _context_hbox:
		return

	var tt := _tool_manager.current_tool_type if _tool_manager else EditorToolManager.ToolType.SHAPE
	var is_shape := tt == EditorToolManager.ToolType.SHAPE
	var is_select := tt == EditorToolManager.ToolType.SELECT
	var is_transform := tt == EditorToolManager.ToolType.TRANSFORM

	# Brush options (only when brush shape is active)
	var is_brush := is_shape and _tool_manager and \
		_tool_manager.current_shape_type == EditorToolManager.ShapeType.BRUSH
	(%BrushSizeLabel as Control).visible = is_brush
	_brush_size_spin.visible = is_brush
	_brush_flat_check.visible = is_brush

	# Shape options (hollow + sides — not for brush)
	var is_non_brush_shape := is_shape and not is_brush
	_hollow_check.visible = is_non_brush_shape
	var is_polygon := is_shape and _tool_manager and \
		_tool_manager.current_shape_type == EditorToolManager.ShapeType.POLYGON
	(%SidesLabel as Control).visible = is_polygon
	_polygon_sides_spin.visible = is_polygon

	# Query options (for Fill/Extrude — not Select, which uses its own criteria buttons)
	var is_fill_query := tt in [EditorToolManager.ToolType.FILL, EditorToolManager.ToolType.EXTRUDE]
	_chk_face.visible = is_fill_query
	_chk_color.visible = is_fill_query
	_chk_material.visible = is_fill_query
	(%RangeLabel as Control).visible = is_fill_query
	_range_slider.visible = is_fill_query
	# Separator between shape and query
	(%QuerySeparator as Control).visible = is_shape or is_fill_query or is_select

	# Transform options
	_wrap_check.visible = is_transform

	# Select sub-tool context controls
	var is_face_select := is_select and _tool_manager and \
		_tool_manager.select_tool.mode == SelectTool.SelectMode.MAGIC
	var is_object_select := is_select and _tool_manager and \
		_tool_manager.select_tool.mode == SelectTool.SelectMode.OBJECT
	var is_brush_select := is_select and _tool_manager and \
		_tool_manager.select_tool.mode == SelectTool.SelectMode.BRUSH
	var show_query_filters := is_face_select or is_object_select
	_btn_geo.visible = is_face_select  # Connectivity toggle only for Face mode
	_btn_mat.visible = show_query_filters
	_btn_col.visible = show_query_filters
	_select_brush_size_label.visible = is_brush_select
	_select_brush_size_spin.visible = is_brush_select

	# Procedural shader controls
	var is_proc := tt == EditorToolManager.ToolType.PROCEDURAL
	_proc_sep.visible = is_proc
	_proc_label.visible = is_proc
	_proc_preset_option.visible = is_proc
	_proc_edit_btn.visible = is_proc

	# Context label text
	match tt:
		EditorToolManager.ToolType.SHAPE:
			_context_label.text = "BRUSH:"
		EditorToolManager.ToolType.FILL:
			_context_label.text = "FILL:"
		EditorToolManager.ToolType.EXTRUDE:
			_context_label.text = "EXTRUDE:"
		EditorToolManager.ToolType.SELECT:
			_context_label.text = "SELECT:"
		EditorToolManager.ToolType.TRANSFORM:
			_context_label.text = "TRANSFORM:"
		EditorToolManager.ToolType.METADATA:
			_context_label.text = "SPAWNS:"
		EditorToolManager.ToolType.PROCEDURAL:
			_context_label.text = "SHADER:"


# ══════════════════════════════════════════════════════════════════════════════
# Main Tool Sync (update sidebar buttons to match tool manager state)
# ══════════════════════════════════════════════════════════════════════════════

func _sync_main_tool_buttons() -> void:
	if not _btn_add:
		return

	var tt := _tool_manager.current_tool_type
	if tt == EditorToolManager.ToolType.SELECT:
		_btn_select.set_pressed_no_signal(true)
	elif tt == EditorToolManager.ToolType.METADATA:
		_btn_spawns.set_pressed_no_signal(true)
	else:
		match _tool_manager.current_mode:
			EditorToolManager.PrimaryMode.ADD:
				_btn_add.set_pressed_no_signal(true)
			EditorToolManager.PrimaryMode.SUBTRACT:
				_btn_subtract.set_pressed_no_signal(true)
			EditorToolManager.PrimaryMode.PAINT:
				_btn_paint.set_pressed_no_signal(true)


# ══════════════════════════════════════════════════════════════════════════════
# Menu Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_file_menu(id: int) -> void:
	match id:
		0: new_tile()
		1: _open_dialog.popup_centered(Vector2i(700, 500))
		2: save_tile()
		3: _save_dialog.popup_centered(Vector2i(700, 500))
		5: _show_export_dialog()
		10: _import_palette_dialog.popup_centered(Vector2i(700, 500))
		11: _export_palette_dialog.popup_centered(Vector2i(700, 500))
		12: _import_scene_dialog.popup_centered(Vector2i(700, 500))


func _on_edit_menu(id: int) -> void:
	match id:
		0: _tool_manager.undo_manager.undo(_tile, _tile_renderer)
		1: _tool_manager.undo_manager.redo(_tile, _tile_renderer)
		10: _open_shader_dialog()


func _on_selection_menu(id: int) -> void:
	match id:
		10: _tool_manager.copy_selection()
		11: _tool_manager.cut_selection()
		12: _tool_manager.begin_paste()
		13: _tool_manager.delete_selection()
		20: _tool_manager.select_all()
		30: _tool_manager.rotate_selection(0)
		31: _tool_manager.rotate_selection(1)
		32: _tool_manager.rotate_selection(2)
		40: _tool_manager.flip_selection(0)
		41: _tool_manager.flip_selection(1)
		42: _tool_manager.flip_selection(2)
		50: _tool_manager.mirror_selection(0)
		51: _tool_manager.mirror_selection(1)
		52: _tool_manager.mirror_selection(2)
		60: _tool_manager.hollow_selection()
		61: _tool_manager.flood_interior_selection()
		62: _tool_manager.dilate_selection()
		63: _tool_manager.erode_selection()
		70: _tool_manager.scale_selection(2.0)
		71: _tool_manager.scale_selection(3.0)
		72: _tool_manager.scale_selection(4.0)
		73: _tool_manager.scale_selection(0.5)
		74: _tool_manager.scale_selection(0.75)


func _on_view_menu(id: int) -> void:
	match id:
		0:
			if _tile:
				_camera_pivot.focus_on(Vector3(_tile.tile_size_x / 2.0, _tile.tile_size_y / 8.0, _tile.tile_size_z / 2.0))
			else:
				_camera_pivot.focus_on(Vector3(64.0, 16.0, 64.0))
		1:
			if _tile:
				_camera_pivot.focus_on(Vector3(_tile.tile_size_x / 2.0, _tile.tile_size_y / 2.0, _tile.tile_size_z / 2.0))
			else:
				_camera_pivot.focus_on(Vector3(64.0, 56.0, 64.0))
		2:
			_tile_renderer.show_wireframe = not _tile_renderer.show_wireframe
			var view_menu: PopupMenu = %MenuBar.get_child(2)
			view_menu.set_item_checked(
				view_menu.get_item_index(2), _tile_renderer.show_wireframe)
		3:
			# Rift Delver View — isometric camera + lit shading
			var center := Vector3(64.0, 16.0, 64.0)
			if _tile:
				center = Vector3(_tile.tile_size_x / 2.0, _tile.tile_size_y / 4.0, _tile.tile_size_z / 2.0)
			_camera_pivot.set_isometric(center, 120.0)
			_set_view_mode(TileRenderer.ViewMode.LIT)
			_tile_renderer.show_wireframe = false
			var vm2: PopupMenu = %MenuBar.get_child(2)
			vm2.set_item_checked(vm2.get_item_index(2), false)
		10: set_ui_scale(0.75)
		11: set_ui_scale(1.0)
		12: set_ui_scale(1.25)
		13: set_ui_scale(1.5)
		14: set_ui_scale(2.0)
		20: _set_view_mode(TileRenderer.ViewMode.UNSHADED)
		21: _set_view_mode(TileRenderer.ViewMode.LIT)
		22: _set_view_mode(TileRenderer.ViewMode.NORMALS)
		23: _set_view_mode(TileRenderer.ViewMode.MATERIAL)
		24: _set_view_mode(TileRenderer.ViewMode.TEXTURED)
		30:
			var vis := not _editor_grid._ref_visible
			_editor_grid.set_ref_visible(vis)
			var vm: PopupMenu = %MenuBar.get_child(2)
			vm.set_item_checked(vm.get_item_index(30), vis)
		31:
			_show_ref_size_dialog()


func _show_ref_size_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Player Reference Size"
	dialog.min_size = Vector2i(250, 0)

	var vbox := VBoxContainer.new()

	var h_row := HBoxContainer.new()
	var h_lbl := Label.new()
	h_lbl.text = "Height:"
	h_lbl.custom_minimum_size.x = 60
	h_row.add_child(h_lbl)
	var h_spin := SpinBox.new()
	h_spin.min_value = 1.0
	h_spin.max_value = 20.0
	h_spin.step = 0.5
	h_spin.value = _editor_grid._ref_height
	h_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_row.add_child(h_spin)
	vbox.add_child(h_row)

	var r_row := HBoxContainer.new()
	var r_lbl := Label.new()
	r_lbl.text = "Radius:"
	r_lbl.custom_minimum_size.x = 60
	r_row.add_child(r_lbl)
	var r_spin := SpinBox.new()
	r_spin.min_value = 0.25
	r_spin.max_value = 5.0
	r_spin.step = 0.25
	r_spin.value = _editor_grid._ref_radius
	r_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_row.add_child(r_spin)
	vbox.add_child(r_row)

	dialog.add_child(vbox)
	dialog.confirmed.connect(func():
		_editor_grid.set_ref_size(h_spin.value, r_spin.value)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _open_shader_dialog() -> void:
	if not _tile:
		_update_status("No tile open")
		return

	if not _shader_dialog:
		var DialogClass := load("res://scripts/voxel_editor/ui/shader_editor_dialog.gd")
		_shader_dialog = DialogClass.new()
		_shader_dialog.apply_requested.connect(_on_shader_apply)
		add_child(_shader_dialog)

	_shader_dialog.set_tile_size(_tile.get_tile_size())

	# Pre-populate with the current procedural code
	if not _tool_manager.procedural_code.is_empty():
		_shader_dialog._code_edit.text = _tool_manager.procedural_code

	# If there's a selection, use its bounding box as the region
	if not _tool_manager.selection.is_empty():
		var bb := _tool_manager.selection.get_bounding_box()
		_shader_dialog.set_region(Vector3i(bb.position), Vector3i(bb.size))

	_shader_dialog.clear_error()
	_shader_dialog.popup_centered(Vector2i(550, 580))


func _on_shader_apply(code: String, origin: Vector3i, region_size: Vector3i, vid_override: int) -> void:
	if not _tile or not _palette:
		return

	# Push edited code back to tool manager for click-drag workflow
	_tool_manager.set_procedural_code(code)

	# Get the voxel ID from the current palette entry
	var vid: int = _palette.get_voxel_id(_tool_manager.selected_palette_index)
	var is_preview := vid_override == -99

	var result: Variant = ProceduralTool.execute(_tile, origin, region_size, vid, code)

	if result is String:
		# Error message
		if _shader_dialog:
			_shader_dialog.show_error(result)
		return

	var changes: Dictionary = result
	if changes.is_empty():
		if _shader_dialog:
			_shader_dialog.show_error("No voxels changed")
		return

	# Apply through undo system
	var action := _tool_manager.undo_manager.create_action(
		"Procedural: %d voxels" % changes.size())
	for pos: Vector3i in changes:
		var old_id := _tile.get_voxel(pos.x, pos.y, pos.z)
		_tool_manager.undo_manager.add_voxel_change(action, pos, old_id, changes[pos])
	_tool_manager.undo_manager.apply_and_commit(action, _tile, _tile_renderer)

	_update_status("Procedural: %d voxels %s" % [changes.size(), "previewed" if is_preview else "applied"])


# ══════════════════════════════════════════════════════════════════════════════
# Tool Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_tool_manager.handle_viewport_click(mb)
	elif event is InputEventMouseMotion:
		if _tool_manager.extrude_tool.active:
			_tool_manager.handle_viewport_drag(event as InputEventMouseMotion)


func _on_mode_changed(_mode: EditorToolManager.PrimaryMode) -> void:
	_sync_main_tool_buttons()
	_update_context_bar_visibility()
	_update_sub_tools()


func _on_shape_changed(_shape_type: EditorToolManager.ShapeType) -> void:
	# Only update sub-tool button selection when in a shape-based tool mode
	var tt := _tool_manager.current_tool_type
	if tt == EditorToolManager.ToolType.SHAPE or \
			tt == EditorToolManager.ToolType.FILL or \
			tt == EditorToolManager.ToolType.EXTRUDE:
		if _sub_tool_buttons.size() > _shape_type:
			for i in _sub_tool_buttons.size():
				if _sub_tool_buttons[i].toggle_mode:
					_sub_tool_buttons[i].set_pressed_no_signal(i == _shape_type)
	_update_context_bar_visibility()


func _on_tool_type_changed(_tool_type: EditorToolManager.ToolType) -> void:
	_sync_main_tool_buttons()
	_update_context_bar_visibility()
	_update_sub_tools()


func _on_snap_grid_changed(option_index: int) -> void:
	var grid := _snap_option.get_item_id(option_index)
	_tool_manager.snap_grid = grid
	if grid == 0:
		_tool_manager.snap_mode = EditorToolManager.SnapMode.OFF
		_snap_mode_option.visible = false
		_editor_grid.set_snap(0, false)
	else:
		var center := _snap_mode_option.selected == 1
		_tool_manager.snap_mode = EditorToolManager.SnapMode.EDGE if not center else EditorToolManager.SnapMode.CENTER
		_snap_mode_option.visible = true
		_editor_grid.set_snap(grid, center)


func _on_snap_mode_changed(option_index: int) -> void:
	var center := option_index == 1
	_tool_manager.snap_mode = EditorToolManager.SnapMode.EDGE if not center else EditorToolManager.SnapMode.CENTER
	_editor_grid.set_snap(_tool_manager.snap_grid, center)


func _on_brush_size_changed(value: float) -> void:
	_tool_manager.brush_size = int(value)
	_tool_manager._sync_hollow()


func _on_brush_flat_toggled(pressed: bool) -> void:
	_tool_manager.brush_flat = pressed
	_tool_manager._sync_hollow()


func _on_hollow_toggled(pressed: bool) -> void:
	_tool_manager.hollow = pressed
	_tool_manager._sync_hollow()


func _on_hollow_changed_from_key(is_hollow: bool) -> void:
	if _hollow_check:
		_hollow_check.set_pressed_no_signal(is_hollow)


func _on_palette_pick(index: int) -> void:
	_palette_panel.select_entry(index)
	_palette_editor.set_selected_entry(index)


func _on_face_toggled(pressed: bool) -> void:
	var q := _tool_manager.select_tool.query
	if pressed:
		q.connectivity = VoxelQuery.Connectivity.FACE
	else:
		q.connectivity = VoxelQuery.Connectivity.GEOMETRY
	_tool_manager.fill_tool.query.connectivity = q.connectivity
	_tool_manager.extrude_tool.query.connectivity = q.connectivity


func _on_color_toggled(pressed: bool) -> void:
	_tool_manager.select_tool.query.filter_color = pressed
	_tool_manager.fill_tool.query.filter_color = pressed
	_tool_manager.extrude_tool.query.filter_color = pressed


func _on_material_toggled(pressed: bool) -> void:
	_tool_manager.select_tool.query.filter_material = pressed
	_tool_manager.fill_tool.query.filter_material = pressed
	_tool_manager.extrude_tool.query.filter_material = pressed




func _on_select_settings_changed() -> void:
	var q := _tool_manager.select_tool.query
	if _chk_face:
		_chk_face.set_pressed_no_signal(q.connectivity == VoxelQuery.Connectivity.FACE)
	if _chk_color:
		_chk_color.set_pressed_no_signal(q.filter_color)
	if _chk_material:
		_chk_material.set_pressed_no_signal(q.filter_material)
	# Sync criteria buttons
	if _btn_geo:
		if not q.filter_color and not q.filter_material:
			_btn_geo.set_pressed_no_signal(true)
		elif q.filter_material:
			_btn_mat.set_pressed_no_signal(true)
		elif q.filter_color:
			_btn_col.set_pressed_no_signal(true)


func _on_select_criteria_changed(criteria: String) -> void:
	var sq := _tool_manager.select_tool.query
	var fq := _tool_manager.fill_tool.query
	match criteria:
		"geo":
			sq.filter_color = false
			sq.filter_material = false
			sq.connectivity = VoxelQuery.Connectivity.GEOMETRY
		"mat":
			sq.filter_color = false
			sq.filter_material = true
			sq.connectivity = VoxelQuery.Connectivity.GEOMETRY
		"col":
			sq.filter_color = true
			sq.filter_material = false
			sq.connectivity = VoxelQuery.Connectivity.GEOMETRY
	fq.filter_color = sq.filter_color
	fq.filter_material = sq.filter_material
	fq.connectivity = sq.connectivity
	var eq := _tool_manager.extrude_tool.query
	eq.filter_color = sq.filter_color
	eq.filter_material = sq.filter_material
	eq.connectivity = sq.connectivity


func _on_select_brush_size_changed(value: float) -> void:
	_tool_manager.select_tool.brush_size = int(value)


func _on_props_sides_changed(sides: int) -> void:
	_tool_manager.polygon_sides = sides
	_tool_manager._sync_hollow()


func _on_props_range_changed(range_val: int) -> void:
	_tool_manager.select_tool.query.search_range = range_val
	_tool_manager.fill_tool.query.search_range = range_val


func _on_props_wrap_changed(enabled: bool) -> void:
	_tool_manager.transform_tool.wrap = enabled


func _on_proc_preset_selected(index: int) -> void:
	if index == 0:
		return  # "(custom)" — keep existing code
	var preset_name: String = _proc_preset_option.get_item_text(index)
	_tool_manager.set_procedural_preset(preset_name)


func _on_procedural_preset_synced(preset_name: String) -> void:
	if not _proc_preset_option:
		return
	# Sync the dropdown to match the tool manager's preset
	if preset_name == "(custom)":
		_proc_preset_option.select(0)
		return
	for i in _proc_preset_option.item_count:
		if _proc_preset_option.get_item_text(i) == preset_name:
			_proc_preset_option.select(i)
			return


func _on_y_slice_changed(value: float) -> void:
	var v := int(value)
	_tile_renderer.clip_y = v
	var val_label: Label = %SliceVal
	val_label.text = "off" if v == 0 else "%d" % v


# ══════════════════════════════════════════════════════════════════════════════
# Selection Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_selection_changed() -> void:
	var count := _tool_manager.selection.get_positions().size()
	(%SelectionCount as Label).text = "Selection: %d" % count
	if count > 0:
		_update_status("Selected %d voxel%s" % [count, "s" if count != 1 else ""])
	else:
		_update_status("Selection cleared")


# ══════════════════════════════════════════════════════════════════════════════
# Symmetry Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_symmetry_changed() -> void:
	var sym: SymmetryManager = _tool_manager.symmetry
	if _btn_sym_x:
		_btn_sym_x.set_pressed_no_signal(sym.mirror_x)
	if _btn_sym_y:
		_btn_sym_y.set_pressed_no_signal(sym.mirror_y)
	if _btn_sym_z:
		_btn_sym_z.set_pressed_no_signal(sym.mirror_z)
	_update_custom_planes_list()


func _on_clear_custom_planes() -> void:
	_tool_manager.clear_custom_mirror_planes()


func _on_remove_selected_plane() -> void:
	if not _custom_planes_list:
		return
	var selected := _custom_planes_list.get_selected_items()
	if selected.is_empty():
		return
	var indices: Array[int] = []
	for i in selected:
		indices.append(i)
	indices.sort()
	indices.reverse()
	for idx in indices:
		_tool_manager.remove_custom_mirror_plane(idx)


func _update_custom_planes_list() -> void:
	if not _custom_planes_list:
		return
	_custom_planes_list.clear()
	var planes: Array[Dictionary] = _tool_manager.symmetry.get_plane_visuals()
	for data in planes:
		if data["is_custom"]:
			var axis: String = data["axis"].to_upper()
			var pos: float = data["position"]
			_custom_planes_list.add_item("%s = %.1f" % [axis, pos])


# ══════════════════════════════════════════════════════════════════════════════
# Palette Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_palette_entry_edited(_index: int) -> void:
	_palette_panel.refresh()
	_tile_renderer.mark_all_dirty()
	_schedule_palette_push()


func _on_palette_switched(_index: int) -> void:
	_palette = _palette_set.get_active()
	_tile_renderer.set_tile(_tile, _palette)
	_palette_panel.refresh()
	_palette_editor.set_selected_entry(_palette_panel.get_selected_index())
	_gradient_panel.set_palette(_palette)
	_update_status("Switched to palette: %s" % _palette.palette_name)


func _on_palette_add_entry_for_material(base_material: int) -> void:
	if not _palette_set:
		return
	var pal := _palette_set.get_active()
	if not pal:
		return
	var mat_name := "New Entry"
	for m in MaterialRegistry.get_all_materials():
		if m["id"] == base_material:
			mat_name = m["name"]
			break
	var idx := pal.add_entry(mat_name, Color.WHITE, base_material)
	_palette_set.sync_entry_count()
	_palette_panel.refresh()
	_palette_panel.select_entry(idx)
	_palette_editor.set_selected_entry(idx)
	_update_status("Added %s palette entry" % mat_name)
	_schedule_palette_push()


func _on_palette_entry_removed(_index: int) -> void:
	_palette_panel.refresh()
	_tile_renderer.mark_all_dirty()
	_update_status("Removed palette entry")
	_schedule_palette_push()


func _on_palette_entry_selected(index: int) -> void:
	_tool_manager.selected_palette_index = index
	_palette_editor.set_selected_entry(index)


func _on_palette_multi_selection_changed(indices: Array[int]) -> void:
	_gradient_panel.update_selection(indices)


func _on_import_palette(path: String) -> void:
	var loaded := ResourceLoader.load(path)
	if loaded is VoxelPalette:
		_palette_set.palettes.append(loaded)
		_palette_set.set_active(_palette_set.count() - 1)
		_palette = _palette_set.get_active()
		_tile_renderer.set_tile(_tile, _palette)
		_palette_panel.refresh()
		_palette_editor.set_palette_set(_palette_set)
		_gradient_panel.set_palette(_palette)
		_update_status("Imported palette: %s" % path.get_file())
	else:
		_update_status("ERROR: Failed to load palette from %s" % path)


func _on_export_palette(path: String) -> void:
	var pal: VoxelPalette = _palette_set.get_active()
	if not pal:
		_update_status("ERROR: No active palette to export")
		return
	var err := ResourceSaver.save(pal, path)
	if err == OK:
		_update_status("Exported palette: %s" % path.get_file())
	else:
		_update_status("ERROR: Failed to export palette — error %d" % err)


func _on_import_scene(path: String) -> void:
	var res := ResourceLoader.load(path)
	if not res is WFCTileDef:
		_update_status("ERROR: Not a valid WFCTileDef resource")
		return
	var imported: WFCTileDef = res as WFCTileDef

	# Load imported tile's voxels into clipboard as relative positions
	var clip := _tool_manager.clipboard
	clip._data.clear()
	clip._size = imported.get_tile_size()

	for lz in imported.tile_size_z:
		for ly in imported.tile_size_y:
			for lx in imported.tile_size_x:
				var vid := imported.get_voxel(lx, ly, lz)
				if vid != 0:
					clip._data[Vector3i(lx, ly, lz)] = vid

	if clip.is_empty():
		_update_status("Imported scene is empty")
		return

	# Merge palette entries from imported tile if it has them
	if not imported.palette_entries.is_empty():
		_merge_imported_palette(imported.palette_entries)

	# Begin paste mode so user can position the imported scene
	_tool_manager.begin_paste()
	_update_status("Imported '%s' — click to place" % path.get_file())


func _merge_imported_palette(entries: Array[Dictionary]) -> void:
	if not _palette_set:
		return
	var pal := _palette_set.get_active()
	if not pal:
		return
	# Add any entries from the imported tile that don't already exist
	for entry_data in entries:
		var entry_name: String = entry_data.get("name", "")
		var color: Color = entry_data.get("color", Color.WHITE)
		var base_mat: int = entry_data.get("base_material", 1)
		# Check if an entry with same name and material already exists
		var found := false
		for existing in pal.entries:
			if existing.entry_name == entry_name and existing.base_material == base_mat:
				found = true
				break
		if not found and not entry_name.is_empty():
			pal.add_entry(entry_name, color, base_mat)
	_palette_set.sync_entry_count()
	_palette_panel.refresh()


# ══════════════════════════════════════════════════════════════════════════════
# Tile Properties Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _sync_tile_properties() -> void:
	if _settings_dialog and _tile:
		_settings_dialog.sync_from_tile(_tile)
	if _editor_grid and _tile:
		_editor_grid.set_tile_size(_tile.tile_size_x, _tile.tile_size_y, _tile.tile_size_z)
	if _y_slice_slider and _tile:
		_y_slice_slider.max_value = _tile.tile_size_y
	if _tool_manager and _tile:
		_tool_manager.sync_symmetry_tile_size()


func _on_settings_pressed() -> void:
	if _settings_dialog:
		if _tile:
			_settings_dialog.sync_from_tile(_tile)
		_settings_dialog.popup_centered()


func _on_marker_scale_changed(value: float) -> void:
	_tool_manager.set_marker_scale(value)


func _on_tile_name_changed(tile_name: String) -> void:
	if _tile:
		_tile.tile_name = tile_name


func _on_edge_changed(side: String, edge_type: int) -> void:
	if not _tile:
		return
	match side:
		"north": _tile.edge_north = edge_type
		"south": _tile.edge_south = edge_type
		"east": _tile.edge_east = edge_type
		"west": _tile.edge_west = edge_type


func _on_biome_changed(biome: String) -> void:
	if _tile:
		_tile.biome = biome


func _on_weight_changed(weight: float) -> void:
	if _tile:
		_tile.weight = weight


func _on_surface_material_changed(mat_id: int) -> void:
	if _tile:
		_tile.surface_material = mat_id


func _on_tile_size_changed(new_size: Vector3i) -> void:
	if not _tile:
		return
	_tile.set_tile_size(new_size.x, new_size.y, new_size.z)
	_editor_grid.set_tile_size(new_size.x, new_size.y, new_size.z)
	_tile_renderer.set_tile(_tile, _palette)
	if _y_slice_slider:
		_y_slice_slider.max_value = new_size.y
	_camera_pivot.focus_on(Vector3(new_size.x / 2.0, new_size.y / 4.0, new_size.z / 2.0))
	_update_status("Tile resized to %dx%dx%d" % [new_size.x, new_size.y, new_size.z])


func _on_tags_changed(tags: PackedStringArray) -> void:
	if _tile:
		_tile.tags = tags


# ══════════════════════════════════════════════════════════════════════════════
# Metadata Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_metadata_confirmed(pos: Vector3i, type: String, properties: Dictionary) -> void:
	if _tile:
		var old_data: Variant = _metadata_tool.get_point(_tile, pos)
		_metadata_tool.set_point(_tile, pos, type, properties)
		var new_data: Variant = _metadata_tool.get_point(_tile, pos)
		var desc := "Add %s" % type if old_data == null else "Edit %s" % type
		_tool_manager.undo_manager.push_metadata_action(
			[{ "pos": pos, "old_data": old_data, "new_data": new_data.duplicate() }], desc)
		_update_status("Metadata set at (%d, %d, %d): %s" % [pos.x, pos.y, pos.z, type])


func _on_metadata_deleted(pos: Vector3i) -> void:
	if _tile:
		var old_data: Variant = _metadata_tool.get_point(_tile, pos)
		_metadata_tool.remove_point(_tile, pos)
		if old_data != null:
			_tool_manager.undo_manager.push_metadata_action(
				[{ "pos": pos, "old_data": (old_data as Dictionary).duplicate(), "new_data": null }],
				"Delete %s" % (old_data as Dictionary).get("type", "metadata"))
		_update_status("Metadata removed at (%d, %d, %d)" % [pos.x, pos.y, pos.z])


func _on_metadata_changed_refresh() -> void:
	_tool_manager.refresh_metadata_markers()


func remove_metadata_at(pos: Vector3i) -> void:
	if _tile and _metadata_tool.has_point(_tile, pos):
		var old_data: Variant = _metadata_tool.get_point(_tile, pos)
		_metadata_tool.remove_point(_tile, pos)
		if old_data != null:
			_tool_manager.undo_manager.push_metadata_action(
				[{ "pos": pos, "old_data": (old_data as Dictionary).duplicate(), "new_data": null }],
				"Delete %s" % (old_data as Dictionary).get("type", "metadata"))
		_update_status("Metadata removed at (%d, %d, %d)" % [pos.x, pos.y, pos.z])


func open_metadata_dialog(pos: Vector3i) -> void:
	if not _tile or not _metadata_dialog:
		return
	var existing: Variant = _metadata_tool.get_point(_tile, pos)
	if existing != null:
		_metadata_dialog.open_edit(pos, existing as Dictionary)
	else:
		_metadata_dialog.open_new(pos, _active_spawn_type)


func open_shader_plane_dialog(pos: Vector3i, surface_positions: PackedInt32Array,
		face_normal: Vector3i) -> void:
	if not _tile or not _metadata_dialog:
		return
	# If there's already a shader_plane at this position, edit it
	var existing: Variant = _metadata_tool.get_point(_tile, pos)
	if existing != null:
		_metadata_dialog.open_edit(pos, existing as Dictionary)
	else:
		_metadata_dialog.open_new_shader_plane(pos, surface_positions, face_normal)


# ══════════════════════════════════════════════════════════════════════════════
# File I/O
# ══════════════════════════════════════════════════════════════════════════════

func new_tile() -> void:
	_tile = WFCTileDef.new()
	_tile.tile_name = "untitled"
	_palette_set = TilePaletteSet.new()
	_palette = _palette_set.get_active()
	_tile_renderer.set_tile(_tile, _palette)
	_palette_panel.set_palette_set(_palette_set)
	_palette_editor.set_palette_set(_palette_set)
	_gradient_panel.set_palette(_palette)
	_tool_manager.undo_manager.clear()
	_sync_tile_properties()
	_tool_manager.refresh_metadata_markers()
	_update_status("New tile")


func open_tile(path: String) -> void:
	var loaded := ResourceLoader.load(path)
	if loaded is WFCTileDef:
		_tile = loaded
		# Restore palette from embedded data if available
		if not _tile.palette_entries.is_empty():
			var pal := VoxelPalette.new()
			pal.entries.clear()
			for entry_data in _tile.palette_entries:
				var entry := PaletteEntry.new()
				entry.entry_name = entry_data.get("name", "")
				entry.color = entry_data.get("color", Color.WHITE)
				entry.base_material = entry_data.get("base_material", MaterialRegistry.STONE)
				var sm: Variant = entry_data.get("shader_material")
				if sm is Material:
					entry.shader_material = sm
				pal.entries.append(entry)
			_palette_set = TilePaletteSet.new()
			_palette_set.palettes[0] = pal
			_palette = _palette_set.get_active()
			_palette_panel.set_palette_set(_palette_set)
			_palette_editor.set_palette_set(_palette_set)
		_gradient_panel.set_palette(_palette)
		_tile_renderer.set_tile(_tile, _palette)
		_tool_manager.undo_manager.clear()
		_sync_tile_properties()
		_tool_manager.refresh_metadata_markers()
		_update_status("Opened: %s" % path.get_file())
	else:
		_update_status("ERROR: Failed to load tile from %s" % path)


func get_palette_set() -> TilePaletteSet:
	return _palette_set


func save_tile() -> void:
	if _tile.resource_path.is_empty():
		_save_dialog.popup_centered(Vector2i(700, 500))
		return
	_do_save(_tile.resource_path)


func _on_open_file(path: String) -> void:
	open_tile(path)


func _on_save_file(path: String) -> void:
	_do_save(path)


func _do_save(path: String) -> void:
	# Embed palette entries into the tile before saving
	if _palette:
		var entries_data: Array[Dictionary] = []
		for entry in _palette.entries:
			var d := {
				"name": entry.entry_name,
				"color": entry.color,
				"base_material": entry.base_material,
			}
			if entry.shader_material:
				d["shader_material"] = entry.shader_material
			entries_data.append(d)
		_tile.palette_entries = entries_data
	var err := ResourceSaver.save(_tile, path)
	if err == OK:
		_update_status("Saved: %s" % path.get_file())
		AssetSyncManager.mark_tile_dirty(_tile, _palette)
	else:
		_update_status("ERROR: Failed to save — error %d" % err)


func get_tile() -> WFCTileDef:
	return _tile


func get_palette() -> VoxelPalette:
	return _palette


func get_tile_renderer() -> TileRenderer:
	return _tile_renderer


# ══════════════════════════════════════════════════════════════════════════════
# Export
# ══════════════════════════════════════════════════════════════════════════════

func _show_export_dialog() -> void:
	if _export_dialog:
		_export_dialog.set_tile(_tile)
		var sel_count := _tool_manager.selection.get_positions().size()
		_export_dialog.set_selection_count(sel_count)
		_export_dialog.popup_centered()


func _on_export_tile(mode: int, path: String) -> void:
	if not _tile:
		_update_status("ERROR: No tile to export")
		return
	var sel_positions: Array[Vector3i] = []
	if mode == TileExportDialog.ExportMode.SELECTED_ONLY:
		sel_positions = _tool_manager.selection.get_positions()
		if sel_positions.is_empty():
			_update_status("ERROR: No voxels selected for export")
			return
	var exported := TileExportDialog.export_tile(_tile, mode, sel_positions)
	var err := ResourceSaver.save(exported, path)
	if err == OK:
		_update_status("Exported tile to %s (%dx%dx%d)" % [
			path.get_file(), exported.tile_size_x, exported.tile_size_y, exported.tile_size_z])
	else:
		_update_status("ERROR: Failed to export — error %d" % err)


# ══════════════════════════════════════════════════════════════════════════════
# UI Utilities
# ══════════════════════════════════════════════════════════════════════════════

func set_ui_scale(scale_factor: float) -> void:
	_ui_scale = scale_factor
	get_tree().root.content_scale_factor = scale_factor
	_update_status("UI Scale: %d%%" % int(scale_factor * 100))


func get_ui_scale() -> float:
	return _ui_scale


func _on_numeric_input_changed(text: String) -> void:
	if text.is_empty():
		_update_status("Ready")
	else:
		_update_status("Size: %s  (Tab=next axis, Enter=commit, Esc=cancel)" % text)


func _update_status(text: String) -> void:
	if _status_label:
		_status_label.text = "VOXL v1.0 | %s" % text


const _VIEW_MODE_NAMES := ["Unshaded", "Lit", "Normals", "Material", "Textured"]


func _set_view_mode(mode: TileRenderer.ViewMode) -> void:
	_tile_renderer.view_mode = mode
	_update_status("View: %s" % _VIEW_MODE_NAMES[mode])


func _cycle_view_mode() -> void:
	var next := (_tile_renderer.view_mode + 1) % TileRenderer.ViewMode.size()
	_set_view_mode(next as TileRenderer.ViewMode)
