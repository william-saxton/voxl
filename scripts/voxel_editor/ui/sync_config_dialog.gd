class_name SyncConfigDialog
extends AcceptDialog
## Settings dialog for configuring the remote MinIO endpoint and auto-sync.

var _endpoint_edit: LineEdit
var _enabled_check: CheckBox
var _auto_push_check: CheckBox
var _auto_pull_check: CheckBox
var _poll_spin: SpinBox
var _test_button: Button
var _status_label: Label


func _init() -> void:
	title = "Remote Sync Settings"
	min_size = Vector2i(420, 280)
	exclusive = true

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Endpoint
	var ep_label := Label.new()
	ep_label.text = "MinIO Endpoint URL"
	vbox.add_child(ep_label)

	_endpoint_edit = LineEdit.new()
	_endpoint_edit.placeholder_text = "http://192.168.1.50:9000"
	_endpoint_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_endpoint_edit)

	# Enable checkbox
	_enabled_check = CheckBox.new()
	_enabled_check.text = "Enable remote sync"
	vbox.add_child(_enabled_check)

	# Auto-push
	_auto_push_check = CheckBox.new()
	_auto_push_check.text = "Auto-push on save"
	_auto_push_check.tooltip_text = "Automatically push tiles and palettes to remote when saving"
	vbox.add_child(_auto_push_check)

	# Auto-pull
	_auto_pull_check = CheckBox.new()
	_auto_pull_check.text = "Auto-pull new/changed assets"
	_auto_pull_check.tooltip_text = "Automatically download new or modified remote assets when detected"
	vbox.add_child(_auto_pull_check)

	# Poll interval
	var poll_row := HBoxContainer.new()
	poll_row.add_theme_constant_override("separation", 8)
	var poll_label := Label.new()
	poll_label.text = "Poll interval (seconds)"
	poll_row.add_child(poll_label)
	_poll_spin = SpinBox.new()
	_poll_spin.min_value = 0
	_poll_spin.max_value = 300
	_poll_spin.step = 5
	_poll_spin.value = 5
	_poll_spin.tooltip_text = "How often to check for remote changes (0 = manual only)"
	poll_row.add_child(_poll_spin)
	vbox.add_child(poll_row)

	# Test connection row
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 8)
	_test_button = Button.new()
	_test_button.text = "Test Connection"
	_test_button.pressed.connect(_on_test_pressed)
	test_row.add_child(_test_button)
	_status_label = Label.new()
	_status_label.text = ""
	test_row.add_child(_status_label)
	vbox.add_child(test_row)

	add_child(vbox)

	confirmed.connect(_on_confirmed)


func populate() -> void:
	var sync := AssetSyncManager
	_endpoint_edit.text = sync.endpoint
	_enabled_check.button_pressed = sync.enabled
	_auto_push_check.button_pressed = sync.auto_push
	_auto_pull_check.button_pressed = sync.auto_pull
	_poll_spin.value = sync.poll_interval
	_status_label.text = "Connected" if sync.connected else ""
	_status_label.add_theme_color_override(
		"font_color", Color.GREEN if sync.connected else Color.GRAY
	)


func _on_test_pressed() -> void:
	var sync := AssetSyncManager
	sync.endpoint = _endpoint_edit.text.strip_edges()
	_status_label.text = "Testing..."
	_status_label.add_theme_color_override("font_color", Color.YELLOW)
	sync.connection_status_changed.connect(_on_test_result, CONNECT_ONE_SHOT)
	sync.test_connection()


func _on_test_result(ok: bool) -> void:
	if ok:
		_status_label.text = "Connected"
		_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_status_label.text = "Failed"
		_status_label.add_theme_color_override("font_color", Color.RED)


func _on_confirmed() -> void:
	var sync := AssetSyncManager
	sync.endpoint = _endpoint_edit.text.strip_edges()
	sync.enabled = _enabled_check.button_pressed
	sync.auto_push = _auto_push_check.button_pressed
	sync.auto_pull = _auto_pull_check.button_pressed
	sync.poll_interval = _poll_spin.value
	sync.save_config()
