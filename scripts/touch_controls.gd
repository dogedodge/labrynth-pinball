class_name TouchControls
extends Control

var left_flipper: VirtualButton
var right_flipper: VirtualButton
var launch: VirtualButton
var pause_btn: VirtualButton
var restart_btn: VirtualButton

var _held: Dictionary = {}
var _action_counts: Dictionary = {}
var _buttons: Array[VirtualButton] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	left_flipper = _add_button(&"flipper_left", "L", Color(0.95, 0.55, 0.12, 0.95), 0.015, 0.48, 0.20, 0.96)
	right_flipper = _add_button(&"flipper_right", "R", Color(0.95, 0.55, 0.12, 0.95), 0.80, 0.48, 0.985, 0.96)
	launch = _add_button(&"plunger", "LAUNCH", Color(0.2, 0.75, 0.45, 0.95), 0.80, 0.30, 0.985, 0.46)
	pause_btn = _add_button(&"pause", "PAUSE", Color(0.7, 0.75, 0.85, 0.9), 0.015, 0.04, 0.13, 0.14)
	restart_btn = _add_button(&"restart", "RESTART", Color(0.85, 0.35, 0.3, 0.9), 0.14, 0.04, 0.27, 0.14)


func _add_button(action: StringName, text: String, accent: Color, l: float, t: float, r: float, b: float) -> VirtualButton:
	var btn := VirtualButton.new()
	btn.action = action
	btn.label_text = text
	btn.accent = accent
	btn.anchor_left = l
	btn.anchor_top = t
	btn.anchor_right = r
	btn.anchor_bottom = b
	btn.offset_left = 6
	btn.offset_top = 6
	btn.offset_right = -6
	btn.offset_bottom = -6
	add_child(btn)
	_buttons.append(btn)
	return btn


func set_launch_charge(ratio: float) -> void:
	if launch:
		launch.set_charge(ratio)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			var btn := _hit(touch.position)
			if btn:
				_held[touch.index] = btn
				_press(btn)
				get_viewport().set_input_as_handled()
		else:
			if _held.has(touch.index):
				var btn: VirtualButton = _held[touch.index]
				_held.erase(touch.index)
				_release(btn)
				get_viewport().set_input_as_handled()


func _hit(screen_pos: Vector2) -> VirtualButton:
	for i in range(_buttons.size() - 1, -1, -1):
		var btn := _buttons[i]
		if btn.get_global_rect().has_point(screen_pos):
			return btn
	return null


func _press(btn: VirtualButton) -> void:
	var n := int(_action_counts.get(btn.action, 0))
	_action_counts[btn.action] = n + 1
	if n == 0:
		Input.action_press(btn.action)
	btn.set_held(true)


func _release(btn: VirtualButton) -> void:
	var n := int(_action_counts.get(btn.action, 0)) - 1
	if n <= 0:
		_action_counts[btn.action] = 0
		Input.action_release(btn.action)
		btn.set_held(false)
	else:
		_action_counts[btn.action] = n
